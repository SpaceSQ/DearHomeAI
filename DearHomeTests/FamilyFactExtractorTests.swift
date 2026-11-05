import XCTest
@testable import DearHome

final class FamilyFactExtractorTests: XCTestCase {
    private let extractor = RuleBasedFamilyFactExtractor()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testChineseLivingRoomClimate() {
        let now = Date(timeIntervalSince1970: 1_761_609_600)
        let facts = extractor.extract(
            from: "客厅空调 07:00 调为 25°C，湿度 60%，风速 1 档",
            now: now,
            source: .appleHome,
            calendar: calendar
        )
        XCTAssertEqual(facts.count, 1)
        guard let fact = facts.first else { return }
        XCTAssertEqual(fact.room, "living_room")
        XCTAssertEqual(fact.device, "air_conditioner")
        XCTAssertEqual(fact.action, "set")
        XCTAssertEqual(fact.sensitivity, .family)
        let parts = calendar.dateComponents([.hour, .minute], from: fact.time ?? now)
        XCTAssertEqual(parts.hour, 7)
        XCTAssertEqual(parts.minute, 0)
    }

    func testEnglishDiningRoomLight() {
        let now = Date(timeIntervalSince1970: 1_761_609_600)
        let facts = extractor.extract(
            from: "Daughter turned on the dining room light at 11:15",
            now: now,
            source: .voice,
            calendar: calendar
        )
        XCTAssertEqual(facts.count, 1)
        guard let fact = facts.first else { return }
        XCTAssertEqual(fact.room, "dining_room")
        XCTAssertEqual(fact.device, "light")
        XCTAssertEqual(fact.action, "turn_on")
        let parts = calendar.dateComponents([.hour, .minute], from: fact.time ?? now)
        XCTAssertEqual(parts.hour, 11)
        XCTAssertEqual(parts.minute, 15)
    }

    func testQuestionsAndConfessionsStayHome() {
        let now = Date()
        XCTAssertTrue(extractor.extract(from: "客厅怎么样", now: now, source: .thisDevice, calendar: calendar).isEmpty)
        XCTAssertTrue(extractor.extract(from: "这是一个秘密，我今天很难过", now: now, source: .thisDevice, calendar: calendar).isEmpty)
        XCTAssertTrue(extractor.extract(from: "I'm sad, please turn off the living room light", now: now, source: .thisDevice, calendar: calendar).isEmpty)
    }

    func testOfflineHouseRefusesToClaimTheSwitch() {
        let engine = LocalDialogueEngine()
        let context = HomeDialogueContext(
            now: Date(timeIntervalSince1970: 1_761_609_600),
            preferredLanguage: .zh,
            vector: EvolutionVector(),
            recentEvents: MockHomeProvider().snapshot(now: Date(timeIntervalSince1970: 1_761_609_600), calendar: calendar).events,
            knownFacts: [],
            turnIndexToday: 3,
            counterpart: .owner,
            calendar: calendar
        )
        let reply = engine.compose(
            input: "把客厅空调调到24度",
            context: context,
            soul: .fallback,
            skills: HomeSkillLibrary(skills: HomeSkill.fallback)
        )
        XCTAssertEqual(reply.intent, .control)
        XCTAssertTrue(reply.suggestOnly)
        XCTAssertTrue(reply.text.contains("建议"))
        XCTAssertFalse(reply.text.contains("已为你打开"))
        XCTAssertFalse(reply.withheldAsPrivate)

        let vent = engine.compose(input: "我很难过", context: context, soul: .fallback, skills: HomeSkillLibrary(skills: HomeSkill.fallback))
        XCTAssertTrue(vent.withheldAsPrivate)
        XCTAssertFalse(vent.suggestOnly)
    }
}
