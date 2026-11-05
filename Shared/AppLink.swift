import Foundation

/// Pages on progradio.com the widgets link to.
enum SitePage: String, CaseIterable, Sendable {
    case schedule, request, history, chat, support

    var url: URL {
        switch self {
        case .schedule: URL(string: "https://www.progradio.com/showschedule")!
        case .request: URL(string: "https://www.progradio.com/req")!
        case .history: URL(string: "https://www.progradio.com/songhistory")!
        case .chat: URL(string: "https://progradio.com/chat")!
        case .support: URL(string: "https://www.progradio.com/supporters")!
        }
    }

    var title: String {
        switch self {
        case .schedule: "Schedule"
        case .request: "Request"
        case .history: "History"
        case .chat: "Chat"
        case .support: "Support"
        }
    }

    var symbol: String {
        switch self {
        case .schedule: "calendar"
        case .request: "music.note.list"
        case .history: "clock.arrow.circlepath"
        case .chat: "bubble.left.and.bubble.right.fill"
        case .support: "heart.fill"
        }
    }
}

/// The `progradio://` URL scheme the widgets and controls use to drive the app.
enum AppLink: Equatable, Sendable {
    case play(Channel)
    case toggle(Channel?)
    case stop
    case open
    /// Opens a progradio.com page in the browser.
    case site(SitePage)

    var url: URL {
        switch self {
        case .play(let channel): URL(string: "progradio://play/\(channel.rawValue)")!
        case .toggle(let channel?): URL(string: "progradio://toggle/\(channel.rawValue)")!
        case .toggle(nil): URL(string: "progradio://toggle")!
        case .stop: URL(string: "progradio://stop")!
        case .open: URL(string: "progradio://open")!
        case .site(let page): URL(string: "progradio://site/\(page.rawValue)")!
        }
    }

    init?(url: URL) {
        guard url.scheme == "progradio", let host = url.host() else { return nil }
        let argument = url.pathComponents.dropFirst().first
        let channel = argument.flatMap(Channel.init(rawValue:))
        switch host {
        case "play":
            guard let channel else { return nil }
            self = .play(channel)
        case "toggle": self = .toggle(channel)
        case "stop": self = .stop
        case "open": self = .open
        case "site":
            guard let page = argument.flatMap(SitePage.init(rawValue:)) else { return nil }
            self = .site(page)
        default: return nil
        }
    }
}
