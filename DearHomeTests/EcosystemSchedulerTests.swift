import XCTest
@testable import DearHome

final class EcosystemSchedulerTests: XCTestCase {
    func testPriorityOrder() {
        XCTAssertEqual(
            EcosystemModelScheduler.decide(currentKeyword: "dearhome", publisherKeyword: "dearhome", allowExternal: false),
            .ownImmediate
        )
        XCTAssertEqual(
            EcosystemModelScheduler.decide(currentKeyword: "dearhome", publisherKeyword: "dearearth", allowExternal: false),
            .greenChannel
        )
        XCTAssertEqual(
            EcosystemModelScheduler.decide(currentKeyword: "dearhome", publisherKeyword: "Some Other App", allowExternal: false),
            .externalRefused
        )
        XCTAssertEqual(
            EcosystemModelScheduler.decide(currentKeyword: "dearhome", publisherKeyword: "Some Other App", allowExternal: true),
            .externalAllowed
        )
        XCTAssertTrue(EcosystemCatalog.contains("dearhome"))
        XCTAssertEqual(EcosystemCatalog.keywords.count, 22)
        XCTAssertEqual(EcosystemIdentity.current.bundleID, "com.s2.dearhome")
        XCTAssertEqual(EcosystemCatalog.appGroupIdentifier, "group.com.robotzero.shared.ai")
        XCTAssertEqual(EcosystemCatalog.legacyAppGroupIdentifier, "group.com.s2.dearuniverse")
        // llama.xcframework is linked in this target; availability is a Bool.
        _ = LlamaRuntime.isAvailable
    }

    func testCharBudgetCountsCharacters() {
        XCTAssertEqual(CharBudget.limit(String(repeating: "字", count: 350), to: 300).count, 300)
        XCTAssertEqual(CharBudget.limit("short", to: 300), "short")
    }
}
