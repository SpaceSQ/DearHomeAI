import SwiftUI

/// 付费功能锁定卡片：在 Home / Space / Memories / Evolution 等主界面插入，
/// 展示某个 Pro / Max 权益的差异化价值，并一键打开「帮助与价格」页去解锁。
///
/// 用法示例（仅在尚未解锁该档次时显示）：
/// ```swift
/// if model.storeKit.activeTier.rank < DearHomeTier.pro.rank {
///     PremiumFeatureCard(
///         icon: "wand.and.stars",
///         title: model.t("Expert Task Mode", "专家任务模式"),
///         detail: model.t("…", "…"),
///         requiredTier: .pro,
///         showUpgrade: $showUpgrade
///     )
/// }
/// ```
struct PremiumFeatureCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    let icon: String
    let title: String
    let detail: String
    /// 解锁该功能所需的最低档次。
    let requiredTier: DearHomeTier
    @Binding var showUpgrade: Bool

    var body: some View {
        let paper = PaperPalette.resolve(scheme)
        let accent = accentColor(paper)
        let isUnlocked = model.storeKit.activeTier.rank >= requiredTier.rank

        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isUnlocked ? paper.moss : accent)
                .frame(width: 34, height: 34)
                .background((isUnlocked ? paper.moss : accent).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(paper.ink)
                    Text(requiredTier == .max ? "MAX" : "PRO")
                        .font(.caption2.bold())
                        .foregroundStyle(paper.card)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(accent, in: Capsule())
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(paper.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isUnlocked {
                    Label(model.t("Unlocked", "已解锁"), systemImage: "checkmark.seal.fill")
                        .font(.caption.bold())
                        .foregroundStyle(paper.moss)
                } else {
                    Button {
                        showUpgrade = true
                    } label: {
                        Label(model.t("Unlock", "解锁"), systemImage: "lock.open")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)
                    .accessibilityIdentifier("premium.unlock.\(requiredTier.rawValue.lowercased())")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(paper.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(paper.rule.opacity(0.6), lineWidth: 1))
    }

    private func accentColor(_ paper: PaperPalette) -> Color {
        requiredTier == .max ? paper.terracotta : paper.moss
    }
}

/// 以 sheet 形式弹出「帮助与价格」页，带右上角关闭按钮，供各主界面复用。
struct UpgradeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HelpAndPricingView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(model.t("Close", "关闭")) { dismiss() }
                    }
                }
        }
    }
}
