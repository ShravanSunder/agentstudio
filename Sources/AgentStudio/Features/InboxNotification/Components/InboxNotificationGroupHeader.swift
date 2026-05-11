import SwiftUI

struct InboxNotificationGroupHeader: View {
    let label: String
    let unreadCount: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        SidebarSectionHeader(
            label: label,
            isCollapsed: isCollapsed,
            onToggle: onToggle
        ) {
            Group {
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
