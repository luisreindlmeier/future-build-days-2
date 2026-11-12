import SwiftUI

@main
struct KairosApp: App {
    @State private var model = AppModel(store: DebugLaunch.store)

    init() {
        Appearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.light)
                .tint(.ink)
        }
    }
}
