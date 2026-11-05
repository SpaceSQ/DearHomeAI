import Foundation

struct ChatTurn: Sendable, Equatable {
    enum Role: String, Sendable { case user, assistant }
    let role: Role
    let content: String
    /// The daytime-log entry this turn came from, when known.
    var id: UUID?
}

/// ChatML as used by the Qwen family (same as Dear Earth).
enum ChatTemplate {
    static let emptyThink = "<think>\n\n</think>\n\n"

    static func chatML(system: String, turns: [ChatTurn], suppressThinking: Bool) -> String {
        var out = "<|im_start|>system\n\(system)<|im_end|>\n"
        for turn in turns {
            if turn.role == .user {
                out += "<|im_start|>user\n\(turn.content)<|im_end|>\n"
            } else {
                out += "<|im_start|>assistant\n\(suppressThinking ? emptyThink : "")\(turn.content)<|im_end|>\n"
            }
        }
        out += "<|im_start|>assistant\n"
        if suppressThinking { out += emptyThink }
        return out
    }
}
