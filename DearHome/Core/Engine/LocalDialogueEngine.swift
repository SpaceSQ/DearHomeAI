import Foundation

enum HomeDialogueIntent: String, Codable, Sendable, Equatable {
    case greeting
    case smalltalk
    case vent
    case climate
    case lighting
    case control
    case memory
    case crisis
    case unknown
}

struct HomeDialogueContext: Sendable, Equatable {
    var now: Date
    var preferredLanguage: ContentLanguage
    var vector: EvolutionVector
    var recentEvents: [SpaceEvent]
    var knownFacts: [FamilyFact]
    var turnIndexToday: Int
    var counterpart: HouseholdCounterpart
    var calendar: Calendar = .current

    static func == (lhs: HomeDialogueContext, rhs: HomeDialogueContext) -> Bool {
        lhs.now == rhs.now
            && lhs.preferredLanguage == rhs.preferredLanguage
            && lhs.vector == rhs.vector
            && lhs.recentEvents == rhs.recentEvents
            && lhs.knownFacts == rhs.knownFacts
            && lhs.turnIndexToday == rhs.turnIndexToday
            && lhs.counterpart == rhs.counterpart
    }
}

struct CompanionReply: Sendable, Equatable {
    var text: String
    var intent: HomeDialogueIntent
    var suggestOnly: Bool
    var skillIDs: [String]
    var withheldAsPrivate: Bool
    var language: ContentLanguage
}

/// Offline house voice. No model weights. Control answers always carry the suggest-only line.
struct LocalDialogueEngine: Sendable {
    func compose(input: String,
                 context: HomeDialogueContext,
                 soul: HomeSoul,
                 skills: HomeSkillLibrary) -> CompanionReply {
        let language = LanguageDetect.resolve(input: input, preferred: context.preferredLanguage)
        let intent = classify(input)
        let seed = StableHash.fnv1a(input + "#" + String(context.turnIndexToday) + Shichen.of(context.now, calendar: context.calendar).rawValue)
        if intent == .crisis {
            return CompanionReply(text: soul.crisis.text(language), intent: .crisis, suggestOnly: false,
                                  skillIDs: [], withheldAsPrivate: true, language: language)
        }

        var parts: [String] = []
        var skillIDs: [String] = []
        if context.turnIndexToday <= 1, intent == .greeting || intent == .smalltalk || intent == .unknown {
            parts.append(soul.greeting(for: Shichen.of(context.now, calendar: context.calendar), language: language))
        }

        if intent == .vent {
            parts.append(soul.listening.text(language))
        } else if intent == .memory {
            parts.append(memoryLine(context: context, soul: soul, language: language, query: input))
        } else if intent == .control {
            // 仅明确的设备指令才检索技能并引用房间手记；绝不把闲聊/天气/心情强行拽回设备话题。
            let recalled = skills.retrieve(query: input, limit: 1)
            if let skill = recalled.first {
                parts.append(skill.body.text(language))
                skillIDs.append(skill.id)
            }
            if let cited = cite(events: context.recentEvents, query: input, language: language, calendar: context.calendar) {
                parts.append(cited)
            }
        } else {
            // greeting / smalltalk / unknown —— 像朋友一样自由回应，不强制套用任何设备技能。
            if intent == .greeting, parts.isEmpty {
                parts.append(soul.greeting(for: Shichen.of(context.now, calendar: context.calendar), language: language))
            } else if !soul.smalltalk.isEmpty {
                let index = Int(seed % UInt64(soul.smalltalk.count))
                parts.append(soul.smalltalk[index].text(language))
            }
        }

        let suggestOnly = intent == .control
        if suggestOnly {
            parts.append(soul.suggestDisclaimer.text(language))
        }
        // No automatic closings. Offline replies should end when the answer ends (same rule as HouseLLM).

        let text = parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
        return CompanionReply(
            text: text.isEmpty ? soul.creed.text(language) : text,
            intent: intent,
            suggestOnly: suggestOnly,
            skillIDs: skillIDs,
            withheldAsPrivate: intent == .vent,
            language: language
        )
    }

    func classify(_ input: String) -> HomeDialogueIntent {
        let folded = input.lowercased()
        if containsAny(folded, ["自杀", "不想活", "结束生命", "suicide", "kill myself"]) {
            return .crisis
        }
        if containsAny(folded, ["秘密", "难过", "伤心", "倾诉", "抑郁", "分手", "哭了", "secret", "confidential", "depressed", "heartbroken", "i feel sad", "i'm sad", "im sad"]) {
            return .vent
        }
        if containsAny(folded, ["记得", "今天发生", "早上发生", "what happened", "this morning", "remember"]) {
            return .memory
        }
        // 仅明确的设备指令才进入控制意图。天气/风景/心情/顺口提到「灯/空调」都不再被硬编码强制关联。
        if looksLikeCommand(folded) { return .control }
        if containsAny(folded, ["你好", "您好", "早安", "晚安", "hello", "hi", "good morning", "good evening"]) {
            return .greeting
        }
        return folded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .unknown : .smalltalk
    }

    private func looksLikeCommand(_ text: String) -> Bool {
        containsAny(text, ["打开", "关掉", "关闭", "调为", "调到", "设为", "调低", "调高", "调暖", "调凉", "降一点", "升一点", "开一点", "关一点", "turn on", "turn off", "switch on", "switch off", "set to", "set the", "lower", "raise", "cooler", "warmer", "turn down", "turn up"])
    }

    private func memoryLine(context: HomeDialogueContext, soul: HomeSoul, language: ContentLanguage, query: String) -> String {
        let calendar = context.calendar
        let events = context.recentEvents.sorted { $0.occurredAt < $1.occurredAt }
        let relevant = events.filter { event in
            let blob = (event.roomName.en + event.roomName.zh + event.title.en + event.title.zh).lowercased()
            let folded = query.lowercased()
            if folded.contains("餐厅") || folded.contains("dining") { return blob.contains("餐厅") || blob.contains("dining") }
            if folded.contains("客厅") || folded.contains("living") { return blob.contains("客厅") || blob.contains("living") }
            return true
        }
        let chosen = (relevant.isEmpty ? events : relevant).prefix(4)
        if chosen.isEmpty { return soul.memoryEmpty.text(language) }
        let lines = chosen.map { event -> String in
            let clock = clockString(event.occurredAt, calendar: calendar)
            return "\(clock)  \(event.title.text(language)) · \(event.sourceLabel.text(language))"
        }
        let head = tr("Here is what I kept from the rooms.", "这些是我从房间里留下的。", language: language)
        return ([head] + lines).joined(separator: "\n")
    }

    private func cite(events: [SpaceEvent], query: String, language: ContentLanguage, calendar: Calendar) -> String? {
        let folded = query.lowercased()
        guard containsAny(folded, ["客厅", "餐厅", "living", "dining", "吊灯", "空调"]) else { return nil }
        let match = events.first { event in
            let blob = (event.roomName.zh + event.roomName.en + event.detail.zh + event.title.zh).lowercased()
            if folded.contains("餐厅") || folded.contains("dining") {
                return blob.contains("餐厅") || blob.contains("dining")
            }
            if folded.contains("客厅") || folded.contains("living") || folded.contains("空调") || folded.contains("吊灯") {
                return blob.contains("客厅") || blob.contains("living")
            }
            return false
        }
        guard let match else { return nil }
        let clock = clockString(match.occurredAt, calendar: calendar)
        return tr("The notebook says \(clock): \(match.detail.en) (\(match.sourceLabel.en)).",
                  "手记上写着 \(clock)：\(match.detail.zh)（\(match.sourceLabel.zh)）。",
                  language: language)
    }

    private func clockString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
