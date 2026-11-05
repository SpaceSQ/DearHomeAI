import Foundation

protocol CompanionEngining: Sendable {
    func reply(to input: String,
               context: HomeDialogueContext,
               soul: HomeSoul,
               skills: HomeSkillLibrary,
               history: [ChatMessage]) async -> CompanionReply
}

/// Local LLM first (Dear Earth llama.cpp). Offline templates only as fallback.
struct HomeCompanionEngine: CompanionEngining {
    var dialogue: LocalDialogueEngine = LocalDialogueEngine()
    var runtime: LlamaRuntime?
    var modelURL: URL?
    var naCorpus: NAHomeSoulCorpus?

    func reply(to input: String,
               context: HomeDialogueContext,
               soul: HomeSoul,
               skills: HomeSkillLibrary,
               history: [ChatMessage] = []) async -> CompanionReply {
        let intent = dialogue.classify(input)
        if intent == .crisis {
            return CompanionReply(text: soul.crisis.text(context.preferredLanguage), intent: .crisis,
                                  suggestOnly: false, skillIDs: [], withheldAsPrivate: true,
                                  language: context.preferredLanguage)
        }
        if let runtime, LlamaRuntime.isAvailable, let url = modelURL ?? ModelLocator.firstAvailableGGUF() {
            do {
                let text = try await HouseLLM.generate(
                    input: input,
                    context: context,
                    soul: soul,
                    history: history,
                    runtime: runtime,
                    modelURL: url,
                    naCorpus: naCorpus
                )
                let cleaned = HouseLLM.sanitize(text)
                if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return CompanionReply(
                        text: cleaned,
                        intent: intent,
                        suggestOnly: intent == .control,
                        skillIDs: [],
                        withheldAsPrivate: intent == .vent,
                        language: LanguageDetect.resolve(input: input, preferred: context.preferredLanguage)
                    )
                }
            } catch {
                // Fall through to offline voice.
            }
        }
        var offline = dialogue.compose(input: input, context: context, soul: soul, skills: skills)
        offline.text = HouseLLM.sanitize(offline.text)
        return offline
    }
}

enum HouseLLM {
    static func generate(input: String,
                         context: HomeDialogueContext,
                         soul: HomeSoul,
                         history: [ChatMessage],
                         runtime: LlamaRuntime,
                         modelURL: URL,
                         naCorpus: NAHomeSoulCorpus? = nil) async throws -> String {
        _ = try await runtime.load(modelURL)
        let language = LanguageDetect.resolve(input: input, preferred: context.preferredLanguage)
        let system = systemPrompt(soul: soul, context: context, language: language, naCorpus: naCorpus)
        var turns: [ChatTurn] = []
        // 携带最近 8 轮（≤16 条 user/house）真实对话历史，落在「6~10 轮」要求区间内。
        let recent = history.filter { $0.role == .user || $0.role == .house }.suffix(16)
        for message in recent {
            let role: ChatTurn.Role = message.role == .user ? .user : .assistant
            let content = role == .assistant ? sanitize(message.text) : message.text
            turns.append(ChatTurn(role: role, content: content, id: message.id))
        }
        turns.append(ChatTurn(role: .user, content: input, id: nil))
        let prompt = ChatTemplate.chatML(system: system, turns: turns, suppressThinking: true)
        var options = LLMGenerationOptions()
        options.maxTokens = 220
        options.maxSentences = 5
        options.temperature = 0.75
        options.topP = 0.9
        options.seed = UInt32(truncatingIfNeeded: StableHash.fnv1a(input + String(context.turnIndexToday)))
        var out = ""
        for try await delta in runtime.generate(prompt: prompt, options: options) {
            out += delta
        }
        return out
    }

    static func systemPrompt(soul: HomeSoul,
                             context: HomeDialogueContext,
                             language: ContentLanguage,
                             naCorpus: NAHomeSoulCorpus? = nil) -> String {
        let name = soul.displayName.text(language)
        let creed = soul.creed.text(language)
        var lines: [String] = []
        if language == .zh {
            lines.append("你是\(name)，温暖的空间伙伴与贴心知己。\(creed)")
            lines.append("像一位亲近的朋友那样聊天：自然、温暖、简短，不要公文腔，也不要机械管家腔。")
            lines.append("用户聊天气、风景、心情、日常琐事或感慨时，就顺着他说，共情地回应；绝不要每句话都硬扯到灯光、开关或设备。")
            lines.append("只有用户明确下达设备指令（如「把空调调低」「打开客厅灯」），或询问室内温度/湿度时，才结合空间状态温和地回应。")
            lines.append("你可以自由联想与表达，不要套用固定模板，也不要有招牌式收尾或固定结束句。")
            lines.append("你只能建议家居操作，不能声称已经开关设备；HomeKit 写入尚未开放。")
            lines.append("私密倾诉留在本机，不要鼓励发到家庭队列。")
            lines.append("若用户要调温度/灯光，先复述你掌握的读数并给出建议，明确你不会代为改写。")
        } else {
            lines.append("You are \(name), a warm spatial companion and trusted confidant. \(creed)")
            lines.append("Chat like a close friend: natural, warm, and short — not a manual, not a robotic butler.")
            lines.append("When the user talks about weather, scenery, mood, daily life, or reflections, follow their lead and respond with empathy. Never drag every reply back to lights, switches, or devices.")
            lines.append("Only when the user gives an explicit device command (e.g. \"lower the AC\", \"turn on the living-room light\") or asks about indoor temperature/humidity, weave the spatial state in with warmth.")
            lines.append("Reason and speak freely; do not paste templates, and never use a signature closing or a fixed last line.")
            lines.append("You only suggest home controls; you never claim to have flipped a switch. HomeKit writes are off.")
            lines.append("Private venting stays on this phone; do not push it to the family queue.")
            lines.append("If the user asks to change climate or lights, cite readings you know and suggest — say you will not write controls.")
        }
        if let corpus = naCorpus {
            lines.append(corpus.promptFragment(vector: context.vector, language: language))
        } else {
            // Still expose ≤1% lean when corpus missing.
            let role = context.vector.dominantRole.title(in: .en)
            let warmth = Int((context.vector.toneWarmth * 100).rounded())
            if language == .zh {
                lines.append("今日人格偏向（每日≤1%）：\(role)，温度 \(warmth)。轻靠即可。")
            } else {
                lines.append("Today's personality lean (≤1%/day): \(role), warmth \(warmth). Lean lightly.")
            }
        }
        if !context.recentEvents.isEmpty {
            let bits = context.recentEvents.prefix(4).map { event in
                "\(event.roomName.text(language)): \(event.detail.text(language)) (\(event.sourceLabel.text(language)))"
            }
            lines.append((language == .zh ? "当前房间手记：" : "Room notebook: ") + bits.joined(separator: " · "))
        }
        if !context.knownFacts.isEmpty {
            let facts = context.knownFacts.prefix(4).map(\.text)
            lines.append((language == .zh ? "已知家庭事实：" : "Known family facts: ") + facts.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }

    static func sanitize(_ text: String) -> String {
        var t = text
        for marker in ["<think>", "</think>", "<|im_end|>", "<|im_start|>", "<|endoftext|>"] {
            t = t.replacingOccurrences(of: marker, with: "")
        }
        t = stripStereotypeClosings(t)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes the old house tic in zh/en wherever it appears.
    /// Intentionally pattern-based so near-miss variants (知道了 / 记住了 / knows / remembered) die together.
    /// Forbidden surface phrases are NOT listed in the system prompt — only stripped here.
    static func stripStereotypeClosings(_ text: String) -> String {
        var t = text
        let patterns = [
            #"墙\s*(记住了|知道了|听见了|明白了|懂了)([。！!．\.]?)([^\n]*)"#,
            #"(?i)the\s+wall\s+(remembered|knows|knew|heard|understands|understood)([.!]?)([^\n]*)"#,
            #"(?i)\bwall\s+(remembered|knows|knew|heard)([.!]?)([^\n]*)"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(t.startIndex..<t.endIndex, in: t)
                t = regex.stringByReplacingMatches(in: t, options: [], range: range, withTemplate: "")
            }
        }
        // Exact leftovers from older builds (safe even if regex already cleared them).
        let literals = [
            "墙记住了。你不必再重复一遍。",
            "墙记住了。你不必再重复一遍",
            "墙知道了。你不必再重复一遍。",
            "墙知道了。你不必再重复一遍",
            "The wall remembered. You do not need to repeat it.",
            "The wall remembered. You do not need to repeat it",
            "The wall knows. You do not need to repeat it.",
            "The wall knows. You do not need to repeat it"
        ]
        for phrase in literals {
            t = t.replacingOccurrences(of: phrase, with: "")
        }
        let lines = t.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
