import Foundation

struct DayFeatures: Sendable, Equatable {
    var userTurns = 0
    var negativeShare = 0.0
    var controlShare = 0.0
    var climateShare = 0.0
    var shortShare = 0.0
    var counterpart: HouseholdCounterpart = .owner
}

struct EvolutionPreview: Sendable, Equatable {
    var raw: [Double]
    var applied: [Double]
    var projected: EvolutionVector
}

struct EvolutionDeltaRecord: Codable, Sendable, Equatable, Identifiable {
    var id: String { day }
    var day: String
    var before: [Double]
    var rawGradient: [Double]
    var applied: [Double]
    var after: [Double]
    var userTurns: Int
    var dominantRoleAfter: HomeRole
    var distilledAt: Date
}

/// Local reading of a day's talk. The numbers may exceed 1%. `EvolutionVector` is what enforces the cap.
/// A day with no user turns does not drift, including from the counterpart bias.
enum MidnightEvolutionEngine {
    static func features(of texts: [String], counterpart: HouseholdCounterpart) -> DayFeatures {
        var features = DayFeatures()
        features.userTurns = texts.count
        features.counterpart = counterpart
        guard !texts.isEmpty else { return features }
        let count = Double(texts.count)
        for text in texts {
            let folded = text.lowercased()
            if containsAny(folded, ["难过", "伤心", "烦", "sad", "anxious", "worried"]) {
                features.negativeShare += 1 / count
            }
            if containsAny(folded, ["打开", "关掉", "关闭", "turn on", "turn off", "调为", "调到", "set to"]) {
                features.controlShare += 1 / count
            }
            if containsAny(folded, ["空调", "温度", "湿度", "climate", "humidity", "temperature"]) {
                features.climateShare += 1 / count
            }
            if text.count <= 8 {
                features.shortShare += 1 / count
            }
        }
        return features
    }

    /// Unclamped daily gradient. Callers must pass it through `EvolutionVector.applyDailyIncrement`.
    static func rawGradient(features: DayFeatures) -> [Double] {
        var gradient = Array(repeating: 0.0, count: EvolutionVector.dimensionCount)
        guard features.userTurns > 0 else { return gradient }
        let confidence = min(1, Double(features.userTurns) / 4)
        gradient[EvolutionAxis.toneWarmth.rawValue] = 0.05 * features.negativeShare
        gradient[EvolutionAxis.speechPace.rawValue] = 0.04 * (0.5 - features.shortShare)
        gradient[EvolutionAxis.stewardshipDepth.rawValue] = 0.04 * features.controlShare
        gradient[EvolutionAxis.quietCare.rawValue] = 0.04 * features.negativeShare
        gradient[EvolutionAxis.climateKeeper.rawValue] = 0.05 * features.climateShare
        gradient[EvolutionAxis.lightKeeper.rawValue] = 0.04 * features.controlShare
        switch features.counterpart {
        case .child:
            gradient[EvolutionAxis.listener.rawValue] += 0.03
            gradient[EvolutionAxis.lightKeeper.rawValue] += 0.02
        case .owner:
            gradient[EvolutionAxis.ritualKeeper.rawValue] += 0.03
            gradient[EvolutionAxis.climateKeeper.rawValue] += 0.02
        case .partner:
            gradient[EvolutionAxis.toneWarmth.rawValue] += 0.03
            gradient[EvolutionAxis.hearthHost.rawValue] += 0.03
        case .elder:
            gradient[EvolutionAxis.quietCare.rawValue] += 0.03
            gradient[EvolutionAxis.nightWatch.rawValue] += 0.02
        case .guest:
            gradient[EvolutionAxis.hearthHost.rawValue] += 0.03
        }
        return gradient.map { $0 * confidence }
    }

    static func evolve(_ vector: EvolutionVector, gradient: [Double]) -> (vector: EvolutionVector, applied: [Double]) {
        var next = vector
        let applied = next.applyDailyIncrement(rawDeltas: gradient)
        return (next, applied)
    }

    static func preview(vector: EvolutionVector, texts: [String], counterpart: HouseholdCounterpart) -> EvolutionPreview {
        let raw = rawGradient(features: features(of: texts, counterpart: counterpart))
        let evolved = evolve(vector, gradient: raw)
        return EvolutionPreview(raw: raw, applied: evolved.applied, projected: evolved.vector)
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
