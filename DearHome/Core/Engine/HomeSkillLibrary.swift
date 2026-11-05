import Foundation

struct HomeSkill: Sendable, Equatable, Identifiable {
    var id: String
    var topics: [String]
    var body: Bilingual

    static let fallback: [HomeSkill] = [
        HomeSkill(
            id: "climate",
            topics: ["空调", "温度", "湿度", "风速", "热", "冷", "climate", "humidity", "temperature", "air conditioner"],
            body: Bilingual(
                en: "The living room likes a gentle climate. A reading I trust is 25°C, 60% humidity, and the fan on its first step. If you want it cooler or warmer, say the room and the number. I will suggest it, not apply it.",
                zh: "客厅适合温和的气候。我信任的一组读数是 25°C、湿度 60%、风速 1 档。你想再凉一点或暖一点，告诉我房间和数字。我只建议，不去改。"
            )
        ),
        HomeSkill(
            id: "lighting",
            topics: ["灯", "吊灯", "开灯", "关灯", "墙面开关", "开关", "light", "lights", "lamp", "pendant", "switch"],
            body: Bilingual(
                en: "Lights in this house have a source. A pendant can be opened from a family phone, and a wall switch can close it again. I will tell you who touched it when I know. I will not flip it myself.",
                zh: "这所房子里的灯都有来处。吊灯可以从家人的手机打开，墙面开关也可以再把它关掉。我知道是谁动的时候，会告诉你。我不会自己去按。"
            )
        ),
        HomeSkill(
            id: "family_rhythm",
            topics: ["家人", "爸爸", "女儿", "主人", "餐厅", "客厅", "family", "daughter", "dad", "owner", "dining"],
            body: Bilingual(
                en: "Mornings often start in the living room around 07:00, and the dining room light sometimes answers a voice near 11:15. I share a note only when it is a household fact.",
                zh: "清晨常常从客厅的 07:00 开始，餐厅的灯有时会在 11:15 前后应答一声语音。只有家庭信息，我才会拿去共享。"
            )
        ),
        HomeSkill(
            id: "privacy",
            topics: ["秘密", "难过", "倾诉", "隐私", "secret", "private", "confession", "mqtt", "同步"],
            body: Bilingual(
                en: "Household facts may ride the family gateway. A confession does not. Each phone may drift at most one percent a day.",
                zh: "家庭信息可以经过家庭网关。倾诉不会。每台手机每天最多漂百分之一。"
            )
        )
    ]
}

struct HomeSkillLibrary: Sendable, Equatable {
    var skills: [HomeSkill]

    static func load(bundle: Bundle = .main) -> HomeSkillLibrary {
        let urls = bundle.urls(forResourcesWithExtension: "md", subdirectory: "Skills") ?? []
        let parsed = urls.compactMap { url -> HomeSkill? in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return parse(text)
        }.sorted { $0.id < $1.id }
        if parsed.isEmpty { return HomeSkillLibrary(skills: HomeSkill.fallback) }
        return HomeSkillLibrary(skills: parsed)
    }

    func retrieve(query: String, limit: Int = 2) -> [HomeSkill] {
        let folded = query.lowercased()
        let ranked = skills.compactMap { skill -> (HomeSkill, Int)? in
            let score = skill.topics.reduce(0) { partial, topic in
                partial + (folded.contains(topic.lowercased()) ? 1 : 0)
            }
            return score > 0 ? (skill, score) : nil
        }.sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0.id < rhs.0.id }
            return lhs.1 > rhs.1
        }
        return ranked.prefix(max(0, limit)).map(\.0)
    }

    static func parse(_ text: String) -> HomeSkill? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let open = lines.firstIndex(of: "---"),
              let close = lines[(open + 1)...].firstIndex(of: "---") else { return nil }
        var id = ""
        var topics: [String] = []
        for line in lines[(open + 1)..<close] {
            if let value = line.value(after: "id:") { id = value }
            if let value = line.value(after: "topics:") {
                topics = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
        }
        var en: [String] = []
        var zh: [String] = []
        var bucket: String?
        for line in lines[(close + 1)...] {
            if line.hasPrefix("en:") {
                bucket = "en"
                en.append(String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("zh:") {
                bucket = "zh"
                zh.append(String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            } else if let bucket {
                if bucket == "en" { en.append(line) } else { zh.append(line) }
            }
        }
        let bodyEN = en.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyZH = zh.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !bodyEN.isEmpty, !bodyZH.isEmpty else { return nil }
        return HomeSkill(id: id, topics: topics, body: Bilingual(en: bodyEN, zh: bodyZH))
    }
}

private extension String {
    func value(after prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
}
