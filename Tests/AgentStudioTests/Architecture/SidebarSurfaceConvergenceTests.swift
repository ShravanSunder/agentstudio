import Foundation
import SwiftUI
import Testing

@testable import AgentStudio
@testable import AgentStudioInboxNotification
@testable import AgentStudioRepoExplorer
@testable import AgentStudioSharedComponents
@testable import AgentStudioTestSupport

@Suite("Sidebar surface convergence")
struct SidebarSurfaceConvergenceTests {
    @Test("inbox grouping uses protocol dispatch and App-owned typed callback adaptation")
    func inboxGroupingUsesProtocolDispatchAndAppOwnedTypedCallbackAdaptation() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let inboxSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift"
            ),
            encoding: .utf8
        )
        let appHostSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift"
            ),
            encoding: .utf8
        )

        #expect(!inboxSource.contains("onSelectGrouping: { prefsAtom.setGrouping($0) }"))
        #expect(inboxSource.contains("onSelectGrouping: selectGrouping"))
        #expect(inboxSource.contains("case .byTab: .setInboxGroupingTab"))
        #expect(inboxSource.contains("case .byRepo: .setInboxGroupingRepo"))
        #expect(inboxSource.contains("case .byPane: .setInboxGroupingPane"))
        #expect(inboxSource.contains("case .none: .setInboxGroupingNone"))
        #expect(!inboxSource.contains("prefsAtom.setGlobalInboxRowStateFilter"))
        #expect(!inboxSource.contains("prefsAtom.setGlobalInboxContentMode"))
        #expect(inboxSource.contains("onToggleRowStateFilter: { setRowStateFilter(nextRowStateFilter) }"))
        #expect(inboxSource.contains("onCycleContentMode: { setContentMode(nextContentMode) }"))
        #expect(inboxSource.contains("onSetRowStateFilter(rowStateFilter)"))
        #expect(inboxSource.contains("onSetContentMode(contentMode)"))
        #expect(appHostSource.contains("onSetRowStateFilter: { filter in"))
        #expect(appHostSource.contains("command: .setInboxRowStateFilter"))
        #expect(appHostSource.contains("arguments: .inboxRowStateFilter(filter)"))
        #expect(appHostSource.contains("onSetContentMode: { mode in"))
        #expect(appHostSource.contains("command: .setInboxContentMode"))
        #expect(appHostSource.contains("arguments: .inboxContentMode(mode)"))
    }

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

    @Test("repo sidebar owns sort and grouping controls through shared header slots")
    func repoSidebarOwnsSortAndGroupingControlsThroughSharedHeaderSlots() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let repoSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )
        #expect(repoSource.contains("} toolbarRow: {"))
        #expect(repoSource.contains("repoSidebarSortButton"))
        #expect(repoSource.contains("repoSidebarGroupingControl"))
        #expect(repoSource.contains("RepoExplorerGroupingMode.allCases"))
        #expect(!repoSource.contains("LocalActionSpec.groupRepoExplorerWorktrees.actionSpec"))
        #expect(repoSource.contains("RepoExplorerToolbarCommandPresentation.resolve("))
        #expect(repoSource.contains("commandPresentation.command(.setRepoSidebarSortOrder)"))
        #expect(repoSource.contains("label: sortCommand.commandSpec.label"))
        #expect(!repoSource.contains("RepoExplorerVisibilityButton"))
        #expect(!repoSource.contains("setRepoSidebarVisibilityMode"))
        #expect(!repoSource.contains("visibilityCommand"))
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
        #expect(!sharedSource.contains("CommandIcon"))
        #expect(sharedSource.contains("@ViewBuilder let icon: () -> Icon"))
    }

    @Test("inbox delete menu uses the shared toolbar menu primitive")
    func inboxDeleteMenuUsesSharedToolbarMenuPrimitive() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let inboxSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift"),
            encoding: .utf8
        )
        let toolbarSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/SharedComponents/SidebarSortButton.swift"),
            encoding: .utf8
        )

        #expect(inboxSource.contains("SidebarToolbarMenuButton("))
        #expect(!inboxSource.contains("private var deleteMenu: some View {\n        Menu {"))
        #expect(toolbarSource.contains("struct SidebarToolbarMenuButton"))
        #expect(toolbarSource.contains(".tint(Color.secondary)"))
    }

    @Test("repo grouping uses shared segments while inbox keeps its selectable popover")
    func repoGroupingUsesSharedSegmentsAndInboxKeepsSelectablePopover() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let repoSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )
        let commandToolbarSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+CommandToolbar.swift"
            ),
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
        let segmentedControlSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/SharedComponents/SidebarToolbarSegmentedControl.swift"),
            encoding: .utf8
        )
        let popoverSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/SharedComponents/SelectablePopover/SidebarGroupingPopover.swift"),
            encoding: .utf8
        )

        #expect(repoSource.contains("SidebarToolbarSegmentedControl("))
        #expect(inboxSource.contains("SidebarToolbarGroupingButton("))
        #expect(!repoSource.contains("SidebarGroupingPopover("))
        #expect(inboxSource.contains("SidebarGroupingPopover("))
        #expect(commandToolbarSource.contains("AppEntityIcon.repo"))
        #expect(commandToolbarSource.contains("AppEntityIcon.pane"))
        #expect(commandToolbarSource.contains("AppEntityIcon.tab"))
        #expect(inboxSource.contains("label: { groupingCommandSpec(for: $0).label }"))
        #expect(repoSource.contains("label: groupingMode.title"))
        #expect(!inboxSource.contains("label: { $0.commandLabel }"))
        #expect(!inboxSource.contains(")\n\n            Divider()\n\n            InboxSidebarContent("))
        #expect(toolbarSource.contains("struct SidebarToolbarGroupingButton"))
        #expect(segmentedControlSource.contains("struct SidebarToolbarSegmentedControl"))
        #expect(segmentedControlSource.contains(".controlHelp(segment.tooltipValue)"))
        #expect(popoverSource.contains("SelectablePopoverKeyboardBridge("))
    }
}
