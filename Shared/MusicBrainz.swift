import Foundation

/// What MusicBrainz adds to a track the station announces.
struct TrackDetails: Equatable, Sendable {
    let track: Track
    var artistMBID: String?
    /// Year the album first came out.
    var year: String?
    /// ISO 3166 code of the artist's country, e.g. "GB".
    var countryCode: String?

    var countryName: String? {
        countryCode.flatMap { Locale.current.localizedString(forRegionCode: $0) }
    }

    /// 🇬🇧 for "GB".
    var countryFlag: String? {
        guard let code = countryCode?.uppercased(), code.count == 2, code.allSatisfy(\.isASCII) else { return nil }
        let scalars = code.unicodeScalars.compactMap { Unicode.Scalar(0x1F1E6 - 0x41 + $0.value) }
        return String(String.UnicodeScalarView(scalars))
    }
}

/// MusicBrainz asks clients to keep to about one request per second.
actor MusicBrainzThrottle {
    static let shared = MusicBrainzThrottle()
    private var next = ContinuousClock.now

    func wait() async {
        let slot = max(next, .now)
        next = slot + .seconds(1)
        try? await Task.sleep(until: slot)
    }
}

/// Looks up tracks on musicbrainz.org.
struct MusicBrainzLookup: Sendable {
    var http: any HTTPClient = URLSessionHTTPClient()
    var throttle: MusicBrainzThrottle? = .shared

    /// The artist, the album's year and the artist's country, as far as MusicBrainz knows them.
    func details(for track: Track, album: String?) async -> TrackDetails? {
        guard !track.artist.isEmpty, !track.isStationBreak else { return nil }
        var details = TrackDetails(track: track)
        if let album, !album.isEmpty,
           let group = await search("release-group",
                                    query: "artist:\(Self.phrase(track.artist)) AND releasegroup:\(Self.phrase(album))",
                                    decode: Self.bestReleaseGroup) {
            details.year = group.year
            details.artistMBID = group.artistMBID
        }
        if details.artistMBID == nil {
            details.artistMBID = await artistMBID(for: track)
        }
        if let id = details.artistMBID {
            details.countryCode = await get("artist/\(id)", decode: Self.artistCountry)
        }
        return details
    }

    /// Searches for the recording first, which tells apart artists that share a name
    /// (there are several "Yes"), then falls back to the best artist match.
    func artistMBID(for track: Track) async -> String? {
        guard !track.artist.isEmpty, !track.isStationBreak else { return nil }
        let artist = Self.phrase(track.artist)
        if let id = await search("recording", query: "artist:\(artist) AND recording:\(Self.phrase(track.title))",
                                 decode: Self.recordingArtist) {
            return id
        }
        return await search("artist", query: "artist:\(artist)", decode: Self.bestArtist)
    }

    // MARK: Requests

    private func search<T>(_ entity: String, query: String, decode: (Data) throws -> T?) async -> T? {
        await get(entity + "/", query: [URLQueryItem(name: "limit", value: "5"), URLQueryItem(name: "query", value: query)],
                  decode: decode)
    }

    private func get<T>(_ path: String, query: [URLQueryItem] = [], decode: (Data) throws -> T?) async -> T? {
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/" + path)!
        components.queryItems = [URLQueryItem(name: "fmt", value: "json")] + query
        guard let url = components.url else { return nil }
        await throttle?.wait()
        guard let data = try? await http.get(url) else { return nil }
        return try? decode(data)
    }

    /// A Lucene phrase, so words like AND or a stray colon in a title stay literal.
    private static func phrase(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: Decoding

    /// Search scores run 0–100; below this the match is usually a different band or album.
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

    static func bestReleaseGroup(from data: Data) throws -> (year: String?, artistMBID: String?)? {
        guard let group = try JSONDecoder().decode(ReleaseGroupSearch.self, from: data).releaseGroups
            .first(where: { $0.score >= minimumScore }) else { return nil }
        let year = group.firstReleaseDate.map { String($0.prefix(4)) }.flatMap { $0.count == 4 ? $0 : nil }
        return (year, group.artistCredit.first?.artist.id)
    }

    static func artistCountry(from data: Data) throws -> String? {
        let artist = try JSONDecoder().decode(ArtistDTO.self, from: data)
        return artist.country ?? artist.area?.iso31661Codes?.first
    }
}

private struct Credit: Decodable {
    struct Artist: Decodable { let id: String }
    let artist: Artist
}

private struct ArtistSearch: Decodable {
    struct Artist: Decodable { let id: String; let score: Int }
    let artists: [Artist]
}

private struct RecordingSearch: Decodable {
    struct Recording: Decodable {
        let score: Int
        let artistCredit: [Credit]
        enum CodingKeys: String, CodingKey { case score, artistCredit = "artist-credit" }
    }
    let recordings: [Recording]
}

private struct ReleaseGroupSearch: Decodable {
    struct Group: Decodable {
        let score: Int
        let firstReleaseDate: String?
        let artistCredit: [Credit]
        enum CodingKeys: String, CodingKey {
            case score, firstReleaseDate = "first-release-date", artistCredit = "artist-credit"
        }
    }
    let releaseGroups: [Group]
    enum CodingKeys: String, CodingKey { case releaseGroups = "release-groups" }
}

private struct ArtistDTO: Decodable {
    struct Area: Decodable {
        let iso31661Codes: [String]?
        enum CodingKeys: String, CodingKey { case iso31661Codes = "iso-3166-1-codes" }
    }
    let country: String?
    let area: Area?
}
