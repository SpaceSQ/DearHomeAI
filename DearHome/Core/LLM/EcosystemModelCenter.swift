import Foundation

struct EcosystemIdentity: Sendable, Equatable, Codable {
    var keyword: String
    var displayName: String
    var bundleID: String

    static let current = EcosystemIdentity(keyword: "dearhome", displayName: "Dear Home AI", bundleID: "com.s2.dearhome")
}

enum EcosystemCatalog {
    static let appGroupIdentifier = "group.com.robotzero.shared.ai"
    static let legacyAppGroupIdentifier = "group.com.s2.dearuniverse"

    static let keywords: [String] = [
        "dearearth", "dearsage", "dearecho", "dearhome", "dearpet", "dearbody", "dearmuse", "dearalien",
        "ahomeeasy", "mhomeeasy", "khomeeasy", "xhomeeasy",
        "voltpilot", "starscope", "quoteshield", "meshdoctor", "powerark", "ghostradar",
        "elderguard", "hometwin", "solartruth", "billsniper"
    ]

    static func contains(_ keyword: String) -> Bool {
        keywords.contains(keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

enum ModelShareDecision: Equatable, Sendable {
    case ownImmediate
    case greenChannel
    case externalAllowed
    case externalRefused

    var rank: Int {
        switch self {
        case .ownImmediate: return 0
        case .greenChannel: return 1
        case .externalAllowed: return 2
        case .externalRefused: return 3
        }
    }
}

/// Priority: this app, then the 22-app green channel, then external only when the switch is on.
enum EcosystemModelScheduler {
    static func decide(currentKeyword: String, publisherKeyword: String, allowExternal: Bool) -> ModelShareDecision {
        let current = currentKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let publisher = publisherKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !publisher.isEmpty, publisher == current { return .ownImmediate }
        if EcosystemCatalog.contains(publisher) { return .greenChannel }
        return allowExternal ? .externalAllowed : .externalRefused
    }
}

enum EcosystemShareStatus: Equatable, Sendable {
    case detecting
    case channelUnavailable
    case weightFoundRuntimeUnlinked(path: String)
    case greenChannel(publisherName: String)
    case externalRefused

    func message(in language: ContentLanguage) -> String {
        switch self {
        case .detecting:
            return tr("Looking for a shared ecosystem model…", "正在检测零号生态共享大模型……", language: language)
        case .channelUnavailable:
            return tr("The shared model container is not available on this install. Chat still uses the offline house voice.",
                      "这台设备上还没有共享模型容器。对话仍使用房子的离线声音。", language: language)
        case .weightFoundRuntimeUnlinked(let path):
            let name = URL(fileURLWithPath: path).lastPathComponent
            if LlamaRuntime.isAvailable {
                return tr("Shared weight ready (\(name)). On-device llama is linked — chat uses the local model when this file loads.",
                          "共享权重已就绪（\(name)）。本机已链接 llama，加载后聊天走本地大模型。", language: language)
            }
            return tr("A shared weight is in the green channel (\(name)). This build does not link llama, so the house still answers offline.",
                      "绿色通道里已有共享权重（\(name)）。这一版没有链接 llama，所以房子仍离线回答。", language: language)
        case .greenChannel(let publisher):
            if LlamaRuntime.isAvailable {
                return tr("Local AI model sharing: green channel (via \(publisher)). On-device llama is linked.",
                          "本地 AI 模型共享：绿色通道（由 \(publisher) 提供）。本机已链接 llama。", language: language)
            }
            return tr("Local AI model sharing: mounted through the ecosystem green channel (provided by \(publisher)). The llama runtime is not linked in this build.",
                      "本地 AI 模型共享状态：已通过内部生态绿色通道挂载（由 \(publisher) 提供支持）。这一版尚未链接 llama 运行时。", language: language)
        case .externalRefused:
            return tr("An external app published a model. Sharing with apps outside the ecosystem stays off.",
                      "有外部应用发布了模型。生态之外的共享保持关闭。", language: language)
        }
    }
}

struct SharedModelDiscovery: Equatable, Sendable {
    var channelAvailable: Bool
    var legacyGroupDetected: Bool
    var mountedModelPath: String?
    var allowExternalSharing: Bool
    var status: EcosystemShareStatus

    static let pending = SharedModelDiscovery(
        channelAvailable: false,
        legacyGroupDetected: false,
        mountedModelPath: nil,
        allowExternalSharing: false,
        status: .detecting
    )
}

enum EcosystemModelCenter {
    static func scan(allowExternal: Bool, fileManager: FileManager = .default) -> SharedModelDiscovery {
        let primary = fileManager.containerURL(forSecurityApplicationGroupIdentifier: EcosystemCatalog.appGroupIdentifier)
        let legacy = fileManager.containerURL(forSecurityApplicationGroupIdentifier: EcosystemCatalog.legacyAppGroupIdentifier)
        let gguf = primary.flatMap { firstGGUF(in: $0.appendingPathComponent("models", isDirectory: true), fileManager: fileManager) }
        let publisher = primary.flatMap { readPublisher(in: $0, fileManager: fileManager) }
        let decision = publisher.map {
            EcosystemModelScheduler.decide(currentKeyword: EcosystemIdentity.current.keyword,
                                           publisherKeyword: $0.keyword,
                                           allowExternal: allowExternal)
        }
        let status: EcosystemShareStatus
        if primary == nil {
            status = .channelUnavailable
        } else if decision == .externalRefused {
            status = .externalRefused
        } else if let publisher, decision == .greenChannel || decision == .ownImmediate {
            status = .greenChannel(publisherName: publisher.displayName)
        } else if let gguf {
            status = .weightFoundRuntimeUnlinked(path: gguf)
        } else {
            status = .detecting
        }
        return SharedModelDiscovery(
            channelAvailable: primary != nil,
            legacyGroupDetected: legacy != nil,
            mountedModelPath: gguf,
            allowExternalSharing: allowExternal,
            status: status
        )
    }

    private static func firstGGUF(in directory: URL, fileManager: FileManager) -> String? {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "gguf" {
            return url.path
        }
        return nil
    }

    private struct PublisherHint {
        var keyword: String
        var displayName: String
    }

    private static func readPublisher(in container: URL, fileManager: FileManager) -> PublisherHint? {
        let url = container.appendingPathComponent("registry.json")
        guard let data = fileManager.contents(atPath: url.path),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let keyword = rows.first?["keyword"] as? String,
              !keyword.isEmpty else { return nil }
        let name = (rows.first?["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? keyword
        return PublisherHint(keyword: keyword, displayName: name)
    }
}
