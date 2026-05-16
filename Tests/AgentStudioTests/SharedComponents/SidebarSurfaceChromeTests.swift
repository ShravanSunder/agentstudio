import SwiftUI
import Testing

@testable import AgentStudio

@Suite("SidebarSurfaceChrome")
struct SidebarSurfaceChromeTests {
    @Test("chrome component exposes the repo sidebar outer surface policy it applies")
    @MainActor
    func chromeComponentExposesRepoSidebarOuterSurfacePolicy() {
        let policy = SidebarSurfaceChrome<EmptyView>.policy

        #expect(policy == .repoMatched)
        #expect(policy.minimumWidth == AppStyles.Shell.Sidebar.minimumWidth)
        #expect(policy.background == .windowBackgroundColor)
        #expect(policy.shadowOpacity == AppStyles.Shell.Sidebar.shadowOpacity)
        #expect(policy.shadowRadius == AppStyles.Shell.Sidebar.shadowRadius)
        #expect(policy.shadowOffsetX == AppStyles.Shell.Sidebar.shadowOffsetX)
        #expect(policy.shadowOffsetY == AppStyles.Shell.Sidebar.shadowOffsetY)
    }
}
