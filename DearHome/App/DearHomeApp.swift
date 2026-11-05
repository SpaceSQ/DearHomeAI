import SwiftUI

@main
@MainActor
struct DearHomeApp: App {
    @State private var model: AppModel
    @State private var showPrelude = true

    init() {
        let model = AppModel()
        model.bootstrap()
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if model.isBound {
                    RootTabView()
                } else {
                    AccountGateView()
                }
            }
            .environment(model)
            .opacity(showPrelude ? 0 : 1)
            .overlay {
                if showPrelude {
                    DearHomeLaunchPreludeView { showPrelude = false }
                        .transition(.opacity)
                }
            }
            .environment(model)
            .animation(.easeInOut(duration: 0.35), value: showPrelude)
            .animation(.easeInOut(duration: 0.3), value: model.isBound)
        }
    }
}
