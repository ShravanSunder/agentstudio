import Foundation
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
        #expect(RepoExplorerView.surfaceBackground == .shellChrome)
        #expect(InboxSidebarRootContainer.surfaceBackground == .shellChrome)
        #expect(InboxSidebarContent.surfaceBackground == .shellChrome)
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

    @Test("repo and inbox grouped headers share source group header chrome")
    @MainActor
    func repoAndInboxGroupedHeadersShareSourceGroupHeaderChrome() {
        #expect(SidebarSourceGroupHeader<EmptyView>.chromePolicy == .sourceGroupHeader)
        #expect(SidebarRepoGroupHeader<EmptyView>.chromePolicy == .sourceGroupHeader)
        #expect(RepoExplorerView.groupHeaderChromePolicy == .sourceGroupHeader)
        #expect(InboxNotificationGroupHeader.chromePolicy(for: .sourceGroup) == .sourceGroupHeader)
    }

    @Test("repo and inbox headers share SidebarHeaderLayout")
    @MainActor
    func repoAndInboxHeadersShareSidebarHeaderLayout() throws {
        #expect(RepoExplorerView.headerLayoutPolicy == SidebarHeaderLayoutPolicy.standard)
        #expect(InboxSidebarHeader.headerLayoutPolicy == SidebarHeaderLayoutPolicy.standard)

        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let repoSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )
        let inboxSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift"),
            encoding: .utf8
        )

        #expect(repoSource.contains("SidebarHeaderLayout {"))
        #expect(inboxSource.contains("SidebarHeaderLayout {"))
        #expect(!repoSource.contains("InboxSidebarHeader("))
    }

    @Test("repo sidebar owns toolbar controls through shared header slots")
    func repoSidebarOwnsToolbarControlsThroughSharedHeaderSlots() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let repoSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )
        let visibilityButtonSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerVisibilityButton.swift"),
            encoding: .utf8
        )

        #expect(repoSource.contains("} toolbarRow: {"))
        #expect(repoSource.contains("RepoExplorerVisibilityButton("))
        #expect(repoSource.contains("repoSidebarSortButton"))
        #expect(repoSource.contains("repoSidebarGroupingButton"))
        #expect(repoSource.contains("RepoExplorerGroupingMode.allCases"))
        #expect(repoSource.contains("LocalActionSpec.repoSidebarCurrentOrder.actionSpec"))
        #expect(repoSource.contains("LocalActionSpec.groupRepoExplorerWorktrees.actionSpec"))
        #expect(visibilityButtonSource.contains("repoSidebarVisibilityButton"))
        #expect(visibilityButtonSource.contains("LocalActionSpec.toggleRepoSidebarFavoritesOnly"))
        #expect(!repoSource.contains("InboxSidebarToolbarTooltipTarget"))
    }

    @Test("repo and inbox sort controls share the toolbar sort primitive")
    func repoAndInboxSortControlsShareToolbarSortPrimitive() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let repoSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )
        let inboxSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift"),
            encoding: .utf8
        )
        let sharedSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/SharedComponents/SidebarSortButton.swift"),
            encoding: .utf8
        )

        #expect(repoSource.contains("SidebarToolbarSortButton("))
        #expect(inboxSource.contains("SidebarToolbarSortButton("))
        #expect(sharedSource.contains("struct SidebarToolbarSortButton"))
    }

    @Test("repo and inbox grouping controls share the labeled trigger and selectable popover")
    func repoAndInboxGroupingControlsShareLabeledTriggerAndSelectablePopover() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let repoSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )
        let inboxSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift"),
            encoding: .utf8
        )
        let toolbarSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/SharedComponents/SidebarSortButton.swift"),
            encoding: .utf8
        )
        let popoverSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/SharedComponents/SelectablePopover/SidebarGroupingPopover.swift"),
            encoding: .utf8
        )

        #expect(repoSource.contains("SidebarToolbarGroupingButton("))
        #expect(inboxSource.contains("SidebarToolbarGroupingButton("))
        #expect(repoSource.contains("SidebarGroupingPopover("))
        #expect(inboxSource.contains("SidebarGroupingPopover("))
        #expect(!inboxSource.contains(")\n\n            Divider()\n\n            InboxSidebarContent("))
        #expect(toolbarSource.contains("struct SidebarToolbarGroupingButton"))
        #expect(popoverSource.contains("SelectablePopoverKeyboardBridge("))
    }
}
