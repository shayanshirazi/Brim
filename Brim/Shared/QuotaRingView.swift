import SwiftUI
import WidgetKit

public struct QuotaRingView: View {
    public var account: QuotaAccount?
    public var diameter: CGFloat
    public var lineWidth: CGFloat
    public var showPercent: Bool

    private var connectionDotSize: CGFloat {
        max(8, diameter * 0.18)
    }

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

                    ConnectionSignalDot(
                        status: account.refreshStatus,
                        size: connectionDotSize,
                        borderOpacity: 0.70,
                        glowRadius: max(4, diameter * 0.07)
                    )
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
        .animation(.snappy(duration: 0.22), value: account?.refreshStatus)
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

    private var connectionDotSize: CGFloat {
        max(8, diameter * 0.18)
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

                ConnectionSignalDot(
                    status: account.refreshStatus,
                    size: connectionDotSize,
                    borderOpacity: isVibrant ? 0.34 : 0.72,
                    glowRadius: 4,
                    isVibrant: isVibrant
                )
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
        .animation(.snappy(duration: 0.22), value: account?.refreshStatus)
    }
}

private struct ConnectionSignalDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var status: QuotaRefreshStatus
    var size: CGFloat
    var borderOpacity: Double
    var glowRadius: CGFloat
    var isVibrant = false

    private var isConnected: Bool {
        status == .ready
    }

    private var signalColor: Color {
        isConnected ? Color(hex: "#22C55E") : Color(hex: "#FF4D57")
    }

    private var dotScale: CGFloat {
        guard !reduceMotion else { return 1 }
        return isConnected ? 1 : 0.96
    }

    var body: some View {
        Circle()
            .fill(signalColor)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(borderOpacity), lineWidth: max(1, size * 0.09))
            }
            .shadow(color: signalColor.opacity(isVibrant ? 0.22 : 0.34), radius: glowRadius)
            .scaleEffect(dotScale)
            .frame(width: size * 1.6, height: size * 1.6)
            .widgetAccentable(false)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: status)
    }
}
