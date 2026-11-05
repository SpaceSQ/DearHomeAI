import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var tab: AppTab = .home
    var language: AppLanguage = .system
    var messages: [ChatMessage] = []
    var draft = ""
    var snapshot: HomeSnapshot = .empty
    var useSampleHome = true
    var vector = EvolutionVector()
    var baseline = EvolutionVector()
    var counterpart: HouseholdCounterpart = .owner
    var familyID = "home-local"
    var deviceName = ""
    var allowExternalSharing = false
    var bus = FamilyBus()
    var store = HippocampusStore()
    var llm: SharedModelDiscovery = .pending
    var isSending = false
    var currentInteractionState: HomeSpiritInteractionState = .idle
    var isBound = true
    var appleUserID: String?
    var appleGivenName: String?
    var appleFamilyName: String?
    var appleEmail: String?
    var isLoadingHome = false
    var isCatchingUp = false
    var driftPreview: EvolutionPreview?
    var exportURL: URL?
    var familyNote: Bilingual?
    var catchUpNote: Bilingual?
    var persistError: Bilingual?
    var soul: HomeSoul = .fallback
    var skills: HomeSkillLibrary = HomeSkillLibrary(skills: HomeSkill.fallback)

    @ObservationIgnored private let sandbox = HomeSandbox.live
    let storeKit = StoreKitManager()
    @ObservationIgnored private var companion = HomeCompanionEngine()
    @ObservationIgnored private var naCorpus: NAHomeSoulCorpus?
    @ObservationIgnored private var llmRuntime: LlamaRuntime?
    @ObservationIgnored private let extractor = RuleBasedFamilyFactExtractor()
    @ObservationIgnored private var liveBridge: LiveHomeKitBridge?
    @ObservationIgnored private var didBootstrap = false

    var resolvedLanguage: ContentLanguage { language.resolved() }

    var appleDisplayName: String? {
        let parts = [appleGivenName, appleFamilyName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    func t(_ en: String, _ zh: String) -> String {
        tr(en, zh, language: resolvedLanguage)
    }

    var syncMode: SyncMode { bus.machine.mode }
    var role: FamilyTransportRole { bus.role }

    var ring: ThirtyDayRingMetadata {
        let occupants = store.occupiedDateKeys.map { key in
            RingOccupant(dateKey: key,
                         hasCompletedTask: store.rawTurns.contains { $0.dateKey == key && $0.isCompletedTask })
        }
        return ThirtyDayRing.metadata(occupants: occupants, now: Date())
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        do { try sandbox.prepare() } catch {
            persistError = Bilingual(en: "The house could not open its notebook on disk.",
                                     zh: "房子打不开磁盘上的手记。")
        }
        soul = HomeSoulLoader.load()
        skills = HomeSkillLibrary.load()
        naCorpus = NAHomeSoulCorpusLoader.load()
        companion.naCorpus = naCorpus
        if let account = sandbox.loadAccountState() {
            isBound = account.isBound
            appleUserID = account.appleUserID
            appleGivenName = account.givenName
            appleFamilyName = account.familyName
            appleEmail = account.email
        } else {
            // First launch or a legacy install without an account record: start signed out so the
            // user signs in with Apple once. Existing on-device data is preserved on sign-in.
            isBound = false
        }
        if let saved = sandbox.loadPreferences() {
            language = saved.language
            useSampleHome = saved.useSampleHome
            familyID = saved.familyID
            deviceName = saved.deviceName
            allowExternalSharing = saved.allowExternalSharing
            counterpart = saved.counterpart
            vector = saved.vector
            baseline = saved.baseline
            bus.role = saved.role
            if bus.machine.mode != saved.syncMode {
                _ = bus.setMode(saved.syncMode)
            }
        }
        if let savedBus = sandbox.loadBus() {
            bus = savedBus
        }
        if let savedStore = sandbox.loadStore() {
            store = savedStore
        }
        messages = sandbox.loadMessages().map { message in
            guard message.role == .house else { return message }
            var scrubbed = message
            scrubbed.text = HouseLLM.sanitize(message.text)
            return scrubbed
        }
        if messages.isEmpty {
            let now = Date()
            let text = soul.greeting(for: Shichen.of(now), language: resolvedLanguage)
            let greeting = ChatMessage(
                role: .house,
                text: text,
                createdAt: now,
                source: .homeAgent,
                sourceLabel: Bilingual(en: "This house", zh: "这所房子")
            )
            messages = [greeting]
            store.rawTurns.append(rawTurn(from: greeting))
        }
        if useSampleHome {
            snapshot = MockHomeProvider().snapshot(now: Date())
        } else {
            Task { @MainActor in
                await self.refreshHome()
            }
        }
        llm = EcosystemModelCenter.scan(allowExternal: allowExternalSharing)
        prepareLocalModelIfNeeded()
        save()
        MidnightTaskRegistrar.register(model: self)
        MidnightTaskRegistrar.scheduleNext()
    }


    private func prepareLocalModelIfNeeded() {
        let modelsDir = sandbox.root.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        let url = ModelLocator.firstAvailableGGUF(sandbox: sandbox)
        companion.modelURL = url
        llm = EcosystemModelCenter.scan(allowExternal: allowExternalSharing)
        guard LlamaRuntime.isAvailable else {
            companion.runtime = nil
            return
        }
        let runtime = llmRuntime ?? LlamaRuntime(configuration: .deviceDefault(contextLength: 4096))
        llmRuntime = runtime
        companion.runtime = runtime
        guard let url else { return }
        Task.detached(priority: .utility) {
            _ = try? await runtime.load(url)
        }
    }

    func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2000, !isSending else { return }
        isSending = true
        currentInteractionState = .listening
        draft = ""
        let now = Date()
        let user = ChatMessage(
            role: .user,
            text: text,
            createdAt: now,
            source: .thisDevice,
            sourceLabel: Bilingual(en: sourceName(in: .en), zh: sourceName(in: .zh))
        )
        let todayKey = DayKey.string(for: now)
        let turnIndex = messages.filter { $0.role == .user && DayKey.string(for: $0.createdAt) == todayKey }.count + 1
        let context = HomeDialogueContext(
            now: now,
            preferredLanguage: resolvedLanguage,
            vector: vector,
            recentEvents: snapshot.events,
            knownFacts: bus.localFacts,
            turnIndexToday: turnIndex,
            counterpart: counterpart
        )
        currentInteractionState = .thinking
        let reply = await companion.reply(to: text, context: context, soul: soul, skills: skills, history: messages)
        let house = ChatMessage(
            role: .house,
            text: reply.text,
            createdAt: Date(),
            source: .homeAgent,
            sourceLabel: Bilingual(en: "This house", zh: "这所房子"),
            suggestOnly: reply.suggestOnly,
            skillIDs: reply.skillIDs,
            withheldAsPrivate: reply.withheldAsPrivate
        )
        messages.append(contentsOf: [user, house])
        store.rawTurns.append(rawTurn(from: user))
        store.rawTurns.append(rawTurn(from: house))
        familyNote = nil
        if !reply.withheldAsPrivate {
            let facts = extractor.extract(from: text, now: now, source: .thisDevice)
            if let fact = facts.first {
                var next = bus
                let outcome = next.publish(fact: fact, familyID: familyID, now: now)
                bus = next
                switch outcome {
                case .withheldSealed:
                    familyNote = nil
                case .held:
                    familyNote = Bilingual(en: "Household fact held until 00:00.", zh: "家庭信息留到 00:00 再交换。")
                case .delivered:
                    familyNote = Bilingual(en: "Household fact entered the family queue.", zh: "家庭信息已进入家庭队列。")
                }
            }
        }
        save()
        isSending = false
        let finishedState: HomeSpiritInteractionState = reply.intent == .control ? .task : .talking
        currentInteractionState = finishedState
        // 让「交谈 / 任务」神态停留片刻，再平静回到静候；若期间已开始新一条发送则不再打扰。
        try? await Task.sleep(for: .milliseconds(1400))
        if currentInteractionState == finishedState {
            currentInteractionState = .idle
        }
    }

    func updateLanguage(_ language: AppLanguage) {
        self.language = language
        save()
    }

    // MARK: Account

    /// Binds a real Apple account (via Sign in with Apple) to this on-device profile.
    /// Re-logging in after a sign-out returns to the existing content because nothing was deleted.
    /// Apple only returns the full name and email on the first sign-in, so we keep the stored
    /// values when a later sign-in omits them. The one-time authorization code is exchanged
    /// server-side for a refresh token that we stash in the Keychain for later revocation.
    func bindAccount(appleUserID: String, givenName: String?, familyName: String?, email: String?, authorizationCode: String?) {
        isBound = true
        self.appleUserID = appleUserID
        if let givenName { self.appleGivenName = givenName }
        if let familyName { self.appleFamilyName = familyName }
        if let email { self.appleEmail = email }
        save()
        if let authorizationCode {
            Task { await storeAppleRefreshToken(authorizationCode: authorizationCode) }
        }
    }

    private func storeAppleRefreshToken(authorizationCode: String) async {
        do {
            if let refreshToken = try await AppleAuthClient.exchange(authorizationCode: authorizationCode) {
                KeychainStore.save(refreshToken, for: KeychainStore.refreshTokenKey)
            }
        } catch {
            // Non-fatal: the account still works fully on-device; server revocation is skipped later.
        }
    }

    /// Signs out of the Apple account but keeps the whole profile on this iPhone.
    func signOut() {
        isBound = false
        save()
    }

    /// Deletes the account: revokes the Apple refresh token server-side (best effort), wipes every
    /// room, memory, and family note, then returns to a fresh, unbound state so the user must sign
    /// in with Apple again to create a new profile.
    func deleteAccount() {
        let refreshToken = KeychainStore.read(KeychainStore.refreshTokenKey)
        KeychainStore.delete(KeychainStore.refreshTokenKey)
        sandbox.wipeAll()
        resetObservableState()
        didBootstrap = false
        bootstrap()
        if let refreshToken {
            Task { try? await AppleAuthClient.revoke(refreshToken: refreshToken) }
        }
    }

    func updateDeviceName(_ name: String) {
        deviceName = String(name.prefix(40))
        save()
    }

    func updateFamilyID(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        familyID = trimmed.isEmpty ? "home-local" : String(trimmed.prefix(64))
        save()
    }

    func updateCounterpart(_ counterpart: HouseholdCounterpart) {
        self.counterpart = counterpart
        save()
    }

    func updateRole(_ role: FamilyTransportRole) {
        var next = bus
        next.role = role
        bus = next
        save()
    }

    func updateSyncMode(_ mode: SyncMode) {
        var next = bus
        let released = next.setMode(mode)
        bus = next
        if released.isEmpty {
            familyNote = mode == .dailyMidnight
                ? Bilingual(en: "New household facts wait for 00:00.", zh: "新的家庭信息会等到 00:00。")
                : Bilingual(en: "New household facts leave as they happen.", zh: "新的家庭信息会当时送出。")
        } else {
            familyNote = Bilingual(en: "Released \(released.count) waiting fact(s) because realtime is on.",
                                   zh: "因为改成了实时，已放出 \(released.count) 条等待中的信息。")
        }
        save()
    }

    func setAllowExternal(_ allowed: Bool) {
        allowExternalSharing = allowed
        prepareLocalModelIfNeeded()
        save()
    }

    func scanModels() {
        llm = EcosystemModelCenter.scan(allowExternal: allowExternalSharing)
    }

    func setUseSampleHome(_ useSample: Bool) async {
        useSampleHome = useSample
        await refreshHome()
        save()
    }

    func refreshHome() async {
        if useSampleHome {
            snapshot = MockHomeProvider().snapshot(now: Date())
            return
        }
        isLoadingHome = true
        defer { isLoadingHome = false }
        if liveBridge == nil { liveBridge = LiveHomeKitBridge() }
        snapshot = await liveBridge?.loadSnapshot() ?? .empty
    }

    func share(event: SpaceEvent) {
        let fact = extractor.extract(event: event)
        var next = bus
        let outcome = next.publish(fact: fact, familyID: familyID, now: Date())
        bus = next
        switch outcome {
        case .held:
            familyNote = Bilingual(en: "Room event held until 00:00.", zh: "房间事件留到 00:00。")
        case .delivered:
            familyNote = Bilingual(en: "Room event entered the family queue.", zh: "房间事件已进入家庭队列。")
        case .withheldSealed:
            familyNote = nil
        }
        save()
    }

    func simulateMidnight() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: start) ?? Date()
        var next = bus
        let released = next.tick(now: nextMidnight, calendar: calendar)
        bus = next
        familyNote = Bilingual(
            en: "00:00 exchange released \(released.count) envelope(s).",
            zh: "00:00 的交换放出了 \(released.count) 封信。"
        )
        save()
    }

    func previewDrift() {
        let today = DayKey.string(for: Date())
        let texts = messages.filter { $0.role == .user && DayKey.string(for: $0.createdAt) == today }.map(\.text)
        driftPreview = MidnightEvolutionEngine.preview(vector: vector, texts: texts, counterpart: counterpart)
    }

    func runCatchUp() async {
        guard !isCatchingUp else { return }
        isCatchingUp = true
        defer { isCatchingUp = false }
        let provider = llm.mountedModelPath == nil ? HomeLLMProvider.unavailable : HomeLLMProvider.sharedAppGroup
        let coordinator = MemoryLifecycleCoordinator(
            daily: LocalDailyDistillJob(invoker: HomeSummarizationInvoker()),
            weekly: LocalWeeklyConsolidator(invoker: HomeSummarizationInvoker())
        )
        let outcome = await coordinator.runCatchUp(now: Date(), provider: provider, store: store)
        store = outcome.store
        for day in outcome.report.distilled {
            guard let summary = store.summary(agentID: HomeAgent.id, dateKey: day),
                  !store.deltas.contains(where: { $0.day == day }) else { continue }
            let before = vector
            var next = vector
            let applied = next.applyNamedDelta(summary.evolutionDelta)
            let record = EvolutionDeltaRecord(
                day: day,
                before: before.asArray,
                rawGradient: EvolutionAxis.allCases.map { summary.evolutionDelta[$0.rawName] ?? 0 },
                applied: applied,
                after: next.asArray,
                userTurns: store.turns(agentID: HomeAgent.id, dateKey: day).filter { $0.role == "user" }.count,
                dominantRoleAfter: next.dominantRole,
                distilledAt: Date()
            )
            vector = next
            store.deltas.append(record)
        }
        if outcome.report.neededModel {
            catchUpNote = Bilingual(
                en: "A day is waiting. No summary was invented, because the shared model is not ready.",
                zh: "有一天在等待。共享模型还没准备好，所以没有编造总结。"
            )
        } else if outcome.report.distilled.isEmpty && outcome.report.pending.isEmpty {
            catchUpNote = Bilingual(
                en: "Nothing was due. Yesterday's notebook is empty or already distilled.",
                zh: "没有到期的事。昨天的手记是空的，或已经蒸馏过。"
            )
        } else {
            catchUpNote = Bilingual(
                en: "Distilled \(outcome.report.distilled.count) day(s).",
                zh: "蒸馏了 \(outcome.report.distilled.count) 天。"
            )
        }
        save()
        MidnightTaskRegistrar.scheduleNext()
    }

    func exportMarkdown() {
        let text = ThirtyDayMarkdownExporter.render(store: store, vector: vector, now: Date(), language: resolvedLanguage)
        do {
            exportURL = try sandbox.writeExport(text, stamp: DayKey.string(for: Date()))
        } catch {
            persistError = Bilingual(en: "The export could not be written.", zh: "导出没有写成。")
        }
    }

    private func resetObservableState() {
        tab = .home
        language = .system
        messages = []
        draft = ""
        snapshot = .empty
        useSampleHome = true
        vector = EvolutionVector()
        baseline = EvolutionVector()
        counterpart = .owner
        familyID = "home-local"
        deviceName = ""
        allowExternalSharing = false
        bus = FamilyBus()
        store = HippocampusStore()
        llm = .pending
        isSending = false
        currentInteractionState = .idle
        isBound = false
        appleUserID = nil
        appleGivenName = nil
        appleFamilyName = nil
        appleEmail = nil
        isLoadingHome = false
        isCatchingUp = false
        driftPreview = nil
        exportURL = nil
        familyNote = nil
        catchUpNote = nil
        persistError = nil
        soul = .fallback
        skills = HomeSkillLibrary(skills: HomeSkill.fallback)
        companion = HomeCompanionEngine()
        naCorpus = nil
        llmRuntime = nil
        liveBridge = nil
    }

    private func save() {
        let preferences = HomePreferences(
            language: language,
            useSampleHome: useSampleHome,
            role: bus.role,
            syncMode: bus.machine.mode,
            familyID: familyID,
            deviceName: deviceName,
            allowExternalSharing: allowExternalSharing,
            counterpart: counterpart,
            vector: vector,
            baseline: baseline,
            greeted: !messages.isEmpty
        )
        do {
            try sandbox.save(preferences: preferences)
            try sandbox.save(store: store)
            try sandbox.save(bus: bus)
            try sandbox.save(messages: messages)
            try sandbox.save(accountState: AccountState(isBound: isBound, appleUserID: appleUserID,
                                                         givenName: appleGivenName, familyName: appleFamilyName,
                                                         email: appleEmail))
            persistError = nil
        } catch {
            persistError = Bilingual(en: "The house could not save its notebook.", zh: "房子没能把手记存下来。")
        }
    }

    private func rawTurn(from message: ChatMessage) -> RawTurn {
        RawTurn(
            id: message.id.uuidString,
            agentID: HomeAgent.id,
            dateKey: DayKey.string(for: message.createdAt),
            timestamp: message.createdAt,
            role: message.role == .user ? "user" : "house",
            content: message.text,
            source: message.source,
            isCompletedTask: false
        )
    }

    private func sourceName(in language: ContentLanguage) -> String {
        let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return tr("This iPhone", "这台 iPhone", language: language)
        }
        return trimmed
    }
}
