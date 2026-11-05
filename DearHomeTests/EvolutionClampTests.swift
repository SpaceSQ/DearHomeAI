import XCTest
@testable import DearHome

final class EvolutionClampTests: XCTestCase {
    func testHardOnePercentClamp() {
        var vector = EvolutionVector()
        let before = vector.asArray
        var deltas = Array(repeating: 0.5, count: EvolutionVector.dimensionCount)
        deltas[1] = -0.9
        deltas[2] = .nan
        let applied = vector.applyDailyIncrement(rawDeltas: deltas)
        let after = vector.asArray

        for index in after.indices {
            XCTAssertLessThanOrEqual(abs(after[index] - before[index]), EvolutionVector.maxDailyStep + 1e-12)
            XCTAssertGreaterThanOrEqual(after[index], 0)
            XCTAssertLessThanOrEqual(after[index], 1)
            XCTAssertEqual(applied[index], after[index] - before[index], accuracy: 1e-12)
        }
        XCTAssertEqual(after[0], before[0] + 0.01, accuracy: 1e-12)
        XCTAssertEqual(after[1], before[1] - 0.01, accuracy: 1e-12)
        XCTAssertEqual(after[2], before[2], accuracy: 1e-12)
    }

    func testClampRespectsZeroAndOne() {
        var ceiling = EvolutionVector(array: Array(repeating: 0.995, count: 12))
        ceiling.applyDailyIncrement(rawDeltas: Array(repeating: 0.5, count: 12))
        XCTAssertEqual(ceiling.asArray, Array(repeating: 1, count: 12))

        var floor = EvolutionVector(array: Array(repeating: 0, count: 12))
        let applied = floor.applyDailyIncrement(rawDeltas: Array(repeating: -0.5, count: 12))
        XCTAssertEqual(floor.asArray, Array(repeating: 0, count: 12))
        XCTAssertEqual(applied, Array(repeating: 0, count: 12))
    }

    func testOneHundredDaysNeverExceedsTheCap() {
        var vector = EvolutionVector(array: Array(repeating: 0.2, count: 12))
        for _ in 0..<100 {
            let before = vector.asArray
            vector.applyDailyIncrement(rawDeltas: Array(repeating: 0.5, count: 12))
            for (lhs, rhs) in zip(before, vector.asArray) {
                XCTAssertLessThanOrEqual(rhs - lhs, 0.01 + 1e-12)
                XCTAssertLessThanOrEqual(rhs, 1)
            }
        }
        XCTAssertEqual(vector.asArray, Array(repeating: 1, count: 12))
    }

    func testNamedDeltaAndNonFiniteValues() {
        var vector = EvolutionVector()
        let before = vector.toneWarmth
        vector.applyNamedDelta(["toneWarmth": 0.2, "listener": .infinity, "nope": 1])
        XCTAssertEqual(vector.toneWarmth, before + 0.01, accuracy: 1e-12)
        XCTAssertEqual(vector.listener, EvolutionVector().listener, accuracy: 1e-12)
        let clamped = OnePercentClamp.enforce(["toneWarmth": 0.5, "speechPace": .nan])
        XCTAssertEqual(clamped["toneWarmth"] ?? 0, 0.01, accuracy: 1e-12)
        XCTAssertEqual(clamped["speechPace"] ?? -1, 0, accuracy: 1e-12)
    }

    func testCounterpartBiasCannotExceedOnePercent() {
        let texts = Array(repeating: "客厅空调温度太高", count: 4)
        let features = MidnightEvolutionEngine.features(of: texts, counterpart: .owner)
        let raw = MidnightEvolutionEngine.rawGradient(features: features)
        XCTAssertGreaterThan(raw[EvolutionAxis.climateKeeper.rawValue], 0.01)
        let evolved = MidnightEvolutionEngine.evolve(EvolutionVector(), gradient: raw)
        XCTAssertLessThanOrEqual(evolved.applied.map(abs).max() ?? 0, 0.01 + 1e-12)
        XCTAssertEqual(evolved.applied[EvolutionAxis.climateKeeper.rawValue], 0.01, accuracy: 1e-12)
    }

    func testSilentDayDoesNotDrift() {
        let preview = MidnightEvolutionEngine.preview(vector: EvolutionVector(), texts: [], counterpart: .child)
        XCTAssertEqual(preview.raw, Array(repeating: 0, count: 12))
        XCTAssertEqual(preview.applied, Array(repeating: 0, count: 12))
        XCTAssertEqual(preview.projected, EvolutionVector())
    }
}
