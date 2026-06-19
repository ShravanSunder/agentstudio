import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationSidebarView", .serialized)
struct InboxNotificationSidebarViewTests {
    @Test("preseeded filter state is consumed when the inbox mounts")
    func preseededFilterDraftIsConsumedOnMount() async {
        let inboxSidebarState = InboxSidebarState()
        inboxSidebarState.setPendingFilter(.worktree(id: UUID()))
        let hostingView = NSHostingView(
            rootView: InboxNotificationSidebarView(
                inboxAtom: InboxNotificationAtom(),
                prefsAtom: InboxNotificationPrefsAtom(),
                uiState: WorkspaceSidebarState(),
                sidebarCache: SidebarCacheState(),
                inboxSidebarState: inboxSidebarState,
                workspacePaneAtom: WorkspacePaneAtom(),
                workspaceRepositoryTopologyAtom: WorkspaceRepositoryTopologyAtom(),
                repoCache: RepoCacheAtom(),
                dispatcher: CommandDispatcher.shared,
                onRefocusActivePane: {}
            )
            .frame(width: 320, height: 420)
        )

        hostingView.layoutSubtreeIfNeeded()

        await assertEventuallyMain("mounted inbox should consume pending filter state") {
            inboxSidebarState.peekPendingFilter() == nil
        }
    }

    @Test("sidebar dismissal clears active inbox filter")
    func sidebarDismissalClearsActiveInboxFilter() async {
        let repoId = UUID()
        let inboxAtom = InboxNotificationAtom()
        inboxAtom.append(makeSourceNotification(repoId: repoId, repoName: "agent-studio"))
        let inboxSidebarState = InboxSidebarState()
        inboxSidebarState.setPendingFilter(.repo(id: repoId))
        let hostingView = NSHostingView(
            rootView: InboxNotificationSidebarView(
                inboxAtom: inboxAtom,
                prefsAtom: InboxNotificationPrefsAtom(),
                uiState: WorkspaceSidebarState(),
                sidebarCache: SidebarCacheState(),
                inboxSidebarState: inboxSidebarState,
                workspacePaneAtom: WorkspacePaneAtom(),
                workspaceRepositoryTopologyAtom: WorkspaceRepositoryTopologyAtom(),
                repoCache: RepoCacheAtom(),
                dispatcher: CommandDispatcher.shared,
                onRefocusActivePane: {}
            )
            .frame(width: 320, height: 420)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hostingView.layoutSubtreeIfNeeded()

        await assertEventuallyMain("mounted inbox should show active filter") {
            inboxSidebarAccessibleElementCount(in: hostingView, identifier: "inboxSidebarActiveFilterChip") == 1
        }

        inboxSidebarState.markDismissed()
        hostingView.layoutSubtreeIfNeeded()

        await assertEventuallyMain("dismissed inbox should clear active filter") {
            inboxSidebarAccessibleElementCount(in: hostingView, identifier: "inboxSidebarActiveFilterChip") == 0
        }
    }

    @Test("root key router maps documented option and command shortcuts")
    func rootKeyRouterMapsShortcuts() {
        #expect(
            InboxSidebarKeyboardRouter.rootAction(
                characters: "f",
                key: "f",
                modifiers: .option
            ) == .focusSearch
        )
        #expect(
            InboxSidebarKeyboardRouter.rootAction(
                characters: "g",
                key: "g",
                modifiers: .option
            ) == .toggleGroupingMenu
        )
        #expect(
            InboxSidebarKeyboardRouter.rootAction(
                characters: "s",
                key: "s",
                modifiers: .option
            ) == .toggleSort
        )
        #expect(
            InboxSidebarKeyboardRouter.rootAction(
                characters: "",
                key: .downArrow,
                modifiers: .option
            ) == .moveGroupBoundary(.next)
        )
        #expect(
            InboxSidebarKeyboardRouter.rootAction(
                characters: "",
                key: .upArrow,
                modifiers: .option
            ) == .moveGroupBoundary(.previous)
        )
        #expect(
            InboxSidebarKeyboardRouter.rootAction(
                characters: "",
                key: .downArrow,
                modifiers: .command
            ) == .moveEnd(.last)
        )
        #expect(
            InboxSidebarKeyboardRouter.rootAction(
                characters: "",
                key: .upArrow,
                modifiers: .command
            ) == .moveEnd(.first)
        )
    }

    @Test("row key router maps activation and read toggle shortcuts")
    func rowKeyRouterMapsShortcuts() {
        #expect(InboxSidebarKeyboardRouter.rowAction(key: .return) == .activate)
        #expect(InboxSidebarKeyboardRouter.rowAction(key: .space) == .toggleRead)
        #expect(InboxSidebarKeyboardRouter.rowAction(key: "x") == .ignored)
    }

    @Test("inbox sidebar keyboard hints describe local shortcuts")
    func inboxSidebarKeyboardHintsDescribeLocalShortcuts() {
        #expect(InboxSidebarKeyboardHint.focusSearch == "⌥F")
        #expect(InboxSidebarKeyboardHint.toggleGroupingMenu == "⌥G")
        #expect(InboxSidebarKeyboardHint.toggleSort == "⌥S")
        #expect(InboxSidebarKeyboardHint.moveNextGroup == "⌥↓")
        #expect(InboxSidebarKeyboardHint.movePreviousGroup == "⌥↑")
        #expect(InboxSidebarKeyboardHint.moveLast == "⌘↓")
        #expect(InboxSidebarKeyboardHint.moveFirst == "⌘↑")
        #expect(InboxSidebarKeyboardHint.activateRow == "↵")
        #expect(InboxSidebarKeyboardHint.toggleRead == "Space")
    }

    @Test("clear action dispatches the clear read inbox command")
    func clearActionDispatchesClearReadInboxCommand() async throws {
        let router = MockAppCommandRouter()
        router.appCommands = [.clearReadInboxNotifications]
        try await withIsolatedCommandDispatcher(
            configure: {
                CommandDispatcher.shared.appCommandRouter = router
                CommandDispatcher.shared.handler = nil
            },
            body: {
                let view = InboxNotificationSidebarView(
                    inboxAtom: InboxNotificationAtom(),
                    prefsAtom: InboxNotificationPrefsAtom(),
                    uiState: WorkspaceSidebarState(),
                    sidebarCache: SidebarCacheState(),
                    inboxSidebarState: InboxSidebarState(),
                    workspacePaneAtom: WorkspacePaneAtom(),
                    workspaceRepositoryTopologyAtom: WorkspaceRepositoryTopologyAtom(),
                    repoCache: RepoCacheAtom(),
                    dispatcher: .shared,
                    onRefocusActivePane: {}
                )

                view.clearReadInboxNotifications()

                #expect(router.handledCommands == [.clearReadInboxNotifications])
            }
        )
    }

    @Test("mounted inbox sidebar delete menu replaces the clear button")
    func mountedInboxSidebarDeleteMenuReplacesClearButton() async throws {
        let router = MockAppCommandRouter()
        router.appCommands = [.clearReadInboxNotifications]
        try await withIsolatedCommandDispatcher(
            configure: {
                CommandDispatcher.shared.appCommandRouter = router
                CommandDispatcher.shared.handler = nil
            },
            body: {
                let hostingView = NSHostingView(
                    rootView: InboxNotificationSidebarView(
                        inboxAtom: InboxNotificationAtom(),
                        prefsAtom: InboxNotificationPrefsAtom(),
                        uiState: WorkspaceSidebarState(),
                        sidebarCache: SidebarCacheState(),
                        inboxSidebarState: InboxSidebarState(),
                        workspacePaneAtom: WorkspacePaneAtom(),
                        workspaceRepositoryTopologyAtom: WorkspaceRepositoryTopologyAtom(),
                        repoCache: RepoCacheAtom(),
                        dispatcher: .shared,
                        onRefocusActivePane: {}
                    )
                    .frame(width: 360, height: 420)
                )
                let window = NSWindow(
                    contentRect: CGRect(x: 0, y: 0, width: 360, height: 420),
                    styleMask: [.titled, .closable],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hostingView
                window.makeKeyAndOrderFront(nil)
                defer { window.orderOut(nil) }
                hostingView.layoutSubtreeIfNeeded()

                #expect(inboxSidebarAccessibleElementCount(in: hostingView, identifier: "inboxSidebarSearchRow") == 1)
                #expect(inboxSidebarAccessibleElementCount(in: hostingView, identifier: "inboxSidebarToolbarRow") == 1)
                #expect(inboxSidebarAccessibleElementCount(in: hostingView, identifier: "inboxSidebarDeleteMenu") == 1)
                #expect(inboxSidebarAccessibleElementCount(in: hostingView, identifier: "inboxSidebarClearButton") == 0)
                #expect(
                    inboxSidebarAccessibleElementCount(in: hostingView, identifier: "inboxSidebarSortButtonFrame") == 0)
                guard
                    let searchRow = inboxSidebarDescendant(
                        in: hostingView,
                        identifier: "inboxSidebarSearchRow"
                    ),
                    let toolbarRow = inboxSidebarDescendant(
                        in: hostingView,
                        identifier: "inboxSidebarToolbarRow"
                    ),
                    let deleteMenuView = inboxSidebarDescendant(
                        in: hostingView,
                        identifier: "inboxSidebarDeleteMenu"
                    ),
                    let sortButton = inboxSidebarDescendant(
                        in: hostingView,
                        identifier: "inboxSidebarSortButtonFrame"
                    ),
                    let deleteMenuBridge = inboxSidebarAccessibleElement(
                        in: hostingView,
                        identifier: "inboxSidebarDeleteMenu"
                    )
                else {
                    Issue.record("mounted inbox sidebar should expose the delete menu accessibility target")
                    return
                }
                let searchRowFrame = searchRow.convert(searchRow.bounds, to: hostingView)
                let toolbarRowFrame = toolbarRow.convert(toolbarRow.bounds, to: hostingView)
                let deleteMenuFrame = deleteMenuView.convert(deleteMenuView.bounds, to: hostingView)
                let sortButtonFrame = sortButton.convert(sortButton.bounds, to: hostingView)

                #expect(deleteMenuFrame.width > 0)
                #expect(deleteMenuFrame.height > 0)
                #expect(deleteMenuFrame.midX > searchRowFrame.midX)
                #expect(deleteMenuFrame.maxX <= searchRowFrame.maxX)
                #expect(sortButtonFrame.midX > toolbarRowFrame.midX)

                pressInboxSidebarAccessibleElement(deleteMenuBridge)

                #expect(router.handledCommands == [.clearReadInboxNotifications])
            }
        )
    }

    @Test("global sidebar content mode is binary attention or all")
    func globalSidebarContentModeIsBinaryAttentionOrAll() {
        #expect(InboxNotificationSidebarView.globalSidebarContentMode(.rollUpAlerts) == .rollUpAlerts)
        #expect(InboxNotificationSidebarView.globalSidebarContentMode(.all) == .all)
        #expect(InboxNotificationSidebarView.globalSidebarContentMode(.activity) == .all)
    }

    @Test("mark visible scope read only marks currently visible attention rows")
    func markVisibleScopeReadOnlyMarksCurrentlyVisibleAttentionRows() {
        let inboxAtom = InboxNotificationAtom()
        let activity = makeClaimedNotification(
            kind: .unseenActivity,
            title: "Activity",
            lane: .activity,
            semantic: .unseenActivity
        )
        let action = makeClaimedNotification(
            kind: .approvalRequested,
            title: "Action",
            lane: .actionNeeded,
            semantic: .approvalRequested
        )
        let settled = makeClaimedNotification(
            kind: .agentSettledActivity,
            title: "Settled",
            lane: .settledAgent,
            semantic: .agentSettled
        )
        inboxAtom.append(activity)
        inboxAtom.append(action)
        inboxAtom.append(settled)
        let view = InboxNotificationSidebarView(
            inboxAtom: inboxAtom,
            prefsAtom: InboxNotificationPrefsAtom(),
            uiState: WorkspaceSidebarState(),
            sidebarCache: SidebarCacheState(),
            inboxSidebarState: InboxSidebarState(),
            workspacePaneAtom: WorkspacePaneAtom(),
            workspaceRepositoryTopologyAtom: WorkspaceRepositoryTopologyAtom(),
            repoCache: RepoCacheAtom(),
            dispatcher: .shared,
            onRefocusActivePane: {}
        )

        view.markVisibleScopeRead()

        let readByNotificationId = Dictionary(
            uniqueKeysWithValues: inboxAtom.notifications.map { ($0.id, $0.isRead) }
        )
        #expect(readByNotificationId[activity.id] == false)
        #expect(readByNotificationId[action.id] == true)
        #expect(readByNotificationId[settled.id] == true)
    }

    @Test("active filter label uses full inbox source when visible rows are empty")
    func activeFilterLabelUsesFullInboxSourceWhenVisibleRowsAreEmpty() {
        let repoId = UUID()
        let notification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .agentRpc,
            title: "Done",
            body: nil,
            source: .pane(
                .init(
                    paneId: UUID(),
                    repoId: repoId,
                    repoName: "askluna",
                    worktreeName: "notification-system"
                )
            ),
            isRead: false,
            isDismissedFromPaneInbox: false
        )
        let visibleModel = InboxNotificationListModel(
            notifications: [notification],
            grouping: .none,
            sort: .newestFirst,
            searchText: "does-not-match",
            filter: .repo(id: repoId),
            collapsedGroups: []
        )

        let hasNoVisibleRows = visibleModel.sections.allSatisfy { $0.notifications.isEmpty }
        #expect(hasNoVisibleRows)
        #expect(
            InboxNotificationSidebarView.activeFilterLabel(
                activeFilter: .repo(id: repoId),
                notifications: [notification]
            ) == "askluna"
        )
    }

    @Test("mounted root keeps active filter label when visible rows are empty")
    func mountedRootKeepsActiveFilterLabelWhenVisibleRowsAreEmpty() throws {
        let repoId = UUID()
        let notification = makeSourceNotification(repoId: repoId, repoName: "askluna")
        let sections = InboxNotificationListModel(
            notifications: [notification],
            grouping: .none,
            sort: .newestFirst,
            searchText: "does-not-match",
            filter: .repo(id: repoId),
            collapsedGroups: []
        ).sections

        let hostingView = NSHostingView(
            rootView: InboxSidebarRootHarness(
                activeFilter: .repo(id: repoId),
                activeFilterLabel: "askluna",
                grouping: .none,
                sections: sections
            )
            .frame(width: 360, height: 420)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hostingView.layoutSubtreeIfNeeded()

        let chip = try #require(
            inboxSidebarAccessibleElement(in: hostingView, identifier: "inboxSidebarActiveFilterChip")
        )

        #expect(inboxSidebarAccessibleElementCount(in: hostingView, identifier: "inboxSidebarActiveFilterChip") == 1)
        #expect(inboxSidebarAccessibleElementCount(in: hostingView, identifier: "inboxSidebarClearFilterButton") == 1)
        #expect(inboxSidebarAccessibilityLabel(of: chip) == "askluna")
    }

    @Test("mounted root hides unread count badges for by-pane grouping")
    func mountedRootHidesUnreadCountBadgesForByPaneGrouping() {
        let paneId = UUID()
        let notification = makeSourceNotification(
            paneId: paneId,
            paneDisplayLabel: "project-dev"
        )
        let sections = InboxNotificationListModel(
            notifications: [notification],
            grouping: .byPane,
            sort: .newestFirst,
            searchText: "",
            filter: nil,
            collapsedGroups: []
        ).sections

        let hostingView = NSHostingView(
            rootView: InboxSidebarRootHarness(
                activeFilter: nil,
                activeFilterLabel: nil,
                grouping: .byPane,
                sections: sections
            )
            .frame(width: 360, height: 420)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hostingView.layoutSubtreeIfNeeded()

        #expect(inboxSidebarAccessibleElementCount(in: hostingView, identifier: "inboxGroupUnreadBadge") == 0)
    }

    @Test("all grouped inbox section headers use source group header chrome")
    @MainActor
    func groupedInboxHeadersUseSourceGroupHeaderChrome() {
        #expect(InboxNotificationGroupHeader.chromePolicy(for: .sourceGroup) == .sourceGroupHeader)
        #expect(RepoExplorerView.groupHeaderChromePolicy == .sourceGroupHeader)
        #expect(SidebarSourceGroupHeader<EmptyView>.chromePolicy == .sourceGroupHeader)
        #expect(SidebarRepoGroupHeader<EmptyView>.chromePolicy == .sourceGroupHeader)
        #expect(SidebarSourceGroupHeader<EmptyView>.leadingInset == AppStyles.Shell.Sidebar.listRowLeadingInset)
    }
}

@MainActor
@Suite("InboxNotificationSidebarView source groups", .serialized)
struct InboxNotificationSidebarViewSourceGroupTests {

    @Test("inbox group header maps every source kind to a fixed icon slot")
    @MainActor
    func inboxGroupHeaderMapsEverySourceKindToFixedIconSlot() {
        #expect(InboxNotificationGroupHeader.icon(for: .repo(organizationName: nil)) == .repo)
        #expect(InboxNotificationGroupHeader.icon(for: .pane) == .pane)
        #expect(InboxNotificationGroupHeader.icon(for: .tab) == .tab)
        #expect(InboxNotificationGroupHeader.icon(for: .workspace) == .workspace)
        #expect(InboxNotificationGroupHeader.icon(for: .otherSources) == .otherSources)
    }

    @Test("repo source group can carry checkout accent color")
    @MainActor
    func repoSourceGroupCanCarryCheckoutAccentColor() {
        let icon = InboxNotificationGroupHeader.icon(
            for: .repo(organizationName: "askluna"),
            accentColorHex: "#EAC54F"
        )

        if case .coloredRepo(let colorHex) = icon {
            #expect(colorHex == "#EAC54F")
        } else {
            Issue.record("Expected colored repo source icon for repo group with accent color")
        }
    }

    @Test("source group header accessibility target is the actionable toggle")
    func sourceGroupHeaderAccessibilityTargetIsActionableToggle() throws {
        var didToggle = false
        let hostingView = NSHostingView(
            rootView: InboxNotificationGroupHeader(
                header: InboxNotificationListSectionHeader(
                    title: "agent-studio",
                    secondaryTitle: "ShravanSunder",
                    sourceKind: .repo(organizationName: "ShravanSunder"),
                    accentColorHex: "#EAC54F"
                ),
                unreadCount: 0,
                isCollapsed: false,
                onToggle: { didToggle = true }
            )
            .frame(width: 320, height: 56)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 56),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hostingView.layoutSubtreeIfNeeded()

        let header = try #require(
            inboxSidebarAccessibleElement(in: hostingView, identifier: "inboxSourceGroupHeader")
        )
        #expect(inboxSidebarAccessibleElementCount(in: hostingView, identifier: "inboxSourceGroupHeader") == 1)
        #expect(inboxSidebarAccessibilityLabel(of: header) == "agent-studio, ShravanSunder")
        pressInboxSidebarAccessibleElement(header)

        #expect(didToggle)
    }

    @Test("mounted grouped roots render source group headers for repo pane and tab")
    func mountedGroupedRootsRenderSourceGroupHeaders() {
        let repoId = UUID()
        let paneId = UUID()
        let notification = makeSourceNotification(
            paneId: paneId,
            repoId: repoId,
            repoName: "agent-studio",
            paneDisplayLabel: "project-dev",
            tabDisplayLabel: "Tab agent-studio"
        )

        for grouping in [InboxNotificationGrouping.byRepo, .byPane, .byTab] {
            let sections = InboxNotificationListModel(
                notifications: [notification],
                grouping: grouping,
                sort: .newestFirst,
                searchText: "",
                filter: nil,
                collapsedGroups: [],
                repoPresentation: { requestedRepoId in
                    guard requestedRepoId == repoId else { return nil }
                    return InboxNotificationRepoGroupPresentation(
                        title: "agent-studio",
                        organizationName: "ShravanSunder",
                        accentColorHex: "#EAC54F"
                    )
                }
            ).sections
            let hostingView = NSHostingView(
                rootView: InboxSidebarRootHarness(
                    activeFilter: nil,
                    activeFilterLabel: nil,
                    grouping: grouping,
                    sections: sections
                )
                .frame(width: 360, height: 420)
            )
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 360, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            hostingView.layoutSubtreeIfNeeded()

            #expect(inboxSidebarAccessibleElementCount(in: hostingView, identifier: "inboxSourceGroupHeader") == 1)
        }
    }

    @Test("mounted by-repo grouping renders repo and other sources through source group headers")
    func mountedByRepoGroupingRendersRepoAndOtherSourcesHeaders() throws {
        let repoId = UUID()
        let repoNotification = makeSourceNotification(
            paneId: UUID(),
            repoId: repoId,
            repoName: "agent-studio",
            paneDisplayLabel: "project-dev"
        )
        let globalNotification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 120),
            kind: .agentRpc,
            title: "Workspace event",
            body: nil,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )
        let sections = InboxNotificationListModel(
            notifications: [repoNotification, globalNotification],
            grouping: .byRepo,
            sort: .newestFirst,
            searchText: "",
            filter: nil,
            collapsedGroups: [],
            repoPresentation: { requestedRepoId in
                guard requestedRepoId == repoId else { return nil }
                return InboxNotificationRepoGroupPresentation(
                    title: "agent-studio",
                    organizationName: "ShravanSunder",
                    accentColorHex: "#EAC54F"
                )
            }
        ).sections

        let hostingView = NSHostingView(
            rootView: InboxSidebarRootHarness(
                activeFilter: nil,
                activeFilterLabel: nil,
                grouping: .byRepo,
                sections: sections
            )
            .frame(width: 360, height: 420)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hostingView.layoutSubtreeIfNeeded()

        let headerLabels = inboxSidebarAccessibleElementLabels(in: hostingView, identifier: "inboxSourceGroupHeader")

        #expect(headerLabels.count == 2)
        #expect(headerLabels.contains("agent-studio, ShravanSunder"))
        #expect(headerLabels.contains("Other sources"))
    }

    @Test("mounted inbox sidebar uses repo presentation atoms for grouped header")
    func mountedInboxSidebarUsesRepoPresentationAtomsForGroupedHeader() throws {
        let repoId = UUID()
        let paneId = UUID()
        let inboxAtom = InboxNotificationAtom()
        let prefsAtom = InboxNotificationPrefsAtom()
        let repositoryTopologyAtom = WorkspaceRepositoryTopologyAtom()
        let repoCache = RepoCacheAtom()
        let worktree = Worktree(
            id: UUID(),
            repoId: repoId,
            name: "notification-inbox-redesign",
            path: URL(fileURLWithPath: "/tmp/agent-studio.notification-inbox-redesign"),
            isMainWorktree: false
        )
        let repo = Repo(
            id: repoId,
            name: "agent-studio.notification-inbox-redesign",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            worktrees: [worktree]
        )
        repositoryTopologyAtom.hydrate(
            runtimeRepos: [repo],
            watchedPaths: [],
            unavailableRepoIds: []
        )
        repoCache.setRepoEnrichment(
            .resolvedRemote(
                repoId: repoId,
                raw: RawRepoOrigin(
                    origin: "git@github.com:ShravanSunder/agent-studio.git",
                    upstream: nil
                ),
                identity: RepoIdentity(
                    groupKey: "github:ShravanSunder/agent-studio",
                    remoteSlug: "ShravanSunder/agent-studio",
                    organizationName: "ShravanSunder",
                    displayName: "agent-studio"
                ),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        prefsAtom.setGrouping(.byRepo)
        prefsAtom.setGlobalInboxContentMode(.all)
        inboxAtom.append(
            makeSourceNotification(
                paneId: paneId,
                repoId: repoId,
                repoName: "filesystem-name",
                paneDisplayLabel: "project-dev"
            )
        )

        let hostingView = NSHostingView(
            rootView: InboxNotificationSidebarView(
                inboxAtom: inboxAtom,
                prefsAtom: prefsAtom,
                uiState: WorkspaceSidebarState(),
                sidebarCache: SidebarCacheState(),
                inboxSidebarState: InboxSidebarState(),
                workspacePaneAtom: WorkspacePaneAtom(),
                workspaceRepositoryTopologyAtom: repositoryTopologyAtom,
                repoCache: repoCache,
                dispatcher: .shared,
                onRefocusActivePane: {}
            )
            .frame(width: 360, height: 420)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hostingView.layoutSubtreeIfNeeded()

        let header = try #require(
            inboxSidebarAccessibleElement(in: hostingView, identifier: "inboxSourceGroupHeader")
        )
        #expect(inboxSidebarAccessibilityLabel(of: header) == "agent-studio, ShravanSunder")
    }

    @Test("mounted inbox sidebar refreshes repo presentation after atom changes")
    func mountedInboxSidebarRefreshesRepoPresentationAfterAtomChanges() async throws {
        let repoId = UUID()
        let paneId = UUID()
        let inboxAtom = InboxNotificationAtom()
        let prefsAtom = InboxNotificationPrefsAtom()
        let repositoryTopologyAtom = WorkspaceRepositoryTopologyAtom()
        let repoCache = RepoCacheAtom()
        let worktree = Worktree(
            id: UUID(),
            repoId: repoId,
            name: "notification-inbox-redesign",
            path: URL(fileURLWithPath: "/tmp/agent-studio.notification-inbox-redesign"),
            isMainWorktree: false
        )
        let repo = Repo(
            id: repoId,
            name: "agent-studio.notification-inbox-redesign",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            worktrees: [worktree]
        )
        repositoryTopologyAtom.hydrate(
            runtimeRepos: [repo],
            watchedPaths: [],
            unavailableRepoIds: []
        )
        prefsAtom.setGrouping(.byRepo)
        prefsAtom.setGlobalInboxContentMode(.all)
        inboxAtom.append(
            makeSourceNotification(
                paneId: paneId,
                repoId: repoId,
                repoName: "filesystem-name",
                paneDisplayLabel: "project-dev"
            )
        )

        let hostingView = NSHostingView(
            rootView: InboxNotificationSidebarView(
                inboxAtom: inboxAtom,
                prefsAtom: prefsAtom,
                uiState: WorkspaceSidebarState(),
                sidebarCache: SidebarCacheState(),
                inboxSidebarState: InboxSidebarState(),
                workspacePaneAtom: WorkspacePaneAtom(),
                workspaceRepositoryTopologyAtom: repositoryTopologyAtom,
                repoCache: repoCache,
                dispatcher: .shared,
                onRefocusActivePane: {}
            )
            .frame(width: 360, height: 420)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hostingView.layoutSubtreeIfNeeded()

        let initialHeader = try #require(
            inboxSidebarAccessibleElement(in: hostingView, identifier: "inboxSourceGroupHeader")
        )
        #expect(inboxSidebarAccessibilityLabel(of: initialHeader) == "agent-studio.notification-inbox-redesign")

        repoCache.setRepoEnrichment(
            .resolvedRemote(
                repoId: repoId,
                raw: RawRepoOrigin(
                    origin: "git@github.com:ShravanSunder/agent-studio.git",
                    upstream: nil
                ),
                identity: RepoIdentity(
                    groupKey: "github:ShravanSunder/agent-studio",
                    remoteSlug: "ShravanSunder/agent-studio",
                    organizationName: "ShravanSunder",
                    displayName: "agent-studio"
                ),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        hostingView.layoutSubtreeIfNeeded()

        await assertEventuallyMain("repo presentation should refresh after cache mutation") {
            inboxSidebarAccessibleElementLabels(in: hostingView, identifier: "inboxSourceGroupHeader")
                .contains("agent-studio, ShravanSunder")
        }
    }
}

private func makeClaimedNotification(
    kind: InboxNotificationKind,
    title: String,
    lane: InboxNotificationClaimLane,
    semantic: InboxNotificationClaimSemantic
) -> InboxNotification {
    let paneId = UUID()
    return InboxNotification(
        id: UUID(),
        timestamp: Date(timeIntervalSince1970: 100),
        kind: kind,
        title: title,
        body: nil,
        source: .pane(.init(paneId: paneId)),
        claimKey: .init(
            paneId: paneId,
            lane: lane,
            semantic: semantic,
            sessionId: nil
        ),
        isRead: false,
        isDismissedFromPaneInbox: false
    )
}

@MainActor
private struct InboxSidebarRootHarness: View {
    let activeFilter: InboxFilter?
    let activeFilterLabel: String?
    let grouping: InboxNotificationGrouping
    let sections: [InboxNotificationListSection]
    let uiState = WorkspaceSidebarState()

    @State private var searchText = ""
    @State private var groupingMenuOpen = false
    @FocusState private var focusedField: InboxFocus?

    var body: some View {
        InboxSidebarRootContainer(
            uiState: uiState,
            searchText: $searchText,
            activeFilter: activeFilter,
            activeFilterLabel: activeFilterLabel,
            contentMode: .all,
            rowStateFilter: .all,
            sort: .newestFirst,
            groupingMenuOpen: $groupingMenuOpen,
            grouping: grouping,
            focusedField: $focusedField,
            sections: sections,
            flashingRowIds: [],
            actions: .init(
                onEscape: {},
                onToggleSort: {},
                onToggleRowStateFilter: {},
                onCycleContentMode: {},
                onMarkVisibleScopeRead: {},
                onClearFilter: {},
                onClearReadHistory: {},
                onClearAllHistory: {},
                onSelectGrouping: { _ in },
                onToggleGroupCollapse: { _ in },
                onMoveGroupBoundary: { _ in false },
                onMoveEnd: { _ in false },
                onActivate: { _ in },
                onToggleRead: { _ in }
            )
        )
    }
}
