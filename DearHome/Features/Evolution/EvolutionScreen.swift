import Charts
import SwiftUI

struct EvolutionScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var showUpgrade = false

    var body: some View {
        let paper = PaperPalette.resolve(scheme)
        let language = model.resolvedLanguage
        let role = model.vector.dominantRole
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(model.t("Evolution", "演化"))
                        .font(.system(.largeTitle, design: .serif))
                        .foregroundStyle(paper.ink)
                    Text(role.title(in: language))
                        .font(.system(.title2, design: .serif))
                        .foregroundStyle(paper.terracotta)
                    Text(role.portrait(in: language))
                        .font(.subheadline)
                        .foregroundStyle(paper.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(model.t("Any axis may move at most 1% in a day, and only after a real distillation. A preview below does not write itself into the house.",
                                 "每一维每天最多移动 1%，而且要等真正的蒸馏。下面的预览不会写进这所房子。"))
                        .font(.footnote)
                        .foregroundStyle(paper.secondary)

                    if model.storeKit.activeTier.rank < DearHomeTier.pro.rank {
                        PremiumFeatureCard(
                            icon: "chart.xyaxis.line",
                            title: model.t("Weekly / monthly / yearly evolution", "周/月/年演化图表"),
                            detail: model.t(
                                "Watch how the house spirit drifts over weeks, months, and years — not just today.",
                                "观察屋灵在周、月、年尺度上的演化，而不只是今天。"
                            ),
                            requiredTier: .pro,
                            showUpgrade: $showUpgrade
                        )
                    }

                    Chart(EvolutionAxis.allCases) { axis in
                        BarMark(
                            x: .value("Level", model.vector[axis]),
                            y: .value("Axis", axis.title(in: language))
                        )
                        .foregroundStyle(axis.isExpression ? paper.moss : paper.terracotta)
                    }
                    .chartXScale(domain: 0...1)
                    .chartXAxis {
                        AxisMarks(values: [0, 0.5, 1])
                    }
                    .frame(height: 380)
                    .accessibilityIdentifier("evolution.chart")

                    driftBlock(paper: paper, language: language)

                    Text(model.t("Mean distance from the day this phone was born: \(percent(model.vector.distance(from: model.baseline))). Family facts can match. This shape does not have to.",
                                 "距离这台手机诞生那天的平均偏移：\(percent(model.vector.distance(from: model.baseline)))。家庭信息可以对齐。这个形状不必相同。"))
                        .font(.footnote)
                        .foregroundStyle(paper.secondary)

                    if model.store.deltas.isEmpty {
                        Text(model.t("No stored midnight step yet. The chart is the house as it is today.",
                                     "还没有存下的午夜一步。这张图是房子今天的样子。"))
                            .font(.footnote)
                            .foregroundStyle(paper.secondary)
                    } else {
                        ForEach(model.store.deltas) { delta in
                            Text("\(delta.day)  ·  \(model.t("largest step", "最大一步")) \(percent(delta.applied.map(abs).max() ?? 0))")
                                .font(.caption.monospaced())
                                .foregroundStyle(paper.ink)
                        }
                    }
                }
                .padding(20)
            }
            .notebookBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showUpgrade) { UpgradeSheet() }
    }

    private func driftBlock(paper: PaperPalette, language: ContentLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(model.t("Preview today's clamp", "预览今天的 1% 限幅")) {
                model.previewDrift()
            }
            .buttonStyle(.bordered)
            .tint(paper.ink)
            .accessibilityIdentifier("evolution.preview")
            if let preview = model.driftPreview {
                let rawMax = preview.raw.map { abs($0) }.max() ?? 0
                let appliedMax = preview.applied.map { abs($0) }.max() ?? 0
                Text(tr("Unclamped peak \(percent(rawMax)). After the rule \(percent(appliedMax)). Nothing was saved.",
                        "限幅前峰值 \(percent(rawMax))。规则之后 \(percent(appliedMax))。没有保存。",
                        language: language))
                    .font(.footnote)
                    .foregroundStyle(paper.ink)
                if model.messages.filter({ $0.role == .user }).isEmpty {
                    Text(model.t("There is no talk yet, so the preview stays still. The counterpart does not move a silent house.",
                                 "还没有对话，所以预览不动。没有说话的时候，沟通对象也不会推动房子。"))
                        .font(.caption)
                        .foregroundStyle(paper.secondary)
                }
            }
        }
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.2f%%", value * 100)
    }
}
