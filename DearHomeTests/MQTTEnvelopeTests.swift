import XCTest
@testable import DearHome

final class MQTTEnvelopeTests: XCTestCase {
    func testRoundTrip() throws {
        let when = FamilyDateFormat.normalized(Date(timeIntervalSince1970: 1_761_609_600))
        let envelope = FamilyMessageEnvelope(
            familyId: "home-local",
            msgId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID(),
            ts: when,
            kind: .fact,
            room: "living_room",
            source: .appleHome,
            payload: FamilyPayload(text: "25°C", room: "living_room", device: "air_conditioner", action: "set", factTime: when),
            syncMode: .dailyMidnight,
            sensitivity: .family
        )
        let decoded = try FamilyJSON.decode(try FamilyJSON.encode(envelope))
        XCTAssertEqual(decoded, envelope)

        let object = try JSONSerialization.jsonObject(with: try FamilyJSON.encode(envelope)) as? [String: Any]
        for key in ["familyId", "msgId", "ts", "kind", "room", "source", "payload", "syncMode"] {
            XCTAssertNotNil(object?[key], key)
        }
        XCTAssertEqual(object?["kind"] as? String, "fact")
        XCTAssertEqual(object?["syncMode"] as? String, "dailyMidnight")
        XCTAssertEqual(object?["source"] as? String, "apple_home")
    }

    func testDigestAndMissingSensitivity() throws {
        let envelope = FamilyMessageEnvelope(
            familyId: "home-local",
            ts: Date(timeIntervalSince1970: 1_700_000_000),
            kind: .digest,
            room: nil,
            source: .homeAgent,
            payload: FamilyPayload(text: "day", room: nil, device: nil, action: nil, factTime: nil),
            syncMode: .realtime
        )
        var object = try JSONSerialization.jsonObject(with: try FamilyJSON.encode(envelope)) as? [String: Any]
        object?.removeValue(forKey: "sensitivity")
        let data = try JSONSerialization.data(withJSONObject: object ?? [:])
        let decoded = try FamilyJSON.decode(data)
        XCTAssertEqual(decoded.kind, .digest)
        XCTAssertNil(decoded.room)
        XCTAssertEqual(decoded.sensitivity, .family)
        XCTAssertEqual(decoded.syncMode, .realtime)
    }

    func testSealedEnvelopeIsRefusedByTheBus() {
        var bus = FamilyBus(role: .ownerGateway)
        let envelope = FamilyMessageEnvelope(
            familyId: "home-local",
            ts: Date(timeIntervalSince1970: 1_700_000_000),
            kind: .fact,
            room: nil,
            source: .thisDevice,
            payload: FamilyPayload(text: "a secret", room: nil, device: nil, action: nil, factTime: nil),
            syncMode: .realtime,
            sensitivity: .sealed
        )
        XCTAssertEqual(bus.receive(envelope), .rejectedSealed)
        XCTAssertTrue(bus.inbox.isEmpty)

        let fact = FamilyFact(source: .thisDevice, text: "秘密", sensitivity: .sealed)
        XCTAssertEqual(bus.publish(fact: fact, familyID: "home-local", now: Date()), .withheldSealed)
        XCTAssertTrue(bus.localFacts.isEmpty)
        XCTAssertTrue(bus.machine.pending.isEmpty)
        XCTAssertTrue(bus.canHostBroker)
        bus.role = .memberClient
        XCTAssertFalse(bus.canHostBroker)
    }
}
