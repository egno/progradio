import Foundation

/// The `progradio://` URL scheme the widgets and controls use to drive the app.
enum AppLink: Equatable, Sendable {
    case play(Channel)
    case toggle(Channel?)
    case stop
    case open

    var url: URL {
        switch self {
        case .play(let channel): URL(string: "progradio://play/\(channel.rawValue)")!
        case .toggle(let channel?): URL(string: "progradio://toggle/\(channel.rawValue)")!
        case .toggle(nil): URL(string: "progradio://toggle")!
        case .stop: URL(string: "progradio://stop")!
        case .open: URL(string: "progradio://open")!
        }
    }

    init?(url: URL) {
        guard url.scheme == "progradio", let host = url.host() else { return nil }
        let channel = url.pathComponents.dropFirst().first.flatMap(Channel.init(rawValue:))
        switch host {
        case "play":
            guard let channel else { return nil }
            self = .play(channel)
        case "toggle": self = .toggle(channel)
        case "stop": self = .stop
        case "open": self = .open
        default: return nil
        }
    }
}
