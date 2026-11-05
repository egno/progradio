import ServiceManagement
import SwiftUI

struct MenuView: View {
    @Bindable var player: RadioPlayer
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NowPlayingCard(player: player)
            controls
            Divider()
            channels
            if let history = player.current?.history, !history.isEmpty {
                Divider()
                RecentTracks(tracks: Array(history.prefix(5)))
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .task { await player.refreshAll() }
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
        HStack {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: launchAtLogin) { _, enabled in
                    if enabled {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            Spacer()
            Link("progradio.com", destination: URL(string: "https://www.progradio.com")!)
                .font(.caption)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .keyboardShortcut("q")
        }
    }
}

private struct NowPlayingCard: View {
    let player: RadioPlayer

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Artwork(image: player.currentArtwork, channel: player.channel)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 4) {
                Label(player.channel.name, systemImage: player.channel.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let track = player.current?.track {
                    Text(track.title)
                        .font(.headline)
                        .lineLimit(3)
                    if !track.artist.isEmpty {
                        Text(track.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
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
            case .playing:
                Label("Live", systemImage: "waveform")
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
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : channel.symbol)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(channel.name).fontWeight(isSelected ? .semibold : .regular)
                    if let track = nowPlaying?.track {
                        Text(track.artist.isEmpty ? track.title : "\(track.artist) – \(track.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
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
            Text("Recently played").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
                HStack(spacing: 4) {
                    Text(track.title).lineLimit(1)
                    if !track.artist.isEmpty {
                        Text("· \(track.artist)").foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .font(.caption)
            }
        }
        .textSelection(.enabled)
    }
}
