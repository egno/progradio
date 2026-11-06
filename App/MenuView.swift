import AVKit
import ServiceManagement
import SwiftUI

struct MenuView: View {
    @Bindable var player: RadioPlayer
    let notifier: TrackNotifier
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("showRecentTracks") private var showRecentTracks = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NowPlayingCard(player: player)
            controls
            Divider()
            channels
            if let history = player.current?.history, !history.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    SectionToggle(title: "Recently played", detail: "on \(player.channel.shortName)", isExpanded: $showRecentTracks)
                    if showRecentTracks {
                        RecentTracks(tracks: Array(history.prefix(5)))
                    }
                }
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .task {
            // Every channel's track is only fetched while the menu is open.
            while !Task.isCancelled {
                await player.refreshAll()
                try? await Task.sleep(for: RadioPlayer.pollInterval)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isActive ? "stop.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.space, modifiers: [])
            .help(player.isActive ? "Stop" : "Play")

            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
            Slider(value: $player.volume, in: 0...1)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            RoutePicker(player: player.avPlayer)
                .frame(width: 22, height: 22)
                .help("Play on AirPlay speakers")
        }
    }

    private var channels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Channels").font(.caption).foregroundStyle(.secondary)
            ForEach(Channel.allCases) { channel in
                ChannelRow(
                    channel: channel,
                    nowPlaying: player.nowPlaying[channel],
                    isSelected: channel == player.channel,
                    isPlaying: channel == player.channel && player.isActive
                ) {
                    player.play(channel)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if notifier.isEnabled, notifier.isBlocked {
                Button("Notifications are off for Prog Radio Mini in System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
                .buttonStyle(.link)
            }
            HStack {
                Spacer()
                settingsMenu
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("q")
            }
        }
        .font(.caption)
    }

    /// Set-once options and links, kept out of the way in a gear menu.
    private var settingsMenu: some View {
        Menu {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { enabled in
                    if enabled {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }))
            Toggle("Notify new tracks", isOn: Binding(
                get: { notifier.isEnabled },
                set: { enabled in Task { await notifier.setEnabled(enabled) } }))
            Divider()
            Button("Send Feedback…") { NSWorkspace.shared.open(URL(string: "https://github.com/egno/progradio/issues")!) }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings")
    }
}

/// The station name in the now-playing card, linking to progradio.com.
private struct StationLink: View {
    let channel: Channel
    @State private var hovering = false

    var body: some View {
        Link(destination: URL(string: "https://www.progradio.com")!) {
            Label(channel.name, systemImage: channel.symbol)
                .underline(hovering)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .help("Open progradio.com")
    }
}

/// A caption header that shows or hides the section below it.
private struct SectionToggle: View {
    let title: String
    var detail: String?
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(title)
                if let detail {
                    Text(detail).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Hide \(title.lowercased())" : "Show \(title.lowercased())")
    }
}

private struct NowPlayingCard: View {
    let player: RadioPlayer

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkLink(image: player.currentArtwork, channel: player.channel, track: player.current?.track)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 4) {
                StationLink(channel: player.channel)
                if let track = player.current?.track {
                    TrackTitle(track: track)
                } else if player.current?.isOnline == false {
                    Text("Channel offline").foregroundStyle(.secondary)
                } else {
                    Text("Loading…").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                status
            }
            .textSelection(.enabled)
        }
    }

    @ViewBuilder private var status: some View {
        if let error = player.lastError {
            Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
        } else {
            switch player.state {
            case .stopped: EmptyView()
            case .buffering: Label("Buffering…", systemImage: "hourglass").font(.caption).foregroundStyle(.secondary)
            case .reconnecting:
                Label("Reconnecting…", systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.secondary)
            case .playing:
                Label(player.usingAirPlayStream ? "Live · AirPlay" : "Live", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }
        }
    }
}

struct Artwork: View {
    let image: NSImage?
    let channel: Channel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: channel.symbol).font(.largeTitle).foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Artwork that opens the artist in progradio.com's Rabbit Hole DB.
private struct ArtworkLink: View {
    let image: NSImage?
    let channel: Channel
    let track: Track?
    @State private var hovering = false
    @State private var lookup: Task<Void, Never>?

    private var artist: String? {
        guard let track, !track.artist.isEmpty, !track.isStationBreak else { return nil }
        return track.artist
    }

    var body: some View {
        if let artist, let track {
            Button { open(track) } label: {
                Artwork(image: image, channel: channel)
                    .overlay {
                        if lookup != nil {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .opacity(hovering ? 0.8 : 1)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Explore \(artist) in the Rabbit Hole DB")
            .onChange(of: track) { lookup?.cancel(); lookup = nil }
        } else {
            Artwork(image: image, channel: channel)
        }
    }

    private func open(_ track: Track) {
        guard lookup == nil else { return }
        lookup = Task {
            let id = await MusicBrainzLookup().artistMBID(for: track)
            guard !Task.isCancelled else { return }
            NSWorkspace.shared.open(id.map(RabbitHole.url(artistMBID:)) ?? RabbitHole.home)
            lookup = nil
        }
    }
}

private struct ChannelRow: View {
    let channel: Channel
    let nowPlaying: NowPlaying?
    let isSelected: Bool
    let isPlaying: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: channel.symbol)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(channel.name)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isPlaying ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    if let track = nowPlaying?.track {
                        Text(track.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isPlaying {
                    Image(systemName: "waveform")
                        .foregroundStyle(.tint)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .help("Playing")
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct RecentTracks: View {
    let tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
                HStack(spacing: 4) {
                    Text(track.title).lineLimit(1)
                    if !track.artist.isEmpty {
                        Text("· \(track.artist)").foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .font(.caption)
                .contextMenu { TrackActions(track: track) }
            }
        }
        .textSelection(.enabled)
    }
}

/// The song and artist; a click pops up the search menu.
private struct TrackTitle: View {
    let track: Track
    @State private var hovering = false

    var body: some View {
        Button {
            TrackActionMenu(track: track).popUpAtMouse()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(3)
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .underline(hovering, color: .secondary)
            .multilineTextAlignment(.leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Find this track")
    }
}

/// `TrackActions` as an AppKit menu, for popping up from an arbitrary view.
@MainActor
private final class TrackActionMenu: NSObject {
    private let track: Track
    private let menu = NSMenu()

    init(track: Track) {
        self.track = track
        super.init()
        for search in TrackSearch.allCases {
            add("Search \(search.name)", tag: TrackSearch.allCases.firstIndex(of: search)!)
        }
        menu.addItem(.separator())
        add("Copy “\(track.displayName)”", tag: -1)
    }

    private func add(_ title: String, tag: Int) {
        let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        item.target = self
        item.tag = tag
        menu.addItem(item)
    }

    /// Blocks until the menu closes, which keeps `self` alive as the items' target.
    func popUpAtMouse() {
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func choose(_ item: NSMenuItem) {
        if TrackSearch.allCases.indices.contains(item.tag) {
            NSWorkspace.shared.open(TrackSearch.allCases[item.tag].url(for: track))
        } else {
            copyToPasteboard(track)
        }
    }
}

private func copyToPasteboard(_ track: Track) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(track.displayName, forType: .string)
}

private struct TrackActions: View {
    let track: Track

    var body: some View {
        ForEach(TrackSearch.allCases) { search in
            Button("Search \(search.name)") { NSWorkspace.shared.open(search.url(for: track)) }
        }
        Divider()
        Button("Copy “\(track.displayName)”") { copyToPasteboard(track) }
    }
}

/// The system AirPlay picker, bound to the radio's player.
private struct RoutePicker: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.player = player
        view.isRoutePickerButtonBordered = false
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        view.player = player
    }
}
