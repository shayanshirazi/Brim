import SwiftUI

struct SettingsPanelHeader: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: "#2CCB68"))
                .frame(width: 36, height: 36)
                .background(Color(hex: "#2CCB68").opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

extension Int {
    var brimAccountCountText: String {
        "\(self) account\(self == 1 ? "" : "s")"
    }
}
