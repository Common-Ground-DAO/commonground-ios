import SwiftUI

@main
struct CommonGroundApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(AppTheme.accent)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        Task { await model.sceneDidBecomeActive() }
                    case .inactive:
                        model.sceneDidBecomeInactive()
                    case .background:
                        model.sceneDidEnterBackground()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
