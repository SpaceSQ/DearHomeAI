import SwiftUI

struct SpaceScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let paper = PaperPalette.resolve(scheme)
        let language = model.resolvedLanguage
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(model.t("Space", "空间"))
                        .font(.system(.largeTitle, design: .serif))
                        .foregroundStyle(paper.ink)
                    Text(model.snapshot.status.text(language))
                        .font(.subheadline)
                        .foregroundStyle(paper.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.isLoadingHome {
                        ProgressView(model.t("Reading Apple Home…", "正在读取 Apple Home……"))
                            .tint(paper.ink)
                    }
                    if model.snapshot.rooms.isEmpty && !model.isLoadingHome {
                        empty(paper: paper)
                    }
                    ForEach(model.snapshot.rooms) { room in
                        roomBlock(room, paper: paper, language: language)
                    }
                    if !model.snapshot.scenes.isEmpty {
                        sceneBlock(paper: paper, language: language)
                    }
                }
                .padding(20)
            }
            .notebookBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            if !model.useSampleHome {
                await model.refreshHome()
            }
        }
    }

    private func empty(paper: PaperPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.t("No rooms yet", "还没有房间"))
                .font(.headline)
                .foregroundStyle(paper.ink)
            Text(model.t("The sample notebook is off, and Apple Home has not handed over a room. You can turn the sample back on in Setting.",
                         "示例手记关着，Apple Home 也还没有交出房间。可以在「设置」里重新打开示例。"))
                .font(.subheadline)
                .foregroundStyle(paper.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(paper.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func roomBlock(_ room: HomeRoom, paper: PaperPalette, language: ContentLanguage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(paper.ink).frame(width: 14, height: 14)
                Text(room.name.text(language))
                    .font(.system(.title2, design: .serif))
                    .foregroundStyle(paper.ink)
            }
            if !room.accessories.isEmpty {
                FlowChips(items: room.accessories.map { chip($0, language: language) }, color: paper)
            }
            let events = model.snapshot.events.filter { $0.roomID == room.id }.sorted { $0.occurredAt < $1.occurredAt }
            ForEach(events) { event in
                eventRow(event, paper: paper, language: language)
            }
        }
    }

    private func chip(_ accessory: HomeAccessory, language: ContentLanguage) -> String {
        var bits = [accessory.name.text(language)]
        if let on = accessory.isOn { bits.append(on ? tr("on", "开", language: language) : tr("off", "关", language: language)) }
        if let temperature = accessory.temperatureC { bits.append(String(format: "%.0f°C", temperature)) }
        if let humidity = accessory.humidity { bits.append(String(format: "%.0f%%", humidity <= 1 ? humidity * 100 : humidity)) }
        if let fan = accessory.fanSpeed { bits.append(tr("fan \(fan)", "风速 \(fan)", language: language)) }
        return bits.joined(separator: " · ")
    }

    private func eventRow(_ event: SpaceEvent, paper: PaperPalette, language: ContentLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(clock(event.occurredAt))
                    .font(.body.monospaced())
                    .foregroundStyle(paper.ink)
                Text(event.title.text(language))
                    .font(.body.weight(.medium))
                    .foregroundStyle(paper.ink)
                Spacer(minLength: 8)
                Button(model.t("Share", "共享")) { model.share(event: event) }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(paper.terracotta)
                    .accessibilityIdentifier("space.share.\(event.id)")
            }
            Text(event.detail.text(language))
                .font(.subheadline)
                .foregroundStyle(paper.secondary)
            Text(event.sourceLabel.text(language))
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(Capsule().stroke(paper.rule, lineWidth: 1))
            Rectangle().fill(paper.rule).frame(height: 1).padding(.top, 4)
        }
    }

    private func sceneBlock(paper: PaperPalette, language: ContentLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.t("Scenes", "场景"))
                .font(.headline)
                .foregroundStyle(paper.ink)
            Text(model.t("Scenes are listed so you can see them. This version will not run one.",
                         "场景列在这里给你看。这一版不会去执行。"))
                .font(.footnote)
                .foregroundStyle(paper.secondary)
            ForEach(model.snapshot.scenes) { scene in
                HStack {
                    Text(scene.name.text(language)).foregroundStyle(paper.ink)
                    Spacer()
                    Text(model.t("Suggest only", "仅建议"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(paper.terracotta)
                }
            }
        }
    }

    private func clock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

private struct FlowChips: View {
    var items: [String]
    var color: PaperPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(item)
                    .font(.caption)
                    .foregroundStyle(color.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(color.card, in: Capsule())
                    .overlay(Capsule().stroke(color.rule, lineWidth: 1))
            }
        }
    }
}
