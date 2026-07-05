import SwiftUI

@main
struct HaloApp: App {
    var body: some Scene {
        WindowGroup {
            HaloAppRootView()
                .frame(minWidth: 760, minHeight: 520)
                .onOpenURL { _ in }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

private struct HaloAppRootView: View {
    @State private var store: QuotaStore?
    @State private var accessWasDenied = false

    private let confirmedAccessKey = "halo.shared-access-confirmed.v1"

    var body: some View {
        Group {
            if let store {
                AccountSettingsView()
                    .environmentObject(store)
            } else {
                SharedAccessView(
                    accessWasDenied: accessWasDenied,
                    continueAction: requestSharedAccess
                )
            }
        }
        .onAppear {
            guard UserDefaults.standard.bool(forKey: confirmedAccessKey) else {
                return
            }
            requestSharedAccess()
        }
    }

    private func requestSharedAccess() {
        let nextStore = QuotaStore()
        if nextStore.isUsingSharedDefaults {
            UserDefaults.standard.set(true, forKey: confirmedAccessKey)
            store = nextStore
            accessWasDenied = false
        } else {
            UserDefaults.standard.set(false, forKey: confirmedAccessKey)
            accessWasDenied = true
        }
    }
}

private struct SharedAccessView: View {
    var accessWasDenied: Bool
    var continueAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: accessWasDenied ? "lock.trianglebadge.exclamationmark" : "slider.horizontal.below.square.filled.and.square")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color(hex: "#2084B5"))

            VStack(spacing: 7) {
                Text(accessWasDenied ? "Widget Data Access Was Not Allowed" : "Manage Halo Widget Data")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text(accessWasDenied ? "Halo cannot edit widget accounts until shared widget data access is allowed." : "Halo uses a shared container so the app and desktop widget can read the same local account list.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 390)
            }

            Button(action: continueAction) {
                Label(accessWasDenied ? "Try Again" : "Continue", systemImage: "arrow.right")
                    .frame(minWidth: 128)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(hex: "#EAF8F2").opacity(0.45)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
