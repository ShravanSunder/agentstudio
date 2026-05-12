import SwiftUI

struct SidebarBadgeOverlay: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        content
            .frame(
                width: AppStyles.Shell.Sidebar.badgeHitboxSize,
                height: AppStyles.Shell.Sidebar.badgeHitboxSize
            )
            .overlay(alignment: .topTrailing) {
                if let text {
                    UnreadCountBadge(text: text)
                        .offset(
                            x: AppStyles.Shell.Sidebar.badgeOffset,
                            y: -AppStyles.Shell.Sidebar.badgeOffset
                        )
                }
            }
    }
}

extension View {
    func sidebarBadgeOverlay(text: String?) -> some View {
        modifier(SidebarBadgeOverlay(text: text))
    }
}
