import WidgetKit

public enum QuotaWidgetCommands {
    public static func snapshot() -> QuotaState {
        let widgetSnapshotLoadResult = QuotaWidgetSnapshotStore().load()
        if widgetSnapshotLoadResult.status == .unavailable {
            // The widget cannot run app-only refresh or login code. This fallback
            // only mirrors the already-scrubbed repository state when the app
            // group snapshot is unavailable, such as during local development.
            return QuotaRepository().load().state.widgetSnapshotState()
        }
        return widgetSnapshotLoadResult.state
    }

    public static func selectAccount(id: QuotaAccount.ID?) {
        update { state in
            state.selectAccount(id: id)
        }
    }

    public static func setAccountTextHidden(_ isHidden: Bool) {
        update { state in
            state.setAccountTextHidden(isHidden)
        }
    }

    public static func toggleAccountTextHidden() {
        update { state in
            state.toggleAccountTextHidden()
        }
    }

    public static func setWidgetPageIndex(_ pageIndex: Int, pageSize: Int) {
        update { state in
            state.setWidgetPageIndex(pageIndex, pageSize: pageSize)
        }
    }

    public static func moveWidgetPage(by offset: Int, pageSize: Int) {
        update { state in
            state.moveWidgetPage(by: offset, pageSize: pageSize)
        }
    }

    private static func update(_ mutate: (inout QuotaState) -> Void) {
        let snapshotStore = QuotaWidgetSnapshotStore()
        var state = snapshotStore.load().state
        mutate(&state)
        _ = snapshotStore.save(state)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
