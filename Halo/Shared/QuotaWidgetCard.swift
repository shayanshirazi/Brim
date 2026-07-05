import SwiftUI
import WidgetKit

public struct QuotaWidgetCard: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

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

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    private var controlForeground: Color {
        isVibrant ? Color(hex: "#24586E").opacity(0.86) : Color.white.opacity(0.72)
    }

    private var controlBackground: Color {
        isVibrant ? Color(hex: "#1B6F95").opacity(0.10) : Color.white.opacity(0.09)
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
            HStack(spacing: family.controlSpacing) {
                Image(systemName: isAccountTextHidden ? "eye.slash" : "eye")
                    .font(.system(size: family.controlIconSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(controlForeground)
                    .frame(width: family.controlButtonSize, height: family.controlButtonSize)
                    .background(controlBackground, in: Circle())

                Link(destination: editURL) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: family.controlIconSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(controlForeground)
                        .frame(width: family.controlButtonSize, height: family.controlButtonSize)
                        .background(controlBackground, in: Circle())
                }
                .buttonStyle(.plain)
            }
        )
    }
}
