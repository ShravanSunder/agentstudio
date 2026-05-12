import SwiftUI

struct InboxNotificationGroupHeader: View {
    let header: InboxNotificationListSectionHeader
    let unreadCount: Int
    let isCollapsed: Bool
    var showsUnreadCount = true
    let onToggle: () -> Void

    var body: some View {
        switch header.style {
        case .plain:
            SidebarSectionHeader(
                isCollapsed: isCollapsed,
                onToggle: onToggle,
                label: {
                    SidebarSectionHeaderTextLabel(label: header.label ?? "")
                },
                trailingContent: {
                    unreadBadge()
                }
            )
        case .repo(let organizationName):
            SidebarRepoGroupHeader(
                isCollapsed: isCollapsed,
                repoTitle: header.label ?? "Other sources",
                organizationName: organizationName,
                onToggle: onToggle
            ) {
                unreadBadge()
            }
        }
    }

    @ViewBuilder
    private func unreadBadge() -> some View {
        if unreadCount > 0, showsUnreadCount {
            UnreadCountBadge(text: "\(unreadCount)")
        }
    }
}
