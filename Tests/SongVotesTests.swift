import XCTest

final class SongVotesTests: XCTestCase {
    func testVoteKeyMatchesSite() {
        // The site: (artist + title).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]/g, "")
        XCTAssertEqual(Track(artist: "Måneskin & Björk", title: "Café: Part II (Live)").voteKey, "maneskinbjorkcafepartiilive")
        XCTAssertEqual(Track(artist: "Yes", title: "Close to the Edge").voteKey, "yesclosetotheedge")
    }

    func testStationBreaksAreNotVotable() {
        XCTAssertFalse(Track(radioTitle: "Prog Radio - Bronze Buffalo 3").isVotable)
        XCTAssertFalse(Track(radioTitle: "Untitled").isVotable)
        XCTAssertTrue(Track(radioTitle: "Camel - Lady Fantasy").isVotable)
    }

    func testChangesFollowSite() {
        func ops(_ current: SongVote?, _ vote: SongVote) -> [String] {
            songVoteChanges(from: current, choosing: vote).map { "\($0.1.rawValue) \($0.0.rawValue)" }
        }
        XCTAssertEqual(ops(nil, .like), ["add like"])
        XCTAssertEqual(ops(.like, .like), ["subtract like"])
        XCTAssertEqual(ops(.like, .dislike), ["subtract like", "add dislike"])
    }

    func testRequestBody() throws {
        let request = SongVoteRequest(track: Track(artist: "Camel", title: "Lady Fantasy"), vote: .like, operation: .add,
                                      channel: .wizardsForest, voterID: "abc123xyz")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: String]
        XCTAssertEqual(json, [
            "title": "Lady Fantasy", "artist": "Camel", "voteType": "like", "operation": "add",
            "uniqueId": "abc123xyz", "chatName": "Prog Radio Mini", "channel": "Wizard's Forest",
        ])
    }

    @MainActor
    func testSwitchingVoteSendsAndPersists() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let sender = RecordingSender()
        let track = Track(artist: "Camel", title: "Lady Fantasy")

        let votes = SongVotes(sender: sender, defaults: defaults)
        await votes.choose(.like, for: track, on: .crimsonHall)
        await votes.choose(.dislike, for: track, on: .crimsonHall)
        XCTAssertEqual(votes.vote(for: track), .dislike)
        XCTAssertEqual(sender.sent.map { "\($0.operation.rawValue) \($0.voteType.rawValue)" },
                       ["add like", "subtract like", "add dislike"])
        XCTAssertEqual(Set(sender.sent.map(\.uniqueId)).count, 1)
        XCTAssertEqual(sender.sent.first?.uniqueId.count, 9)

        // Remembered across launches.
        XCTAssertEqual(SongVotes(sender: sender, defaults: defaults).vote(for: track), .dislike)
    }

    @MainActor
    func testFailedSendKeepsVoteAndReportsError() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let sender = RecordingSender()
        sender.fails = true
        let track = Track(artist: "Camel", title: "Lady Fantasy")

        let votes = SongVotes(sender: sender, defaults: defaults)
        await votes.choose(.like, for: track, on: .crimsonHall)
        XCTAssertNil(votes.vote(for: track))
        XCTAssertNotNil(votes.error(for: track))
        XCTAssertNil(votes.error(for: Track(artist: "Yes", title: "Awaken")))
    }
}

private final class RecordingSender: SongVoteSender, @unchecked Sendable {
    var sent: [SongVoteRequest] = []
    var fails = false

    func send(_ request: SongVoteRequest) async throws {
        if fails { throw URLError(.notConnectedToInternet) }
        sent.append(request)
    }
}
