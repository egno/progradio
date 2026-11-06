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

/// Resolves a track's artist to a MusicBrainz id.
struct MusicBrainzLookup: Sendable {
    var http: any HTTPClient = URLSessionHTTPClient()

    /// Searches for the recording first, which tells apart artists that share a name
    /// (there are several "Yes"), then falls back to the best artist match.
    func artistMBID(for track: Track) async -> String? {
        guard !track.artist.isEmpty, !track.isStationBreak else { return nil }
        let artist = Self.phrase(track.artist)
        if let id = await search("recording", query: "artist:\(artist) AND recording:\(Self.phrase(track.title))",
                                 decode: { try Self.recordingArtist(from: $0) }) {
            return id
        }
        return await search("artist", query: "artist:\(artist)", decode: { try Self.bestArtist(from: $0) })
    }

    private func search(_ entity: String, query: String, decode: (Data) throws -> String?) async -> String? {
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/\(entity)/")!
        components.queryItems = [
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "query", value: query),
        ]
        guard let url = components.url, let data = try? await http.get(url) else { return nil }
        return try? decode(data)
    }

    /// A Lucene phrase, so words like AND or a stray colon in a title stay literal.
    private static func phrase(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Search scores run 0–100; below this the match is usually a different band.
    static let minimumScore = 90

    static func recordingArtist(from data: Data) throws -> String? {
        try JSONDecoder().decode(RecordingSearch.self, from: data).recordings
            .first { $0.score >= minimumScore }?
            .artistCredit.first?.artist.id
    }

    static func bestArtist(from data: Data) throws -> String? {
        try JSONDecoder().decode(ArtistSearch.self, from: data).artists
            .first { $0.score >= minimumScore }?.id
    }
}

private struct ArtistSearch: Decodable {
    struct Artist: Decodable { let id: String; let score: Int }
    let artists: [Artist]
}

private struct RecordingSearch: Decodable {
    struct Recording: Decodable {
        struct Credit: Decodable {
            struct Artist: Decodable { let id: String }
            let artist: Artist
        }
        let score: Int
        let artistCredit: [Credit]

        enum CodingKeys: String, CodingKey {
            case score
            case artistCredit = "artist-credit"
        }
    }
    let recordings: [Recording]
}
