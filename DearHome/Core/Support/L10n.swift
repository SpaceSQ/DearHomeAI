import Foundation

enum ContentLanguage: String, Codable, Sendable, Equatable {
    case en
    case zh
}

enum AppLanguage: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case system
    case en
    case zh

    var id: String { rawValue }

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> ContentLanguage {
        switch self {
        case .en: return .en
        case .zh: return .zh
        case .system:
            let folded = preferredLanguages.first?.lowercased() ?? "en"
            return folded.hasPrefix("zh") ? .zh : .en
        }
    }
}

struct Bilingual: Codable, Sendable, Equatable, Hashable {
    var en: String
    var zh: String

    func text(_ language: ContentLanguage) -> String {
        language == .zh ? zh : en
    }
}

func tr(_ en: String, _ zh: String, language: ContentLanguage) -> String {
    language == .zh ? zh : en
}

func tr(_ en: String, _ zh: String) -> String {
    let folded = Locale.preferredLanguages.first?.lowercased() ?? "en"
    return tr(en, zh, language: folded.hasPrefix("zh") ? .zh : .en)
}

enum LanguageDetect {
    /// Chinese in the sentence wins over the app language. A wordless tap falls back to the preference.
    static func resolve(input: String, preferred: ContentLanguage) -> ContentLanguage {
        var cjk = 0
        var latin = 0
        for scalar in input.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) {
                cjk += 1
            } else if scalar.value >= 65 && scalar.value <= 122 {
                latin += 1
            }
        }
        if cjk == 0 && latin == 0 { return preferred }
        if cjk > 0 && latin == 0 { return .zh }
        if latin > 0 && cjk == 0 { return .en }
        return cjk >= latin ? .zh : .en
    }
}
