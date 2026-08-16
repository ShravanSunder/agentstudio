import AgentStudioInfrastructure
import SwiftUI
import Testing

@testable import AgentStudioSharedComponents

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

    @Test("pane and tab group icons use their group semantic colors")
    func paneAndTabGroupIconsUseTheirGroupSemanticColors() {
        #expect(AppEntityIcon.paneGroup != .pane)
        #expect(AppEntityIcon.tabGroup != .tab)
        #expect(AppEntityIcon.paneGroup.foregroundStyle == Color.secondary)
        #expect(
            AppEntityIcon.tabGroup.foregroundStyle
                == AppStyles.Shell.Sidebar.mutedPrimaryAccentColor
        )
    }

    @Test("group headers and row lines share one icon-to-text spacing token")
    func groupHeadersAndRowsShareIconTextSpacing() throws {
        let groupHeaderSource = try String(
            contentsOfFile: "Sources/AgentStudio/SharedComponents/SidebarSourceGroupHeader.swift",
            encoding: .utf8
        )
        let groupRowSource = try String(
            contentsOfFile: "Sources/AgentStudio/SharedComponents/SidebarGroupRow.swift",
            encoding: .utf8
        )
        let worktreeRowSource = try String(
            contentsOfFile: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift",
            encoding: .utf8
        )
        let paneRowSource = try String(
            contentsOfFile: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerPaneNavigation.swift",
            encoding: .utf8
        )
        let sectionHeaderSource = try String(
            contentsOfFile: "Sources/AgentStudio/SharedComponents/SidebarSectionHeader.swift",
            encoding: .utf8
        )
        let metadataLineSource = try String(
            contentsOfFile: "Sources/AgentStudio/SharedComponents/SidebarMetadataLine.swift",
            encoding: .utf8
        )
        let statusRowsSource = try String(
            contentsOfFile: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerStatusRows.swift",
            encoding: .utf8
        )
        let appStylesSource = try String(
            contentsOfFile: "Sources/AgentStudio/Infrastructure/AppStyles.swift",
            encoding: .utf8
        )

        #expect(
            appStylesSource.contains(
                "iconTextSpacing: CGFloat = AppStyles.General.Spacing.tight"
            )
        )
        for source in [
            groupHeaderSource,
            groupRowSource,
            sectionHeaderSource,
            metadataLineSource,
            worktreeRowSource,
            paneRowSource,
            statusRowsSource,
        ] {
            #expect(source.contains("AppStyles.Shell.Sidebar.iconTextSpacing"))
            #expect(!source.contains("groupIconTitleSpacing"))
            #expect(!source.contains("sectionHeaderChevronLabelSpacing"))
        }
    }
}
