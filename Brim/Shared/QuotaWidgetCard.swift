import SwiftUI
import WidgetKit

public struct QuotaWidgetCard: View {
    public var accounts: [QuotaAccount]
    public var family: WidgetFamilyShape
    public var showsEditLink: Bool
    public var selectedAccountID: QuotaAccount.ID?
    public var isAccountTextHidden: Bool
    public var pageIndex: Int

    public init(
        accounts: [QuotaAccount],
        family: WidgetFamilyShape,
        showsEditLink: Bool = false,
        selectedAccountID: QuotaAccount.ID? = nil,
        isAccountTextHidden: Bool = false,
        pageIndex: Int = 0
    ) {
        self.accounts = accounts
        self.family = family
        self.showsEditLink = showsEditLink
        self.selectedAccountID = selectedAccountID
        self.isAccountTextHidden = isAccountTextHidden
        self.pageIndex = pageIndex
    }

    private var controlForeground: Color {
        Color.primary.opacity(0.55)
    }

    public var body: some View {
        QuotaWidgetContent(
            accounts: accounts,
            family: family,
            selectedAccountID: selectedAccountID,
            isAccountTextHidden: isAccountTextHidden,
            pageIndex: pageIndex,
            surfaceStyle: .editorPreview,
            controls: { controlsView }
        )
    }

    private var controlsView: AnyView {
        guard showsEditLink, let editURL = URL(string: AppRoute.accounts.urlString) else {
            return AnyView(EmptyView())
        }

        return AnyView(
            Link(destination: editURL) {
                controlIcon("pencil")
            }
            .buttonStyle(.plain)
        )
    }

    private func controlIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: family.controlIconSize + 2, weight: .semibold, design: .rounded))
            .foregroundStyle(controlForeground)
            .frame(width: family.controlButtonSize, height: family.controlButtonSize)
    }
}
