import SwiftUI

struct FirstRunOnboardingView: View {
    var storageStatus: QuotaStorageStatus
    var addAccount: () -> Void

    var body: some View {
        ZStack {
            FirstRunBackground()

            VStack(spacing: 20) {
                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: 16) {
                    BrimLogoMark(size: 82)
                        .offset(x: -1)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Brim")
                            .font(.system(size: 54, weight: .black, design: .rounded))
                            .lineLimit(1)

                        Text("Your usage limits, visible at a glance.")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                OnboardingQuotaInstrument()

                VStack(spacing: 10) {
                    Button(action: addAccount) {
                        Label("Add first account", systemImage: "plus")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .frame(height: 42)
                            .background(Color(hex: "#2CCB68"), in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(Color.white.opacity(0.26), lineWidth: 1)
                            }
                            .shadow(color: Color(hex: "#2CCB68").opacity(0.28), radius: 16, y: 8)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .help("Add your first account")

                    OnboardingStatusLine(status: storageStatus)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 72)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct FirstRunBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(hex: "#F6FCFA"),
                    Color(hex: "#EAF8F2").opacity(0.76)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color(hex: "#2CCB68").opacity(0.14))
                    .frame(height: 1)
                Spacer()
                Rectangle()
                    .fill(Color(hex: "#5AC8FA").opacity(0.12))
                    .frame(height: 1)
            }
            .padding(.horizontal, 76)
            .padding(.vertical, 54)

            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(hex: "#2CCB68").opacity(0.10))
                    .frame(width: 1)
                Spacer()
                Rectangle()
                    .fill(Color(hex: "#5AC8FA").opacity(0.10))
                    .frame(width: 1)
            }
            .padding(.horizontal, 112)
            .padding(.vertical, 78)
        }
    }
}

private struct OnboardingQuotaInstrument: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAwake = false

    private let previewAccount = QuotaAccount(
        name: "Preview",
        colorHex: "#2CCB68",
        weeklyLimitMinutes: 300,
        usedMinutes: 72,
        sessionLimitMinutes: 300,
        sessionUsedMinutes: 115,
        resetWeekday: 2,
        resetHour: 0,
        resetMinute: 0,
        connectionKind: .manual,
        refreshStatus: .ready
    )

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Color(hex: "#2CCB68").opacity(0.062 - Double(index) * 0.012), lineWidth: 1)
                    .frame(width: 168 + CGFloat(index * 74), height: 168 + CGFloat(index * 74))
                    .scaleEffect(isAwake ? 1.0 : 0.94)
            }

            MiniQuotaDial(percent: "94%", opacity: 0.34)
                .offset(x: -156, y: 16)

            MiniQuotaDial(percent: "61%", opacity: 0.42)
                .offset(x: 154, y: -62)

            MiniQuotaDial(percent: "24h", opacity: 0.26)
                .offset(x: 118, y: 96)

            OnboardingStep(icon: "person.crop.circle.badge.checkmark", title: "Connect")
                .offset(x: -162, y: 90)
                .opacity(isAwake ? 1 : 0)
                .scaleEffect(isAwake ? 1 : 0.92)

            OnboardingStep(icon: "timer", title: "Watch")
                .offset(x: -14, y: -118)
                .opacity(isAwake ? 1 : 0)
                .scaleEffect(isAwake ? 1 : 0.92)

            OnboardingStep(icon: "macwindow", title: "Glance")
                .offset(x: 168, y: 38)
                .opacity(isAwake ? 1 : 0)
                .scaleEffect(isAwake ? 1 : 0.92)

            VStack(spacing: 8) {
                QuotaRingView(account: previewAccount, diameter: 112, showPercent: false)
                    .frame(width: 134, height: 134)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.56), lineWidth: 1)
                    }
                    .shadow(color: Color(hex: "#2CCB68").opacity(0.22), radius: 24, y: 10)

                Text("76% ready")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#245C3D").opacity(0.72))
            }
            .scaleEffect(isAwake ? 1 : 0.98)
            .opacity(isAwake ? 1 : 0)
        }
        .frame(width: 456, height: 270)
        .onAppear {
            guard !reduceMotion else {
                isAwake = true
                return
            }

            withAnimation(.spring(response: 0.70, dampingFraction: 0.84)) {
                isAwake = true
            }
        }
    }
}

private struct MiniQuotaDial: View {
    var percent: String
    var opacity: Double

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .stroke(Color(hex: "#2CCB68").opacity(opacity), lineWidth: 5)
                .frame(width: 56, height: 56)
                .overlay {
                    Text(percent)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "#245C3D").opacity(0.64))
                }

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(hex: "#245C3D").opacity(0.12))
                .frame(width: 34, height: 4)
        }
        .opacity(opacity + 0.22)
    }
}

private struct OnboardingStep: View {
    var icon: String
    var title: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "#2CCB68"))

            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.white.opacity(0.50), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color(hex: "#2CCB68").opacity(0.16), lineWidth: 1)
        }
        .shadow(color: Color(hex: "#2CCB68").opacity(0.10), radius: 14, y: 6)
    }
}

private struct OnboardingStatusLine: View {
    var status: QuotaStorageStatus

    var body: some View {
        if let copy {
            Label(copy, systemImage: icon)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var icon: String {
        switch status {
        case .corrupted, .saveFailed, .unavailable:
            return "exclamationmark.triangle"
        case .firstRun:
            return "checkmark.seal"
        case .ready:
            return "lock"
        }
    }

    private var copy: String? {
        switch status {
        case .ready:
            return "Tokens stay in Keychain."
        case .firstRun:
            return "Takes less than a minute."
        case .corrupted:
            return "Saved account data could not be read."
        case .saveFailed:
            return "Brim could not save the latest account changes."
        case .unavailable:
            return "Shared widget storage is unavailable."
        }
    }
}
