import XCTest

final class ScheduleTests: XCTestCase {
    private func eastern(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testParsesEmbeddedWixRecords() throws {
        // Trimmed from progradio.com/showschedule; braces and quotes inside strings must not confuse the scanner.
        let html = #"""
        <html><script>{"appsWarmupData":{"dataBinding":{"dataStore":{"recordInfosByDatasetId":{"x":{"itemIds":["a"]}},
        "recordsByCollectionId":{"ShowsSchedule":{
          "a":{"_id":"a","showName":"What's New Proggy Cats?","showDate":"2026-11-09","showTime":"12 Noon (ET) \/ 5 PM (GMT)","channel":"Crimson Hall","description":"<p class=\"x\">{not json}<\/p>"},
          "b":{"_id":"b","showName":"Take 10 Hot Seat","showHost":"HOST: Kevin Carmony","showDate":"2026-11-04","showTime":"12 Noon (ET) \/ 5 PM (GMT)","channel":"Crimson Hall"},
          "c":{"_id":"c","showName":"Limited Shows Mar. 2 - 13","showDate":"2026-03-13"},
          "d":{"_id":"d","showName":"The Prog Corner LIVE Sunday Stream","showHost":"HOST: Scot Lade","showDate":"2026-11-08","showTime":"11 AM (ET) \/ 3 PM (GMT)","channel":"YouTube"}
        }},"uniqueFieldValuesByCollection":{}}}}}</script></html>
        """#
        let shows = try Schedule.parse(html: Data(html.utf8))
        XCTAssertEqual(shows.map(\.id), ["b", "d", "a"], "sorted by start; the notice without a time is dropped")
        XCTAssertEqual(shows[0].host, "Kevin Carmony")
        XCTAssertEqual(shows[0].channel, .crimsonHall)
        XCTAssertEqual(shows[1].channel, nil)
        XCTAssertEqual(shows[1].venue, "YouTube")
        XCTAssertEqual(shows[2].start, eastern(2026, 11, 9, 12))
    }

    func testMissingDataThrows() {
        XCTAssertThrowsError(try Schedule.parse(html: Data("<html>maintenance</html>".utf8)))
    }

    func testStartTimesUseEasternTime() {
        XCTAssertEqual(Schedule.startDate(day: "2026-11-05", time: "12 Noon (ET) / 5 PM (GMT)"), eastern(2026, 11, 5, 12))
        XCTAssertEqual(Schedule.startDate(day: "2026-11-04", time: "12 AM (ET) / 5 AM (GMT)"), eastern(2026, 11, 4, 0))
        XCTAssertEqual(Schedule.startDate(day: "2026-08-06", time: "6 PM (ET) / 10 PM (GMT)"), eastern(2026, 8, 6, 18))
        XCTAssertEqual(Schedule.startDate(day: "2026-08-06", time: "6:30 pm (ET)"), eastern(2026, 8, 6, 18, 30))
        // Daylight saving: noon ET is 16:00 UTC in summer.
        XCTAssertEqual(Schedule.startDate(day: "2026-04-14", time: "12 Noon (ET) / 4 PM (GMT)"),
                       Date(timeIntervalSince1970: 1_776_182_400))
        XCTAssertNil(Schedule.startDate(day: "2026-11-05", time: "TBA"))
    }

    func testUpcomingKeepsShowsOnAir() {
        let start = eastern(2026, 11, 5, 12)
        let show = Show(id: "1", name: "Show", host: "", venue: "Crimson Hall", channel: .crimsonHall, start: start)
        XCTAssertEqual(Schedule.upcoming([show], at: start.addingTimeInterval(3600)), [show])
        XCTAssertTrue(show.isOnAir(at: start.addingTimeInterval(3600)))
        XCTAssertEqual(Schedule.upcoming([show], at: start.addingTimeInterval(3 * 3600)), [])
    }
}

final class LinkTests: XCTestCase {
    func testSiteLinksRoundTrip() {
        for page in SitePage.allCases {
            XCTAssertEqual(AppLink(url: AppLink.site(page).url), .site(page))
        }
        XCTAssertNil(AppLink(url: URL(string: "progradio://site/nope")!))
    }

    func testTrackSearchURLs() {
        let track = Track(artist: "Yes", title: "Close to the Edge")
        XCTAssertEqual(TrackSearch.appleMusic.url(for: track).absoluteString, "https://music.apple.com/search?term=Yes%20Close%20to%20the%20Edge")
        XCTAssertEqual(TrackSearch.spotify.url(for: track).absoluteString, "https://open.spotify.com/search/Yes%20Close%20to%20the%20Edge")
        XCTAssertEqual(TrackSearch.bandcamp.url(for: track).absoluteString, "https://bandcamp.com/search?q=Yes%20Close%20to%20the%20Edge")
        XCTAssertEqual(track.displayName, "Yes – Close to the Edge")
        XCTAssertEqual(Track(artist: "", title: "Station ID").searchQuery, "Station ID")
    }
}
