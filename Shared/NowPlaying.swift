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

    /// Station IDs and promos are tagged with the station itself as the artist,
    /// e.g. "Prog Radio - Bronze Buffalo 3".
    var isStationBreak: Bool {
        artist.caseInsensitiveCompare("Prog Radio") == .orderedSame
    }
}

struct NowPlaying: Equatable, Sendable {
    let channel: Channel
    let isOnline: Bool
    let track: Track?
    let startedAt: Date?
    let artworkURL: URL?
    let history: [Track]
    /// From radio.co's v2 API; the status payload doesn't carry it.
    var album: String? = nil
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
            // The first history entry is the current track; station breaks aren't songs.
            history: (status.history ?? []).dropFirst().map { Track(radioTitle: $0.title) }.filter { !$0.isStationBreak }
        )
    }

    /// The album from radio.co's v2 `/{station}/track/current`, if it describes `track` (the two endpoints can
    /// disagree for a moment when a track changes).
    static func decodeAlbum(_ data: Data, track: Track?) throws -> String? {
        let current = try JSONDecoder().decode(CurrentTrackDTO.self, from: data).data
        guard let track, current.title.map(Track.init(radioTitle:)) == track, let album = current.track_album?.trimmingCharacters(in: .whitespaces),
              !album.isEmpty else { return nil }
        return album
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

private struct CurrentTrackDTO: Decodable {
    struct TrackDTO: Decodable {
        let title: String?
        let track_album: String?
    }
    let data: TrackDTO
}
