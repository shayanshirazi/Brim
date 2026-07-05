import SwiftUI

@main
struct HaloApp: App {
    @StateObject private var store = QuotaStore()

    var body: some Scene {
        WindowGroup {
            AccountSettingsView()
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 520)
                .onOpenURL { _ in }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
