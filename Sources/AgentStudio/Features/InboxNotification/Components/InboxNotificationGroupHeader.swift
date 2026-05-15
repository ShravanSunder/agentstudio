import SwiftUI

struct InboxNotificationGroupHeader: View {
    let header: InboxNotificationListSectionHeader
    let unreadCount: Int
    let isCollapsed: Bool
    var showsUnreadCount = true
    let onToggle: () -> Void

    static func chromePolicy(for _: InboxNotificationListSectionHeader.Style) -> SidebarHeaderChromePolicy {
        SidebarSourceGroupHeader<EmptyView>.chromePolicy
    }

    static func icon(
        for sourceKind: InboxNotificationListSectionHeader.SourceKind,
        accentColorHex: String?
    ) -> AppEntityIcon {
        switch sourceKind {
        case .repo:
            if let accentColorHex {
                return .coloredRepo(colorHex: accentColorHex)
            }
            return .repo
        case .pane:
            return .pane
        case .tab:
            return .tab
        case .workspace:
            return .workspace
        case .otherSources:
            return .otherSources
        }
    }

    static func icon(for sourceKind: InboxNotificationListSectionHeader.SourceKind) -> AppEntityIcon {
        icon(for: sourceKind, accentColorHex: nil)
    }

    var body: some View {
        SidebarSourceGroupHeader(
            isCollapsed: isCollapsed,
            icon: Self.icon(for: header.sourceKind, accentColorHex: header.accentColorHex),
            title: header.title,
            secondaryTitle: header.secondaryTitle,
            accessibilityIdentifier: nil,
            onToggle: onToggle
        ) {
            unreadBadge()
        }
        .accessibilityHidden(true)
        .background(
            AccessibilityPressBridge(
                identifier: "inboxSourceGroupHeader",
                label: accessibilityLabel,
                action: { onToggle() }
            )
        )
    }

    private var accessibilityLabel: String {
        guard let secondaryTitle = header.secondaryTitle, !secondaryTitle.isEmpty else {
            return header.title
        }
        return "\(header.title), \(secondaryTitle)"
    }

    @ViewBuilder
    private func unreadBadge() -> some View {
        if unreadCount > 0, showsUnreadCount {
            UnreadCountBadge(text: "\(unreadCount)")
                .accessibilityIdentifier("inboxGroupUnreadBadge")
        }
    }
}
