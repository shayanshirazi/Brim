import SwiftUI
import WidgetKit

public typealias QuotaAccountSlotDecorator = (QuotaAccount, QuotaAccountSlotView) -> AnyView
public typealias QuotaPagerDecorator = (PagerDirection, PagerChevron) -> AnyView

public struct QuotaWidgetContent: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    public var accounts: [QuotaAccount]
    public var family: WidgetFamilyShape
    public var selectedAccountID: QuotaAccount.ID?
    public var isAccountTextHidden: Bool
    public var pageIndex: Int
    public var surfaceStyle: QuotaWidgetSurfaceStyle
    public var accountSlotDecorator: QuotaAccountSlotDecorator
    public var pagerDecorator: QuotaPagerDecorator
    public var controls: () -> AnyView

    public init(
        accounts: [QuotaAccount],
        family: WidgetFamilyShape,
        selectedAccountID: QuotaAccount.ID? = nil,
        isAccountTextHidden: Bool = false,
        pageIndex: Int = 0,
        surfaceStyle: QuotaWidgetSurfaceStyle = .editorPreview,
        accountSlotDecorator: @escaping QuotaAccountSlotDecorator = { _, slot in AnyView(slot) },
        pagerDecorator: @escaping QuotaPagerDecorator = { _, chevron in AnyView(chevron) },
        controls: @escaping () -> AnyView = { AnyView(EmptyView()) }
    ) {
        self.accounts = accounts
        self.family = family
        self.selectedAccountID = selectedAccountID
        self.isAccountTextHidden = isAccountTextHidden
        self.pageIndex = pageIndex
        self.surfaceStyle = surfaceStyle
        self.accountSlotDecorator = accountSlotDecorator
        self.pagerDecorator = pagerDecorator
        self.controls = controls
    }

    public var body: some View {
        let page = QuotaWidgetPage(accounts: accounts, selectedAccountID: selectedAccountID, pageIndex: pageIndex, pageSize: family.slotCount)
        let visibleAccounts = page.visibleAccounts(paddedTo: family.slotCount)
        let showsPager = accounts.count > family.slotCount

        ZStack(alignment: .bottomTrailing) {
            if surfaceStyle == .editorPreview {
                BrimBackground(cornerRadius: family.cornerRadius)
            }

            if accounts.isEmpty {
                QuotaWidgetEmptyState(family: family)
            } else {
                HStack(spacing: family.pagerSpacing) {
                    renderedPager(.left, showsPager: showsPager)

                    HStack(spacing: family.accountSpacing) {
                        ForEach(Array(visibleAccounts.enumerated()), id: \.offset) { _, account in
                            if let account {
                                let slot = QuotaAccountSlotView(
                                    account: account,
                                    family: family,
                                    isSelected: account.id == page.selectedAccount?.id,
                                    isTextHidden: isAccountTextHidden
                                )
                                accountSlotDecorator(account, slot)
                            } else {
                                QuotaAccountSlotView(account: nil, family: family)
                            }
                        }
                    }

                    renderedPager(.right, showsPager: showsPager)
                }
                .padding(.horizontal, family.horizontalPadding)
                .padding(.top, family.verticalPadding)
                .padding(.bottom, family.accountRowBottomPadding)
            }

            if !accounts.isEmpty {
                controls()
                    .padding(.bottom, family.controlButtonPadding)
                    .padding(.trailing, family.controlButtonPadding)
            }
        }
    }

    private func renderedPager(_ direction: PagerDirection, showsPager: Bool) -> some View {
        let chevron = PagerChevron(direction: direction, family: family, isVisible: showsPager)
        return Group {
            if showsPager {
                pagerDecorator(direction, chevron)
            } else {
                chevron
            }
        }
    }
}

private struct QuotaWidgetEmptyState: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    var family: WidgetFamilyShape

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    private var foreground: Color {
        isVibrant ? Color(hex: "#24586E") : Color(hex: "#173B46")
    }

    var body: some View {
        Group {
            if let accountsURL = URL(string: AppRoute.accounts.urlString) {
                Link(destination: accountsURL) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
        .widgetAccentable(false)
    }

    private var content: some View {
        VStack(spacing: family == .small ? 7 : 9) {
            ZStack {
                Circle()
                    .stroke(foreground.opacity(0.12), lineWidth: 5)
                Circle()
                    .stroke(
                        Color(hex: "#2CCB68"),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Circle()
                    .fill(Color(hex: "#2CCB68"))
                    .frame(width: 10, height: 10)
                    .shadow(color: Color(hex: "#2CCB68").opacity(0.28), radius: 5)
            }
            .frame(width: family == .small ? 44 : 48, height: family == .small ? 44 : 48)

            Text("Open Brim")
                .font(.system(size: family == .small ? 12 : 13, weight: .bold, design: .rounded))
                .foregroundStyle(foreground.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if family == .medium {
                Text("Local widget data is private")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(foreground.opacity(0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

public struct QuotaWidgetPage {
    public var accounts: [QuotaAccount]
    public var selectedAccountID: QuotaAccount.ID?
    public var pageIndex: Int
    public var pageSize: Int

    public var visiblePageIndex: Int {
        let safePageSize = max(1, pageSize)
        let maxPageIndex = max(0, Int(ceil(Double(accounts.count) / Double(safePageSize))) - 1)
        return min(max(0, pageIndex), maxPageIndex)
    }

    public var visibleRealAccounts: [QuotaAccount] {
        let safePageSize = max(1, pageSize)
        let startIndex = visiblePageIndex * safePageSize
        return accounts.dropFirst(startIndex).prefix(safePageSize).map { $0 }
    }

    public var selectedAccount: QuotaAccount? {
        visibleRealAccounts.first(where: { $0.id == selectedAccountID }) ?? visibleRealAccounts.first ?? accounts.first
    }

    public func visibleAccounts(paddedTo count: Int) -> [QuotaAccount?] {
        let slots = visibleRealAccounts.map(Optional.some)
        let emptySlots = Array<QuotaAccount?>(repeating: nil, count: max(0, count - slots.count))
        return slots + emptySlots
    }
}
