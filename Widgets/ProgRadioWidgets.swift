import AppIntents
import SwiftUI
import WidgetKit

@main
struct ProgRadioWidgets: WidgetBundle {
    var body: some Widget {
        ChannelWidget()
        AllChannelsWidget()
        ShowsWidget()
        PlayChannelControl()
    }
}

struct ChannelWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "io.github.egno.ProgRadio.channel", intent: SelectChannelIntent.self, provider: ChannelProvider()) { entry in
            ChannelWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Now Playing")
        .description("What's playing on a Prog Radio channel.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct AllChannelsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "io.github.egno.ProgRadio.all", provider: AllChannelsProvider()) { entry in
            AllChannelsView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("All Channels")
        .description("Now playing on every Prog Radio channel. Click one to listen.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// A Control Center / menu bar control that plays or stops a channel.
struct PlayChannelControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "io.github.egno.ProgRadio.control", intent: SelectChannelControlIntent.self) { configuration in
            ControlWidgetButton(action: ToggleChannelIntent(channel: configuration.channel)) {
                Label(configuration.channel.channel.shortName, systemImage: configuration.channel.channel.symbol)
            }
        }
        .displayName("Prog Radio")
        .description("Play or stop a Prog Radio channel.")
    }
}
