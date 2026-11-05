import XCTest
@testable import DearHome

final class HouseLLMSanitizeTests: XCTestCase {
    func testStripsWallKnowsAndRememberedVariants() {
        let samples = [
            "客厅现在大约 26°C。\n\n墙知道了。",
            "好的，我记下了。墙记住了。你不必再重复一遍。",
            "I can suggest seventy-one.\nThe wall knows.",
            "Done for now. The wall remembered. You do not need to repeat it.",
            "Wall remembered.",
            "普通回复，没有刻板收尾。"
        ]
        let cleaned = samples.map { HouseLLM.sanitize($0) }
        XCTAssertEqual(cleaned[0], "客厅现在大约 26°C。")
        XCTAssertFalse(cleaned[1].contains("墙"))
        XCTAssertEqual(cleaned[2], "I can suggest seventy-one.")
        XCTAssertFalse(cleaned[3].lowercased().contains("wall"))
        XCTAssertEqual(cleaned[4], "")
        XCTAssertEqual(cleaned[5], "普通回复，没有刻板收尾。")
    }

    func testNACorpusPromptFragmentIsBoundedAndUseful() {
        guard let url = Bundle.main.url(forResource: "na_home_soul_corpus", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let corpus = try? JSONCoding.decoder().decode(NAHomeSoulCorpus.self, from: data) else {
            // Simulator test host should include the resource after xcodegen; skip soft if missing in odd hosts.
            XCTAssertNotNil(NAHomeSoulCorpusLoader.load(), "na_home_soul_corpus.json must ship in the app bundle")
            return
        }
        XCTAssertGreaterThanOrEqual(corpus.stats?.wordCount ?? 0, 4500)
        let fragment = corpus.promptFragment(vector: EvolutionVector(), language: .en, budget: 3200)
        XCTAssertFalse(fragment.isEmpty)
        XCTAssertLessThanOrEqual(fragment.count, 3300)
        XCTAssertTrue(fragment.contains("SOUL") || fragment.lowercased().contains("personality") || fragment.contains("- "))
        XCTAssertFalse(fragment.contains("墙知道了"))
        XCTAssertFalse(fragment.lowercased().contains("the wall knows"))
    }
}
