import SwiftUI
import WidgetKit

/// Upcoming shows from progradio.com/showschedule, plus links to the station's pages.
struct ShowsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "io.github.egno.ProgRadio.shows", provider: ShowsProvider()) { entry in
            ShowsView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Shows")
        .description("Upcoming Prog Radio shows, song requests, history and chat.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ShowsEntry: TimelineEntry {
    let date: Date
    /// nil when the schedule couldn't be loaded.
    let shows: [Show]?
}

struct ShowsProvider: TimelineProvider {
    let service: any ScheduleService = WebScheduleService()
    /// The schedule changes a few times a week; an hourly check is plenty.
    static let refreshInterval: TimeInterval = 60 * 60

    func placeholder(in context: Context) -> ShowsEntry {
        ShowsEntry(date: .now, shows: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ShowsEntry) -> Void) {
        if context.isPreview { return completion(placeholder(in: context)) }
        Task { completion(ShowsEntry(date: .now, shows: try? await service.shows())) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ShowsEntry>) -> Void) {
        Task {
            let shows = try? await service.shows()
            let now = Date.now
            let refresh = now.addingTimeInterval(Self.refreshInterval)
            // Extra entries when a show starts or ends, so "On air" and the list stay right between fetches.
            let changes = (shows.map { Schedule.upcoming($0, at: now) } ?? [])
                .flatMap { [$0.start, $0.start.addingTimeInterval(Show.assumedLength)] }
                .filter { $0 > now && $0 < refresh }
            let entries = ([now] + changes.sorted()).map { ShowsEntry(date: $0, shows: shows) }
            completion(Timeline(entries: entries, policy: .after(refresh)))
        }
    }

    static let sample: [Show] = [
        Show(id: "1", name: "What's New Proggy Cats?", host: "", venue: "Crimson Hall", channel: .crimsonHall,
             start: .now.addingTimeInterval(3 * 3600)),
        Show(id: "2", name: "What's New Proggy Cats? METAL Edition", host: "", venue: "Dragons Tower", channel: .dragonsTower,
             start: .now.addingTimeInterval(27 * 3600)),
        Show(id: "3", name: "The Prog Corner LIVE Sunday Stream", host: "Scot Lade", venue: "YouTube", channel: nil,
             start: .now.addingTimeInterval(50 * 3600)),
    ]
}

struct ShowsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShowsEntry

    private var upcoming: [Show] { Schedule.upcoming(entry.shows ?? [], at: entry.date) }

    private var limit: Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 2
        default: 5
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 6) {
            Link(destination: AppLink.site(.schedule).url) {
                Label("Upcoming shows", systemImage: "calendar")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if entry.shows == nil {
                Text("Schedule unavailable").font(.caption).foregroundStyle(.secondary)
            } else if upcoming.isEmpty {
                Text("No shows scheduled").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(upcoming.prefix(limit)) { show in
                    ShowRow(show: show, now: entry.date, compact: family == .systemSmall)
                }
            }
            Spacer(minLength: 0)
            if family != .systemSmall { SiteLinks() }
        }
        .widgetURL(AppLink.site(.schedule).url)
    }
}

private struct ShowRow: View {
    let show: Show
    let now: Date
    let compact: Bool

    var body: some View {
        // Shows on a channel start it playing; others (YouTube streams) open the schedule.
        Link(destination: show.channel.map { AppLink.play($0).url } ?? AppLink.site(.schedule).url) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: show.channel?.symbol ?? "play.rectangle.fill")
                    .foregroundStyle(.tint)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(show.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(compact ? 3 : 1)
                    Text(details)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(compact ? 2 : 1)
                    when
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var details: String {
        let place = show.channel?.shortName ?? show.venue
        return [place, show.host].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder private var when: some View {
        if show.isOnAir(at: now) {
            Text("On air now").font(.caption2.weight(.semibold)).foregroundStyle(.tint)
        } else if show.start.timeIntervalSince(now) < 24 * 3600 {
            Text("\(show.start, format: .dateTime.hour().minute()) · in \(Text(show.start, style: .relative))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else {
            Text(show.start, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

/// Request a song, song history, chat and supporting the station, on progradio.com.
struct SiteLinks: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach([SitePage.request, .history, .chat, .support], id: \.self) { page in
                Link(destination: AppLink.site(page).url) {
                    VStack(spacing: 2) {
                        Image(systemName: page.symbol).font(.caption)
                        Text(page.title).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(page == .support ? AnyShapeStyle(.pink) : AnyShapeStyle(.secondary))
                }
            }
        }
    }
}
