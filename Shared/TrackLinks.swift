import Foundation

/// Places to look up a track the station is playing.
enum TrackSearch: String, CaseIterable, Identifiable, Sendable {
    case appleMusic, spotify, bandcamp, youtube

    var id: String { rawValue }

    var name: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .bandcamp: "Bandcamp"
        case .youtube: "YouTube"
        }
    }

    func url(for track: Track) -> URL {
        let query = track.searchQuery
        var components: URLComponents
        switch self {
        case .appleMusic:
            components = URLComponents(string: "https://music.apple.com/search")!
            components.queryItems = [URLQueryItem(name: "term", value: query)]
        case .spotify:
            // Spotify takes the query as a path segment.
            components = URLComponents(string: "https://open.spotify.com/search")!
            components.path += "/" + query
        case .bandcamp:
            components = URLComponents(string: "https://bandcamp.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        case .youtube:
            components = URLComponents(string: "https://www.youtube.com/results")!
            components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        }
        return components.url!
    }
}

extension Track {
    /// "Artist – Title", or just the title when the artist is unknown.
    var displayName: String { artist.isEmpty ? title : "\(artist) – \(title)" }

    var searchQuery: String { artist.isEmpty ? title : "\(artist) \(title)" }
}
