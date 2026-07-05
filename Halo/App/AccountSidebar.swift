import SwiftUI

struct AccountSidebar: View {
    var accounts: [QuotaAccount]
    @Binding var selectedAccountID: QuotaAccount.ID?
    var addAccount: () -> Void
    var removeSelectedAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 9) {
                    HaloLogoMark(size: 26)

                    Text("Halo")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                }

                Spacer()

                Button(action: addAccount) {
                    Image(systemName: "plus")
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Add account")

                Button(action: removeSelectedAccount) {
                    Image(systemName: "minus")
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.04), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Remove selected account")
                .disabled(selectedAccountID == nil)
                .opacity(selectedAccountID == nil ? 0.3 : 1)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(accounts) { account in
                        AccountSidebarRow(
                            account: account,
                            isSelected: selectedAccountID == account.id
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onTapGesture {
                            selectedAccountID = account.id
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.82),
                    Color(hex: "#EEF7F6").opacity(0.54)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct AccountSidebarRow: View {
    var account: QuotaAccount
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            QuotaRingView(account: account, diameter: 32, lineWidth: 4, showPercent: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Text("\(account.remainingPercentText) remaining")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            isSelected ? Color.primary.opacity(0.075) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}
