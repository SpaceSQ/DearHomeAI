import SwiftUI

struct RootTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var model = model
        let paper = PaperPalette.resolve(scheme)
        TabView(selection: $model.tab) {
            ChatScreen()
                .tag(AppTab.home)
                .tabItem { Label(model.t("Home", "房子"), systemImage: AppTab.home.symbol) }
            SpaceScreen()
                .tag(AppTab.space)
                .tabItem { Label(model.t("Space", "空间"), systemImage: AppTab.space.symbol) }
            MemoriesScreen()
                .tag(AppTab.memories)
                .tabItem { Label(model.t("Memories", "记忆"), systemImage: AppTab.memories.symbol) }
            EvolutionScreen()
                .tag(AppTab.evolution)
                .tabItem { Label(model.t("Evolution", "演化"), systemImage: AppTab.evolution.symbol) }
            SettingsScreen()
                .tag(AppTab.setting)
                .tabItem { Label(model.t("Setting", "设置"), systemImage: AppTab.setting.symbol) }
        }
        .tint(paper.terracotta)
        .toolbarBackground(paper.paper, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
