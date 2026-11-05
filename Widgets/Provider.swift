import AppKit
import WidgetKit

struct ChannelSnapshot: Sendable {
    let channel: Channel
    let nowPlaying: NowPlaying?
    let artwork: Data?

    var image: NSImage? { artwork.flatMap(NSImage.init(data:)) }

    static func placeholder(_ channel: Channel) -> ChannelSnapshot {
        ChannelSnapshot(
            channel: channel,
            nowPlaying: NowPlaying(
                channel: channel, isOnline: true,
                track: Track(artist: "Prog Radio", title: "Now Playing"),
                startedAt: nil, artworkURL: nil, history: []),
            artwork: nil)
    }

    static func load(_ channel: Channel, service: any NowPlayingService) async -> ChannelSnapshot {
        let info = try? await service.nowPlaying(channel)
        var artwork: Data?
        if let url = info?.artworkURL {
            artwork = try? await URLSession.shared.data(from: url).0
        }
        return ChannelSnapshot(channel: channel, nowPlaying: info, artwork: artwork)
    }
}

/// Widgets can't follow the stream live; WidgetKit budgets refreshes, and the app reloads
/// timelines on every track change while it runs.
private let refreshInterval: TimeInterval = 5 * 60

struct ChannelEntry: TimelineEntry {
    let date: Date
    let snapshot: ChannelSnapshot
}

struct ChannelProvider: AppIntentTimelineProvider {
    let service: any NowPlayingService = RadioCoService()

    func placeholder(in context: Context) -> ChannelEntry {
        ChannelEntry(date: .now, snapshot: .placeholder(.crimsonHall))
    }

    func snapshot(for configuration: SelectChannelIntent, in context: Context) async -> ChannelEntry {
        if context.isPreview { return ChannelEntry(date: .now, snapshot: .placeholder(configuration.channel.channel)) }
        return ChannelEntry(date: .now, snapshot: await .load(configuration.channel.channel, service: service))
    }

    func timeline(for configuration: SelectChannelIntent, in context: Context) async -> Timeline<ChannelEntry> {
        let entry = ChannelEntry(date: .now, snapshot: await .load(configuration.channel.channel, service: service))
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(refreshInterval)))
    }
}

struct AllChannelsEntry: TimelineEntry {
    let date: Date
    let snapshots: [ChannelSnapshot]
}

struct AllChannelsProvider: TimelineProvider {
    let service: any NowPlayingService = RadioCoService()

    func placeholder(in context: Context) -> AllChannelsEntry {
        AllChannelsEntry(date: .now, snapshots: Channel.allCases.map(ChannelSnapshot.placeholder))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (AllChannelsEntry) -> Void) {
        if context.isPreview { return completion(placeholder(in: context)) }
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<AllChannelsEntry>) -> Void) {
        Task {
            completion(Timeline(entries: [await load()], policy: .after(.now.addingTimeInterval(refreshInterval))))
        }
    }

    private func load() async -> AllChannelsEntry {
        var snapshots: [ChannelSnapshot] = []
        for channel in Channel.allCases {
            snapshots.append(await .load(channel, service: service))
        }
        return AllChannelsEntry(date: .now, snapshots: snapshots)
    }
}
