import SwiftUI

struct UsagePanel: View {
    @Binding var account: QuotaAccount

    private var color: Binding<Color> {
        Binding(
            get: { Color(hex: account.colorHex) },
            set: { account.colorHex = $0.quotaHexString }
        )
    }

    private var sessionLimit: Binding<Int> {
        Binding(
            get: { account.sessionLimit },
            set: { newValue in
                account.sessionLimitMinutes = newValue
                if account.sessionUsed > newValue {
                    account.sessionUsedMinutes = newValue
                }
            }
        )
    }

    private var sessionUsed: Binding<Double> {
        Binding(
            get: { Double(account.sessionUsed) },
            set: { account.sessionUsedMinutes = Int($0.rounded()) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelTitle(icon: "gauge.with.dots.needle.bottom.50percent", title: "Quota")

            VStack(spacing: 10) {
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

            Divider()
                .opacity(0.35)

            VStack(alignment: .leading, spacing: 10) {
                Text("Account")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                TextField("Name", text: $account.name)
                    .textFieldStyle(.roundedBorder)

                ColorPicker("Halo colour", selection: color)
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 14) {
                    ManualNumberField(title: "Weekly limit", value: $account.weeklyLimitMinutes)

                    ManualSlider(
                        title: "Weekly used",
                        value: Binding(
                            get: { Double(account.usedMinutes) },
                            set: { account.usedMinutes = Int($0.rounded()) }
                        ),
                        range: 0...Double(max(1, account.weeklyLimitMinutes))
                    )

                    ManualNumberField(title: "Session limit", value: sessionLimit)

                    ManualSlider(
                        title: "Session used",
                        value: sessionUsed,
                        range: 0...Double(max(1, account.sessionLimit))
                    )

                    Picker("Reset day", selection: $account.resetWeekday) {
                        Text("Sun").tag(1)
                        Text("Mon").tag(2)
                        Text("Tue").tag(3)
                        Text("Wed").tag(4)
                        Text("Thu").tag(5)
                        Text("Fri").tag(6)
                        Text("Sat").tag(7)
                    }

                    HStack {
                        ManualNumberField(title: "Hour", value: $account.resetHour)
                        ManualNumberField(title: "Minute", value: $account.resetMinute)
                    }
                }
                .padding(.top, 12)
            } label: {
                Text("Manual fallback")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.secondary)
        }
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
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ManualNumberField: View {
    var title: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 78)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
    }
}

private struct ManualSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: range)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
    }
}
