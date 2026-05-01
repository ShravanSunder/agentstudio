import SwiftUI

struct InboxNotificationGroupHeader: View {
    let label: String
    let unreadCount: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)

                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}
