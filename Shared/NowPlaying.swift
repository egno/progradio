import Foundation

struct Track: Equatable, Sendable {
    let artist: String
    let title: String

    /// radio.co titles look like "Artist - Song"; a band name may itself contain " - " rarely,
    /// so only the first separator splits.
    init(radioTitle: String) {
        let parts = radioTitle.components(separatedBy: " - ")
        if parts.count >= 2 {
            artist = parts[0].trimmingCharacters(in: .whitespaces)
            title = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
        } else {
            artist = ""
            title = radioTitle.trimmingCharacters(in: .whitespaces)
        }
    }

    init(artist: String, title: String) {
        self.artist = artist
        self.title = title
    }
}

struct NowPlaying: Equatable, Sendable {
    let channel: Channel
    let isOnline: Bool
    let track: Track?
    let startedAt: Date?
    let artworkURL: URL?
    let history: [Track]
}

extension NowPlaying {
    /// Decodes the radio.co `/stations/{id}/status` payload.
    static func decode(_ data: Data, channel: Channel) throws -> NowPlaying {
        let status = try JSONDecoder().decode(StatusDTO.self, from: data)
        let current = status.current_track
        return NowPlaying(
            channel: channel,
            isOnline: status.status == "online",
            track: current.map { Track(radioTitle: $0.title) },
            startedAt: current?.start_time.flatMap(Self.parseDate),
            artworkURL: (current?.artwork_url_large ?? current?.artwork_url).flatMap(URL.init(string:)),
            // The first history entry is the current track.
            history: (status.history ?? []).dropFirst().map { Track(radioTitle: $0.title) }
        )
    }

    private static func parseDate(_ string: String) -> Date? {
        try? Date(string, strategy: .iso8601)
    }
}

private struct StatusDTO: Decodable {
    struct TrackDTO: Decodable {
        let title: String
        let start_time: String?
        let artwork_url: String?
        let artwork_url_large: String?
    }
    struct HistoryDTO: Decodable { let title: String }

    let status: String
    let current_track: TrackDTO?
    let history: [HistoryDTO]?
}
