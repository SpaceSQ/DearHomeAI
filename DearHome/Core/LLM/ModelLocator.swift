import Foundation

/// Resolves a GGUF the same way Dear Earth shares weights: App Group first, then local sandbox.
enum ModelLocator {
    static let appGroupID = EcosystemCatalog.appGroupIdentifier
    static let legacyAppGroupID = EcosystemCatalog.legacyAppGroupIdentifier

    static func firstAvailableGGUF(fileManager: FileManager = .default,
                                   sandbox: HomeSandbox = .live) -> URL? {
        let roots: [URL] = [
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
                .appendingPathComponent("models", isDirectory: true),
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: legacyAppGroupID)?
                .appendingPathComponent("models", isDirectory: true),
            sandbox.root.appendingPathComponent("models", isDirectory: true)
        ].compactMap { $0 }

        var matches: [URL] = []
        for root in roots {
            matches.append(contentsOf: allGGUF(in: root, fileManager: fileManager))
        }
        let preferred = ["Qwen3.5-2B", "Qwen3-1.7B", "Qwen3.5-0.8B", "Qwen3-0.6B"]
        for key in preferred {
            if let hit = matches.first(where: { $0.lastPathComponent.contains(key) }) { return hit }
        }
        return matches.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
    }

    private static func allGGUF(in directory: URL, fileManager: FileManager) -> [URL] {
        guard fileManager.fileExists(atPath: directory.path),
              let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        var matches: [URL] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "gguf" {
            matches.append(url)
        }
        return matches
    }
}
