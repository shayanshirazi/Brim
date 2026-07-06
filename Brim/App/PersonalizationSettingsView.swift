import ServiceManagement
import SwiftUI

private enum RefreshFrequencyMode: String {
    case preset
    case custom
}

private enum CustomRefreshUnit: String, CaseIterable, Identifiable, Hashable {
    case minutes
    case hours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minutes: return "min"
        case .hours: return "hr"
        }
    }

    var amountRange: ClosedRange<Int> {
        switch self {
        case .minutes: return 1...1440
        case .hours: return 1...24
        }
    }

    func seconds(for amount: Int) -> Int {
        switch self {
        case .minutes: return amount * 60
        case .hours: return amount * 3600
        }
    }
}

@MainActor
private final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published var notice: String?

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            refresh()
            notice = SMAppService.mainApp.status == .requiresApproval
                ? "Approve Brim in macOS Login Items to finish."
                : nil
        } catch {
            refresh()
            notice = enabled
                ? "macOS could not add Brim to Login Items."
                : "macOS could not remove Brim from Login Items."
        }
    }
}

struct PersonalizationSettingsTab: View {
    @AppStorage(BrimRefreshInterval.storageKey) private var refreshIntervalSeconds = BrimRefreshInterval.defaultSeconds
    @AppStorage(BrimRefreshInterval.modeStorageKey) private var refreshModeRaw = RefreshFrequencyMode.preset.rawValue
    @AppStorage("brim.refresh-custom-amount.v1") private var customRefreshAmount = 45
    @AppStorage("brim.refresh-custom-unit.v1") private var customRefreshUnitRaw = CustomRefreshUnit.minutes.rawValue
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPanelHeader(
                icon: "slider.horizontal.3",
                title: "Personalization",
                subtitle: "Tune the small habits that make Brim feel native on this Mac."
            )

            VStack(spacing: 10) {
                PreferenceControlRow(
                    icon: "power",
                    title: "Start Brim on startup",
                    detail: "Open Brim automatically when you sign in to this Mac."
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { launchAtLogin.isEnabled },
                            set: { launchAtLogin.setEnabled($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                RefreshFrequencyPreferenceRow(
                    refreshIntervalSeconds: $refreshIntervalSeconds,
                    refreshModeRaw: $refreshModeRaw,
                    customRefreshAmount: $customRefreshAmount,
                    customRefreshUnitRaw: $customRefreshUnitRaw
                )
            }

            if let notice = launchAtLogin.notice {
                SettingsInlineNotice(icon: "info.circle.fill", text: notice)
            }

            Spacer(minLength: 0)
        }
        .panelStyle()
        .onAppear {
            launchAtLogin.refresh()
        }
    }
}

private struct RefreshFrequencyPreferenceRow: View {
    @Binding var refreshIntervalSeconds: Int
    @Binding var refreshModeRaw: String
    @Binding var customRefreshAmount: Int
    @Binding var customRefreshUnitRaw: String

    private static let customSelectionTag = -1

    private var mode: RefreshFrequencyMode {
        RefreshFrequencyMode(rawValue: refreshModeRaw) ?? .preset
    }

    private var customUnit: CustomRefreshUnit {
        CustomRefreshUnit(rawValue: customRefreshUnitRaw) ?? .minutes
    }

    private var isCustomSelected: Bool {
        mode == .custom || BrimRefreshInterval(rawValue: refreshIntervalSeconds) == nil
    }

    private var customRefreshIntervalSeconds: Int {
        customUnit.seconds(for: clamped(customRefreshAmount, for: customUnit))
    }

    private var selection: Binding<Int> {
        Binding(
            get: {
                if isCustomSelected {
                    return Self.customSelectionTag
                }

                return BrimRefreshInterval(rawValue: refreshIntervalSeconds)?.rawValue
                    ?? Self.customSelectionTag
            },
            set: { nextSelection in
                withAnimation(.snappy(duration: 0.18)) {
                    if nextSelection == Self.customSelectionTag {
                        refreshModeRaw = RefreshFrequencyMode.custom.rawValue
                        refreshIntervalSeconds = BrimRefreshInterval.normalizedSeconds(customRefreshIntervalSeconds)
                    } else if let interval = BrimRefreshInterval(rawValue: nextSelection) {
                        refreshModeRaw = RefreshFrequencyMode.preset.rawValue
                        refreshIntervalSeconds = interval.rawValue
                    }
                }
            }
        )
    }

    private var customRefreshAmountBinding: Binding<Int> {
        Binding(
            get: { clamped(customRefreshAmount, for: customUnit) },
            set: { nextAmount in
                customRefreshAmount = clamped(nextAmount, for: customUnit)
                refreshModeRaw = RefreshFrequencyMode.custom.rawValue
                refreshIntervalSeconds = BrimRefreshInterval.normalizedSeconds(customRefreshIntervalSeconds)
            }
        )
    }

    private var customRefreshUnitBinding: Binding<CustomRefreshUnit> {
        Binding(
            get: { customUnit },
            set: { nextUnit in
                let nextAmount = clamped(customRefreshAmount, for: nextUnit)
                customRefreshUnitRaw = nextUnit.rawValue
                customRefreshAmount = nextAmount
                refreshModeRaw = RefreshFrequencyMode.custom.rawValue
                refreshIntervalSeconds = BrimRefreshInterval.normalizedSeconds(nextUnit.seconds(for: nextAmount))
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 13) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "#2CCB68"))
                    .frame(width: 32, height: 32)
                    .background(Color(hex: "#2CCB68").opacity(0.11), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Refresh frequency")
                        .font(.system(size: 13, weight: .bold, design: .rounded))

                    Text("How often Brim checks connected accounts.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Picker("Refresh frequency", selection: selection) {
                    ForEach(BrimRefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval.rawValue)
                    }

                    Text("Custom").tag(Self.customSelectionTag)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 356)
            }

            if isCustomSelected {
                customEditor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isCustomSelected ? Color(hex: "#2CCB68").opacity(0.16) : Color.primary.opacity(0.055), lineWidth: 1)
        }
        .animation(.snappy(duration: 0.18), value: isCustomSelected)
    }

    private var customEditor: some View {
        HStack(spacing: 8) {
            Label("Every", systemImage: "timer")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .frame(width: 72, alignment: .leading)

            Spacer(minLength: 0)

            IntervalAdjustButton(
                icon: "minus",
                isEnabled: customRefreshAmountBinding.wrappedValue > customUnit.amountRange.lowerBound,
                action: { adjustCustomAmount(by: -1) }
            )

            HStack(spacing: 7) {
                TextField("Amount", value: customRefreshAmountBinding, format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 50)

                Picker("Unit", selection: customRefreshUnitBinding) {
                    ForEach(CustomRefreshUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 88)
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(height: 34)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.92), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.primary.opacity(0.065), lineWidth: 1)
            }

            IntervalAdjustButton(
                icon: "plus",
                isEnabled: customRefreshAmountBinding.wrappedValue < customUnit.amountRange.upperBound,
                action: { adjustCustomAmount(by: 1) }
            )
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.46), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        }
    }

    private func clamped(_ amount: Int, for unit: CustomRefreshUnit) -> Int {
        min(max(amount, unit.amountRange.lowerBound), unit.amountRange.upperBound)
    }

    private func adjustCustomAmount(by delta: Int) {
        customRefreshAmountBinding.wrappedValue = customRefreshAmountBinding.wrappedValue + delta
    }
}

private struct IntervalAdjustButton: View {
    var icon: String
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isEnabled ? Color.primary.opacity(0.58) : Color.primary.opacity(0.22))
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(isEnabled ? 0.045 : 0.022), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(isEnabled ? 0.055 : 0.025), lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct PreferenceControlRow<Control: View>: View {
    var icon: String
    var title: String
    var detail: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "#2CCB68"))
                .frame(width: 32, height: 32)
                .background(Color(hex: "#2CCB68").opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))

                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            control()
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        }
    }
}

private struct SettingsInlineNotice: View {
    var icon: String
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))

            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))

            Spacer(minLength: 0)
        }
        .foregroundStyle(Color(hex: "#2F7A4B"))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color(hex: "#2CCB68").opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
