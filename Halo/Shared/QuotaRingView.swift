import SwiftUI

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
    public var account: QuotaAccount?
    public var diameter: CGFloat
    public var isSelected: Bool

    public init(account: QuotaAccount?, diameter: CGFloat, isSelected: Bool = false) {
        self.account = account
        self.diameter = diameter
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(account == nil ? 0.16 : 0.28), lineWidth: 4)

            if let account {
                Circle()
                    .trim(from: 0, to: account.weeklyRemainingFraction)
                    .stroke(
                        Color(hex: account.colorHex),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Circle()
                    .stroke(.white.opacity(0.20), lineWidth: 7)
                    .padding(13)

                Circle()
                    .trim(from: 0, to: account.sessionRemainingFraction)
                    .stroke(
                        Color.white.opacity(0.92),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(13)

                Circle()
                    .fill(Color(hex: account.colorHex).opacity(0.24))
                    .padding(24)
            }

            if isSelected {
                Circle()
                    .stroke(.white.opacity(0.72), lineWidth: 1.3)
                    .padding(-4)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.snappy(duration: 0.22), value: isSelected)
    }
}

public struct QuotaWidgetCard: View {
    public var accounts: [QuotaAccount]
    public var family: WidgetFamilyShape
    public var showsEditLink: Bool
    public var selectedAccountID: QuotaAccount.ID?

    public init(
        accounts: [QuotaAccount],
        family: WidgetFamilyShape,
        showsEditLink: Bool = false,
        selectedAccountID: QuotaAccount.ID? = nil
    ) {
        self.accounts = accounts
        self.family = family
        self.showsEditLink = showsEditLink
        self.selectedAccountID = selectedAccountID
    }

    public var body: some View {
        let slots = accounts.prefix(family.slotCount).map(Optional.some)
        let emptySlots = Array<QuotaAccount?>(repeating: nil, count: max(0, family.slotCount - slots.count))
        let visibleAccounts = slots + emptySlots
        let selectedAccount = selectedAccount(from: accounts)

        ZStack(alignment: .topTrailing) {
            HaloBackground(cornerRadius: family.cornerRadius)

            VStack(spacing: family.verticalSpacing) {
                Spacer(minLength: 0)

                HStack(spacing: family.ringSpacing) {
                    ForEach(Array(visibleAccounts.enumerated()), id: \.offset) { _, account in
                        NestedQuotaRingView(
                            account: account,
                            diameter: family.ringDiameter,
                            isSelected: account?.id == selectedAccount?.id
                        )
                        .frame(width: family.ringSlotWidth, height: family.ringSlotWidth)
                    }
                }
                .frame(maxWidth: .infinity)

                if family.showsDetails, let selectedAccount {
                    QuotaWidgetDetail(account: selectedAccount)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, family.horizontalPadding)
            .padding(.vertical, family.verticalPadding)

            if showsEditLink, let editURL = URL(string: "halo://accounts") {
                Link(destination: editURL) {
                    Image(systemName: "pencil")
                        .font(.system(size: family.editIconSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: family.editButtonSize, height: family.editButtonSize)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, family.editButtonPadding)
                .padding(.trailing, family.editButtonPadding)
            }
        }
    }

    private func selectedAccount(from accounts: [QuotaAccount]) -> QuotaAccount? {
        accounts.first(where: { $0.id == selectedAccountID }) ?? accounts.first
    }
}

public struct QuotaWidgetDetail: View {
    public var account: QuotaAccount

    public init(account: QuotaAccount) {
        self.account = account
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Text(account.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text("resets \(account.resetText)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .opacity(0.72)
                    .lineLimit(1)
            }

            Text("5h \(formatMinutes(account.sessionRemainingMinutes)) left / weekly \(formatMinutes(account.weeklyRemainingMinutes)) left")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .opacity(0.78)
        }
        .foregroundStyle(.white)
    }
}

public struct HaloBackground: View {
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "#52B9F1").opacity(0.36),
                        Color(hex: "#1C78A8").opacity(0.20)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.28), lineWidth: 1)
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
            return 5
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
            return 13
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
            return 20
        }
    }

    public var verticalPadding: CGFloat {
        switch self {
        case .small:
            return 15
        case .medium:
            return 16
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

    public var editButtonSize: CGFloat {
        switch self {
        case .small:
            return 22
        case .medium:
            return 24
        }
    }

    public var editIconSize: CGFloat {
        switch self {
        case .small:
            return 9
        case .medium:
            return 10
        }
    }

    public var editButtonPadding: CGFloat {
        switch self {
        case .small:
            return 10
        case .medium:
            return 10
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
