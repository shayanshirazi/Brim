import SwiftUI
import WidgetKit

public struct QuotaRingView: View {
    public var account: QuotaAccount?
    public var diameter: CGFloat
    public var lineWidth: CGFloat
    public var showPercent: Bool

    public init(
        account: QuotaAccount?,
        diameter: CGFloat,
        lineWidth: CGFloat = 5,
        showPercent: Bool = true
    ) {
        self.account = account
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.showPercent = showPercent
    }

    public var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(account == nil ? 0.08 : 0.12), lineWidth: lineWidth)

                if let account {
                    Circle()
                        .trim(from: 0, to: account.weeklyRemainingFraction)
                        .stroke(
                            Color(hex: account.colorHex),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    Circle()
                        .fill(Color(hex: account.colorHex).opacity(0.16))
                        .padding(lineWidth * 2.5)
                }
            }
            .frame(width: diameter, height: diameter)

            if showPercent {
                Text(account?.remainingPercentText ?? "")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary.opacity(account == nil ? 0 : 0.62))
                    .frame(height: 15)
            }
        }
        .frame(width: diameter + 8)
    }
}

public struct NestedQuotaRingView: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    public var account: QuotaAccount?
    public var diameter: CGFloat
    public var isSelected: Bool

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    public init(account: QuotaAccount?, diameter: CGFloat, isSelected: Bool = false) {
        self.account = account
        self.diameter = diameter
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(
                    isVibrant
                        ? Color(hex: "#1B6F95").opacity(account == nil ? 0.16 : 0.22)
                        : Color.white.opacity(account == nil ? 0.13 : 0.22),
                    lineWidth: 4
                )

            if let account {
                Circle()
                    .trim(from: 0, to: account.weeklyRemainingFraction)
                    .stroke(
                        Color(hex: account.colorHex),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Circle()
                    .stroke(
                        isVibrant
                            ? Color(hex: "#1B6F95").opacity(0.16)
                            : Color.white.opacity(0.16),
                        lineWidth: 7
                    )
                    .padding(13)

                Circle()
                    .trim(from: 0, to: account.sessionRemainingFraction)
                    .stroke(
                        isVibrant
                            ? Color(hex: "#1B6F95").opacity(0.70)
                            : Color.white.opacity(0.82),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(13)

                Circle()
                    .fill(Color(hex: account.colorHex).opacity(isVibrant ? 0.10 : 0.24))
                    .padding(24)
            }

            if isSelected {
                Circle()
                    .stroke(
                        isVibrant
                            ? Color(hex: "#1B6F95").opacity(0.44)
                            : Color.white.opacity(0.58),
                        lineWidth: 1.3
                    )
                    .padding(-4)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.snappy(duration: 0.22), value: isSelected)
    }
}

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
        let visiblePageIndex = clampedPageIndex(for: accounts)
        let pageStartIndex = visiblePageIndex * family.slotCount
        let slots = accounts.dropFirst(pageStartIndex).prefix(family.slotCount).map(Optional.some)
        let emptySlots = Array<QuotaAccount?>(repeating: nil, count: max(0, family.slotCount - slots.count))
        let visibleAccounts = slots + emptySlots
        let selectedAccount = selectedAccount(from: accounts)
        let showsPager = accounts.count > family.slotCount

        ZStack(alignment: .bottomTrailing) {
            HaloBackground(cornerRadius: family.cornerRadius)

            HStack(spacing: family.pagerSpacing) {
                PagerChevron(direction: .left, family: family, isVisible: showsPager)

                HStack(spacing: family.accountSpacing) {
                    ForEach(Array(visibleAccounts.enumerated()), id: \.offset) { _, account in
                        QuotaAccountSlotView(
                            account: account,
                            family: family,
                            isSelected: account?.id == selectedAccount?.id,
                            isTextHidden: isAccountTextHidden
                        )
                    }
                }

                PagerChevron(direction: .right, family: family, isVisible: showsPager)
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

            if showsEditLink, let editURL = URL(string: "halo://accounts") {
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
                .padding(.bottom, family.controlButtonPadding)
                .padding(.trailing, family.controlButtonPadding)
            }
        }
    }

    private func selectedAccount(from accounts: [QuotaAccount]) -> QuotaAccount? {
        accounts.first(where: { $0.id == selectedAccountID }) ?? accounts.first
    }

    private func clampedPageIndex(for accounts: [QuotaAccount]) -> Int {
        guard family.slotCount > 0 else {
            return 0
        }
        let maxPageIndex = max(0, Int(ceil(Double(accounts.count) / Double(family.slotCount))) - 1)
        return min(max(0, pageIndex), maxPageIndex)
    }
}

public struct QuotaAccountSlotView: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    public var account: QuotaAccount?
    public var family: WidgetFamilyShape
    public var isSelected: Bool
    public var isTextHidden: Bool

    public init(
        account: QuotaAccount?,
        family: WidgetFamilyShape,
        isSelected: Bool = false,
        isTextHidden: Bool = false
    ) {
        self.account = account
        self.family = family
        self.isSelected = isSelected
        self.isTextHidden = isTextHidden
    }

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    private var labelColor: Color {
        isVibrant ? Color(hex: "#24586E") : Color.white
    }

    public var body: some View {
        VStack(spacing: family.accountLabelSpacing) {
            NestedQuotaRingView(
                account: account,
                diameter: family.ringDiameter,
                isSelected: isSelected
            )
            .frame(width: family.ringSlotWidth, height: family.ringSlotWidth)

            VStack(spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(account == nil ? "" : "5h")
                        .font(.system(size: family.weeklyLabelFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(labelColor.opacity(account == nil ? 0 : 0.58))
                        .lineLimit(1)

                    Text(account == nil ? "" : (isTextHidden ? "***" : (account?.sessionPercentText ?? "")))
                        .font(.system(size: family.sessionLabelFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(labelColor.opacity(account == nil ? 0 : 0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(height: family.sessionLabelHeight)

                Text(account == nil ? "" : (isTextHidden ? "***" : "weekly \(account?.remainingPercentText ?? "")"))
                    .font(.system(size: family.weeklyLabelFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(labelColor.opacity(account == nil ? 0 : 0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(height: family.weeklyLabelHeight)
            }
            .frame(width: family.accountSlotWidth)
        }
        .frame(width: family.accountSlotWidth)
    }
}

public struct QuotaResetReadout: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    public var account: QuotaAccount
    public var family: WidgetFamilyShape
    public var isTextHidden: Bool

    public init(account: QuotaAccount, family: WidgetFamilyShape, isTextHidden: Bool = false) {
        self.account = account
        self.family = family
        self.isTextHidden = isTextHidden
    }

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    private var labelColor: Color {
        isVibrant ? Color(hex: "#24586E") : Color.white
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(isTextHidden ? "***" : "Weekly reset in \(account.weeklyResetRelativeText())")
                .font(.system(size: family.resetInfoPrimaryFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(labelColor.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text(isTextHidden ? "***" : account.weeklyResetDateText())
                .font(.system(size: family.resetInfoSecondaryFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(labelColor.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(width: family.resetInfoWidth, alignment: .leading)
    }
}

public enum PagerDirection {
    case left
    case right
}

public struct PagerChevron: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    public var direction: PagerDirection
    public var family: WidgetFamilyShape
    public var isVisible: Bool

    public init(direction: PagerDirection, family: WidgetFamilyShape, isVisible: Bool) {
        self.direction = direction
        self.family = family
        self.isVisible = isVisible
    }

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    private var chevronColor: Color {
        isVibrant ? Color(hex: "#24586E") : Color.white
    }

    public var body: some View {
        Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
            .font(.system(size: family.pagerIconSize, weight: .bold, design: .rounded))
            .foregroundStyle(chevronColor.opacity(isVisible ? 0.58 : 0))
            .frame(width: family.pagerButtonSize, height: family.pagerButtonSize)
    }
}

public struct QuotaWidgetDetail: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    public var account: QuotaAccount
    public var isTextHidden: Bool

    public init(account: QuotaAccount, isTextHidden: Bool = false) {
        self.account = account
        self.isTextHidden = isTextHidden
    }

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Text(isTextHidden ? "***" : account.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text(isTextHidden ? "***" : "resets \(account.resetText)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .opacity(0.72)
                    .lineLimit(1)
            }

            Text(isTextHidden ? "***" : "5h \(formatMinutes(account.sessionRemainingMinutes)) left / weekly \(formatMinutes(account.weeklyRemainingMinutes)) left")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .opacity(0.78)
        }
        .foregroundStyle(isVibrant ? Color(hex: "#24586E") : Color.white.opacity(0.84))
    }
}

public struct HaloBackground: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                isVibrant
                    ? Color(hex: "#2F94C7").opacity(0.16)
                    : Color(hex: "#2084B5").opacity(0.20)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isVibrant
                            ? Color(hex: "#1B6F95").opacity(0.22)
                            : Color.white.opacity(0.22),
                        lineWidth: 1
                    )
            }
    }
}

public enum WidgetFamilyShape {
    case small
    case medium

    public var slotCount: Int {
        switch self {
        case .small:
            return 2
        case .medium:
            return 4
        }
    }

    public var ringDiameter: CGFloat {
        switch self {
        case .small:
            return 54
        case .medium:
            return 52
        }
    }

    public var ringSlotWidth: CGFloat {
        ringDiameter + 2
    }

    public var ringSpacing: CGFloat {
        switch self {
        case .small:
            return 12
        case .medium:
            return 12
        }
    }

    public var accountSpacing: CGFloat {
        switch self {
        case .small:
            return 13
        case .medium:
            return 16
        }
    }

    public var accountSlotWidth: CGFloat {
        switch self {
        case .small:
            return 60
        case .medium:
            return 58
        }
    }

    public var accountLabelSpacing: CGFloat {
        switch self {
        case .small:
            return 6
        case .medium:
            return 6
        }
    }

    public var weeklyLabelFontSize: CGFloat {
        switch self {
        case .small:
            return 9
        case .medium:
            return 9
        }
    }

    public var weeklyLabelHeight: CGFloat {
        switch self {
        case .small:
            return 11
        case .medium:
            return 11
        }
    }

    public var sessionLabelFontSize: CGFloat {
        switch self {
        case .small:
            return 18
        case .medium:
            return 18
        }
    }

    public var sessionLabelHeight: CGFloat {
        switch self {
        case .small:
            return 21
        case .medium:
            return 21
        }
    }

    public var verticalSpacing: CGFloat {
        switch self {
        case .small:
            return 8
        case .medium:
            return 12
        }
    }

    public var horizontalPadding: CGFloat {
        switch self {
        case .small:
            return 15
        case .medium:
            return 16
        }
    }

    public var verticalPadding: CGFloat {
        switch self {
        case .small:
            return 15
        case .medium:
            return 13
        }
    }

    public var accountRowBottomPadding: CGFloat {
        switch self {
        case .small:
            return 15
        case .medium:
            return 39
        }
    }

    public var cornerRadius: CGFloat {
        switch self {
        case .small:
            return 24
        case .medium:
            return 24
        }
    }

    public var controlButtonSize: CGFloat {
        switch self {
        case .small:
            return 22
        case .medium:
            return 24
        }
    }

    public var controlIconSize: CGFloat {
        switch self {
        case .small:
            return 9
        case .medium:
            return 10
        }
    }

    public var controlButtonPadding: CGFloat {
        switch self {
        case .small:
            return 10
        case .medium:
            return 10
        }
    }

    public var controlSpacing: CGFloat {
        switch self {
        case .small:
            return 5
        case .medium:
            return 6
        }
    }

    public var pagerButtonSize: CGFloat {
        switch self {
        case .small:
            return 16
        case .medium:
            return 18
        }
    }

    public var pagerIconSize: CGFloat {
        switch self {
        case .small:
            return 10
        case .medium:
            return 11
        }
    }

    public var pagerSpacing: CGFloat {
        switch self {
        case .small:
            return 5
        case .medium:
            return 7
        }
    }

    public var resetInfoWidth: CGFloat {
        switch self {
        case .small:
            return 0
        case .medium:
            return 220
        }
    }

    public var resetInfoLeadingPadding: CGFloat {
        switch self {
        case .small:
            return 0
        case .medium:
            return 18
        }
    }

    public var resetInfoBottomPadding: CGFloat {
        switch self {
        case .small:
            return 0
        case .medium:
            return 11
        }
    }

    public var resetInfoPrimaryFontSize: CGFloat {
        switch self {
        case .small:
            return 0
        case .medium:
            return 10
        }
    }

    public var resetInfoSecondaryFontSize: CGFloat {
        switch self {
        case .small:
            return 0
        case .medium:
            return 9
        }
    }

    public var showsDetails: Bool {
        switch self {
        case .small:
            return false
        case .medium:
            return true
        }
    }
}

public func formatMinutes(_ minutes: Int) -> String {
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours == 0 {
        return "\(remainder)m"
    }
    return "\(hours)h \(remainder)m"
}
