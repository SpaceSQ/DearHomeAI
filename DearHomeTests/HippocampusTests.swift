import XCTest
@testable import DearHome

final class HippocampusTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testDayKeyAndISOWeek() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let date = formatter.date(from: "2026-10-27T12:00:00Z")!
        XCTAssertEqual(DayKey.string(for: date, calendar: calendar), "2026-10-27")
        XCTAssertEqual(ISOWeek.key(for: date, calendar: calendar), "2026-W44")
        XCTAssertEqual(ISOWeek.previousWeekKey(before: date, calendar: calendar), "2026-W43")
        let monday = ISOWeek.monday(of: "2026-W44", calendar: calendar)
        XCTAssertEqual(monday.map { DayKey.string(for: $0, calendar: calendar) }, "2026-10-26")
        XCTAssertEqual(ISOWeek.dateKeys(in: "2026-W44", calendar: calendar).first, "2026-10-26")
    }

    func testRingEvictsTheThirtyFirstDayAndWarnsThreeDaysOut() {
        let today = "2026-10-27"
        XCTAssertEqual(ThirtyDayRing.keysToEvict(dateKeys: ["2026-09-27", "2026-09-28", "2026-10-27"],
                                                  currentDateKey: today,
                                                  calendar: calendar),
                       ["2026-09-27"])
        let meta = ThirtyDayRing.metadata(
            occupants: [
                RingOccupant(dateKey: "2026-09-30", hasCompletedTask: true),
                RingOccupant(dateKey: "2026-10-26", hasCompletedTask: false)
            ],
            now: calendar.date(from: DateComponents(year: 2026, month: 10, day: 27))!,
            calendar: calendar
        )
        XCTAssertTrue(meta.exportWarning)
        XCTAssertTrue(meta.completedTaskAtRisk)
        XCTAssertEqual(meta.daysUntilOverwrite, 3)
        XCTAssertEqual(meta.hotKeys, ["2026-10-26"])
        XCTAssertEqual(meta.warmKeys, ["2026-09-30"])
        XCTAssertEqual(meta.capacity, 30)
        XCTAssertEqual(meta.hotWindowDays, 7)
    }

    func testTagWeightFormula() {
        let scored = TagWeight.effective(cumulative: 0, weekly: 4)
        XCTAssertEqual(scored.total, 4)
        XCTAssertEqual(scored.weight, 8.8 / 25, accuracy: 1e-12)
    }

    func testUnavailableModelQueuesPendingAndWritesNothing() async throws {
        let job = LocalDailyDistillJob(invoker: ScriptedSummarizer(day: "{}", week: "{}"))
        let turn = RawTurn(id: "1", agentID: HomeAgent.id, dateKey: "2026-10-26", timestamp: Date(),
                           role: "user", content: "客厅灯", source: .thisDevice, isCompletedTask: false)
        let outcome = try await job.execute(agentID: HomeAgent.id, dateKey: "2026-10-26", provider: .unavailable,
                                             turns: [turn], store: HippocampusStore(rawTurns: [turn]), now: Date())
        XCTAssertNil(outcome.result)
        XCTAssertTrue(outcome.enqueuedPending)
        XCTAssertTrue(outcome.store.summaries.isEmpty)
        XCTAssertEqual(outcome.store.pending.map(\.reason), [.noModel])
    }

    func testDistillClampsCharactersAndOnePercent() async throws {
        let long = String(repeating: "字", count: 350)
        let json = """
        {"dialogueSummary300":"\(long)","contextAndTaskSummary300":"\(long)","dailyOnePercentDelta":{"toneWarmth":0.5,"listener":-0.2}}
        """
        let job = LocalDailyDistillJob(invoker: ScriptedSummarizer(day: json, week: "{}"))
        let turn = RawTurn(id: "1", agentID: HomeAgent.id, dateKey: "2026-10-26", timestamp: Date(),
                           role: "user", content: "hello", source: .thisDevice, isCompletedTask: false)
        let outcome = try await job.execute(agentID: HomeAgent.id, dateKey: "2026-10-26", provider: .onDevice,
                                             turns: [turn], store: HippocampusStore(), now: Date())
        let result = try XCTUnwrap(outcome.result)
        XCTAssertEqual(result.dialogueSummary300.count, 300)
        XCTAssertEqual(result.contextAndTaskSummary300.count, 300)
        XCTAssertEqual(result.dailyOnePercentDelta["toneWarmth"] ?? 0, 0.01, accuracy: 1e-12)
        XCTAssertEqual(result.dailyOnePercentDelta["listener"] ?? 0, -0.01, accuracy: 1e-12)
        XCTAssertTrue(outcome.store.pending.isEmpty)
    }

    func testWeeklyConsolidationIgnoresRawTranscript() async throws {
        let spy = ScriptedSummarizer(
            day: "{}",
            week: #"{"weeklyOverview":"a quiet week","weightedTags":[{"keyword":"客厅","category":"schedule_habit","count":4}]}"#
        )
        let weekly = LocalWeeklyConsolidator(invoker: spy)
        var store = HippocampusStore()
        store.rawTurns = [RawTurn(id: "raw", agentID: HomeAgent.id, dateKey: "2026-10-20", timestamp: Date(),
                                  role: "user", content: "RAW_SENTINEL_DO_NOT_LEAK", source: .thisDevice, isCompletedTask: true)]
        store.summaries = [DailyDistilledSummary(
            summaryID: "home_01_2026-10-20", agentID: HomeAgent.id, dateKey: "2026-10-20", weekKey: "2026-W43",
            dialogueSummary300: "talk", contextTaskSummary300: "rooms", evolutionDelta: [:],
            llmSource: "onDevice", createdAt: Date()
        )]
        let outcome = try await weekly.consolidate(agentID: HomeAgent.id, weekKey: "2026-W43", provider: .onDevice,
                                                    store: store, now: Date())
        XCTAssertTrue(outcome.created)
        XCTAssertEqual(spy.weekPrompts.count, 1)
        XCTAssertFalse(spy.weekPrompts[0].contains("RAW_SENTINEL_DO_NOT_LEAK"))
        XCTAssertEqual(outcome.store.tags.first?.keyword, "客厅")
        XCTAssertEqual(outcome.store.tags.first?.weight ?? 0, 8.8 / 25, accuracy: 1e-12)
    }

    func testSkillSeedParses() {
        let skill = HomeSkillLibrary.parse("""
        ---
        id: climate
        topics: 空调, humidity
        ---
        en: Keep 25°C.
        zh: 保持 25°C。
        """)
        XCTAssertEqual(skill?.id, "climate")
        XCTAssertEqual(HomeSkillLibrary(skills: [skill].compactMap { $0 }).retrieve(query: "空调太热").map(\.id), ["climate"])
    }

    func testSuggestOnlyWriteIsRefused() async {
        let mock = MockHomeProvider()
        do {
            try await mock.performWrite(accessoryID: "living.pendant", powerOn: true)
            XCTFail("expected suggest-only refusal")
        } catch HomeKitControlError.suggestOnly {
            let snapshot = mock.snapshot(now: Date())
            XCTAssertEqual(snapshot.rooms.map(\.id), ["living_room", "dining_room"])
            XCTAssertEqual(snapshot.events.map(\.id), ["sample-living-climate", "sample-pendant-on", "sample-pendant-off", "sample-dining-voice"])
            XCTAssertTrue(HomeSuggestions.make(for: snapshot.events[0]).suggestOnly)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}

final class ScriptedSummarizer: SummarizationInvoking, @unchecked Sendable {
    var day: String
    var week: String
    var weekPrompts: [String] = []

    init(day: String, week: String) {
        self.day = day
        self.week = week
    }

    func summarizeDay(provider: HomeLLMProvider, systemPrompt: String, transcript: String) async throws -> String {
        _ = provider
        _ = systemPrompt
        _ = transcript
        return day
    }

    func summarizeWeek(provider: HomeLLMProvider, prompt: String) async throws -> String {
        _ = provider
        weekPrompts.append(prompt)
        return week
    }
}
