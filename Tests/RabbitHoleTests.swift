import XCTest

final class RabbitHoleTests: XCTestCase {
    func testURLCarriesArtistMBID() {
        XCTAssertEqual(RabbitHole.url(artistMBID: "ece57992-dc2e-4f67-a269-fa43626c1a3d").absoluteString,
                       "https://www.progradio.com/rabbithole?artistMbid=ece57992-dc2e-4f67-a269-fa43626c1a3d")
    }

    func testPrefersRecordingMatch() async throws {
        let http = RoutedHTTP([
            "/ws/2/recording/": #"{"recordings":[{"score":100,"artist-credit":[{"artist":{"id":"yes-band"}}]}]}"#,
            "/ws/2/artist/": #"{"artists":[{"id":"other","score":100}]}"#,
        ])
        let id = await MusicBrainzLookup(http: http, throttle: nil).artistMBID(for: Track(artist: "Yes", title: "Roundabout"))
        XCTAssertEqual(id, "yes-band")
        XCTAssertEqual(http.requested.map { $0.path() }, ["/ws/2/recording/"])
        let query = URLComponents(url: http.requested[0], resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "query" }?.value
        XCTAssertEqual(query, #"artist:"Yes" AND recording:"Roundabout""#)
    }

    func testFallsBackToArtistWhenRecordingIsWeak() async {
        let http = RoutedHTTP([
            "/ws/2/recording/": #"{"recordings":[{"score":40,"artist-credit":[{"artist":{"id":"wrong"}}]}]}"#,
            "/ws/2/artist/": #"{"artists":[{"id":"tull","score":100}]}"#,
        ])
        let id = await MusicBrainzLookup(http: http, throttle: nil).artistMBID(for: Track(artist: "Jethro Tull", title: "Unreleased Demo"))
        XCTAssertEqual(id, "tull")
    }

    func testDetailsFromAlbumAndArtist() async {
        let http = RoutedHTTP([
            "/ws/2/release-group/": #"{"release-groups":[{"score":100,"first-release-date":"1973-01-23","artist-credit":[{"artist":{"id":"wakeman"}}]}]}"#,
            "/ws/2/artist/wakeman": #"{"id":"wakeman","country":"GB"}"#,
        ])
        let track = Track(artist: "Rick Wakeman", title: "Catherine Parr")
        let details = await MusicBrainzLookup(http: http, throttle: nil).details(for: track, album: "The Six Wives Of Henry VIII")
        XCTAssertEqual(details, TrackDetails(track: track, artistMBID: "wakeman", year: "1973", countryCode: "GB"))
        XCTAssertEqual(details?.countryFlag, "🇬🇧")
        XCTAssertEqual(http.requested.map { $0.path() }, ["/ws/2/release-group/", "/ws/2/artist/wakeman"])
    }

    func testDetailsWithoutAlbumFallBackToArtistSearch() async {
        let http = RoutedHTTP([
            "/ws/2/recording/": #"{"recordings":[]}"#,
            "/ws/2/artist/": #"{"artists":[{"id":"faun","score":100}]}"#,
            "/ws/2/artist/faun": #"{"id":"faun","country":null,"area":{"iso-3166-1-codes":["DE"]}}"#,
        ])
        let track = Track(artist: "Faun", title: "Nimue")
        let details = await MusicBrainzLookup(http: http, throttle: nil).details(for: track, album: nil)
        XCTAssertEqual(details, TrackDetails(track: track, artistMBID: "faun", year: nil, countryCode: "DE"))
    }

    func testThrottleSpacesRequests() async {
        let throttle = MusicBrainzThrottle()
        let start = ContinuousClock.now
        await throttle.wait()
        await throttle.wait()
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - start, .milliseconds(950))
    }

    func testNoMatchOrNoArtist() async {
        let http = RoutedHTTP(["/ws/2/recording/": #"{"recordings":[]}"#, "/ws/2/artist/": #"{"artists":[]}"#])
        let lookup = MusicBrainzLookup(http: http, throttle: nil)
        let unknown = await lookup.artistMBID(for: Track(artist: "Nobody", title: "Nothing"))
        let untitled = await lookup.artistMBID(for: Track(artist: "", title: "Untitled"))
        let stationID = await lookup.artistMBID(for: Track(artist: "Prog Radio", title: "Bronze Buffalo 3"))
        XCTAssertNil(unknown)
        XCTAssertNil(untitled)
        XCTAssertNil(stationID)
        XCTAssertEqual(http.requested.count, 2, "only the real artist is looked up")
    }
}

private final class RoutedHTTP: HTTPClient, @unchecked Sendable {
    let bodies: [String: String]
    private(set) var requested: [URL] = []
    init(_ bodies: [String: String]) { self.bodies = bodies }
    func get(_ url: URL) async throws -> Data {
        requested.append(url)
        guard let body = bodies[url.path()] else { throw URLError(.badServerResponse) }
        return Data(body.utf8)
    }
}
