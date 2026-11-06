import Foundation

protocol NowPlayingService: Sendable {
    func nowPlaying(_ channel: Channel) async throws -> NowPlaying
}

protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> Data
}

struct URLSessionHTTPClient: HTTPClient {
    var session: URLSession = .shared

    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
        return "ProgRadioMini/\(version) (https://github.com/egno/progradio)"
    }()

    func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // MusicBrainz rejects requests without an identifying User-Agent.
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

struct RadioCoService: NowPlayingService {
    var http: any HTTPClient = URLSessionHTTPClient()

    func nowPlaying(_ channel: Channel) async throws -> NowPlaying {
        async let album = http.get(channel.currentTrackURL)
        let status = try await http.get(channel.statusURL)
        var info = try NowPlaying.decode(status, channel: channel)
        // The album is a nicety: a failed request leaves it out rather than failing the update.
        if let data = try? await album {
            info.album = try? NowPlaying.decodeAlbum(data, track: info.track)
        }
        return info
    }
}
