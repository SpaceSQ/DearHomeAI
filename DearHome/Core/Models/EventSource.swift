import Foundation

/// Where a household fact came from. Wire values stay stable for the family envelope.
enum EventSource: String, Codable, Sendable, Equatable, CaseIterable {
    case appleHome = "apple_home"
    case familyApp = "family_app"
    case homeAgent = "home_agent"
    case voice
    case thisDevice = "this_device"

    func label(in language: ContentLanguage, deviceName: String = "") -> String {
        switch self {
        case .appleHome:
            return tr("Apple Home", "Apple 智能家居", language: language)
        case .familyApp:
            return tr("Family app", "家人 APP", language: language)
        case .homeAgent:
            return tr("This house", "这所房子", language: language)
        case .voice:
            return tr("Voice", "语音", language: language)
        case .thisDevice:
            let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return tr("This iPhone", "这台 iPhone", language: language)
            }
            return trimmed
        }
    }
}
