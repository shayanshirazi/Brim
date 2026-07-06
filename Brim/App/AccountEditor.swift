import SwiftUI

struct AccountEditor: View {
    @Binding var account: QuotaAccount
    @State private var copiedCommand: CopiedCommand?

    private let detailPanelHeight: CGFloat = 372

    private var codexProfilePath: Binding<String> {
        Binding(
            get: { account.resolvedCodexProfilePath },
            set: { account.codexProfilePath = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HeaderPanel(account: $account)

            HStack(alignment: .top, spacing: 18) {
                CodexProfilePanel(
                    account: $account,
                    codexProfilePath: codexProfilePath,
                    copiedCommand: $copiedCommand
                )
                .frame(maxWidth: .infinity)
                .frame(height: detailPanelHeight, alignment: .top)

                UsagePanel(account: $account)
                    .frame(maxWidth: .infinity)
                    .frame(height: detailPanelHeight, alignment: .top)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct HeaderPanel: View {
    @Binding var account: QuotaAccount
    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            QuotaRingView(account: account, diameter: 76, lineWidth: 6, showPercent: false)
                .frame(width: 92, height: 92)
                .background(Color(hex: account.colorHex).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 7) {
                nameEditor

                Text(accountIdentityLine)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(account.accountEmail == nil ? .tertiary : .secondary)
                    .lineLimit(1)
                    .blur(radius: isQuotaRedacted ? 3.2 : 0)
                    .saturation(isQuotaRedacted ? 0.20 : 1)
                    .opacity(isQuotaRedacted ? 0.54 : 1)
                    .animation(.snappy(duration: 0.18), value: isQuotaRedacted)

                quotaReadout
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                ConnectionStatusPill(account: account)

                if let refreshCopy {
                    Text(refreshCopy)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 180, alignment: .trailing)
                }
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: account.colorHex).opacity(0.12),
                    Color(nsColor: .controlBackgroundColor).opacity(0.62)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        }
    }

    private var nameEditor: some View {
        HStack(alignment: .center, spacing: 7) {
            if isEditingName {
                TextField("Account name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .focused($isNameFieldFocused)
                    .onSubmit(commitName)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .frame(maxWidth: 320, alignment: .leading)
                    .background(
                        Color(nsColor: .textBackgroundColor).opacity(0.82),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            } else {
                Text(account.name)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Button(action: isEditingName ? commitName : beginEditingName) {
                Image(systemName: isEditingName ? "checkmark" : "pencil.tip")
                    .font(.system(size: isEditingName ? 11 : 13, weight: .bold))
                    .foregroundStyle(isEditingName ? Color(hex: account.colorHex) : .primary.opacity(0.56))
                    .frame(width: 26, height: 26)
                    .background(
                        Color(nsColor: .textBackgroundColor).opacity(0.72),
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help(isEditingName ? "Save account name" : "Edit account name")
            .offset(y: -1)
        }
    }

    private func beginEditingName() {
        draftName = account.name
        isEditingName = true

        DispatchQueue.main.async {
            isNameFieldFocused = true
        }
    }

    private func commitName() {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            account.name = trimmedName
        }

        isEditingName = false
        isNameFieldFocused = false
    }

    private var accountIdentityLine: String {
        account.accountEmail ?? "Email not set"
    }

    private var isQuotaRedacted: Bool {
        account.refreshStatus.hidesQuotaDetails
    }

    private var quotaReadout: some View {
        ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 7) {
                Text(QuotaFormatting.remainingLine(for: account))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                ProgressView(value: account.weeklyRemainingFraction)
                    .tint(Color(hex: account.colorHex))
                    .frame(maxWidth: 340)
            }
            .blur(radius: isQuotaRedacted ? 3.2 : 0)
            .saturation(isQuotaRedacted ? 0.20 : 1)
            .opacity(isQuotaRedacted ? 0.54 : 1)
        }
        .frame(height: 36, alignment: .leading)
        .animation(.snappy(duration: 0.18), value: isQuotaRedacted)
    }

    private var refreshCopy: String? {
        if account.refreshStatus == .notConnected {
            return nil
        }

        if account.refreshStatus == .ready {
            return nil
        }

        if let refreshMessage = account.refreshMessage, !refreshMessage.isEmpty {
            return refreshMessage
        }

        if let lastSuccessfulRefreshAt = account.lastSuccessfulRefreshAt {
            return "Last refreshed \(lastSuccessfulRefreshAt.formatted(date: .omitted, time: .shortened))"
        }

        if let lastRefreshAttemptAt = account.lastRefreshAttemptAt {
            return "Last attempt \(lastRefreshAttemptAt.formatted(date: .omitted, time: .shortened))"
        }

        return "Attempts refresh every 5 min once connected"
    }
}

struct ConnectionStatusPill: View {
    var account: QuotaAccount

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(account.refreshStatus.title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }

    private var color: Color {
        switch account.refreshStatus {
        case .ready:
            return Color(hex: "#32D873")
        case .waitingForQuotaSource:
            return Color(hex: "#54C7EC")
        case .refreshFailed:
            return Color(hex: "#E58C30")
        case .manual:
            return Color.secondary
        case .notConnected:
            return Color(hex: "#FF4D57")
        }
    }
}
