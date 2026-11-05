import SwiftUI
import WidgetKit

struct ArtworkView: View {
    let snapshot: ChannelSnapshot

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image = snapshot.image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: snapshot.channel.symbol).font(.title).foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct TrackText: View {
    let snapshot: ChannelSnapshot
    var titleFont: Font = .headline
    var lines = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let track = snapshot.nowPlaying?.track {
                Text(track.title).font(titleFont).lineLimit(lines)
                if !track.artist.isEmpty {
                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text(snapshot.nowPlaying?.isOnline == false ? "Offline" : "Unavailable")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ChannelLabel: View {
    let channel: Channel

    var body: some View {
        Label(channel.shortName, systemImage: channel.symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

struct PlayLink: View {
    let channel: Channel

    var body: some View {
        Link(destination: AppLink.toggle(channel).url) {
            Image(systemName: "playpause.fill")
                .font(.body)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.tint.opacity(0.2)))
        }
    }
}

struct ChannelWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ChannelEntry

    private var snapshot: ChannelSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemLarge: large
        default: medium
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                ArtworkView(snapshot: snapshot).frame(width: 52, height: 52)
                Spacer()
                PlayLink(channel: snapshot.channel)
            }
            Spacer(minLength: 0)
            ChannelLabel(channel: snapshot.channel)
            TrackText(snapshot: snapshot, titleFont: .subheadline.weight(.semibold))
        }
        .widgetURL(AppLink.play(snapshot.channel).url)
    }

    private var medium: some View {
        HStack(spacing: 12) {
            ArtworkView(snapshot: snapshot).aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 6) {
                ChannelLabel(channel: snapshot.channel)
                TrackText(snapshot: snapshot, lines: 3)
                Spacer(minLength: 0)
                HStack {
                    PlayLink(channel: snapshot.channel)
                    Spacer()
                    Text(entry.date, style: .time).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            medium.frame(height: 130)
            Divider()
            Text("Recently played").font(.caption).foregroundStyle(.secondary)
            ForEach(Array((snapshot.nowPlaying?.history ?? []).prefix(6).enumerated()), id: \.offset) { _, track in
                VStack(alignment: .leading, spacing: 0) {
                    Text(track.title).font(.caption.weight(.medium)).lineLimit(1)
                    Text(track.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct AllChannelsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AllChannelsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 14 : 6) {
            ForEach(entry.snapshots, id: \.channel) { snapshot in
                Link(destination: AppLink.play(snapshot.channel).url) {
                    HStack(spacing: 10) {
                        ArtworkView(snapshot: snapshot)
                            .frame(width: family == .systemLarge ? 72 : 36, height: family == .systemLarge ? 72 : 36)
                        VStack(alignment: .leading, spacing: 1) {
                            ChannelLabel(channel: snapshot.channel)
                            TrackText(snapshot: snapshot, titleFont: .caption.weight(.semibold), lines: family == .systemLarge ? 2 : 1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            if family == .systemLarge { Spacer(minLength: 0) }
        }
    }
}
