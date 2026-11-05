import Foundation

enum PublishOutcome: Equatable, Sendable {
    case withheldSealed
    case held(FamilyMessageEnvelope)
    case delivered(FamilyMessageEnvelope)
}

enum ReceiveOutcome: Equatable, Sendable {
    case stored
    case rejectedSealed
}

/// In-memory family bus. The owner's phone is the gateway host; members only enqueue toward it.
struct FamilyBus: Codable, Equatable, Sendable {
    var role: FamilyTransportRole
    var machine: SyncModeMachine
    var inbox: [FamilyMessageEnvelope]
    var localFacts: [FamilyFact]

    var canHostBroker: Bool { role.canHostBroker }

    init(role: FamilyTransportRole = .ownerGateway,
         machine: SyncModeMachine = SyncModeMachine(),
         inbox: [FamilyMessageEnvelope] = [],
         localFacts: [FamilyFact] = []) {
        self.role = role
        self.machine = machine
        self.inbox = inbox
        self.localFacts = localFacts
    }

    mutating func publish(fact: FamilyFact, familyID: String, now: Date, calendar: Calendar = .current) -> PublishOutcome {
        guard fact.sensitivity == .family else { return .withheldSealed }
        let envelope = FamilyMessageEnvelope(
            familyId: familyID,
            ts: now,
            kind: fact.origin,
            room: fact.room,
            source: fact.source,
            payload: FamilyPayload(
                text: fact.text,
                room: fact.room,
                device: fact.device,
                action: fact.action,
                factTime: fact.time.map(FamilyDateFormat.normalized)
            ),
            syncMode: machine.mode,
            sensitivity: .family
        )
        localFacts.append(fact)
        let outbound = machine.ingest(envelope, now: now, calendar: calendar)
        if let sent = outbound.first {
            return .delivered(sent)
        }
        return .held(envelope)
    }

    mutating func receive(_ envelope: FamilyMessageEnvelope) -> ReceiveOutcome {
        guard envelope.sensitivity == .family else { return .rejectedSealed }
        inbox.append(envelope)
        return .stored
    }

    @discardableResult
    mutating func tick(now: Date, calendar: Calendar = .current) -> [FamilyMessageEnvelope] {
        machine.tick(now: now, calendar: calendar)
    }

    @discardableResult
    mutating func setMode(_ mode: SyncMode) -> [FamilyMessageEnvelope] {
        machine.setMode(mode)
    }
}
