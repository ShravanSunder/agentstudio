import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite("SidebarHeaderLayout")
struct SidebarHeaderLayoutTests {
    @Test("layout exposes the sidebar header spacing policy it applies")
    func layoutExposesSidebarHeaderSpacingPolicy() {
        let policy = SidebarHeaderLayout<EmptyView, EmptyView, EmptyView, EmptyView>.policy

        #expect(policy == .standard)
        #expect(policy.rowSpacing == AppStyles.General.Spacing.tight)
        #expect(policy.searchActionSpacing == AppStyles.General.Spacing.standard)
        #expect(policy.contentPadding == AppStyles.Shell.Sidebar.Header.contentPadding)
    }
}
