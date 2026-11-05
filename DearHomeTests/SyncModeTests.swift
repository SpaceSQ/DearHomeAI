import XCTest
@testable import DearHome

final class SyncModeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func instant(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text) ?? Date(timeIntervalSince1970: 0)
    }

    private func envelope(ts: Date, mode: SyncMode = .realtime) -> FamilyMessageEnvelope {
        FamilyMessageEnvelope(
            familyId: "home-local",
            ts: ts,
            kind: .event,
            room: "dining_room",
            source: .voice,
            payload: FamilyPayload(text: "light on", room: "dining_room", device: "light", action: "turn_on", factTime: ts),
            syncMode: mode
        )
    }

    func testRealtimeDeliversImmediately() {
        var machine = SyncModeMachine(mode: .realtime)
        let now = instant("2026-10-27T15:00:00Z")
        let sent = machine.ingest(envelope(ts: now), now: now, calendar: calendar)
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(machine.pending.isEmpty)
        XCTAssertEqual(machine.delivered.count, 1)
        XCTAssertEqual(machine.phase, .caughtUp)
        XCTAssertEqual(sent[0].syncMode, .realtime)
    }

    func testDailyHoldsUntilTheNextLocalMidnight() {
        var machine = SyncModeMachine(mode: .dailyMidnight)
        let afternoon = instant("2026-10-27T15:00:00Z")
        let stamped = envelope(ts: afternoon, mode: .realtime)
        let immediate = machine.ingest(stamped, now: afternoon, calendar: calendar)
        XCTAssertTrue(immediate.isEmpty)
        XCTAssertEqual(machine.phase, .accumulating)
        XCTAssertEqual(machine.pending.count, 1)
        XCTAssertEqual(machine.pending[0].syncMode, .dailyMidnight, "The owner's mode wins over the envelope's old mode.")

        let evening = instant("2026-10-27T23:30:00Z")
        XCTAssertTrue(machine.tick(now: evening, calendar: calendar).isEmpty)
        XCTAssertEqual(machine.pending.count, 1)

        let midnight = instant("2026-10-28T00:00:00Z")
        let released = machine.tick(now: midnight, calendar: calendar)
        XCTAssertEqual(released.map(\.msgId), [stamped.msgId])
        XCTAssertTrue(machine.pending.isEmpty)
        XCTAssertEqual(machine.phase, .caughtUp)
        XCTAssertEqual(machine.delivered.count, 1)
    }

    func testSwitchingToRealtimeFlushesTheQueue() {
        var machine = SyncModeMachine(mode: .dailyMidnight)
        let now = instant("2026-10-27T08:00:00Z")
        _ = machine.ingest(envelope(ts: now), now: now, calendar: calendar)
        _ = machine.ingest(envelope(ts: now), now: now, calendar: calendar)
        let flushed = machine.setMode(.realtime)
        XCTAssertEqual(flushed.count, 2)
        XCTAssertTrue(machine.pending.isEmpty)
        XCTAssertEqual(machine.mode, .realtime)
        XCTAssertEqual(machine.phase, .caughtUp)

        let later = machine.ingest(envelope(ts: now), now: now, calendar: calendar)
        XCTAssertEqual(later.count, 1)
    }

    func testSwitchingToDailyDoesNotRepublish() {
        var machine = SyncModeMachine(mode: .realtime)
        let now = instant("2026-10-27T08:00:00Z")
        _ = machine.ingest(envelope(ts: now), now: now, calendar: calendar)
        let republished = machine.setMode(.dailyMidnight)
        XCTAssertTrue(republished.isEmpty)
        XCTAssertEqual(machine.delivered.count, 1)
        XCTAssertEqual(machine.phase, .idle)
    }
}
