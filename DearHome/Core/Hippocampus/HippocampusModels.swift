import Foundation

enum HomeAgent {
    static let id = "home_01"
}

enum HomeLLMProvider: String, Codable, Sendable, Equatable {
    case unavailable
    case sharedAppGroup
    case onDevice
    case appleIntelligence
    case cloudAPI
}

enum PendingReason: String, Codable, Sendable, Equatable {
    case noModel = "no_model"
    case runtimeNotLinked = "runtime_not_linked"
    case parseFailed = "parse_failed"
}

struct PendingDistillation: Codable, Sendable, Equatable, Identifiable {
    var agentID: String
    var dateKey: String
    var enqueuedAt: Date
    var reason: PendingReason

    var id: String { "\(agentID)|\(dateKey)" }
}

struct RawTurn: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var agentID: String
    var dateKey: String
    var timestamp: Date
    var role: String
    var content: String
    var source: EventSource
    var isCompletedTask: Bool
}

struct DailySummaryResult: Codable, Sendable, Equatable {
    var dateKey: String
    var dialogueSummary300: String
    var contextAndTaskSummary300: String
    var dailyOnePercentDelta: [String: Double]
}

struct DailyDistilledSummary: Codable, Sendable, Equatable, Identifiable {
    var summaryID: String
    var agentID: String
    var dateKey: String
    var weekKey: String
    var dialogueSummary300: String
    var contextTaskSummary300: String
    var evolutionDelta: [String: Double]
    var llmSource: String
    var createdAt: Date

    var id: String { summaryID }

    var asResult: DailySummaryResult {
        DailySummaryResult(dateKey: dateKey,
                           dialogueSummary300: dialogueSummary300,
                           contextAndTaskSummary300: contextTaskSummary300,
                           dailyOnePercentDelta: evolutionDelta)
    }
}

struct WeightedMemoryTag: Codable, Sendable, Equatable, Identifiable {
    var keyword: String
    var category: String
    var weeklyCount: Int
    var id: String { keyword }
}

struct WeeklyLLMResult: Sendable, Equatable {
    var weeklyOverview: String
    var weightedTags: [WeightedMemoryTag]
}

struct WeeklyMemoryRecord: Codable, Sendable, Equatable, Identifiable {
    var weekID: String
    var agentID: String
    var weekKey: String
    var sevenDays: [DailySummaryResult]
    var weeklyOverview: String
    var tags: [WeightedMemoryTag]
    var createdAt: Date

    var id: String { weekID }
}

struct StoredTag: Codable, Sendable, Equatable, Identifiable {
    var keyword: String
    var category: String
    var cumulativeCount: Int
    var weeklyCount: Int
    var weight: Double
    var weekKey: String

    var id: String { keyword }
}

struct HippocampusStore: Codable, Sendable, Equatable {
    var rawTurns: [RawTurn] = []
    var summaries: [DailyDistilledSummary] = []
    var weekly: [WeeklyMemoryRecord] = []
    var tags: [StoredTag] = []
    var pending: [PendingDistillation] = []
    var deltas: [EvolutionDeltaRecord] = []

    func summary(agentID: String, dateKey: String) -> DailyDistilledSummary? {
        summaries.first { $0.agentID == agentID && $0.dateKey == dateKey }
    }

    func turns(agentID: String, dateKey: String) -> [RawTurn] {
        rawTurns.filter { $0.agentID == agentID && $0.dateKey == dateKey }
            .sorted { $0.timestamp < $1.timestamp }
    }

    var occupiedDateKeys: [String] {
        Array(Set(rawTurns.map(\.dateKey) + summaries.map(\.dateKey))).sorted()
    }

    mutating func enqueuePending(agentID: String, dateKey: String, reason: PendingReason, now: Date) {
        pending.removeAll { $0.agentID == agentID && $0.dateKey == dateKey }
        pending.append(PendingDistillation(agentID: agentID, dateKey: dateKey, enqueuedAt: now, reason: reason))
    }

    mutating func removePending(agentID: String, dateKey: String) {
        pending.removeAll { $0.agentID == agentID && $0.dateKey == dateKey }
    }

    mutating func save(summary: DailyDistilledSummary) {
        summaries.removeAll { $0.summaryID == summary.summaryID }
        summaries.append(summary)
        summaries.sort { $0.dateKey < $1.dateKey }
        removePending(agentID: summary.agentID, dateKey: summary.dateKey)
    }

    mutating func evictRawTurns(dateKeys: [String]) {
        guard !dateKeys.isEmpty else { return }
        let drop = Set(dateKeys)
        rawTurns.removeAll { drop.contains($0.dateKey) }
    }
}

enum TagWeight {
    /// effective = cumulative × 0.7 + this week's count × 1.5, then scaled by 25 and capped at 1.
    static func effective(cumulative: Int, weekly: Int) -> (total: Int, weight: Double) {
        let total = cumulative + weekly
        let raw = Double(total) * 0.7 + Double(weekly) * 1.5
        return (total, min(1, raw / 25))
    }
}

enum HippocampusJSONParser {
    static func daily(from raw: String, dateKey: String) throws -> DailySummaryResult {
        let object = try jsonObject(from: raw)
        let dialogue = object["dialogueSummary300"] as? String ?? ""
        let context = object["contextAndTaskSummary300"] as? String ?? ""
        var delta: [String: Double] = [:]
        if let box = object["dailyOnePercentDelta"] as? [String: Any] {
            for (key, value) in box {
                if let number = value as? NSNumber {
                    delta[key] = number.doubleValue
                }
            }
        }
        return DailySummaryResult(dateKey: dateKey,
                                  dialogueSummary300: dialogue,
                                  contextAndTaskSummary300: context,
                                  dailyOnePercentDelta: delta)
    }

    static func weekly(from raw: String) throws -> WeeklyLLMResult {
        let object = try jsonObject(from: raw)
        let overview = object["weeklyOverview"] as? String ?? ""
        var tags: [WeightedMemoryTag] = []
        let rows = object["weightedTags"] as? [[String: Any]] ?? []
        for row in rows {
            let keyword = (row["keyword"] as? String) ?? (row["tag"] as? String) ?? ""
            guard !keyword.isEmpty else { continue }
            let category = (row["category"] as? String) ?? "topic"
            let count = Self.intValue(row["count"]) ?? Self.intValue(row["weeklyCount"]) ?? 0
            tags.append(WeightedMemoryTag(keyword: keyword, category: category, weeklyCount: count))
        }
        return WeeklyLLMResult(weeklyOverview: overview, weightedTags: tags)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private static func jsonObject(from raw: String) throws -> [String: Any] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            body = String(trimmed[start...end])
        } else {
            body = trimmed
        }
        guard let data = body.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HippocampusError.parse("not a JSON object")
        }
        return object
    }
}

enum HippocampusError: Error, Equatable, Sendable {
    case parse(String)
    case llmUnavailable
    case runtimeNotLinked
}

struct RingOccupant: Sendable, Equatable {
    var dateKey: String
    var hasCompletedTask: Bool
}

struct ThirtyDayRingMetadata: Sendable, Equatable {
    var capacity: Int
    var hotWindowDays: Int
    var occupied: Int
    var oldestKey: String?
    var newestKey: String?
    var daysUntilOverwrite: Int?
    var exportWarning: Bool
    var completedTaskAtRisk: Bool
    var hotKeys: [String]
    var warmKeys: [String]
}

enum ThirtyDayRing {
    static let capacity = 30
    static let hotWindow = 7
    static let exportLeadDays = 3

    static func metadata(occupants: [RingOccupant], now: Date, calendar: Calendar = .current) -> ThirtyDayRingMetadata {
        let current = DayKey.string(for: now, calendar: calendar)
        let unique = Dictionary(occupants.map { ($0.dateKey, $0.hasCompletedTask) }, uniquingKeysWith: { $0 || $1 })
        var hot: [String] = []
        var warm: [String] = []
        var soonest: Int?
        var taskRisk = false
        for (key, task) in unique {
            guard let age = DayKey.ageInDays(of: key, current: current, calendar: calendar), age >= 0 else { continue }
            if age < hotWindow {
                hot.append(key)
            } else if age < capacity {
                warm.append(key)
            }
            let remaining = capacity - age
            if remaining > 0 && remaining <= exportLeadDays {
                soonest = min(soonest ?? remaining, remaining)
                if task { taskRisk = true }
            }
        }
        let kept = (hot + warm).sorted()
        return ThirtyDayRingMetadata(
            capacity: capacity,
            hotWindowDays: hotWindow,
            occupied: kept.count,
            oldestKey: kept.first,
            newestKey: kept.last,
            daysUntilOverwrite: soonest,
            exportWarning: soonest != nil,
            completedTaskAtRisk: taskRisk,
            hotKeys: hot.sorted(),
            warmKeys: warm.sorted()
        )
    }

    /// Keys whose age is at least 30 days are dropped. The ring then holds today and the 29 days before it.
    static func keysToEvict(dateKeys: [String], currentDateKey: String, calendar: Calendar = .current) -> [String] {
        dateKeys.filter { key in
            guard let age = DayKey.ageInDays(of: key, current: currentDateKey, calendar: calendar) else { return false }
            return age >= capacity
        }.sorted()
    }
}
