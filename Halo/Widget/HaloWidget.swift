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
            accounts: QuotaAccount.examples,
            selectedAccountID: QuotaAccount.examples.first?.id,
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
        let accounts = QuotaStore.widgetSnapshot()
        return QuotaEntry(
            date: Date(),
            accounts: accounts,
            selectedAccountID: QuotaStore.selectedAccountID() ?? accounts.first?.id,
            isAccountTextHidden: QuotaStore.isAccountTextHidden(),
            pageIndex: QuotaStore.widgetPageIndex()
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
            QuotaStore.setSelectedAccountID(uuid)
        }
        return .result()
    }
}

struct ToggleAccountTextVisibilityIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle account text visibility"

    init() {}

    func perform() async throws -> some IntentResult {
        QuotaStore.toggleAccountTextHidden()
        return .result()
    }
}

struct MoveWidgetPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Move widget page"

    @Parameter(title: "Offset")
    var offset: Int

    @Parameter(title: "Account count")
    var accountCount: Int

    @Parameter(title: "Page size")
    var pageSize: Int

    init() {
        offset = 0
        accountCount = 0
        pageSize = 1
    }

    init(offset: Int, accountCount: Int, pageSize: Int) {
        self.offset = offset
        self.accountCount = accountCount
        self.pageSize = pageSize
    }

    func perform() async throws -> some IntentResult {
        QuotaStore.moveWidgetPage(by: offset, accountCount: accountCount, pageSize: pageSize)
        return .result()
    }
}

struct HaloWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let entry: QuotaEntry

    var body: some View {
        let family: WidgetFamilyShape = widgetFamily == .systemSmall ? .small : .medium

        InteractiveQuotaWidgetCard(
            accounts: entry.accounts,
            family: family,
            selectedAccountID: entry.selectedAccountID,
            isAccountTextHidden: entry.isAccountTextHidden,
            pageIndex: entry.pageIndex
        )
        .containerBackground(for: .widget) {
            HaloBackground(cornerRadius: family.cornerRadius)
        }
    }
}

private struct InteractiveQuotaWidgetCard: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    var accounts: [QuotaAccount]
    var family: WidgetFamilyShape
    var selectedAccountID: QuotaAccount.ID?
    var isAccountTextHidden: Bool
    var pageIndex: Int

    private var selectedAccount: QuotaAccount? {
        accounts.first(where: { $0.id == selectedAccountID }) ?? accounts.first
    }

    private var visiblePageIndex: Int {
        guard family.slotCount > 0 else {
            return 0
        }
        let maxPageIndex = max(0, Int(ceil(Double(accounts.count) / Double(family.slotCount))) - 1)
        return min(max(0, pageIndex), maxPageIndex)
    }

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    private var controlForeground: Color {
        isVibrant ? Color(hex: "#24586E").opacity(0.86) : Color.white.opacity(0.72)
    }

    private var controlBackground: Color {
        isVibrant ? Color(hex: "#1B6F95").opacity(0.10) : Color.white.opacity(0.09)
    }

    var body: some View {
        let pageStartIndex = visiblePageIndex * family.slotCount
        let slots = accounts.dropFirst(pageStartIndex).prefix(family.slotCount).map(Optional.some)
        let emptySlots = Array<QuotaAccount?>(repeating: nil, count: max(0, family.slotCount - slots.count))
        let visibleAccounts = slots + emptySlots
        let showsPager = accounts.count > family.slotCount

        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: family.pagerSpacing) {
                if showsPager {
                    Button(intent: MoveWidgetPageIntent(offset: -1, accountCount: accounts.count, pageSize: family.slotCount)) {
                        PagerChevron(direction: .left, family: family, isVisible: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    PagerChevron(direction: .left, family: family, isVisible: false)
                }

                HStack(spacing: family.accountSpacing) {
                    ForEach(Array(visibleAccounts.enumerated()), id: \.offset) { _, account in
                        if let account {
                            Button(intent: SelectQuotaAccountIntent(accountID: account.id.uuidString)) {
                                QuotaAccountSlotView(
                                    account: account,
                                    family: family,
                                    isSelected: account.id == selectedAccount?.id,
                                    isTextHidden: isAccountTextHidden
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            QuotaAccountSlotView(account: nil, family: family)
                        }
                    }
                }

                if showsPager {
                    Button(intent: MoveWidgetPageIntent(offset: 1, accountCount: accounts.count, pageSize: family.slotCount)) {
                        PagerChevron(direction: .right, family: family, isVisible: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    PagerChevron(direction: .right, family: family, isVisible: false)
                }
            }
            .padding(.horizontal, family.horizontalPadding)
            .padding(.top, family.verticalPadding)
            .padding(.bottom, family.accountRowBottomPadding)

            if family.showsDetails, let selectedAccount {
                QuotaResetReadout(account: selectedAccount, family: family, isTextHidden: isAccountTextHidden)
                    .padding(.leading, family.resetInfoLeadingPadding)
                    .padding(.bottom, family.resetInfoBottomPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

            HStack(spacing: family.controlSpacing) {
                Button(intent: ToggleAccountTextVisibilityIntent()) {
                    Image(systemName: isAccountTextHidden ? "eye.slash" : "eye")
                        .font(.system(size: family.controlIconSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(controlForeground)
                        .frame(width: family.controlButtonSize, height: family.controlButtonSize)
                        .background(controlBackground, in: Circle())
                }
                .buttonStyle(.plain)

                if let editURL = URL(string: "halo://accounts") {
                    Link(destination: editURL) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: family.controlIconSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(controlForeground)
                            .frame(width: family.controlButtonSize, height: family.controlButtonSize)
                            .background(controlBackground, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, family.controlButtonPadding)
            .padding(.trailing, family.controlButtonPadding)
        }
    }
}

@main
struct HaloWidget: Widget {
    let kind = "HaloWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaProvider()) { entry in
            HaloWidgetView(entry: entry)
        }
        .configurationDisplayName("Halo")
        .description("Track weekly quota across local accounts.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}
