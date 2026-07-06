import SwiftUI

struct UsagePanel: View {
    @Binding var account: QuotaAccount

    private var isQuotaRedacted: Bool {
        account.refreshStatus.hidesQuotaDetails
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelTitle(icon: "gauge.with.dots.needle.bottom.50percent", title: "Rate limits")

            VStack(spacing: 8) {
                QuotaMetricRow(
                    title: "Session",
                    remaining: account.sessionRemainingMinutes,
                    limit: account.sessionLimit,
                    fraction: account.sessionRemainingFraction,
                    color: Color(hex: account.colorHex)
                )

                QuotaMetricRow(
                    title: "Weekly",
                    remaining: account.weeklyRemainingMinutes,
                    limit: account.weeklyLimitMinutes,
                    fraction: account.weeklyRemainingFraction,
                    color: Color(hex: account.colorHex)
                )
            }
            .blur(radius: isQuotaRedacted ? 3.8 : 0)
            .saturation(isQuotaRedacted ? 0.18 : 1)
            .opacity(isQuotaRedacted ? 0.58 : 1)
            .animation(.snappy(duration: 0.18), value: isQuotaRedacted)

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
        .panelStyle()
    }
}

private struct QuotaMetricRow: View {
    var title: String
    var remaining: Int
    var limit: Int
    var fraction: Double
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))

                Spacer()

                Text("\(QuotaFormatting.minutes(remaining)) left")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: fraction)
                .tint(color)

            Text("Limit \(QuotaFormatting.minutes(limit))")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct RingColorControl: View {
    @Binding var colorHex: String
    @State private var showsPalette = false

    private let swatches = [
        "#D7EA48", "#40E06B", "#65D6FF", "#4F8CFF",
        "#8B6CFF", "#F45EE5", "#FF5A66", "#FFB33F",
        "#8BD56B", "#37D6B8", "#7CA1FF", "#D48CFF"
    ]

    var body: some View {
        Button {
            showsPalette.toggle()
        } label: {
            HStack(spacing: 10) {
                Text("Ring colour")
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
                selectedHex: colorHex,
                swatches: swatches,
                select: { hex in
                    colorHex = QuotaColor.normalizedHex(hex) ?? QuotaColor.fallbackHex
                    showsPalette = false
                }
            )
        }
    }
}

private struct RingColorPalette: View {
    var selectedHex: String
    var swatches: [String]
    var select: (String) -> Void

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ring colour")
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
            }
        }
        .padding(14)
        .frame(width: 174)
    }

    private func isSelected(_ hex: String) -> Bool {
        QuotaColor.normalizedHex(hex) == QuotaColor.normalizedHex(selectedHex)
    }
}
