import Foundation

protocol SummarizationInvoking: Sendable {
    func summarizeDay(provider: HomeLLMProvider, systemPrompt: String, transcript: String) async throws -> String
    func summarizeWeek(provider: HomeLLMProvider, prompt: String) async throws -> String
}

protocol DailyDistilling: Sendable {
    func execute(agentID: String,
                 dateKey: String,
                 provider: HomeLLMProvider,
                 turns: [RawTurn],
                 store: HippocampusStore,
                 now: Date) async throws -> DailyDistillOutcome
}

struct DailyDistillOutcome: Sendable, Equatable {
    var result: DailySummaryResult?
    var store: HippocampusStore
    var enqueuedPending: Bool
}

/// 00:00 job: 300 characters of talk + 300 characters of the house, and a ≤1% delta.
/// When no model is available the day is queued. Nothing is invented.
struct LocalDailyDistillJob: DailyDistilling, Sendable {
    var invoker: any SummarizationInvoking

    func execute(agentID: String,
                 dateKey: String,
                 provider: HomeLLMProvider,
                 turns: [RawTurn],
                 store: HippocampusStore,
                 now: Date) async throws -> DailyDistillOutcome {
        var store = store
        if let existing = store.summary(agentID: agentID, dateKey: dateKey) {
            store.removePending(agentID: agentID, dateKey: dateKey)
            return DailyDistillOutcome(result: existing.asResult, store: store, enqueuedPending: false)
        }
        if provider == .unavailable {
            store.enqueuePending(agentID: agentID, dateKey: dateKey, reason: .noModel, now: now)
            return DailyDistillOutcome(result: nil, store: store, enqueuedPending: true)
        }
        let prompt = """
        Summarize the household day \(dateKey) as JSON with exactly these keys:
        "dialogueSummary300": at most 300 characters of what was said, without small talk filler.
        "contextAndTaskSummary300": at most 300 characters of rooms, devices, schedule, and finished tasks.
        "dailyOnePercentDelta": an object of personality axis deltas, each number inside [-0.01, 0.01].
        Do not rewrite long-term tags. Do not invent a day that is not in the transcript.
        """
        let transcript = turns.map { turn in
            "[\(turn.dateKey)] \(turn.role): \(turn.content)"
        }.joined(separator: "\n")
        let raw = try await invoker.summarizeDay(provider: provider, systemPrompt: prompt, transcript: transcript)
        let parsed = try HippocampusJSONParser.daily(from: raw, dateKey: dateKey)
        let limited = DailySummaryResult(
            dateKey: dateKey,
            dialogueSummary300: CharBudget.limit(parsed.dialogueSummary300, to: 300),
            contextAndTaskSummary300: CharBudget.limit(parsed.contextAndTaskSummary300, to: 300),
            dailyOnePercentDelta: OnePercentClamp.enforce(parsed.dailyOnePercentDelta)
        )
        let row = DailyDistilledSummary(
            summaryID: "\(agentID)_\(dateKey)",
            agentID: agentID,
            dateKey: dateKey,
            weekKey: ISOWeek.key(forDateKey: dateKey),
            dialogueSummary300: limited.dialogueSummary300,
            contextTaskSummary300: limited.contextAndTaskSummary300,
            evolutionDelta: limited.dailyOnePercentDelta,
            llmSource: provider.rawValue,
            createdAt: now
        )
        store.save(summary: row)
        return DailyDistillOutcome(result: limited, store: store, enqueuedPending: false)
    }
}

struct HomeSummarizationInvoker: SummarizationInvoking {
    func summarizeDay(provider: HomeLLMProvider, systemPrompt: String, transcript: String) async throws -> String {
        try refuseUntilRuntimeLinked(provider)
    }

    func summarizeWeek(provider: HomeLLMProvider, prompt: String) async throws -> String {
        try refuseUntilRuntimeLinked(provider)
    }

    private func refuseUntilRuntimeLinked(_ provider: HomeLLMProvider) throws -> String {
        if provider == .unavailable { throw HippocampusError.llmUnavailable }
        throw HippocampusError.runtimeNotLinked
    }
}
