import AppIntents
import Foundation

enum ChannelOption: String, AppEnum {
    case crimson, wizard, dragon

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Channel"
    static let caseDisplayRepresentations: [ChannelOption: DisplayRepresentation] = [
        .crimson: DisplayRepresentation(title: "The Crimson Hall", image: .init(systemName: "building.columns.fill")),
        .wizard: DisplayRepresentation(title: "The Wizard's Forest", image: .init(systemName: "tree.fill")),
        .dragon: DisplayRepresentation(title: "The Dragon's Tower", image: .init(systemName: "flame.fill")),
    ]

    var channel: Channel { Channel(rawValue: rawValue)! }
}

struct SelectChannelIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Channel"
    static let description = IntentDescription("Choose which Prog Radio channel to show.")

    @Parameter(title: "Channel", default: .crimson)
    var channel: ChannelOption
}

struct SelectChannelControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Channel"

    @Parameter(title: "Channel", default: .crimson)
    var channel: ChannelOption
}

/// Starts or stops a channel by handing a `progradio://` link to the app.
struct ToggleChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Stop Prog Radio"
    static let isDiscoverable = true

    @Parameter(title: "Channel")
    var channel: ChannelOption

    init() {}
    init(channel: ChannelOption) { self.channel = channel }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AppLink.toggle(channel.channel).url))
    }
}
