import Foundation

enum ChatRole: String, Codable, Sendable, Equatable {
    case user
    case house
}

struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    var id: UUID
    var role: ChatRole
    var text: String
    var createdAt: Date
    var source: EventSource
    var sourceLabel: Bilingual
    var suggestOnly: Bool
    var skillIDs: [String]
    var withheldAsPrivate: Bool

    init(id: UUID = UUID(),
         role: ChatRole,
         text: String,
         createdAt: Date,
         source: EventSource,
         sourceLabel: Bilingual,
         suggestOnly: Bool = false,
         skillIDs: [String] = [],
         withheldAsPrivate: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.source = source
        self.sourceLabel = sourceLabel
        self.suggestOnly = suggestOnly
        self.skillIDs = skillIDs
        self.withheldAsPrivate = withheldAsPrivate
    }
}

enum AppTab: String, Codable, CaseIterable, Identifiable, Sendable {
    case home
    case space
    case memories
    case evolution
    case setting

    var id: String { rawValue }

    func title(in language: ContentLanguage) -> String {
        switch self {
        case .home: return tr("Home", "房子", language: language)
        case .space: return tr("Space", "空间", language: language)
        case .memories: return tr("Memories", "记忆", language: language)
        case .evolution: return tr("Evolution", "演化", language: language)
        case .setting: return tr("Setting", "设置", language: language)
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .space: return "square.grid.2x2"
        case .memories: return "book.closed"
        case .evolution: return "chart.xyaxis.line"
        case .setting: return "gearshape"
        }
    }
}
