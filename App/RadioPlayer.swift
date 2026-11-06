import AVFoundation
import AppKit
import Network
import Observation
import WidgetKit
import os

private let log = Logger(subsystem: "io.github.egno.ProgRadio", category: "player")

/// Plays one channel at a time, reconnects when the stream drops, and keeps now-playing info fresh.
@MainActor
@Observable
final class RadioPlayer {
    enum State: Equatable { case stopped, buffering, playing, reconnecting }

    private(set) var channel: Channel
    private(set) var state: State = .stopped
    private(set) var nowPlaying: [Channel: NowPlaying] = [:]
    private(set) var artwork: [Channel: NSImage] = [:]
    private(set) var lastError: String?
    /// Playing the station's AirPlay HLS stream because the audio goes to an AirPlay receiver.
    private(set) var usingAirPlayStream = false

    var volume: Float {
        didSet {
            player.volume = volume
            defaults.set(volume, forKey: Keys.volume)
        }
    }

    var current: NowPlaying? { nowPlaying[channel] }
    var currentArtwork: NSImage? { artwork[channel] }
    var isActive: Bool { state != .stopped }
    /// For the AirPlay route picker.
    var avPlayer: AVPlayer { player }

    @ObservationIgnored var onChange: (() -> Void)?
    /// A new track started on the channel being played (not the one playing when playback began).
    @ObservationIgnored var onTrackChange: ((Channel, Track, NSImage?) -> Void)?

    private let service: any NowPlayingService
    private let defaults: UserDefaults
    private let player = AVPlayer()
    private let audioOutput = AudioOutputMonitor()
    private let pathMonitor = NWPathMonitor()

    /// The user wants sound; stays true through drops and reconnects until they press stop.
    @ObservationIgnored private var wantsPlay = false
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var stallTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var itemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var heardTrack: Track?
    @ObservationIgnored private var networkUp = true
    private var artworkURLs: [Channel: URL] = [:]

    private enum Keys {
        static let channel = "channel"
        static let volume = "volume"
    }

    /// Polling the station while playing; the other channels are refreshed only while the menu is open.
    static let pollInterval: Duration = .seconds(20)
    /// Give up on a stream that has been buffering this long and reconnect.
    static let stallTimeout: Duration = .seconds(20)

    init(service: any NowPlayingService = RadioCoService(), defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        channel = defaults.string(forKey: Keys.channel).flatMap(Channel.init(rawValue:)) ?? .crimsonHall
        volume = defaults.object(forKey: Keys.volume) as? Float ?? 0.8
        player.volume = volume
        player.automaticallyWaitsToMinimizeStalling = true
        observePlayer()
        observeSystem()
    }

    // MARK: Commands

    func play(_ channel: Channel? = nil) {
        if let channel { setChannel(channel) }
        wantsPlay = true
        retries = 0
        heardTrack = nil
        lastError = nil
        log.info("play \(self.channel.rawValue, privacy: .public)")
        startStream()
        startPolling()
    }

    func stop() {
        wantsPlay = false
        cancelTasks()
        pollTask?.cancel()
        pollTask = nil
        tearDownItem()
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
        case .site(let page): NSWorkspace.shared.open(page.url)
        }
    }

    // MARK: Stream

    /// A fresh item each time so playback starts at the live edge.
    private func startStream() {
        cancelTasks()
        tearDownItem()
        usingAirPlayStream = audioOutput.isAirPlay || player.isExternalPlaybackActive
        let url = usingAirPlayStream ? channel.airPlayStreamURL : channel.streamURL
        let item = AVPlayerItem(url: url)
        let center = NotificationCenter.default
        itemObservers = [
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] note in
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                MainActor.assumeIsolated { self?.streamDropped(error?.localizedDescription ?? "Stream ended") }
            },
            // A live stream never reaches its end, so reaching it means the server closed the connection.
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.streamDropped("Stream ended") }
            },
        ]
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Couldn't open the stream"
            MainActor.assumeIsolated { self?.streamDropped(message) }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        if state != .reconnecting { state = .buffering }
        log.info("stream \(url.absoluteString, privacy: .public)")
        watchForStall()
        changed()
    }

    private func tearDownItem() {
        itemObservers.forEach(NotificationCenter.default.removeObserver)
        itemObservers = []
        itemStatusObservation = nil
        player.replaceCurrentItem(with: nil)
    }

    private func cancelTasks() {
        reconnectTask?.cancel()
        reconnectTask = nil
        stallTask?.cancel()
        stallTask = nil
    }

    /// The stream failed, ended or stalled: retry with backoff (1, 2, 4 … 30 s) while the user wants sound.
    private func streamDropped(_ reason: String) {
        guard wantsPlay, reconnectTask == nil else { return }
        log.error("stream dropped: \(reason, privacy: .public)")
        tearDownItem()
        lastError = nil
        state = .reconnecting
        changed()
        let delay = min(30, 1 << min(retries, 5))
        retries += 1
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.wantsPlay else { return }
            self.reconnectTask = nil
            if self.networkUp {
                self.startStream()
            } else {
                log.info("waiting for network")
            }
        }
    }

    /// Reconnect right away, e.g. after wake or when the network comes back.
    private func reconnectNow(_ reason: String) {
        guard wantsPlay else { return }
        log.info("reconnect: \(reason, privacy: .public)")
        retries = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        state = .reconnecting
        startStream()
    }

    private func watchForStall() {
        stallTask?.cancel()
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: Self.stallTimeout)
            guard !Task.isCancelled, let self, self.wantsPlay, self.state != .playing else { return }
            self.stallTask = nil
            self.streamDropped("no audio for \(Self.stallTimeout)")
        }
    }

    // MARK: Observing

    private func observePlayer() {
        observations.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            MainActor.assumeIsolated { self?.timeControlStatusChanged(status) }
        })
        // Routed to AirPlay from the route picker: switch to the station's AirPlay stream.
        observations.append(player.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputChanged() }
        })
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.wantsPlay else { return }
                log.info("sleep")
                self.cancelTasks()
                self.tearDownItem()
            }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconnectNow("wake") }
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(up: up) }
        }
        pathMonitor.start(queue: .main)
        audioOutput.onChange = { [weak self] in self?.outputChanged() }
    }

    private func networkChanged(up: Bool) {
        guard up != networkUp else { return }
        networkUp = up
        log.info("network \(up ? "up" : "down", privacy: .public)")
        if up, wantsPlay, state != .playing { reconnectNow("network back") }
    }

    private func outputChanged() {
        let airPlay = audioOutput.isAirPlay || player.isExternalPlaybackActive
        guard wantsPlay, airPlay != usingAirPlayStream else { return }
        log.info("output changed, AirPlay \(airPlay, privacy: .public)")
        retries = 0
        startStream()
    }

    private func timeControlStatusChanged(_ status: AVPlayer.TimeControlStatus) {
        guard player.currentItem != nil, wantsPlay else { return }
        if status == .playing {
            retries = 0
            stallTask?.cancel()
            stallTask = nil
            lastError = nil
            if state != .playing {
                log.info("state playing")
                state = .playing
                changed()
            }
        } else if state == .playing {
            // Stalled mid-stream; AVPlayer keeps trying, but don't let it hang forever.
            log.info("state buffering")
            state = .buffering
            watchForStall()
            changed()
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

    /// While playing, only the current channel is polled.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(self.channel)
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func refresh(_ channel: Channel) async {
        do {
            let info = try await service.nowPlaying(channel)
            let trackChanged = nowPlaying[channel]?.track != info.track
            nowPlaying[channel] = info
            if info.artworkURL != artworkURLs[channel] { await loadArtwork(channel, url: info.artworkURL) }
            if trackChanged {
                if channel == self.channel { changed() }
                WidgetCenter.shared.reloadAllTimelines()
            }
            noteHeard(info.track, on: channel)
        } catch {
            log.error("now playing \(channel.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func noteHeard(_ track: Track?, on channel: Channel) {
        // Skipping station breaks keeps the last song as heardTrack, so the next song still notifies.
        guard wantsPlay, channel == self.channel, let track, !track.isStationBreak else { return }
        defer { heardTrack = track }
        guard let heardTrack, heardTrack != track else { return }
        onTrackChange?(channel, track, artwork[channel])
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

    private func changed() { onChange?() }
}
