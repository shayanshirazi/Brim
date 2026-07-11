import SwiftUI

struct UsagePanel: View {
    @Binding var account: QuotaAccount

    private var isQuotaRedacted: Bool {
        account.refreshStatus.hidesQuotaDetails
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(
                icon: account.provider.usesProviderDashboard ? "arrow.up.forward.app" : "hourglass",
                title: account.provider.usesProviderDashboard ? "Usage" : "Rate limits"
            )

            if account.provider.usesProviderDashboard {
                DashboardOnlyUsageState(provider: account.provider)
                    .frame(maxWidth: .infinity, minHeight: 154, alignment: .center)
            } else if account.hasUsageSnapshot {
                VStack(spacing: 8) {
                    QuotaMetricRow(
                        title: account.connectionKind == .apiToken
                            ? "Requests per minute"
                            : QuotaFormatting.usageLimitTitle(minutes: account.sessionWindowMinutes),
                        resetLine: account.sessionResetLine(),
                        fraction: account.sessionRemainingFraction,
                        color: Color(hex: account.colorHex)
                    )

                    QuotaMetricRow(
                        title: account.connectionKind == .apiToken
                            ? "Tokens per minute"
                            : "Weekly usage limit",
                        resetLine: account.weeklyResetLine(),
                        fraction: account.weeklyRemainingFraction,
                        color: Color(hex: account.colorHex)
                    )
                }
                .blur(radius: isQuotaRedacted ? 3.8 : 0)
                .saturation(isQuotaRedacted ? 0.18 : 1)
                .opacity(isQuotaRedacted ? 0.58 : 1)
                .animation(.snappy(duration: 0.18), value: isQuotaRedacted)
            } else {
                UsageUnavailableState(providerName: account.provider.displayName, detail: account.refreshMessage)
                    .frame(maxWidth: .infinity, minHeight: 154, alignment: .center)
            }

            Spacer(minLength: account.hasUsageSnapshot ? 0 : 8)

            if let usageURL = account.provider.usageURL(for: account.connectionKind) {
                UsageDashboardLink(
                    providerName: account.provider.displayName,
                    url: usageURL,
                    dashboardOnly: account.provider.usesProviderDashboard
                )
            }

            Divider()
                .opacity(0.28)

            VStack(alignment: .leading, spacing: 8) {
                Text("Appearance")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                RingColorControl(colorHex: $account.colorHex)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct UsageDashboardLink: View {
    var providerName: String
    var url: URL
    var dashboardOnly: Bool

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 11, weight: .semibold))

                Text(dashboardOnly ? "Open \(providerName) usage" : "Verify in \(providerName)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.72)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.primary.opacity(0.026), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.primary.opacity(0.055), lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
        .help("Open the \(providerName) usage dashboard")
    }
}

private struct DashboardOnlyUsageState: View {
    var provider: QuotaProviderKind

    private var accent: Color {
        Color(hex: provider.brandColorHex)
    }

    var body: some View {
        VStack(spacing: 10) {
            ProviderLogoMark(provider: provider, size: 42)
                .padding(5)
                .background(accent.opacity(0.08), in: Circle())

            VStack(spacing: 5) {
                Text("Shown by \(provider.displayName)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))

                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: 248)
    }

    private var detail: String {
        switch provider {
        case .chatgpt:
            return "Ordinary chat limits are separate from Codex and available in ChatGPT."
        case .claude:
            return "Claude and Claude Code share the limits shown on Claude's usage page."
        case .codex, .gemini:
            return "Open the provider dashboard to view usage."
        }
    }
}

private struct UsageUnavailableState: View {
    var providerName: String
    var detail: String?

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#54C7EC").opacity(0.12))
                    .frame(width: 44, height: 44)

                Circle()
                    .stroke(Color(hex: "#54C7EC").opacity(0.16), lineWidth: 1)
                    .frame(width: 44, height: 44)

                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color(hex: "#54C7EC"))
            }

            VStack(spacing: 5) {
                Text("Usage not available")
                    .font(.system(size: 14, weight: .bold, design: .rounded))

                Text(detail ?? "\(providerName) is connected, but Brim has not received live rate-limit data yet.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: 238)
    }
}

private struct QuotaMetricRow: View {
    var title: String
    var resetLine: String
    var fraction: Double
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer()

                Text("\(QuotaFormatting.percentText(fraction)) left")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: fraction)
                .tint(color)

            Text(resetLine)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 11)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct RingColorControl: View {
    @Binding var colorHex: String
    @State private var showsPalette = false

    private let presetSwatches = QuotaAccountDefaults.presetColorHexes

    var body: some View {
        Button {
            showsPalette.toggle()
        } label: {
            HStack(spacing: 10) {
                Text("Ring color")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Capsule()
                    .fill(Color(hex: colorHex))
                    .frame(width: 46, height: 20)
                    .overlay {
                        Capsule()
                            .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                    }
                    .shadow(color: Color(hex: colorHex).opacity(0.28), radius: 5, y: 1)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsPalette, arrowEdge: .trailing) {
            RingColorPalette(
                colorHex: $colorHex,
                swatches: presetSwatches,
                select: { hex in
                    colorHex = QuotaColor.normalizedHex(hex) ?? QuotaColor.fallbackHex
                    showsPalette = false
                }
            )
        }
    }
}

private struct RingColorPalette: View {
    @Binding var colorHex: String
    var swatches: [String]
    var select: (String) -> Void
    @StateObject private var colorPanel = RingColorPanelController()

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 8), count: 4)
    private var isCustomColorSelected: Bool {
        !swatches.contains { QuotaColor.normalizedHex($0) == QuotaColor.normalizedHex(colorHex) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ring color")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(swatches, id: \.self) { hex in
                    Button {
                        select(hex)
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 30, height: 30)
                            .overlay {
                                Circle()
                                    .stroke(
                                        isSelected(hex) ? Color.primary.opacity(0.72) : Color.primary.opacity(0.10),
                                        lineWidth: isSelected(hex) ? 2 : 1
                                    )
                            }
                            .overlay {
                                if isSelected(hex) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    colorPanel.open(initialHex: colorHex) { selectedHex in
                        colorHex = selectedHex
                    }
                } label: {
                    CustomColorSwatch(
                        color: Color(hex: colorHex),
                        isSelected: isCustomColorSelected
                    )
                }
                .buttonStyle(.plain)
                .help("Choose custom color")
            }
        }
        .padding(14)
        .frame(width: 174)
    }

    private func isSelected(_ hex: String) -> Bool {
        QuotaColor.normalizedHex(hex) == QuotaColor.normalizedHex(colorHex)
    }
}

private final class RingColorPanelController: NSObject, ObservableObject {
    private var onChange: ((String) -> Void)?

    func open(initialHex: String, onChange: @escaping (String) -> Void) {
        self.onChange = onChange

        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = NSColor(Color(hex: initialHex))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        guard let color = sender.color.usingColorSpace(.sRGB) else {
            return
        }

        let hex = String(
            format: "#%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
        onChange?(hex)
    }
}

private struct CustomColorSwatch: View {
    var color: Color
    var isSelected: Bool

    var body: some View {
        Circle()
            .fill(
                AngularGradient(
                    colors: [
                        Color(hex: "#FF5A66"),
                        Color(hex: "#FFB33F"),
                        Color(hex: "#40E06B"),
                        Color(hex: "#65D6FF"),
                        Color(hex: "#8B6CFF"),
                        Color(hex: "#FF5A66")
                    ],
                    center: .center
                )
            )
            .frame(width: 30, height: 30)
            .overlay {
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.82), lineWidth: 1)
                    }
            }
            .overlay {
                Image(systemName: "eyedropper.halffull")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .overlay {
                Circle()
                    .stroke(
                        isSelected ? Color.primary.opacity(0.72) : Color.primary.opacity(0.10),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
    }
}
