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

    @Test("app entity icons describe fixed sidebar icon slots")
    func appEntityIconsDescribeFixedSidebarIconSlots() {
        #expect(AppEntityIcon.repo.symbol == .octicon(.repo))
        #expect(AppEntityIcon.otherSources.symbol == .system(.tray))
        #expect(AppEntityIcon.pane.symbol == .system(.rectangleSplit2x1))
        #expect(AppEntityIcon.tab.symbol == .system(.squareStackFill))
        #expect(AppEntityIcon.paneGroup.symbol == .system(.rectangleSplit2x1))
        #expect(AppEntityIcon.tabGroup.symbol == .system(.squareStackFill))
    }

    @Test("app entity icons use semantic variants for colored pane and tab groups")
    func appEntityIconsUseSemanticVariantsForColoredPaneAndTabGroups() {
        #expect(AppEntityIcon.paneGroup != .pane)
        #expect(AppEntityIcon.tabGroup != .tab)
    }
}
