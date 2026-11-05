import Foundation

struct HomePreferences: Codable, Sendable, Equatable {
    var language: AppLanguage = .system
    var useSampleHome: Bool = true
    var role: FamilyTransportRole = .ownerGateway
    var syncMode: SyncMode = .dailyMidnight
    var familyID: String = "home-local"
    var deviceName: String = ""
    var allowExternalSharing: Bool = false
    var counterpart: HouseholdCounterpart = .owner
    var vector: EvolutionVector = EvolutionVector()
    var baseline: EvolutionVector = EvolutionVector()
    var greeted: Bool = false
}

/// Local account session backed by "Sign in with Apple". The Apple user identifier ties this
/// on-device profile to a real Apple ID. Signing out flips `isBound` to false but keeps every file;
/// deleting the account wipes the data and the stored Apple identity.
struct AccountState: Codable, Sendable, Equatable {
    var isBound: Bool = true
    var appleUserID: String?
    var givenName: String?
    var familyName: String?
    var email: String?
}

/// 100% on-device under Application Support/DearHome/.
struct HomeSandbox: Sendable {
    var root: URL

    static let live: HomeSandbox = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return HomeSandbox(root: base.appendingPathComponent("DearHome", isDirectory: true))
    }()

    private var fm: FileManager { .default }

    var profileDirectory: URL { root.appendingPathComponent("UserProfile", isDirectory: true) }
    var preferencesURL: URL { profileDirectory.appendingPathComponent("preferences.json") }
    var agentDirectory: URL { root.appendingPathComponent("HomeAgent/\(HomeAgent.id)", isDirectory: true) }
    var metaURL: URL { agentDirectory.appendingPathComponent("agent_meta.json") }
    var logsDirectory: URL { agentDirectory.appendingPathComponent("DaytimeLogs", isDirectory: true) }
    var memoriesDirectory: URL { agentDirectory.appendingPathComponent("Memories_MD", isDirectory: true) }
    var evolutionDirectory: URL { agentDirectory.appendingPathComponent("Evolution_History", isDirectory: true) }
    var familyDirectory: URL { root.appendingPathComponent("FamilyLayer", isDirectory: true) }
    var busURL: URL { familyDirectory.appendingPathComponent("bus.json") }
    var hippocampusDirectory: URL { root.appendingPathComponent("Hippocampus", isDirectory: true) }
    var memoryURL: URL { hippocampusDirectory.appendingPathComponent("memory.json") }
    var messagesURL: URL { root.appendingPathComponent("messages.json") }
    var exportDirectory: URL { memoriesDirectory.appendingPathComponent("Exports", isDirectory: true) }
    var accountURL: URL { profileDirectory.appendingPathComponent("account.json") }

    func prepare() throws {
        for url in [root, profileDirectory, agentDirectory, logsDirectory, memoriesDirectory, evolutionDirectory, familyDirectory, hippocampusDirectory, exportDirectory] {
            if !fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
        var rootURL = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? rootURL.setResourceValues(values)
    }

    func loadPreferences() -> HomePreferences? {
        read(HomePreferences.self, from: preferencesURL)
    }

    func save(preferences: HomePreferences) throws {
        try write(preferences, to: preferencesURL)
        try write(AgentMetaMirror(vector: preferences.vector, dominantRole: preferences.vector.dominantRole), to: metaURL)
    }

    func loadStore() -> HippocampusStore? {
        read(HippocampusStore.self, from: memoryURL)
    }

    func save(store: HippocampusStore) throws {
        try write(store, to: memoryURL)
        let grouped = Dictionary(grouping: store.rawTurns, by: \.dateKey)
        let lineEncoder = JSONEncoder()
        lineEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        lineEncoder.dateEncodingStrategy = .iso8601
        if let existing = try? fm.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil) {
            for url in existing where url.lastPathComponent.hasPrefix("raw_") && url.pathExtension == "jsonl" {
                let day = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "raw_", with: "")
                if grouped[day] == nil { try? fm.removeItem(at: url) }
            }
        }
        for (day, turns) in grouped {
            let url = logsDirectory.appendingPathComponent("raw_\(day).jsonl")
            let lines = turns.sorted { $0.timestamp < $1.timestamp }.compactMap { turn -> String? in
                guard let data = try? lineEncoder.encode(turn) else { return nil }
                return String(data: data, encoding: .utf8)
            }
            if let data = lines.joined(separator: "\n").appending("\n").data(using: .utf8) {
                try data.write(to: url, options: .atomic)
            }
        }
        for summary in store.summaries {
            let markdown = """
            ---
            date: \(summary.dateKey)
            agent: \(summary.agentID)
            llm: \(summary.llmSource)
            ---

            ## Dialogue
            \(summary.dialogueSummary300)

            ## House and schedule
            \(summary.contextTaskSummary300)
            """
            let url = memoriesDirectory.appendingPathComponent("DearHome_\(summary.dateKey).md")
            try markdown.data(using: .utf8)?.write(to: url, options: .atomic)
        }
        for delta in store.deltas {
            try write(delta, to: evolutionDirectory.appendingPathComponent("delta_\(delta.day).json"))
        }
    }

    func loadBus() -> FamilyBus? {
        read(FamilyBus.self, from: busURL)
    }

    func save(bus: FamilyBus) throws {
        try write(bus, to: busURL)
    }

    func loadMessages() -> [ChatMessage] {
        read([ChatMessage].self, from: messagesURL) ?? []
    }

    func save(messages: [ChatMessage]) throws {
        try write(messages, to: messagesURL)
    }

    func loadAccountState() -> AccountState? {
        read(AccountState.self, from: accountURL)
    }

    func save(accountState: AccountState) throws {
        try write(accountState, to: accountURL)
    }

    /// Deletes every piece of on-device profile data (preferences, messages, memories, evolution,
    /// family queue). The `models/` folder is preserved so a downloaded GGUF does not need re-downloading.
    func wipeAll() {
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            try? fm.removeItem(at: root)
            return
        }
        for url in items where url.lastPathComponent != "models" {
            try? fm.removeItem(at: url)
        }
    }

    func writeExport(_ text: String, stamp: String) throws -> URL {
        try prepare()
        let url = exportDirectory.appendingPathComponent("DearHome_\(stamp).md")
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try prepare()
        let data = try JSONCoding.encoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONCoding.decoder().decode(type, from: data)
    }
}

private struct AgentMetaMirror: Codable, Sendable {
    var vector: EvolutionVector
    var dominantRole: HomeRole
}
