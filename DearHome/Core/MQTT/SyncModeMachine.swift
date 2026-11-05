import Foundation

enum SyncPhase: String, Codable, Sendable, Equatable {
    case idle
    case accumulating
    case exchanging
    case delivering
    case caughtUp
}

/// Owner chooses daily 00:00 or realtime. Daily facts stay on the device until the next local day.
struct SyncModeMachine: Codable, Equatable, Sendable {
    var mode: SyncMode
    var phase: SyncPhase
    var pending: [FamilyMessageEnvelope]
    var delivered: [FamilyMessageEnvelope]

    init(mode: SyncMode = .dailyMidnight,
         phase: SyncPhase = .idle,
         pending: [FamilyMessageEnvelope] = [],
         delivered: [FamilyMessageEnvelope] = []) {
        self.mode = mode
        self.phase = phase
        self.pending = pending
        self.delivered = delivered
    }

    /// Switching to realtime releases what was waiting. Switching to daily holds what is already pending.
    @discardableResult
    mutating func setMode(_ mode: SyncMode) -> [FamilyMessageEnvelope] {
        self.mode = mode
        if mode == .realtime {
            return flushPending()
        }
        phase = pending.isEmpty ? .idle : .accumulating
        return []
    }

    /// Stamps the envelope with the machine's mode. Realtime returns it now. Daily keeps it.
    @discardableResult
    mutating func ingest(_ envelope: FamilyMessageEnvelope, now: Date, calendar: Calendar = .current) -> [FamilyMessageEnvelope] {
        var stamped = envelope
        stamped.syncMode = mode
        _ = now
        _ = calendar
        if mode == .realtime {
            phase = .delivering
            delivered.append(stamped)
            phase = .caughtUp
            return [stamped]
        }
        pending.append(stamped)
        phase = .accumulating
        return []
    }

    /// At local midnight (any tick whose day is after the fact's day), daily facts are released.
    @discardableResult
    mutating func tick(now: Date, calendar: Calendar = .current) -> [FamilyMessageEnvelope] {
        if mode == .realtime {
            return flushPending()
        }
        let today = DayKey.string(for: now, calendar: calendar)
        let due = pending.filter { DayKey.string(for: $0.ts, calendar: calendar) < today }
        let keep = pending.filter { DayKey.string(for: $0.ts, calendar: calendar) >= today }
        guard !due.isEmpty else {
            phase = pending.isEmpty ? .idle : .accumulating
            return []
        }
        phase = .exchanging
        pending = keep
        delivered.append(contentsOf: due)
        phase = pending.isEmpty ? .caughtUp : .accumulating
        return due
    }

    private mutating func flushPending() -> [FamilyMessageEnvelope] {
        guard !pending.isEmpty else {
            phase = delivered.isEmpty ? .idle : .caughtUp
            return []
        }
        phase = .delivering
        let due = pending
        pending = []
        delivered.append(contentsOf: due)
        phase = .caughtUp
        return due
    }
}
