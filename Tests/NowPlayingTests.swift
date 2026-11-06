import XCTest

final class NowPlayingTests: XCTestCase {
    func testDecodesRadioCoStatus() throws {
        let json = #"""
        {"status":"online","current_track":{"title":"Rush - Heresy","start_time":"2026-11-05T15:37:28+00:00",
        "artwork_url":"https://x/100.jpg","artwork_url_large":"https://x/600.jpg"},
        "history":[{"title":"Rush - Heresy"},{"title":"Jethro Tull - Uniform"},{"title":"Untitled"}]}
        """#
        let info = try NowPlaying.decode(Data(json.utf8), channel: .crimsonHall)
        XCTAssertTrue(info.isOnline)
        XCTAssertEqual(info.track, Track(artist: "Rush", title: "Heresy"))
        XCTAssertEqual(info.artworkURL, URL(string: "https://x/600.jpg"))
        XCTAssertNotNil(info.startedAt)
        XCTAssertEqual(info.history, [Track(artist: "Jethro Tull", title: "Uniform"), Track(artist: "", title: "Untitled")])
    }

    func testHistorySkipsStationBreaks() throws {
        let json = #"""
        {"status":"online","current_track":{"title":"Prog Radio - Bronze Buffalo 3"},
        "history":[{"title":"Prog Radio - Bronze Buffalo 3"},{"title":"Renaissance - On the Frontier"},
        {"title":"PROG RADIO - Bronze Buffalo 12"},{"title":"King Crimson - Starless"}]}
        """#
        let info = try NowPlaying.decode(Data(json.utf8), channel: .wizardsForest)
        XCTAssertEqual(info.track?.isStationBreak, true)
        XCTAssertEqual(info.history, [Track(artist: "Renaissance", title: "On the Frontier"),
                                      Track(artist: "King Crimson", title: "Starless")])
    }

    func testDecodesOfflineStation() throws {
        let info = try NowPlaying.decode(Data(#"{"status":"offline","current_track":null}"#.utf8), channel: .dragonsTower)
        XCTAssertFalse(info.isOnline)
        XCTAssertNil(info.track)
        XCTAssertEqual(info.history, [])
    }

    func testTrackSplitsOnFirstSeparatorOnly() {
        XCTAssertEqual(Track(radioTitle: "Yes - Close to the Edge - Live"), Track(artist: "Yes", title: "Close to the Edge - Live"))
    }

    func testServiceUsesStationStatusURL() async throws {
        let http = FakeHTTP(body: #"{"status":"online","current_track":{"title":"A - B"}}"#)
        let info = try await RadioCoService(http: http).nowPlaying(.wizardsForest)
        XCTAssertEqual(http.requested, [URL(string: "https://public.radio.co/stations/s95a101d27/status")!])
        XCTAssertEqual(info.track, Track(artist: "A", title: "B"))
    }

    func testAppLinkRoundTrips() {
        let links: [AppLink] = [.play(.dragonsTower), .toggle(.crimsonHall), .toggle(nil), .stop, .open]
        for link in links { XCTAssertEqual(AppLink(url: link.url), link) }
        XCTAssertNil(AppLink(url: URL(string: "progradio://play/nope")!))
        XCTAssertNil(AppLink(url: URL(string: "https://play/crimson")!))
    }
}

private final class FakeHTTP: HTTPClient, @unchecked Sendable {
    let body: String
    private(set) var requested: [URL] = []
    init(body: String) { self.body = body }
    func get(_ url: URL) async throws -> Data {
        requested.append(url)
        return Data(body.utf8)
    }
}
