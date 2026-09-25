import Foundation

/// Every exact reading, one JSON object per line, so history outlives the 8 days of logs the
/// meter keeps in memory.
enum HistoryLog {
    private static var url: URL { Paths.support.appendingPathComponent("history.jsonl") }

    static func append(_ reading: ExactReading) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(reading) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: .atomic)
        }
    }

    static func load(since: Date) -> [ExactReading] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A)
            .compactMap { try? decoder.decode(ExactReading.self, from: Data($0)) }
            .filter { $0.at >= since }
    }
}

/// The subscription tiers, by how much each allows relative to Pro.
enum Plan: String, CaseIterable, Identifiable {
    case pro, max5x, max20x
    var id: String { rawValue }
    var name: String {
        switch self {
        case .pro: "Pro"
        case .max5x: "Max 5x"
        case .max20x: "Max 20x"
        }
    }
    var multiplier: Double {
        switch self {
        case .pro: 1
        case .max5x: 5
        case .max20x: 20
        }
    }
}

/// One 5-hour window, at its highest.
struct HistoryWindow: Identifiable {
    var id: Date { start }
    let start: Date
    let end: Date
    let peak: Double
    /// Backed by an exact reading, not only estimated from the logs.
    let exact: Bool
    /// Still running.
    let open: Bool
}

/// How the same usage would have gone on another plan.
struct PlanFit: Identifiable {
    var id: String { plan.rawValue }
    let plan: Plan
    let current: Bool
    let capped: Int
    let peak: Double
    let weekAtReset: Double?
    /// When this plan's weekly limit would run out at the current pace, if before the reset.
    let weekRunsOut: Date?
    /// Already past this plan's weekly limit.
    let weekOver: Bool
}

struct History {
    var windows: [HistoryWindow] = []
    var weekStart: Date?
    var weekEnd: Date?
    var weekSeries: [PacePoint] = []
    var weekNow: Double?
    var weekAtReset: Double?
    /// Points of the weekly limit per hour at the recent pace.
    var weekRate: Double?
    var plans: [PlanFit] = []
    /// When exact readings start in the history log.
    var exactSince: Date?
    var calibrated = false
}
