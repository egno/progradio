import Foundation

/// A show from progradio.com/showschedule.
struct Show: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    /// "Kevin Carmony", without the site's "HOST:" prefix; empty when none is listed.
    let host: String
    /// Where it airs as the site writes it: a channel name or "YouTube".
    let venue: String
    let channel: Channel?
    let start: Date

    /// Shows have no end time on the site; treat one as on air for this long after it starts.
    static let assumedLength: TimeInterval = 2 * 60 * 60

    func isOnAir(at date: Date) -> Bool {
        start <= date && date < start.addingTimeInterval(Self.assumedLength)
    }
}

enum ScheduleError: Error {
    case noData
}

/// The schedule page is a Wix site with no API, but it embeds its "ShowsSchedule" collection as JSON
/// (`"dataStore": {"recordsByCollectionId": {"ShowsSchedule": {id: record}}}`), which is far sturdier
/// to read than the rendered markup.
enum Schedule {
    static let pageURL = SitePage.schedule.url
    private static let eastern = TimeZone(identifier: "America/New_York")!

    /// Shows that haven't finished yet at `date`, soonest first.
    static func upcoming(_ shows: [Show], at date: Date = .now) -> [Show] {
        shows.filter { $0.start.addingTimeInterval(Show.assumedLength) > date }.sorted { $0.start < $1.start }
    }

    static func parse(html: Data) throws -> [Show] {
        guard let json = embeddedObject(after: Data(#""dataStore":"#.utf8), in: html),
              let store = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let collections = store["recordsByCollectionId"] as? [String: Any],
              let records = collections["ShowsSchedule"] as? [String: [String: Any]]
        else { throw ScheduleError.noData }
        return records.values.compactMap(show).sorted { $0.start < $1.start }
    }

    private static func show(_ record: [String: Any]) -> Show? {
        guard let id = record["_id"] as? String,
              let name = (record["showName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
              let day = record["showDate"] as? String,
              let time = record["showTime"] as? String,
              let start = startDate(day: day, time: time)
        else { return nil } // Notices like "Limited shows…" have no time.
        let venue = (record["channel"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        var host = (record["showHost"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        if let colon = host.firstIndex(of: ":"), host[..<colon].uppercased().hasPrefix("HOST") {
            host = host[host.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return Show(id: id, name: name, host: host, venue: venue, channel: channel(venue), start: start)
    }

    static func channel(_ venue: String) -> Channel? {
        let venue = venue.lowercased()
        if venue.contains("crimson") { return .crimsonHall }
        if venue.contains("wizard") { return .wizardsForest }
        if venue.contains("dragon") { return .dragonsTower }
        return nil
    }

    /// `day` is "2026-11-05"; `time` is like "12 Noon (ET) / 5 PM (GMT)", "12 AM (ET) / 5 AM (GMT)" or
    /// "6:30 PM (ET) / …". The Eastern time is used since it accounts for daylight saving.
    static func startDate(day: String, time: String) -> Date? {
        let dayParts = day.split(separator: "-").compactMap { Int($0) }
        guard dayParts.count == 3 else { return nil }
        let eastern = time.components(separatedBy: "(ET)").first ?? time
        guard let match = eastern.firstMatch(of: #/(?i)(\d{1,2})(?::(\d{2}))?\s*(AM|PM|Noon|Midnight)/#) else { return nil }
        guard var hour = Int(match.1), (1...12).contains(hour) else { return nil }
        let minute = match.2.flatMap { Int($0) } ?? 0
        switch match.3.lowercased() {
        case "am", "midnight": if hour == 12 { hour = 0 }
        default: if hour != 12 { hour += 12 }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.eastern
        return calendar.date(from: DateComponents(
            year: dayParts[0], month: dayParts[1], day: dayParts[2], hour: hour, minute: minute))
    }

    /// The JSON object that follows `key`, found by matching braces outside of strings.
    private static func embeddedObject(after key: Data, in data: Data) -> Data? {
        guard let keyRange = data.range(of: key) else { return nil }
        let bytes = [UInt8](data[keyRange.upperBound...])
        guard let start = bytes.firstIndex(of: UInt8(ascii: "{")) else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for index in start..<bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped { escaped = false }
                else if byte == UInt8(ascii: "\\") { escaped = true }
                else if byte == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"): depth += 1
            case UInt8(ascii: "}"):
                depth -= 1
                if depth == 0 { return Data(bytes[start...index]) }
            default: break
            }
        }
        return nil
    }
}

protocol ScheduleService: Sendable {
    func shows() async throws -> [Show]
}

struct WebScheduleService: ScheduleService {
    var session: URLSession = .shared

    func shows() async throws -> [Show] {
        var request = URLRequest(url: Schedule.pageURL, timeoutInterval: 20)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try Schedule.parse(html: data)
    }
}
