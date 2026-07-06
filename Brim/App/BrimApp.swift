import AppKit
import SwiftUI

@main
struct BrimApp: App {
    var body: some Scene {
        WindowGroup {
            BrimAppRootView()
                .frame(
                    minWidth: BrimWindowMetrics.minWidth,
                    maxWidth: .infinity,
                    minHeight: BrimWindowMetrics.minHeight,
                    maxHeight: .infinity
                )
                .background(WindowSizeConfigurator())
        }
        .defaultSize(width: BrimWindowMetrics.defaultWidth, height: BrimWindowMetrics.defaultHeight)
        .windowStyle(.hiddenTitleBar)
    }
}

enum BrimWindowMetrics {
    static let defaultWidth: CGFloat = 980
    static let defaultHeight: CGFloat = 620
    static let minWidth: CGFloat = 980
    static let minHeight: CGFloat = 620
    static let maxWidth: CGFloat = 1280
    static let maxHeight: CGFloat = 820
}

private struct WindowSizeConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configureWindow(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindow(for: nsView, coordinator: context.coordinator)
    }

    private func configureWindow(for view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }

            let minSize = NSSize(width: BrimWindowMetrics.minWidth, height: BrimWindowMetrics.minHeight)
            let maxSize = NSSize(width: BrimWindowMetrics.maxWidth, height: BrimWindowMetrics.maxHeight)
            window.minSize = minSize
            window.maxSize = maxSize
            window.styleMask.insert(.resizable)

            guard !coordinator.didApplyInitialSize else {
                return
            }
            coordinator.didApplyInitialSize = true

            let currentSize = window.frame.size
            let targetSize = NSSize(
                width: min(max(currentSize.width, BrimWindowMetrics.defaultWidth), BrimWindowMetrics.maxWidth),
                height: min(max(currentSize.height, BrimWindowMetrics.defaultHeight), BrimWindowMetrics.maxHeight)
            )

            guard currentSize != targetSize else {
                return
            }

            window.setContentSize(targetSize)
            window.center()
        }
    }

    final class Coordinator {
        var didApplyInitialSize = false
    }
}

private struct BrimAppRootView: View {
    @State private var store: QuotaStore
    @State private var route: AppRoute?

    init() {
        let refreshService = QuotaRefreshService(
            apiTokenIsAvailable: { CredentialStore.shared.hasAPIToken(credentialID: $0) }
        )
        _store = State(initialValue: QuotaStore(repository: QuotaRepository(), refreshService: refreshService))
    }

    var body: some View {
        AccountSettingsView(route: route)
            .environmentObject(store)
            .onOpenURL { url in
                route = AppRoute.parse(url)
            }
    }
}
