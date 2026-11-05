import AVFoundation
import AppKit
import Observation
import WidgetKit
import os

private let log = Logger(subsystem: "local.progradio", category: "player")

/// Plays one channel at a time and keeps now-playing info for every channel fresh.
@MainActor
@Observable
final class RadioPlayer {
    enum State: Equatable { case stopped, buffering, playing }

    private(set) var channel: Channel
    private(set) var state: State = .stopped
    private(set) var nowPlaying: [Channel: NowPlaying] = [:]
    private(set) var artwork: [Channel: NSImage] = [:]
    private(set) var lastError: String?

    var volume: Float {
        didSet {
            player.volume = volume
            defaults.set(volume, forKey: Keys.volume)
        }
    }

    var current: NowPlaying? { nowPlaying[channel] }
    var currentArtwork: NSImage? { artwork[channel] }
    var isActive: Bool { state != .stopped }

    @ObservationIgnored var onChange: (() -> Void)?

    private let service: any NowPlayingService
    private let defaults: UserDefaults
    private let player = AVPlayer()
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    private var artworkURLs: [Channel: URL] = [:]

    private enum Keys {
        static let channel = "channel"
        static let volume = "volume"
    }

    init(service: any NowPlayingService = RadioCoService(), defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        channel = defaults.string(forKey: Keys.channel).flatMap(Channel.init(rawValue:)) ?? .crimsonHall
        volume = defaults.object(forKey: Keys.volume) as? Float ?? 0.8
        player.volume = volume
        player.automaticallyWaitsToMinimizeStalling = true
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            MainActor.assumeIsolated { self?.timeControlStatusChanged(status) }
        }
        startPolling()
    }

    // MARK: Commands

    func play(_ channel: Channel? = nil) {
        if let channel { setChannel(channel) }
        lastError = nil
        // A fresh item each time so playback resumes at the live edge, not where it was stopped.
        let item = AVPlayerItem(url: self.channel.streamURL)
        NotificationCenter.default.addObserver(
            self, selector: #selector(itemFailed(_:)),
            name: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)
        player.replaceCurrentItem(with: item)
        player.play()
        state = .buffering
        log.info("play \(self.channel.rawValue, privacy: .public)")
        changed()
        Task { await refresh(self.channel) }
    }

    func stop() {
        player.replaceCurrentItem(with: nil)
        player.pause()
        state = .stopped
        log.info("stop")
        changed()
    }

    func toggle(_ channel: Channel? = nil) {
        if isActive, channel == nil || channel == self.channel {
            stop()
        } else {
            play(channel)
        }
    }

    /// Switches channel; keeps playing if something was playing.
    func select(_ channel: Channel) {
        guard channel != self.channel else { return }
        if isActive {
            play(channel)
        } else {
            setChannel(channel)
            changed()
        }
    }

    private func setChannel(_ channel: Channel) {
        self.channel = channel
        defaults.set(channel.rawValue, forKey: Keys.channel)
    }

    func step(_ offset: Int) {
        let all = Channel.allCases
        let index = all.firstIndex(of: channel)!
        select(all[(index + offset + all.count) % all.count])
    }

    func handle(_ link: AppLink) {
        switch link {
        case .play(let channel): play(channel)
        case .toggle(let channel): toggle(channel)
        case .stop: stop()
        case .open: break
        }
    }

    // MARK: Now playing

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for channel in Channel.allCases {
                group.addTask { await self.refresh(channel) }
            }
        }
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func refresh(_ channel: Channel) async {
        do {
            let info = try await service.nowPlaying(channel)
            let trackChanged = nowPlaying[channel]?.track != info.track
            nowPlaying[channel] = info
            if info.artworkURL != artworkURLs[channel] { await loadArtwork(channel, url: info.artworkURL) }
            if trackChanged {
                if channel == self.channel { changed() }
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            log.error("now playing \(channel.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadArtwork(_ channel: Channel, url: URL?) async {
        artworkURLs[channel] = url
        guard let url else {
            artwork[channel] = nil
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data) else { return }
        guard artworkURLs[channel] == url else { return }
        artwork[channel] = image
        if channel == self.channel { changed() }
    }

    // MARK: Player state

    private func timeControlStatusChanged(_ status: AVPlayer.TimeControlStatus) {
        guard player.currentItem != nil else { return }
        let newState: State = status == .playing ? .playing : .buffering
        if newState != state {
            log.info("state \(String(describing: newState), privacy: .public)")
            state = newState
            changed()
        }
    }

    @objc private func itemFailed(_ notification: Notification) {
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        MainActor.assumeIsolated {
            lastError = error?.localizedDescription ?? "Playback failed"
            stop()
        }
    }

    private func changed() { onChange?() }
}
