import Foundation
import Observation

/// A 👍 or 👎 for a song, as progradio.com's player sends it.
enum SongVote: String, Codable, Sendable {
    case like, dislike
}

/// One request to progradio.com's `/_functions/rateSong`, the endpoint behind the thumbs on the site's player.
/// Votes are anonymous; the site keeps who voted for what only in the browser, as `SongVotes` does here.
struct SongVoteRequest: Equatable, Sendable, Encodable {
    enum Operation: String, Encodable, Sendable { case add, subtract }

    static let url = URL(string: "https://www.progradio.com/_functions/rateSong")!
    /// Shown in the station's Likes & Dislikes report where the site would send the listener's chat name.
    static let voterName = "Prog Radio Mini"

    let title: String
    let artist: String
    let voteType: SongVote
    let operation: Operation
    let uniqueId: String
    let chatName: String
    let channel: String

    init(track: Track, vote: SongVote, operation: Operation, channel: Channel, voterID: String) {
        title = track.title
        artist = track.artist
        voteType = vote
        self.operation = operation
        uniqueId = voterID
        chatName = Self.voterName
        self.channel = channel.shortName
    }
}

extension Track {
    /// The site's key for a song: artist and title run together, accents dropped, lowercased, letters and digits only.
    var voteKey: String {
        let scalars = (artist + title).decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { !(0x300...0x36F).contains($0.value) }
        return String(scalars).lowercased()
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// Station breaks and untitled tracks can't be voted on.
    var isVotable: Bool { !artist.isEmpty && !title.isEmpty && !isStationBreak }
}

/// The requests that move a song from one vote to another, in the site's order: choosing the current vote
/// again takes it back, and switching takes the old vote back before adding the new one.
func songVoteChanges(from current: SongVote?, choosing vote: SongVote) -> [(SongVote, SongVoteRequest.Operation)] {
    if current == vote { return [(vote, .subtract)] }
    if let current { return [(current, .subtract), (vote, .add)] }
    return [(vote, .add)]
}

protocol SongVoteSender: Sendable {
    func send(_ request: SongVoteRequest) async throws
}

struct ProgRadioVoteSender: SongVoteSender {
    var session: URLSession = .shared

    func send(_ vote: SongVoteRequest) async throws {
        var request = URLRequest(url: SongVoteRequest.url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(URLSessionHTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(vote)
        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
    }
}

/// This listener's votes, kept in user defaults by song key.
@MainActor
@Observable
final class SongVotes {
    private static let votesKey = "songVotes"
    private static let voterIDKey = "songVoterID"

    private(set) var votes: [String: SongVote]
    /// Keys of songs with a vote on its way.
    private(set) var sending: Set<String> = []
    /// The song whose last vote failed to send.
    private(set) var failedKey: String?

    private let sender: any SongVoteSender
    private let defaults: UserDefaults

    init(sender: any SongVoteSender = ProgRadioVoteSender(), defaults: UserDefaults = .standard) {
        self.sender = sender
        self.defaults = defaults
        votes = (defaults.data(forKey: Self.votesKey))
            .flatMap { try? JSONDecoder().decode([String: SongVote].self, from: $0) } ?? [:]
    }

    func vote(for track: Track) -> SongVote? { votes[track.voteKey] }

    func isSending(_ track: Track) -> Bool { sending.contains(track.voteKey) }

    func error(for track: Track) -> String? { failedKey == track.voteKey ? "Couldn't send the vote" : nil }

    /// Likes or dislikes `track`, or takes the vote back if it's already the one chosen.
    func choose(_ vote: SongVote, for track: Track, on channel: Channel) async {
        let key = track.voteKey
        guard track.isVotable, !key.isEmpty, !sending.contains(key) else { return }
        sending.insert(key)
        defer { sending.remove(key) }
        failedKey = nil
        // Each request is recorded as soon as it succeeds, so a failure halfway through a switch leaves no vote
        // rather than one the station never counted.
        for (type, operation) in songVoteChanges(from: votes[key], choosing: vote) {
            let request = SongVoteRequest(track: track, vote: type, operation: operation, channel: channel, voterID: voterID)
            do {
                try await sender.send(request)
            } catch {
                failedKey = key
                return
            }
            votes[key] = operation == .add ? type : nil
            save()
        }
    }

    /// A random 9-character id like the one the site makes for each browser.
    private var voterID: String {
        if let id = defaults.string(forKey: Self.voterIDKey) { return id }
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let id = String((0..<9).map { _ in alphabet.randomElement()! })
        defaults.set(id, forKey: Self.voterIDKey)
        return id
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(votes), forKey: Self.votesKey)
    }
}
