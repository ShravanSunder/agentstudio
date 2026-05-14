import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite("SidebarSourceGroupHeader")
struct SidebarSourceGroupHeaderTests {
    @Test("source group header uses shared chrome policy and leading inset")
    func sourceGroupHeaderUsesSharedChromePolicyAndLeadingInset() {
        #expect(SidebarSourceGroupHeader<EmptyView>.chromePolicy == .sourceGroupHeader)
        #expect(
            SidebarSourceGroupHeader<EmptyView>.leadingInset
                == AppStyles.Shell.Sidebar.listRowLeadingInset
        )
    }

    @Test("default repo header wraps source group header chrome")
    func defaultRepoHeaderWrapsSourceGroupHeaderChrome() {
        #expect(SidebarRepoGroupHeader<EmptyView>.chromePolicy == .sourceGroupHeader)
        #expect(
            SidebarRepoGroupHeader<EmptyView>.leadingInset
                == SidebarSourceGroupHeader<EmptyView>.leadingInset
        )
    }

    @Test("source group icons describe fixed sidebar icon slots")
    func sourceGroupIconsDescribeFixedSidebarIconSlots() {
        #expect(SidebarSourceGroupIcon.repo.symbolName == "octicon-repo")
        #expect(SidebarSourceGroupIcon.otherSources.symbolName == "tray")
        #expect(SidebarSourceGroupIcon.pane.symbolName == "rectangle.inset.filled")
        #expect(SidebarSourceGroupIcon.tab.symbolName == "macwindow")
    }
}
