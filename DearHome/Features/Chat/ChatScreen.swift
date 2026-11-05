import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

struct ChatScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @FocusState private var inputFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    @State private var showUpgrade = false

    var body: some View {
        @Bindable var model = model
        let paper = PaperPalette.resolve(scheme)
        let language = model.resolvedLanguage
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header(paper: paper, language: language)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if model.storeKit.activeTier.rank < DearHomeTier.pro.rank {
                                PremiumFeatureCard(
                                    icon: "wand.and.stars",
                                    title: model.t("Expert Task Mode", "专家任务模式"),
                                    detail: model.t(
                                        "Turn any room makeover, schedule, or spatial-flow design into a professional decision plan you can export with one tap.",
                                        "把房间改造、日程或空间动线设计变成可一键导出的专业决策方案。"
                                    ),
                                    requiredTier: .pro,
                                    showUpgrade: $showUpgrade
                                )
                            }
                            ForEach(model.messages) { message in
                                bubble(message, paper: paper, language: language)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: model.messages.count) { _, _ in
                        if let last = model.messages.last?.id {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                if let note = model.familyNote {
                    Text(note.text(language))
                        .font(.footnote)
                        .foregroundStyle(paper.moss)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)
                        .accessibilityIdentifier("chat.familyNote")
                }
                inputBar(model: model, draft: $model.draft, paper: paper)
            }
            .notebookBackground()
            .toolbar(.hidden, for: .navigationBar)
            .contentShape(Rectangle())
            .onTapGesture { hideKeyboard() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: max(0, keyboardHeight))
            }
            .animation(.easeOut(duration: 0.22), value: keyboardHeight)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
                if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    keyboardHeight = frame.height
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
        }
        .sheet(isPresented: $showUpgrade) { UpgradeSheet() }
    }

    private func header(paper: PaperPalette, language: ContentLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(mqttLine(language))
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(paper.secondary)
                Spacer()
                Text(model.syncMode == .realtime ? "LIVE" : "00:00")
                    .font(.caption2.monospaced())
                    .foregroundStyle(paper.terracotta)
            }
            HStack(spacing: 14) {
                HomeSpiritFaceView(state: model.currentInteractionState, size: 88)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.soul.addressLine.text(language))
                        .font(.system(.title2, design: .serif))
                        .foregroundStyle(paper.ink)
                    Text(model.soul.creed.text(language))
                        .font(.subheadline)
                        .foregroundStyle(paper.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Rectangle().fill(paper.rule).frame(height: 1).padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func hideKeyboard() {
        inputFocused = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private func submitDraft() {
        inputFocused = false
        Task { await model.sendDraft() }
    }

    private func mqttLine(_ language: ContentLanguage) -> String {
        let role = model.role == .ownerGateway
            ? tr("MQTT · OWNER", "MQTT · 主人", language: language)
            : tr("MQTT · FAMILY", "MQTT · 家人", language: language)
        return role
    }

    private func bubble(_ message: ChatMessage, paper: PaperPalette, language: ContentLanguage) -> some View {
        let mine = message.role == .user
        return VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            Text(message.text)
                .font(.body)
                .foregroundStyle(mine ? paper.card : paper.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(mine ? paper.ink : paper.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(paper.rule, lineWidth: mine ? 0 : 1)
                )
            HStack(spacing: 8) {
                Text(message.sourceLabel.text(language))
                    .font(.caption2)
                    .foregroundStyle(paper.secondary)
                if message.suggestOnly {
                    Text(tr("Suggestion only", "仅建议", language: language))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(paper.terracotta)
                }
                if message.withheldAsPrivate {
                    Text(tr("Stays in the house", "留在房子里", language: language))
                        .font(.caption2)
                        .foregroundStyle(paper.moss)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private func inputBar(model: AppModel, draft: Binding<String>, paper: PaperPalette) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(model.t("Talk to the house", "和房子说"), text: draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { submitDraft() }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(paper.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(paper.rule, lineWidth: 1))
                .accessibilityIdentifier("chat.input")
            Button {
                Task { await model.sendDraft() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(paper.card)
                    .background(paper.ink, in: Circle())
            }
            .disabled(model.isSending || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("chat.send")
            .accessibilityLabel(model.t("Send", "发送"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(paper.paper)
    }
}
