import Foundation

protocol WeeklyConsolidating: Sendable {
    func consolidate(agentID: String,
                     weekKey: String,
                     provider: HomeLLMProvider,
                     store: HippocampusStore,
                     now: Date) async throws -> WeeklyConsolidateOutcome
}

struct WeeklyConsolidateOutcome: Sendable, Equatable {
    var record: WeeklyMemoryRecord?
    var store: HippocampusStore
    var neededModel: Bool
    var created: Bool
}

/// Monday 00:00 path: read the seven daily 300+300 notes, never the raw transcript.
struct LocalWeeklyConsolidator: WeeklyConsolidating, Sendable {
    var invoker: any SummarizationInvoking

    func consolidate(agentID: String,
                     weekKey: String,
                     provider: HomeLLMProvider,
                     store: HippocampusStore,
                     now: Date) async throws -> WeeklyConsolidateOutcome {
        var store = store
        if store.weekly.contains(where: { $0.agentID == agentID && $0.weekKey == weekKey }) {
            return WeeklyConsolidateOutcome(record: store.weekly.first { $0.weekKey == weekKey },
                                            store: store, neededModel: false, created: false)
        }
        let days = store.summaries
            .filter { $0.agentID == agentID && $0.weekKey == weekKey }
            .sorted { $0.dateKey < $1.dateKey }
            .map(\.asResult)
        guard !days.isEmpty else {
            return WeeklyConsolidateOutcome(record: nil, store: store, neededModel: false, created: false)
        }
        if provider == .unavailable {
            return WeeklyConsolidateOutcome(record: nil, store: store, neededModel: true, created: false)
        }
        let body = days.map { day in
            """
            [\(day.dateKey)]
            dialogue: \(day.dialogueSummary300)
            home: \(day.contextAndTaskSummary300)
            """
        }.joined(separator: "\n")
        let prompt = """
        These are daily 300+300 distillations for \(weekKey). Do not ask for raw chat.
        Return JSON:
        "weeklyOverview": a short overview of the household week.
        "weightedTags": [{ "keyword": string, "category": string, "count": number }]
        \(body)
        """
        let raw = try await invoker.summarizeWeek(provider: provider, prompt: prompt)
        let parsed = try HippocampusJSONParser.weekly(from: raw)
        for tag in parsed.weightedTags {
            let previous = store.tags.first { $0.keyword == tag.keyword }?.cumulativeCount ?? 0
            let scored = TagWeight.effective(cumulative: previous, weekly: tag.weeklyCount)
            store.tags.removeAll { $0.keyword == tag.keyword }
            store.tags.append(StoredTag(
                keyword: tag.keyword,
                category: tag.category,
                cumulativeCount: scored.total,
                weeklyCount: tag.weeklyCount,
                weight: scored.weight,
                weekKey: weekKey
            ))
        }
        let record = WeeklyMemoryRecord(
            weekID: "\(agentID)_\(weekKey)",
            agentID: agentID,
            weekKey: weekKey,
            sevenDays: days,
            weeklyOverview: parsed.weeklyOverview,
            tags: parsed.weightedTags,
            createdAt: now
        )
        store.weekly.removeAll { $0.weekID == record.weekID }
        store.weekly.append(record)
        return WeeklyConsolidateOutcome(record: record, store: store, neededModel: false, created: true)
    }
}
