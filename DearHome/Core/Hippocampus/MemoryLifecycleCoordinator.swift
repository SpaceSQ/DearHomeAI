import Foundation

struct CatchUpReport: Sendable, Equatable {
    var distilled: [String] = []
    var pending: [String] = []
    var weekly: [String] = []
    var evicted: [String] = []
    var neededModel = false
    var failures: [String] = []

    var isEmpty: Bool {
        distilled.isEmpty && pending.isEmpty && weekly.isEmpty && evicted.isEmpty && !neededModel && failures.isEmpty
    }
}

/// Sync, 30-day eviction, midnight distill, and the previous week's consolidation.
struct MemoryLifecycleCoordinator: Sendable {
    var daily: LocalDailyDistillJob
    var weekly: LocalWeeklyConsolidator

    func runCatchUp(now: Date,
                    provider: HomeLLMProvider,
                    store: HippocampusStore,
                    calendar: Calendar = .current,
                    agentID: String = HomeAgent.id) async -> (store: HippocampusStore, report: CatchUpReport) {
        var store = store
        var report = CatchUpReport()
        let today = DayKey.string(for: now, calendar: calendar)
        let evict = ThirtyDayRing.keysToEvict(dateKeys: Array(Set(store.rawTurns.map(\.dateKey))),
                                              currentDateKey: today,
                                              calendar: calendar)
        if !evict.isEmpty {
            store.evictRawTurns(dateKeys: evict)
            report.evicted = evict
        }

        let days = Array(Set(store.rawTurns.filter { $0.agentID == agentID }.map(\.dateKey)))
            .filter { $0 < today }
            .sorted()
        for day in days where store.summary(agentID: agentID, dateKey: day) == nil {
            let turns = store.turns(agentID: agentID, dateKey: day)
            guard !turns.isEmpty else { continue }
            do {
                let outcome = try await daily.execute(agentID: agentID,
                                                       dateKey: day,
                                                       provider: provider,
                                                       turns: turns,
                                                       store: store,
                                                       now: now)
                store = outcome.store
                if let result = outcome.result {
                    report.distilled.append(result.dateKey)
                } else if outcome.enqueuedPending {
                    report.pending.append(day)
                    report.neededModel = true
                }
            } catch HippocampusError.runtimeNotLinked {
                store.enqueuePending(agentID: agentID, dateKey: day, reason: .runtimeNotLinked, now: now)
                report.pending.append(day)
                report.neededModel = true
            } catch {
                store.enqueuePending(agentID: agentID, dateKey: day, reason: .parseFailed, now: now)
                report.failures.append(day)
                report.pending.append(day)
            }
        }

        let weekKey = ISOWeek.previousWeekKey(before: now, calendar: calendar)
        let weekDays = Set(ISOWeek.dateKeys(in: weekKey, calendar: calendar))
        let rawInWeek = Set(store.rawTurns.filter { weekDays.contains($0.dateKey) }.map(\.dateKey))
        let summarized = Set(store.summaries.filter { $0.weekKey == weekKey }.map(\.dateKey))
        let incomplete = !rawInWeek.isEmpty && !rawInWeek.isSubset(of: summarized)
        if !incomplete {
            do {
                let outcome = try await weekly.consolidate(agentID: agentID,
                                                            weekKey: weekKey,
                                                            provider: provider,
                                                            store: store,
                                                            now: now)
                store = outcome.store
                if outcome.neededModel { report.neededModel = true }
                if outcome.created, let record = outcome.record {
                    report.weekly.append(record.weekKey)
                }
            } catch HippocampusError.runtimeNotLinked {
                report.neededModel = true
            } catch {
                report.failures.append(weekKey)
            }
        }
        return (store, report)
    }
}

enum ThirtyDayMarkdownExporter {
    static func render(store: HippocampusStore,
                       vector: EvolutionVector,
                       now: Date,
                       language: ContentLanguage,
                       calendar: Calendar = .current) -> String {
        let current = DayKey.string(for: now, calendar: calendar)
        let occupants = store.occupiedDateKeys.map { key in
            RingOccupant(dateKey: key, hasCompletedTask: store.rawTurns.contains { $0.dateKey == key && $0.isCompletedTask })
        }
        let ring = ThirtyDayRing.metadata(occupants: occupants, now: now, calendar: calendar)
        var lines: [String] = []
        lines.append("---")
        lines.append("agent: \(HomeAgent.id)")
        lines.append("exported: \(current)")
        lines.append("dominant_role: \(vector.dominantRole.rawValue)")
        lines.append("ring_capacity: \(ThirtyDayRing.capacity)")
        lines.append("export_warning: \(ring.exportWarning)")
        lines.append("pending: [\(store.pending.map(\.dateKey).joined(separator: ", "))]")
        lines.append("privacy: Local backup. Private talk may be in this file. It is not published to the family MQTT bus.")
        lines.append("---")
        lines.append("")
        lines.append(tr("# Dear Home memory", "# 亲爱的房子 · 记忆", language: language))
        lines.append("")
        if ring.exportWarning {
            lines.append(tr("> The oldest day in the 30-day ring will be released within 3 days.",
                            "> 30 天循环里最早的一天将在 3 天内释放。", language: language))
            lines.append("")
        }
        let days = store.occupiedDateKeys.sorted().reversed()
        for day in days {
            lines.append("## \(day)")
            if let summary = store.summary(agentID: HomeAgent.id, dateKey: day) {
                lines.append("")
                lines.append(tr("### Dialogue", "### 对话要点", language: language))
                lines.append(summary.dialogueSummary300)
                lines.append("")
                lines.append(tr("### House and schedule", "### 家居与日程", language: language))
                lines.append(summary.contextTaskSummary300)
            } else if store.pending.contains(where: { $0.dateKey == day }) {
                lines.append("")
                lines.append(tr("_Pending distillation. No summary was invented._",
                                "_待蒸馏。没有用规则编造总结。_", language: language))
            }
            let turns = store.turns(agentID: HomeAgent.id, dateKey: day)
            if !turns.isEmpty {
                lines.append("")
                for turn in turns {
                    lines.append("- \(turn.role): \(turn.content)")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
