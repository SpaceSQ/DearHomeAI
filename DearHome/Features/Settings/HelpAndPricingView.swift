import SwiftUI
import StoreKit

/// 应用内帮助与权益价格说明页。
///
/// 顶部呈现「Dear Home AI 使用指南」，下方以卡片 + 对比表格呈现
/// Free / Pro / Max 的权益边界与价格，页面底部提供直观的订阅升级入口
/// （订阅购买、恢复购买、当前订阅状态）。
struct HelpAndPricingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var model = model
        let paper = PaperPalette.resolve(scheme)
        let store = model.storeKit

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(paper: paper)

                guideSection(paper: paper)

                pricingSection(paper: paper)

                comparisonTable(paper: paper)

                if let error = store.purchaseError {
                    Text(error.text(model.resolvedLanguage))
                        .font(.footnote)
                        .foregroundStyle(paper.terracotta)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                upgradeSection(paper: paper)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .notebookBackground()
        .navigationTitle(model.t("Help & Pricing", "帮助与价格"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadProducts() }
    }

    // MARK: - Header

    private func header(paper: PaperPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RosetteMark(color: paper.terracotta)
                Text(model.t("Dear Home AI", "Dear Home AI"))
                    .font(.system(.title2, design: .serif))
                    .foregroundStyle(paper.ink)
            }
            Text(model.t("A warm house that talks, remembers, and quietly becomes more like you.",
                         "一所会说话、会记得、慢慢更像你的温暖房子。"))
                .font(.subheadline)
                .foregroundStyle(paper.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - User Guide

    private func guideSection(paper: PaperPalette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(model.t("User Guide", "使用指南"), paper: paper)

            guideCard(
                number: 1,
                title: model.t("Offline & private", "离线私密对话"),
                body: model.t(
                    "This app is built 100% on-device and offline-first. Every chat, space note, and memory stays in your iPhone's local sandbox and is never uploaded to the cloud.",
                    "本应用采用 100% 端侧离线优先架构，所有聊天记录、空间备忘与记忆均保存在您的 iPhone 本地沙盒中，绝不上传云端。"
                ),
                paper: paper
            )

            guideCard(
                number: 2,
                title: model.t("Daily 00:00 memory letter", "每日 00:00 记忆书信"),
                body: model.t(
                    "Every midnight at 00:00, the house spirit distills the whole day's conversation and environment rhythm into a warm Markdown (.md) memory letter to help you sort out your timeline.",
                    "每晚午夜 00:00，屋灵会自动将全天对话与环境节奏蒸馏为一封温馨的 Markdown (.md) 记忆书信，助您梳理心灵时间轴。"
                ),
                paper: paper
            )

            guideCard(
                number: 3,
                title: model.t("Expert Task Mode", "专家任务模式 (Task Mode)"),
                body: model.t(
                    "When you need a room makeover, a schedule, or a spatial flow design, switch to Task Mode and the house spirit will draft a professional decision plan you can export with one tap.",
                    "当您需要进行房间改造、日程规划或空间动线设计时，切换至任务模式，屋灵将为您生成可一键导出的专业决策方案。"
                ),
                paper: paper
            )

            guideCard(
                number: 4,
                title: model.t("Daily 1% soul evolution", "每日 1% 灵魂演化"),
                body: model.t(
                    "Guided by your daily interactions and local weather, the house spirit performs a subtle 1% subconscious evolution every day — becoming a little more like you.",
                    "屋灵会根据您的日常互动与本地环境气象，每天进行 1% 的潜意识微演化，变得愈发懂您。"
                ),
                paper: paper
            )
        }
    }

    private func guideCard(number: Int, title: String, body: String, paper: PaperPalette) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(.subheadline, design: .serif).bold())
                .foregroundStyle(paper.card)
                .frame(width: 26, height: 26)
                .background(paper.terracotta, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.body, design: .serif).bold())
                    .foregroundStyle(paper.ink)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(paper.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(paper.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Pricing

    private func pricingSection(paper: PaperPalette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(model.t("Tiers & Pricing", "档次与价格"), paper: paper)

            tierCard(tier: .free, paper: paper)
            tierCard(tier: .pro, paper: paper)
            tierCard(tier: .max, paper: paper)
        }
    }

    private func tierCard(tier: DearHomeTier, paper: PaperPalette) -> some View {
        let headline = tier != .free
        let accent: Color = tier == .max ? paper.terracotta : (tier == .pro ? paper.moss : paper.secondary)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tierName(tier))
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(paper.ink)
                Spacer()
                Text(priceLine(tier))
                    .font(.system(.subheadline, design: .serif).bold())
                    .foregroundStyle(accent)
            }

            ForEach(benefits(tier), id: \.self) { benefit in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(accent)
                    Text(benefit)
                        .font(.subheadline)
                        .foregroundStyle(paper.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(headline ? paper.card : paper.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(headline ? accent.opacity(0.8) : paper.rule.opacity(0.5), lineWidth: headline ? 1.5 : 1)
        )
    }

    // MARK: - Comparison table

    private func comparisonTable(paper: PaperPalette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(model.t("Benefit comparison", "权益对照"), paper: paper)

            let columns = [DearHomeTier.free, .pro, .max]
            let rows = comparisonRows()

            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    Text(model.t("Benefit", "权益"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(columns, id: \.self) { tier in
                        Text(tierName(tier))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .font(.caption.bold())
                .foregroundStyle(paper.ink)
                .padding(.vertical, 10)
                .background(paper.card)

                Divider().overlay(paper.rule)

                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    HStack(spacing: 0) {
                        Text(row.label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(columns, id: \.self) { tier in
                            cell(row.values[tier] ?? false, paper: paper)
                        }
                    }
                    .font(.caption)
                    .padding(.vertical, 8)
                    .background(index.isMultiple(of: 2) ? paper.card.opacity(0.35) : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(paper.rule, lineWidth: 1))
        }
    }

    private func cell(_ on: Bool, paper: PaperPalette) -> some View {
        Image(systemName: on ? "checkmark" : "minus")
            .font(.caption.bold())
            .foregroundStyle(on ? paper.moss : paper.secondary.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Upgrade entry

    private func upgradeSection(paper: PaperPalette) -> some View {
        let store = model.storeKit
        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle(model.t("Upgrade", "订阅升级"), paper: paper)

            HStack {
                Image(systemName: "crown.fill")
                    .foregroundStyle(paper.terracotta)
                Text(activeTierLine(store.activeTier))
                    .font(.subheadline)
                    .foregroundStyle(paper.ink)
                Spacer()
            }

            if store.activeTier == .free {
                upgradeButton(product: store.maxMonthly, tierName: tierName(.max), accent: paper.terracotta, paper: paper)
                upgradeButton(product: store.proMonthly, tierName: tierName(.pro), accent: paper.moss, paper: paper)
            }

            Button {
                Task { await store.restorePurchases() }
            } label: {
                Text(model.t("Restore Purchases", "恢复购买"))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(paper.ink)
            .accessibilityIdentifier("help.restore")

            if case .failed(let message) = store.loadState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(paper.terracotta)
            }
        }
        .padding(.bottom, 24)
    }

    private func upgradeButton(product: Product?, tierName: String, accent: Color, paper: PaperPalette) -> some View {
        let store = model.storeKit
        return Button {
            guard let product else { return }
            Task { await store.purchase(product) }
        } label: {
            HStack {
                if store.isPurchasing {
                    ProgressView().controlSize(.small)
                }
                Text(model.t("Subscribe to \(tierName)", "订阅 \(tierName)"))
                    .frame(maxWidth: .infinity)
                if let product {
                    Text(product.displayPrice)
                        .bold()
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
        .disabled(store.isPurchasing || product == nil)
        .accessibilityIdentifier("help.subscribe.\(tierName.lowercased())")
    }

    // MARK: - Data

    private func sectionTitle(_ title: String, paper: PaperPalette) -> some View {
        Text(title)
            .font(.system(.title3, design: .serif).bold())
            .foregroundStyle(paper.ink)
    }

    private func tierName(_ tier: DearHomeTier) -> String {
        switch tier {
        case .free: return model.t("Free", "免费版")
        case .pro: return model.t("Pro", "专业版")
        case .max: return model.t("Max", "旗舰版")
        }
    }

    private func priceLine(_ tier: DearHomeTier) -> String {
        switch tier {
        case .free: return model.t("$0 · forever", "$0 · 永久免费")
        case .pro: return model.t("$4.99/mo · $39.99/yr", "$4.99/月 · 年付 $39.99")
        case .max: return model.t("$9.99/mo · $79.99/yr", "$9.99/月 · 年付 $79.99")
        }
    }

    private func benefits(_ tier: DearHomeTier) -> [String] {
        switch tier {
        case .free:
            return [
                model.t("Default 'Hearth House Spirit' conversation", "默认基础「暖炉屋灵」对话"),
                model.t("100% local on-device offline engine", "100% 本地端侧离线私密引擎"),
                model.t("Manual SOUL profile & same-day chat history", "手动设置 SOUL 画像与当日记录"),
            ]
        case .pro:
            return [
                model.t("S2 SOUL smart matching (24 personality archetypes)", "解锁 S2 SOUL (24 种人格原型)"),
                model.t("Full nightly Markdown memory letters — read & export", "完整每晚 Markdown 记忆书信阅读与导出"),
                model.t("Weekly / monthly / yearly evolution charts", "周/月/年演化图表"),
                model.t("Cloud LLM API free switching", "云端大模型 API 自由切换"),
                model.t("Expert Task Mode", "专家任务模式 (Task Mode)"),
            ]
        case .max:
            return [
                model.t("Everything in Pro", "包含 Pro 全部权益"),
                model.t("All building-space companion prototypes & advanced scenes", "全系建筑空间伴侣原型与高级场景"),
                model.t("Custom SOUL & SKILL workshop (import/edit local SKILL library)", "自定义 SOUL 与 SKILL 工坊（支持导入/编辑本地 SKILL 库）"),
            ]
        }
    }

    private struct ComparisonRow {
        let label: String
        let values: [DearHomeTier: Bool]
    }

    private func comparisonRows() -> [ComparisonRow] {
        [
            ComparisonRow(label: model.t("Offline private chat", "离线私密对话"),
                          values: [.free: true, .pro: true, .max: true]),
            ComparisonRow(label: model.t("Manual SOUL profile", "手动 SOUL 画像"),
                          values: [.free: true, .pro: true, .max: true]),
            ComparisonRow(label: model.t("S2 SOUL (24 archetypes)", "S2 SOUL (24 人格)"),
                          values: [.free: false, .pro: true, .max: true]),
            ComparisonRow(label: model.t("Nightly Markdown memory letters", "每晚 Markdown 记忆书信"),
                          values: [.free: false, .pro: true, .max: true]),
            ComparisonRow(label: model.t("Evolution charts (W/M/Y)", "周/月/年演化图表"),
                          values: [.free: false, .pro: true, .max: true]),
            ComparisonRow(label: model.t("Cloud LLM API switching", "云端 LLM API 切换"),
                          values: [.free: false, .pro: true, .max: true]),
            ComparisonRow(label: model.t("Expert Task Mode", "专家任务模式"),
                          values: [.free: false, .pro: true, .max: true]),
            ComparisonRow(label: model.t("Companion prototypes & advanced scenes", "建筑空间伴侣原型与高级场景"),
                          values: [.free: false, .pro: false, .max: true]),
            ComparisonRow(label: model.t("Custom SOUL & SKILL workshop", "自定义 SOUL 与 SKILL 工坊"),
                          values: [.free: false, .pro: false, .max: true]),
        ]
    }

    private func activeTierLine(_ tier: DearHomeTier) -> String {
        switch tier {
        case .free: return model.t("Current plan: Free", "当前套餐：免费版")
        case .pro: return model.t("Current plan: Pro", "当前套餐：专业版")
        case .max: return model.t("Current plan: Max", "当前套餐：旗舰版")
        }
    }
}
