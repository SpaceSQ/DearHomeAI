import Foundation

/// North American butler / smart-home speech SOUL packed for on-device LLM prompts.
struct NAHomeSoulCorpus: Codable, Sendable, Equatable {
    var id: String
    var locale: String
    var version: Int
    var title: String?
    var purpose: String?
    var soulRules: [String]
    var tones: [NAHomeTone]
    var doNot: [String]
    var evolution: NAHomeEvolutionHook?
    var promptPack: NAHomePromptPack?
    var examples: [NAHomeExample]
    var stats: NAHomeCorpusStats?

    struct NAHomeTone: Codable, Sendable, Equatable {
        var id: String
        var guide: String
    }

    struct NAHomeExample: Codable, Sendable, Equatable {
        var topic: String?
        var role: String?
        var text: String
    }

    struct NAHomeEvolutionHook: Codable, Sendable, Equatable {
        var rule: String?
        var promptHook: String?
        var axesHints: [String: String]?
    }

    struct NAHomePromptPack: Codable, Sendable, Equatable {
        var maxChars: Int?
        var instruction: String?
    }

    struct NAHomeCorpusStats: Codable, Sendable, Equatable {
        var wordCount: Int?
        var charCount: Int?
        var exampleCount: Int?
    }

    /// Compact SOUL block for ChatML system prompts. Truncates to `budget` characters.
    func promptFragment(vector: EvolutionVector, language: ContentLanguage, budget: Int = 3200) -> String {
        let packBudget = promptPack?.maxChars ?? budget
        let limit = min(budget, packBudget)
        var lines: [String] = []
        if let instruction = promptPack?.instruction, !instruction.isEmpty {
            lines.append(instruction)
        } else {
            lines.append("Treat the following as SOUL/personality for this home. Answer, then stop.")
        }
        lines.append("SOUL rules:")
        lines.append(contentsOf: soulRules.prefix(12).map { "- \($0)" })
        if !doNot.isEmpty {
            lines.append("Boundaries:")
            lines.append(contentsOf: doNot.prefix(8).map { "- \($0)" })
        }
        lines.append(evolutionLeanLine(vector: vector, language: language))
        if let hook = evolution?.promptHook, !hook.isEmpty {
            lines.append(hook)
        }
        // Sample example lines by topic diversity for speech habits (not few-shot scripts).
        let sample = sampleExamples(limit: 14)
        if !sample.isEmpty {
            lines.append("Speech habits (paraphrase; do not copy verbatim):")
            lines.append(contentsOf: sample.map { "- \($0)" })
        }
        if language == .zh {
            lines.append("用户使用中文时用自然中文回复，但仍保持上述管家分寸与北美家居语境里的务实习惯。")
        }
        var text = lines.joined(separator: "\n")
        if text.count > limit {
            let idx = text.index(text.startIndex, offsetBy: limit)
            text = String(text[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return text
    }

    private func evolutionLeanLine(vector: EvolutionVector, language: ContentLanguage) -> String {
        let role = vector.dominantRole.title(in: .en)
        let warmth = Int((vector.toneWarmth * 100).rounded())
        let pace = Int((vector.speechPace * 100).rounded())
        let quiet = Int((vector.quietCare * 100).rounded())
        if language == .zh {
            return "今日人格偏向（每日最多 1% 漂移）：角色 \(role)；温度 \(warmth)；节奏 \(pace)；安静照料 \(quiet)。轻靠，不翻盘。"
        }
        return "Today's personality lean (≤1% daily drift): role \(role); warmth \(warmth); pace \(pace); quiet care \(quiet). Lean, do not reinvent."
    }

    private func sampleExamples(limit: Int) -> [String] {
        guard !examples.isEmpty else { return [] }
        var seenTopics = Set<String>()
        var picked: [String] = []
        // Prefer non-pad examples first.
        let ordered = examples.sorted { lhs, rhs in
            let lPad = (lhs.topic == "pad")
            let rPad = (rhs.topic == "pad")
            if lPad != rPad { return !lPad && rPad }
            return (lhs.topic ?? "") < (rhs.topic ?? "")
        }
        for item in ordered {
            let topic = item.topic ?? "general"
            if seenTopics.contains(topic), picked.count >= limit / 2 { continue }
            seenTopics.insert(topic)
            let role = item.role ?? "line"
            let line = "\(role): \(item.text)"
            picked.append(line)
            if picked.count >= limit { break }
        }
        return picked
    }
}

enum NAHomeSoulCorpusLoader {
    static func load(bundle: Bundle = .main) -> NAHomeSoulCorpus? {
        guard let url = bundle.url(forResource: "na_home_soul_corpus", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let corpus = try? JSONCoding.decoder().decode(NAHomeSoulCorpus.self, from: data) else {
            return nil
        }
        return corpus
    }
}
