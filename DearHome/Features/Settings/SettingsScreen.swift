import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var showDeleteConfirmation = false

    var body: some View {
        @Bindable var model = model
        let paper = PaperPalette.resolve(scheme)
        let language = model.resolvedLanguage
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        RosetteMark(color: paper.terracotta)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dear Home AI")
                                .font(.system(.title3, design: .serif))
                            Text(model.t("Talk to the house", "和房子说话"))
                                .font(.caption)
                                .foregroundStyle(paper.secondary)
                        }
                    }
                    Picker(model.t("Language", "语言"), selection: Binding(
                        get: { model.language },
                        set: { model.updateLanguage($0) }
                    )) {
                        Text(model.t("System", "跟随系统")).tag(AppLanguage.system)
                        Text("English").tag(AppLanguage.en)
                        Text("简体中文").tag(AppLanguage.zh)
                    }
                }

                Section(model.t("Apple Home", "Apple 智能家居")) {
                    Toggle(model.t("Sample rooms from the notebook", "使用手记里的示例房间"), isOn: Binding(
                        get: { model.useSampleHome },
                        set: { useSample in Task { await model.setUseSampleHome(useSample) } }
                    ))
                    .accessibilityIdentifier("settings.sampleHome")
                    LabeledContent(model.t("Authorization", "授权")) {
                        Text(authTitle(model.snapshot.authorization, language: language))
                    }
                    Text(model.t("Reading rooms is allowed after you turn the sample off. Writing a device is refused in this version.",
                                 "关掉示例之后，可以读取房间。这一版会拒绝写入设备。"))
                        .font(.footnote)
                        .foregroundStyle(paper.secondary)
                }

                Section(model.t("Family MQTT", "家庭 MQTT")) {
                    Picker(model.t("This iPhone", "这台 iPhone"), selection: Binding(
                        get: { model.role },
                        set: { model.updateRole($0) }
                    )) {
                        ForEach(FamilyTransportRole.allCases) { role in
                            Text(role.title(in: language)).tag(role)
                        }
                    }
                    Text(model.role.detail(in: language))
                        .font(.footnote)
                        .foregroundStyle(paper.secondary)
                    Picker(model.t("Sync", "同步"), selection: Binding(
                        get: { model.syncMode },
                        set: { model.updateSyncMode($0) }
                    )) {
                        ForEach(SyncMode.allCases) { mode in
                            Text(mode.title(in: language)).tag(mode)
                        }
                    }
                    .accessibilityIdentifier("settings.sync")
                    LabeledContent(model.t("Phase", "阶段"), value: model.bus.machine.phase.rawValue)
                    LabeledContent(model.t("Waiting", "等待中"), value: "\(model.bus.machine.pending.count)")
                    LabeledContent(model.t("Delivered on this phone", "本机已交出"), value: "\(model.bus.machine.delivered.count)")
                    LabeledContent(model.t("Inbox", "收件"), value: "\(model.bus.inbox.count)")
                    TextField(model.t("Family id", "家庭编号"), text: Binding(
                        get: { model.familyID },
                        set: { model.updateFamilyID($0) }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    TextField(model.t("Name at home", "在家里的名字"), text: Binding(
                        get: { model.deviceName },
                        set: { model.updateDeviceName($0) }
                    ))
                    Picker(model.t("This phone mostly speaks as", "这台手机主要以谁的身份说话"), selection: Binding(
                        get: { model.counterpart },
                        set: { model.updateCounterpart($0) }
                    )) {
                        ForEach(HouseholdCounterpart.allCases) { person in
                            Text(person.title(in: language)).tag(person)
                        }
                    }
                    Button(model.t("Run the 00:00 exchange now", "现在跑一次 00:00 交换")) {
                        model.simulateMidnight()
                    }
                    .accessibilityIdentifier("settings.midnight")
                    Text(model.t("Discovery type \(FamilyTransport.bonjourType) is reserved. No broker is embedded (usesEmbeddedBroker = \(FamilyTransport.usesEmbeddedBroker)).",
                                 "发现类型 \(FamilyTransport.bonjourType) 先留着。没有内嵌 broker（usesEmbeddedBroker = \(FamilyTransport.usesEmbeddedBroker)）。"))
                        .font(.footnote)
                        .foregroundStyle(paper.secondary)
                    if let note = model.familyNote {
                        Text(note.text(language))
                            .font(.footnote)
                            .foregroundStyle(paper.moss)
                    }
                }

                Section(model.t("Shared model", "共享模型")) {
                    Text(model.llm.status.message(in: language))
                        .font(.subheadline)
                    LabeledContent(model.t("Green channel", "绿色通道")) {
                        Text(model.llm.channelAvailable ? model.t("Container present", "容器在") : model.t("Not on this install", "这次安装没有"))
                    }
                    LabeledContent("group.com.s2.dearuniverse") {
                        Text(model.llm.legacyGroupDetected ? model.t("Detected", "探测到") : model.t("Not detected", "未探测到"))
                    }
                    Toggle(model.t("Allow external apps to use a local model", "允许外部应用使用本地模型"), isOn: Binding(
                        get: { model.allowExternalSharing },
                        set: { model.setAllowExternal($0) }
                    ))
                    Button(model.t("Scan again", "再扫描一次")) { model.scanModels() }
                    Text(model.t("Off by default. The 22-app green channel (Dear Earth and siblings) is the one this house recognizes. On-device llama is linked; put a Qwen GGUF in the shared models folder or Application Support/DearHome/models.",
                                 "默认关闭。这所房子认得的是 22 应用绿色通道（Dear Earth 等同系）。本机已链接 llama；把 Qwen 的 GGUF 放到共享 models 或 Application Support/DearHome/models。"))
                        .font(.footnote)
                        .foregroundStyle(paper.secondary)
                }

                Section(model.t("Subscription", "订阅")) {
                    NavigationLink {
                        HelpAndPricingView()
                    } label: {
                        LabeledContent(model.t("Help & Pricing", "帮助与价格"), value: model.t("Free · Pro · Max", "免费 · 专业 · 旗舰"))
                    }
                    .accessibilityIdentifier("settings.helpPricing")
                    Text(model.t("View the user guide, compare Free / Pro / Max benefits and prices, and upgrade your membership.",
                                 "查看使用指南，对照免费 / 专业 / 旗舰的权益与价格，并升级会员。"))
                        .font(.footnote)
                        .foregroundStyle(paper.secondary)
                }

                if let error = model.persistError {
                    Section {
                        Text(error.text(language))
                            .foregroundStyle(paper.terracotta)
                    }
                }

                Section(model.t("Account", "账户")) {
                    LabeledContent(model.t("Status", "状态")) {
                        Text(model.isBound
                             ? model.t("Signed in with Apple", "已通过 Apple 登录")
                             : model.t("Signed out", "已登出"))
                    }
                    if let name = model.appleDisplayName {
                        LabeledContent(model.t("Name", "姓名")) { Text(name) }
                    }
                    if let email = model.appleEmail {
                        LabeledContent(model.t("Email", "邮箱")) { Text(email) }
                    }
                    Button(role: .destructive) {
                        model.signOut()
                    } label: {
                        Text(model.t("Sign out", "登出"))
                    }
                    .accessibilityIdentifier("settings.signOut")
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Text(model.t("Delete account", "注销"))
                    }
                    .accessibilityIdentifier("settings.deleteAccount")
                    Text(model.t("Signing out keeps your profile on this iPhone; signing back in with the same Apple account returns to the same content. Deleting the account erases every room, memory, and family note, and you must sign in with Apple again to start a new profile.",
                                 "登出会把你的档案留在这台 iPhone 上；用同一个 Apple 账户再次登录会回到原来的内容。注销会清除所有房间、记忆与家庭记录，你需要重新使用 Apple 登录来建立新的用户档案。"))
                        .font(.footnote)
                        .foregroundStyle(paper.secondary)
                }

                Section(model.t("About", "关于")) {
                    Text(model.t("One house lives on this iPhone. Household facts may travel. Personality may drift at most one percent a day, so two phones can share a memory and still sound a little different.",
                                 "一所房子住在这台 iPhone 上。家庭信息可以出门。人格每天最多漂百分之一，所以两台手机可以共享记忆，听起来仍有一点不同。"))
                        .font(.footnote)
                        .foregroundStyle(paper.secondary)
                    LabeledContent(model.t("Version", "版本"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")
                }
            }
            .scrollContentBackground(.hidden)
            .notebookBackground()
            .navigationTitle(model.t("Setting", "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                model.t("Delete account?", "确定注销吗？"),
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(model.t("Delete everything", "删除全部"), role: .destructive) {
                    model.deleteAccount()
                }
                Button(model.t("Cancel", "取消"), role: .cancel) {}
            } message: {
                Text(model.t("This erases the whole local profile. It cannot be undone.",
                             "这会清除整份本机档案，无法撤销。"))
            }
        }
        .task { model.scanModels() }
    }

    private func authTitle(_ state: HomeAuthorizationState, language: ContentLanguage) -> String {
        switch state {
        case .notDetermined: return tr("Not asked", "还没问", language: language)
        case .authorized: return tr("Allowed", "已允许", language: language)
        case .restricted: return tr("Restricted", "受限制", language: language)
        case .mock: return tr("Sample", "示例", language: language)
        }
    }
}
