import SwiftUI

struct InboxNotificationGroupHeader: View {
    let label: String
    let unreadCount: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        SidebarSectionHeader(
            title: label,
            isExpanded: !isCollapsed,
            onToggle: onToggle
        ) {
            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.system(size: AppStyles.Shell.Sidebar.chipFontSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppStyles.Shell.Sidebar.countBadgeHorizontalPadding)
                    .padding(.vertical, AppStyles.Shell.Sidebar.countBadgeVerticalPadding)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(AppStyles.Shell.Sidebar.countBadgeBackgroundOpacity))
                    )
            }
        }
    }
}
