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
        #expect(policy.background == .shellChrome)
        #expect(policy.background.nsColor == AppStyles.Shell.TabBar.titlebarBackground)
        #expect(policy.shadowOpacity == 0)
        #expect(policy.shadowRadius == 0)
        #expect(policy.shadowOffsetX == 0)
        #expect(policy.shadowOffsetY == 0)
    }
}
