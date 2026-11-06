import Foundation

/// progradio.com's Rabbit Hole DB, keyed by MusicBrainz artist id.
enum RabbitHole {
    static let home = URL(string: "https://www.progradio.com/rabbithole")!

    static func url(artistMBID: String) -> URL {
        var components = URLComponents(url: home, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "artistMbid", value: artistMBID)]
        return components.url!
    }
}
