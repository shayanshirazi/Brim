import AppIntents
import SwiftUI
import WidgetKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let accounts: [QuotaAccount]
    let selectedAccountID: QuotaAccount.ID?
    let isAccountTextHidden: Bool
    let pageIndex: Int
}

struct QuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(
            date: Date(),
            accounts: QuotaAccountDefaults.examples,
            selectedAccountID: QuotaAccountDefaults.examples.first?.id,
            isAccountTextHidden: false,
            pageIndex: 0
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(snapshotEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let entry = snapshotEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func snapshotEntry() -> QuotaEntry {
        let state = QuotaWidgetCommands.snapshot()
        return QuotaEntry(
            date: Date(),
            accounts: state.accounts,
            selectedAccountID: state.selectedAccountID,
            isAccountTextHidden: state.isAccountTextHidden,
            pageIndex: state.widgetPageIndex
        )
    }
}

struct SelectQuotaAccountIntent: AppIntent {
    static var title: LocalizedStringResource = "Select quota account"

    @Parameter(title: "Account ID")
    var accountID: String

    init() {
        accountID = ""
    }

    init(accountID: String) {
        self.accountID = accountID
    }

    func perform() async throws -> some IntentResult {
        if let uuid = UUID(uuidString: accountID) {
            QuotaWidgetCommands.selectAccount(id: uuid)
        }
        return .result()
    }
}

struct ToggleAccountTextVisibilityIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle account text visibility"

    init() {}

    func perform() async throws -> some IntentResult {
        QuotaWidgetCommands.toggleAccountTextHidden()
        return .result()
    }
}

struct MoveWidgetPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Move widget page"

    @Parameter(title: "Offset")
    var offset: Int

    @Parameter(title: "Page size")
    var pageSize: Int

    init() {
        offset = 0
        pageSize = 1
    }

    init(offset: Int, pageSize: Int) {
        self.offset = offset
        self.pageSize = pageSize
    }

    func perform() async throws -> some IntentResult {
        QuotaWidgetCommands.moveWidgetPage(by: offset, pageSize: pageSize)
        return .result()
    }
}

struct BrimWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let entry: QuotaEntry

    var body: some View {
        let family: WidgetFamilyShape = widgetFamily == .systemSmall ? .small : .medium

        QuotaWidgetContent(
            accounts: entry.accounts,
            family: family,
            selectedAccountID: entry.selectedAccountID,
            isAccountTextHidden: entry.isAccountTextHidden,
            pageIndex: entry.pageIndex,
            surfaceStyle: .none,
            accountSlotDecorator: { account, slot in
                AnyView(
                    Button(intent: SelectQuotaAccountIntent(accountID: account.id.uuidString)) {
                        slot
                    }
                    .buttonStyle(.plain)
                )
            },
            pagerDecorator: { direction, chevron in
                AnyView(
                    Button(intent: MoveWidgetPageIntent(offset: direction == .left ? -1 : 1, pageSize: family.slotCount)) {
                        chevron
                    }
                    .buttonStyle(.plain)
                )
            },
            controls: {
                AnyView(
                    WidgetControls(family: family, isAccountTextHidden: entry.isAccountTextHidden)
                )
            }
        )
        .containerBackground(for: .widget) {
            DesktopWidgetSurface(cornerRadius: family.cornerRadius)
        }
    }
}

private struct WidgetControls: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    var family: WidgetFamilyShape
    var isAccountTextHidden: Bool

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    private var controlForeground: Color {
        (isVibrant ? Color(hex: "#24586E") : Color(hex: "#173B46")).opacity(0.76)
    }

    private var controlBackground: Color {
        (isVibrant ? Color(hex: "#1B6F95") : Color(hex: "#173B46")).opacity(0.08)
    }

    var body: some View {
        HStack(spacing: family.controlSpacing) {
            Button(intent: ToggleAccountTextVisibilityIntent()) {
                controlIcon(isAccountTextHidden ? "eye.slash" : "eye")
            }
            .buttonStyle(.plain)

            if let editURL = URL(string: AppRoute.accounts.urlString) {
                Link(destination: editURL) {
                    controlIcon("pencil")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func controlIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: family.controlIconSize, weight: .semibold, design: .rounded))
            .foregroundStyle(controlForeground)
            .frame(width: family.controlButtonSize, height: family.controlButtonSize)
            .background(controlBackground, in: Circle())
            .overlay {
                Circle()
                    .stroke(controlForeground.opacity(0.12), lineWidth: 0.8)
            }
    }
}

@main
struct BrimWidget: Widget {
    let kind = "BrimWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaProvider()) { entry in
            BrimWidgetView(entry: entry)
        }
        .configurationDisplayName("Brim")
        .description("Track weekly quota across local accounts.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}
