import SwiftUI
import Testing

@testable import AgentStudio

@Suite("SidebarBadgeOverlay")
struct SidebarBadgeOverlayTests {
    @Test("badge overlay modifier builds with and without badge text")
    @MainActor
    func badgeOverlayModifierBuildsWithOptionalBadgeText() {
        let badged = Image(systemName: "bell.fill")
            .frame(
                width: AppStyles.General.Button.compact,
                height: AppStyles.General.Button.compact
            )
            .sidebarBadgeOverlay(text: "3")
        let unbadged = Image(systemName: "bell")
            .frame(
                width: AppStyles.General.Button.compact,
                height: AppStyles.General.Button.compact
            )
            .sidebarBadgeOverlay(text: nil)

        #expect(String(describing: type(of: badged)).contains("ModifiedContent"))
        #expect(String(describing: type(of: unbadged)).contains("ModifiedContent"))
    }

    @Test("badge offset comes from sidebar badge placement token")
    func badgeOffsetComesFromSidebarToken() {
        #expect(AppStyles.Shell.Sidebar.badgeOffset > 0)
        #expect(AppStyles.Shell.Sidebar.badgeHitboxSize == AppStyles.General.Button.compact)
    }
}
