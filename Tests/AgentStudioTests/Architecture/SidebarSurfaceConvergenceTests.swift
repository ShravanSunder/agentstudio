import SwiftUI
import Testing

@testable import AgentStudio

@Suite("Sidebar surface convergence")
struct SidebarSurfaceConvergenceTests {
    @Test("repo and inbox sidebars share the repo-matched outer chrome and list policy")
    @MainActor
    func repoAndInboxSidebarsShareChromeAndListPolicy() {
        #expect(SidebarSurfaceHost.surfaceChromePolicy == SidebarSurfaceChrome<EmptyView>.policy)
        #expect(SidebarSurfaceHost.surfaceChromePolicy == .repoMatched)
        #expect(RepoExplorerView.surfaceListPolicy == .nativeSidebarList)
        #expect(InboxSidebarContent.surfaceListPolicy == .nativeSidebarList)
    }

    @Test("repo and inbox rows share SidebarRowShell chrome")
    @MainActor
    func repoAndInboxRowsShareSidebarRowShellChrome() {
        #expect(SidebarRowShell<EmptyView>.chromePolicy == .sidebarRowShell)
        #expect(RepoExplorerWorktreeRow.rowChromePolicy == .sidebarRowShell)
        #expect(InboxSidebarNotificationRow.rowChromePolicy == .sidebarRowShell)
        #expect(PaneInboxNotificationPopover.rowChromePolicy == .sidebarRowShell)
    }
}
