import Foundation

/// A Prog Radio channel. The station ids and stream URLs come from progradio.com/listen.
enum Channel: String, CaseIterable, Identifiable, Codable, Sendable {
    case crimsonHall = "crimson"
    case wizardsForest = "wizard"
    case dragonsTower = "dragon"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .crimsonHall: "The Crimson Hall"
        case .wizardsForest: "The Wizard's Forest"
        case .dragonsTower: "The Dragon's Tower"
        }
    }

    var shortName: String {
        switch self {
        case .crimsonHall: "Crimson Hall"
        case .wizardsForest: "Wizard's Forest"
        case .dragonsTower: "Dragon's Tower"
        }
    }

    var symbol: String {
        switch self {
        case .crimsonHall: "building.columns.fill"
        case .wizardsForest: "tree.fill"
        case .dragonsTower: "flame.fill"
        }
    }

    /// radio.co station id.
    var stationID: String {
        switch self {
        case .crimsonHall: "s1e0b382a0"
        case .wizardsForest: "s95a101d27"
        case .dragonsTower: "s141f9a810"
        }
    }

    /// 320 kbps AAC.
    var streamURL: URL {
        switch self {
        case .crimsonHall: URL(string: "https://s4.radio.co/s1e0b382a0/listen")!
        case .wizardsForest: URL(string: "https://streamer.radio.co/s95a101d27/listen")!
        case .dragonsTower: URL(string: "https://s4.radio.co/s141f9a810/listen")!
        }
    }

    /// HLS stream the station publishes for AirPlay receivers, which handle it better than the raw stream.
    var airPlayStreamURL: URL {
        URL(string: "https://stream.progradio.com/hls/\(rawValue)_air.m3u8")!
    }

    var statusURL: URL {
        URL(string: "https://public.radio.co/stations/\(stationID)/status")!
    }
}
