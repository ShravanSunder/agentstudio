import SwiftUI

struct InboxNotificationGroupHeader: View {
    let label: String
    let unreadCount: Int

    var body: some View {
        HStack {
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
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}
