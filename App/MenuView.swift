import AVKit
import ServiceManagement
import SwiftUI

struct MenuView: View {
    @Bindable var player: RadioPlayer
    let notifier: TrackNotifier
    let votes: SongVotes
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var volumeBeforeMute: Float = 0.8
    @AppStorage("showRecentTracks") private var showRecentTracks = false
    @AppStorage(Channel.colorsKey) private var channelColors = true

    private var error: String? {
        player.lastError ?? player.current?.track.flatMap(votes.error(for:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NowPlayingCard(player: player, votes: votes) { settingsMenu }
                // The text column's spacer would otherwise take whatever height the window offers.
                .fixedSize(horizontal: false, vertical: true)
            controls
            if let error {
                Banner(text: error)
            }
            if notifier.isEnabled, notifier.isBlocked {
                Banner(text: "Notifications are off for Prog Radio Mini. Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
            }
            Divider()
            channels
            if let history = player.current?.history, !history.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    SectionToggle(title: "Recently played", detail: "on \(player.channel.shortName)", isExpanded: $showRecentTracks)
                    if showRecentTracks {
                        RecentTracks(tracks: Array(history.prefix(5)))
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(alignment: .top) { AmbientArtwork(image: player.currentArtwork) }
        .tint(player.channel.accent(channelColors))
        .animation(.snappy(duration: 0.25), value: player.channel)
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
            PlayButton(player: player)
            Button(action: toggleMute) {
                Image(systemName: volumeSymbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(player.volume == 0 ? "Unmute" : "Mute")
            Slider(value: $player.volume, in: 0...1)
                .controlSize(.small)
            RoutePicker(player: player.avPlayer)
                .frame(width: 22, height: 22)
                .help("Play on AirPlay speakers")
        }
    }

    private var volumeSymbol: String {
        switch player.volume {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    private func toggleMute() {
        if player.volume == 0 {
            player.volume = volumeBeforeMute > 0 ? volumeBeforeMute : 0.8
        } else {
            volumeBeforeMute = player.volume
            player.volume = 0
        }
    }

    private var channels: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: "Channels")
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

    /// "Version 1.3.1", from the bundle.
    private static let versionTitle: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version.map { "Version \($0)" } ?? "Releases"
    }()

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
            Toggle("Channel colors", isOn: $channelColors)
            Divider()
            Button("Send Feedback…") { NSWorkspace.shared.open(URL(string: "https://github.com/egno/progradio/issues")!) }
            Button(Self.versionTitle) { NSWorkspace.shared.open(URL(string: "https://github.com/egno/progradio/releases")!) }
                .help("See the release notes")
            Divider()
            Button("Quit Prog Radio Mini") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Settings")
    }
}

/// Each channel's accent, used as the popover's tint while it's selected.
extension Channel {
    /// Whether the popover uses the channels' colors or the system accent color.
    static let colorsKey = "channelColors"

    /// `color`, or the system accent color when channel colors are turned off.
    func accent(_ enabled: Bool) -> Color { enabled ? color : .accentColor }

    var color: Color {
        switch self {
        case .crimsonHall: Color(red: 0.78, green: 0.12, blue: 0.22)
        case .wizardsForest: Color(red: 0.20, green: 0.56, blue: 0.32)
        case .dragonsTower: Color(red: 0.91, green: 0.50, blue: 0.10)
        }
    }
}

/// Play/stop as a filled circle in the channel's color, with a spinning ring while the stream loads.
private struct PlayButton: View {
    let player: RadioPlayer
    @State private var spin = false

    private var isLoading: Bool { player.state == .buffering || player.state == .reconnecting }

    var body: some View {
        Button {
            player.toggle()
        } label: {
            ZStack {
                Circle().fill(.tint)
                Image(systemName: player.isActive ? "stop.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: player.isActive ? 0 : 1)
                    .contentTransition(.symbolEffect(.replace))
                if isLoading {
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .padding(-4)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .onAppear {
                            spin = false
                            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
                        }
                }
            }
            .frame(width: 34, height: 34)
            .padding(4)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .help(help)
        .accessibilityLabel(player.isActive ? "Stop" : "Play")
        .accessibilityValue(isLoading ? help : "")
    }

    private var help: String {
        switch player.state {
        case .buffering: "Buffering…"
        case .reconnecting: "Reconnecting…"
        case .playing: "Stop"
        case .stopped: "Play"
        }
    }
}

/// A full-width strip for problems: a failed stream or vote, or blocked notifications.
private struct Banner: View {
    let text: String
    var action: (() -> Void)?

    var body: some View {
        let content = Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(.red.opacity(0.1)))
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .pointerStyle(.link)
        } else {
            content
        }
    }
}

/// The current artwork, blurred and faded behind the top of the popover, like Control Center's Now Playing.
private struct AmbientArtwork: View {
    let image: NSImage?

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 180)
                .blur(radius: 40)
                .opacity(0.35)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }
}

/// The station name in the now-playing card, linking to progradio.com.
private struct StationLink: View {
    let channel: Channel
    @State private var hovering = false

    var body: some View {
        Link(destination: URL(string: "https://www.progradio.com")!) {
            Label(channel.name.uppercased(), systemImage: channel.symbol)
                .underline(hovering)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tint)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .help("Open progradio.com")
    }
}

/// A section's caption title.
private struct SectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: 4) {
            Text(title).fontWeight(.medium)
            if let detail {
                Text(detail).foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }
}

/// A section header that shows or hides the section below it, with the chevron trailing so titles line up.
private struct SectionToggle: View {
    let title: String
    var detail: String?
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            HStack {
                SectionHeader(title: title, detail: detail)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .padding(.trailing, 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Hide \(title.lowercased())" : "Show \(title.lowercased())")
    }
}

private struct NowPlayingCard<Accessory: View>: View {
    let player: RadioPlayer
    let votes: SongVotes
    @ViewBuilder let accessory: () -> Accessory

    private static var artworkSize: CGFloat { 96 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkLink(image: player.currentArtwork, channel: player.channel, track: player.current?.track,
                        knownArtistMBID: player.currentDetails?.artistMBID)
                .frame(width: Self.artworkSize, height: Self.artworkSize)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    StationLink(channel: player.channel)
                    Spacer(minLength: 4)
                    accessory()
                }
                if let track = player.current?.track {
                    TrackTitle(track: track)
                    TrackFacts(track: track, album: player.current?.album, details: player.currentDetails)
                } else if player.current?.isOnline == false {
                    Text("Channel offline").foregroundStyle(.secondary)
                } else {
                    Text("Loading…").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let track = player.current?.track, track.isVotable {
                    HStack {
                        Spacer()
                        VoteButtons(votes: votes, track: track, channel: player.channel)
                    }
                }
            }
            .frame(minHeight: Self.artworkSize, alignment: .top)
            .textSelection(.enabled)
        }
    }
}

struct Artwork: View {
    let image: NSImage?
    let channel: Channel
    @AppStorage(Channel.colorsKey) private var channelColors = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: channel.symbol).font(.largeTitle).foregroundStyle(channelColors ? AnyShapeStyle(channel.color.opacity(0.7)) : AnyShapeStyle(.secondary))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Artwork that opens the artist in progradio.com's Rabbit Hole DB.
private struct ArtworkLink: View {
    let image: NSImage?
    let channel: Channel
    let track: Track?
    /// Already found by the player's MusicBrainz lookup; saves a search on click.
    let knownArtistMBID: String?
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
        if let knownArtistMBID {
            NSWorkspace.shared.open(RabbitHole.url(artistMBID: knownArtistMBID))
            return
        }
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
    @AppStorage(Channel.colorsKey) private var channelColors = true

    private var accent: Color { channel.accent(channelColors) }

    /// The selected channel's song is already in the card, so its row says what the player is doing instead.
    private var subtitle: String? {
        if isSelected { return isPlaying ? "Now playing" : "Selected" }
        return nowPlaying?.track?.displayName
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(accent.opacity(hovering ? 0.18 : 0.12)) }
        return hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: channel.symbol)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? AnyShapeStyle(accent)
                        : channelColors ? AnyShapeStyle(channel.color.opacity(0.6)) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(channel.name)
                        .fontWeight(isSelected ? .semibold : .regular)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(isPlaying ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isPlaying {
                    Image(systemName: "waveform")
                        .foregroundStyle(accent)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .help("Playing")
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6).fill(background))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isSelected ? "" : "Listen to \(channel.name)")
    }
}

private struct RecentTracks: View {
    let tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
                RecentTrackRow(track: track)
            }
        }
    }
}

/// A recent song, with a ⋯ menu on hover (and the same actions on right-click).
private struct RecentTrackRow: View {
    let track: Track
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(track.title).lineLimit(1)
            if !track.artist.isEmpty {
                Text("· \(track.artist)").foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                TrackActions(track: track)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0)
            .help("Find this track")
        }
        .font(.caption)
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { TrackActions(track: track) }
    }
}

/// The album on one line, "1973 · 🇬🇧 United Kingdom" on the next, with whatever parts are known.
/// The short year and country get their own line so a long album name never cuts them off.
private struct TrackFacts: View {
    let track: Track
    let album: String?
    let details: TrackDetails?

    /// Singles are usually titled after the song; repeating it would only push the facts off the line.
    private var shownAlbum: String? {
        guard let album, album.caseInsensitiveCompare(track.title) != .orderedSame else { return nil }
        return album
    }

    private var yearAndCountry: String? {
        var parts: [String] = []
        if let year = details?.year { parts.append(year) }
        if let country = details?.countryName {
            parts.append([details?.countryFlag, country].compactMap { $0 }.joined(separator: " "))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let shownAlbum {
                Text(shownAlbum).lineLimit(1).help(shownAlbum)
            }
            if let yearAndCountry {
                Text(yearAndCountry).lineLimit(1).help(yearAndCountry)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// 👍 and 👎 for the current song, counted in progradio.com's Likes & Dislikes report.
private struct VoteButtons: View {
    let votes: SongVotes
    let track: Track
    let channel: Channel

    var body: some View {
        let current = votes.vote(for: track)
        HStack(spacing: 2) {
            button(.like, symbol: "hand.thumbsup", chosen: current == .like)
            button(.dislike, symbol: "hand.thumbsdown", chosen: current == .dislike)
        }
        .disabled(votes.isSending(track))
    }

    private func button(_ vote: SongVote, symbol: String, chosen: Bool) -> some View {
        Button {
            Task { await votes.choose(vote, for: track, on: channel) }
        } label: {
            Image(systemName: chosen ? symbol + ".fill" : symbol)
                .foregroundStyle(chosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(chosen ? "Take back your \(vote == .like ? "like" : "dislike")" : (vote == .like ? "Like this song" : "Dislike this song"))
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
                    .lineLimit(2)
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .underline(hovering, color: .secondary)
            .multilineTextAlignment(.leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Find “\(track.displayName)”")
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
