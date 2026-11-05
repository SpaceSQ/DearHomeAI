import SwiftUI

struct MemoriesScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var showUpgrade = false

    var body: some View {
        let paper = PaperPalette.resolve(scheme)
        let language = model.resolvedLanguage
        let ring = model.ring
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(model.t("Memories", "记忆"))
                        .font(.system(.largeTitle, design: .serif))
                        .foregroundStyle(paper.ink)
                    Text(model.t("Seven hot days stay close. Days 8 through 30 wait in the ring. On the 31st morning the oldest raw day leaves. Distillation never invents a summary when the model is missing.",
                                 "热的 7 天留在手边。第 8 到 30 天待在环里。第 31 天清晨，最早的原始记录离开。没有模型的时候，蒸馏不会编造总结。"))
                        .font(.subheadline)
                        .foregroundStyle(paper.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if model.storeKit.activeTier.rank < DearHomeTier.pro.rank {
                        PremiumFeatureCard(
                            icon: "envelope.open.fill",
                            title: model.t("Nightly memory letters", "每晚记忆书信"),
                            detail: model.t(
                                "Read and export the full Markdown memory letter the house writes for you each midnight.",
                                "阅读并导出屋灵每晚午夜为你写下的完整 Markdown 记忆书信。"
                            ),
                            requiredTier: .pro,
                            showUpgrade: $showUpgrade
                        )
                    }

                    if ring.exportWarning {
                        warning(paper: paper, language: language, task: ring.completedTaskAtRisk, days: ring.daysUntilOverwrite)
                    }

                    stats(ring: ring, paper: paper, language: language)

                    if let note = model.catchUpNote {
                        Text(note.text(language))
                            .font(.footnote)
                            .foregroundStyle(paper.moss)
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task { await model.runCatchUp() }
                        } label: {
                            Text(model.isCatchingUp
                                 ? model.t("Distilling…", "蒸馏中……")
                                 : model.t("Run midnight catch-up", "补跑午夜蒸馏"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(paper.ink)
                        .disabled(model.isCatchingUp)
                        .accessibilityIdentifier("memories.catchup")
                    }

                    if let url = model.exportURL {
                        ShareLink(item: url) {
                            Text(model.t("Share the .md backup", "分享 .md 备份"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(paper.terracotta)
                    } else {
                        Button {
                            if model.storeKit.activeTier.rank >= DearHomeTier.pro.rank {
                                model.exportMarkdown()
                            } else {
                                showUpgrade = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if model.storeKit.activeTier.rank < DearHomeTier.pro.rank {
                                    Image(systemName: "lock.fill")
                                }
                                Text(model.t("Export 30-day .md", "导出 30 天 .md"))
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(paper.terracotta)
                        .accessibilityIdentifier("memories.export")
                    }

                    pendingBlock(paper: paper, language: language)
                    summaryBlock(paper: paper)
                }
                .padding(20)
            }
            .notebookBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showUpgrade) { UpgradeSheet() }
    }

    private func warning(paper: PaperPalette, language: ContentLanguage, task: Bool, days: Int?) -> some View {
        let soon = days.map(String.init) ?? "3"
        let text = task
            ? tr("The month's conversations and finished tasks will be released in \(soon) days. Export a .md backup if you want to keep them.",
                 "本月完整对话与任务记录将于 \(soon) 天后循环释放空间。若要留下，请导出 .md 备份。", language: language)
            : tr("The oldest day in the ring will be released within \(soon) days.",
                 "环里最早的一天将在 \(soon) 天内被释放。", language: language)
        return Text(text)
            .font(.footnote)
            .foregroundStyle(paper.ink)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(paper.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(paper.terracotta.opacity(0.7), lineWidth: 1))
    }

    private func stats(ring: ThirtyDayRingMetadata, paper: PaperPalette, language: ContentLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Ring \(ring.occupied)/\(ring.capacity) · hot \(ring.hotKeys.count) · warm \(ring.warmKeys.count)",
                    "循环 \(ring.occupied)/\(ring.capacity) · 热周 \(ring.hotKeys.count) · 温档 \(ring.warmKeys.count)",
                    language: language))
                .font(.subheadline.monospaced())
                .foregroundStyle(paper.ink)
            if let oldest = ring.oldestKey, let newest = ring.newestKey {
                Text(tr("\(oldest) → \(newest)", "\(oldest) → \(newest)", language: language))
                    .font(.caption)
                    .foregroundStyle(paper.secondary)
            }
        }
    }

    private func pendingBlock(paper: PaperPalette, language: ContentLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.t("Pending distillation", "待蒸馏"))
                .font(.headline)
                .foregroundStyle(paper.ink)
            if model.store.pending.isEmpty {
                Text(model.t("No day is waiting. A quiet day is not filled in.",
                             "没有日子在等待。安静的一天不会被填上假总结。"))
                    .font(.subheadline)
                    .foregroundStyle(paper.secondary)
            } else {
                ForEach(model.store.pending) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.dateKey).font(.body.monospaced()).foregroundStyle(paper.ink)
                        Text(reason(item.reason, language: language))
                            .font(.caption)
                            .foregroundStyle(paper.secondary)
                    }
                }
            }
        }
    }

    private func summaryBlock(paper: PaperPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.t("Distilled days", "已蒸馏的日子"))
                .font(.headline)
                .foregroundStyle(paper.ink)
            if model.store.summaries.isEmpty {
                Text(model.t("Summaries appear here after a model can do the 300 + 300.",
                             "等模型能做那 300 + 300 字，总结会出现在这里。"))
                    .font(.subheadline)
                    .foregroundStyle(paper.secondary)
            } else {
                ForEach(model.store.summaries) { summary in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.dateKey).font(.caption.monospaced()).foregroundStyle(paper.secondary)
                        Text(summary.dialogueSummary300)
                            .font(.subheadline)
                            .foregroundStyle(paper.ink)
                    }
                }
            }
        }
    }

    private func reason(_ reason: PendingReason, language: ContentLanguage) -> String {
        switch reason {
        case .noModel:
            return tr("Waiting for a shared on-device model.", "在等共享的本地模型。", language: language)
        case .runtimeNotLinked:
            return tr("A weight may be present, but llama is not linked in this build.",
                      "权重也许在，但这一版没有链接 llama。", language: language)
        case .parseFailed:
            return tr("The model answered, and the answer could not be read. The day is still waiting.",
                      "模型答了，但答案读不懂。这一天仍在等待。", language: language)
        }
    }
}
