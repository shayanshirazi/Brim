import SwiftUI

struct TransferSettingsTab: View {
    var accountCount: Int
    var notice: AccountTransferNotice?
    var exportAccounts: () -> Void
    var importAccounts: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPanelHeader(
                icon: "arrow.up.arrow.down",
                title: "Move accounts",
                subtitle: "Carry Brim account setup between Macs with a JSON file."
            )

            Spacer(minLength: 0)

            HStack(spacing: 16) {
                AccountTransferAction(
                    icon: "square.and.arrow.up",
                    title: "Export JSON",
                    detail: "\(accountCount.brimAccountCountText), setup only",
                    color: Color(hex: "#2CCB68"),
                    action: exportAccounts
                )

                AccountTransferAction(
                    icon: "square.and.arrow.down",
                    title: "Import JSON",
                    detail: "Replace accounts on this Mac",
                    color: Color(hex: "#54C7EC"),
                    action: importAccounts
                )
            }
            .padding(.horizontal, 38)
            .frame(maxWidth: 430)
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)

            VStack(spacing: 9) {
                AccountTransferNoticeBanner(notice: notice)
                    .frame(maxWidth: .infinity)

                Text("Imports replace the current Brim account list. Tokens, login sessions, local profile paths, and live usage are intentionally not portable; reconnect them after import.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 430, alignment: .center)
                    .padding(.horizontal, 26)
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panelStyle()
    }
}

private struct AccountTransferAction: View {
    var icon: String
    var title: String
    var detail: String
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.13), in: Circle())

                VStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 142, height: 142, alignment: .center)
            .background(
                LinearGradient(
                    colors: [color.opacity(0.11), Color.primary.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(color.opacity(0.20), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 142, height: 142)
    }
}

enum AccountTransferNotice: Equatable {
    case success(String)
    case failure(String)
}

private struct AccountTransferNoticeBanner: View {
    var notice: AccountTransferNotice?

    var body: some View {
        if let notice {
            HStack(spacing: 9) {
                Image(systemName: icon(for: notice))
                    .font(.system(size: 13, weight: .bold))
                Text(text(for: notice))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(color(for: notice))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(color(for: notice).opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func text(for notice: AccountTransferNotice) -> String {
        switch notice {
        case .success(let text), .failure(let text):
            return text
        }
    }

    private func icon(for notice: AccountTransferNotice) -> String {
        switch notice {
        case .success:
            return "checkmark.seal.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    private func color(for notice: AccountTransferNotice) -> Color {
        switch notice {
        case .success:
            return Color(hex: "#2CCB68")
        case .failure:
            return Color(hex: "#FF4D57")
        }
    }
}
