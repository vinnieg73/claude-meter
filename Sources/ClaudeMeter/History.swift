import Foundation

/// Every exact reading, one JSON object per line, so history outlives the 8 days of logs the
/// meter keeps in memory. Pruned to the last five weeks.
enum HistoryLog {
    private static let keep: TimeInterval = 35 * 86400

    /// One write with O_APPEND, so a line lands whole and never over another writer's. If the
    /// file doesn't end in a newline (a write cut short), one goes first so lines don't fuse.
    static func append(_ reading: ExactReading) {
        guard var line = try? JSONCoding.encoder().encode(reading) else { return }
        line.append(0x0A)
        Paths.makeSupport()
        let fd = open(Paths.history.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var last: UInt8 = 0x0A
        let size = lseek(fd, 0, SEEK_END)
        if size > 0 {
            let reader = open(Paths.history.path, O_RDONLY)
            if reader >= 0 {
                _ = pread(reader, &last, 1, size - 1)
                close(reader)
            }
        }
        if last != 0x0A { line.insert(0x0A, at: 0) }
        _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }

    /// Readings from `offset` on, and where the file ended.
    static func load(from offset: UInt64 = 0) -> (readings: [ExactReading], end: UInt64) {
        // A failed open keeps the place: reporting 0 would read the whole file again next time.
        guard let handle = try? FileHandle(forReadingFrom: Paths.history) else { return ([], offset) }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() else {
            return ([], offset)
        }
        // Stop at the last newline; a line still being written is read next time.
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return ([], offset) }
        let decoder = JSONCoding.decoder()
        let readings = data[data.startIndex...lastNewline].split(separator: 0x0A)
            .compactMap { try? decoder.decode(ExactReading.self, from: Data($0)) }
        return (readings, offset + UInt64(lastNewline - data.startIndex + 1))
    }

    /// The first line's reading: the oldest, which is all compaction needs to know whether it has
    /// anything to do (every day, nearly always nothing).
    private static func firstReading() -> ExactReading? {
        guard let handle = try? FileHandle(forReadingFrom: Paths.history) else { return nil }
        defer { try? handle.close() }
        guard let chunk = try? handle.read(upToCount: 65536), let end = chunk.firstIndex(of: 0x0A) else { return nil }
        return try? JSONCoding.decoder().decode(ExactReading.self, from: chunk[chunk.startIndex..<end])
    }

    /// Drops lines older than five weeks, once they're there to drop.
    static func compact() {
        let cutoff = Date().addingTimeInterval(-keep)
        // A first line that won't read (a write cut short) can't say, so go by the first that does,
        // or the log would never be pruned.
        var everything: [ExactReading]?
        if firstReading() == nil { everything = load().readings }
        guard let first = firstReading() ?? everything?.first, first.at < cutoff else { return }
        let readings = everything ?? load().readings
        let encoder = JSONCoding.encoder()
        var out = Data()
        for r in readings where r.at >= cutoff {
            guard let line = try? encoder.encode(r) else { continue }
            out.append(line)
            out.append(0x0A)
        }
        try? out.write(to: Paths.history, options: .atomic)
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
    /// What the plan costs a month, in US dollars.
    var monthlyPrice: Double {
        switch self {
        case .pro: 20
        case .max5x: 100
        case .max20x: 200
        }
    }
    /// One week of it: twelve months over 52 weeks.
    var weeklyPrice: Double { monthlyPrice * 12 / 52 }
}

/// This week's use at pay-as-you-go prices: this Mac's Claude Code turns, counted from the logs,
/// and what the weekly % says was used elsewhere (claude.ai, cloud sessions, other devices).
struct WeekValue {
    /// Where the week counts from (its start, or an early reset), and its reset.
    let begin: Date
    let resets: Date
    let mac: Double
    /// Nil when the weekly % shows no use beyond this Mac's, or no weekly cap is known yet.
    var elsewhere: Double?
    /// One per local day from the week's first day to the reset's, this Mac's spend only.
    var days: [ValueDay] = []
    /// This Mac's spend by model name ("Opus 5.5"), highest first.
    var models: [Row] = []

    var total: Double { mac + (elsewhere ?? 0) }
}

/// One local day of the week's value.
struct ValueDay: Identifiable {
    var id: Date { day }
    let day: Date
    /// This Mac's spend that day (elsewhere can't be split by day).
    let mac: Double
    /// Starts after now.
    let future: Bool
    /// Ends before the week counts from (an early reset later in the week).
    let before: Bool
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
    /// Whether `weekRate` is the average (exact readings over days) rather than today's pace.
    var weekRateIsAverage = false
    var plans: [PlanFit] = []
    /// When exact readings start in the history log.
    var exactSince: Date?
    var calibrated = false
    /// This week at pay-as-you-go prices. Nil without a weekly window.
    var value: WeekValue?
}
