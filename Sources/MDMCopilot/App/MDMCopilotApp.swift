import SwiftUI

enum AppBrand {
    static var displayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "MDM Profile Builder Demo"
    }
}

@main
struct MDMCopilotApp: App {
    @StateObject private var workspace = WorkspaceViewModel()
    @StateObject private var access = AccessController()

    var body: some Scene {
        WindowGroup(AppBrand.displayName) {
            AccessGateView()
                .environmentObject(workspace)
                .environmentObject(access)
                .frame(minWidth: 1_100, minHeight: 720)
                .task {
                    await workspace.restoreEnhancedModelIfEnabled()
                }
        }
        .defaultSize(width: 1_360, height: 860)

        Settings {
            AccessSettingsGateView()
                .environmentObject(access)
        }
    }
}
