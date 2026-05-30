import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationSidebarView", .serialized)
struct InboxNotificationSidebarViewTests {
    @Test("preseeded filter state is consumed when the inbox mounts")
    func preseededFilterDraftIsConsumedOnMount() async {
        let inboxSidebarState = InboxSidebarStateAtom()
        inboxSidebarState.setPendingFilter(.worktree(id: UUID()))
        let hostingView = NSHostingView(
            rootView: InboxNotificationSidebarView(
                inboxAtom: InboxNotificationAtom(),
                prefsAtom: InboxNotificationPrefsAtom(),
                uiState: WorkspaceSidebarState(),
                sidebarCache: SidebarCacheAtom(),
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
                    sidebarCache: SidebarCacheAtom(),
                    inboxSidebarState: InboxSidebarStateAtom(),
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
                        sidebarCache: SidebarCacheAtom(),
                        inboxSidebarState: InboxSidebarStateAtom(),
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

                #expect(inboxSidebarAccessibleElementCount(in: hostingView, identifier: "inboxSidebarDeleteMenu") == 1)
                #expect(inboxSidebarAccessibleElementCount(in: hostingView, identifier: "inboxSidebarClearButton") == 0)
            }
        )
    }

    @Test("inbox header controls use distinct symbols and grouped row indentation")
    func inboxHeaderControlsUseDistinctSymbolsAndGroupedRowIndentation() {
        let sortIcon = AppCommand.toggleInboxNotificationSort.definition.icon

        #expect(sortIcon == .system(.arrowUpArrowDown))
        #expect(InboxSidebarHeader.groupIconName == "square.stack.3d.up")
        #expect(InboxSidebarHeader.filterIconName == "line.3.horizontal.decrease.circle")
        #expect(sortIcon != .system(.rectangle3GroupFill))
        #expect(InboxSidebarHeader.groupIconName != InboxSidebarHeader.filterIconName)
        #expect(InboxSidebarRootContainer.surfaceBackground == .windowBackgroundColor)
        #expect(InboxSidebarContent.surfaceBackground == .windowBackgroundColor)
        #expect(InboxSidebarContent.rowLeadingInset(isGrouped: false) == 0)
        #expect(
            InboxSidebarContent.rowLeadingInset(isGrouped: true)
                == AppStyles.Shell.Sidebar.groupChildRowLeadingInset
        )
        #expect(InboxSidebarContent.showsUnreadCount(for: .byPane) == false)
        #expect(InboxSidebarContent.showsUnreadCount(for: .byRepo))
        #expect(InboxSidebarContent.showsUnreadCount(for: .byTab))
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
                sidebarCache: SidebarCacheAtom(),
                inboxSidebarState: InboxSidebarStateAtom(),
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
                sidebarCache: SidebarCacheAtom(),
                inboxSidebarState: InboxSidebarStateAtom(),
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

@MainActor
@Suite("InboxNotificationSidebarView focus and activation", .serialized)
struct InboxSidebarFocusActivationTests {
    @Test("publishing non-nil inbox focus flips sidebarHasFocus true")
    func nonNilInboxFocusPublishesTrue() {
        let uiState = WorkspaceSidebarState()
        #expect(uiState.sidebarHasFocus == false)

        InboxSidebarFocusPublisher.publish(focusedField: .search, into: uiState)

        #expect(uiState.sidebarHasFocus == true)
    }

    @Test("publishing nil inbox focus flips sidebarHasFocus false")
    func nilInboxFocusPublishesFalse() {
        let uiState = WorkspaceSidebarState()
        uiState.setSidebarHasFocus(true)

        InboxSidebarFocusPublisher.publish(focusedField: nil, into: uiState)

        #expect(uiState.sidebarHasFocus == false)
    }

    @Test("focus bridge publishes sidebar focus and escape callback through mounted view")
    func focusBridgePublishesMountedViewEvents() async throws {
        let uiState = WorkspaceSidebarState()
        let workspacePaneAtom = WorkspacePaneAtom()
        var didRefocusActivePane = false
        let hostingView = NSHostingView(
            rootView: InboxNotificationSidebarView(
                inboxAtom: InboxNotificationAtom(),
                prefsAtom: InboxNotificationPrefsAtom(),
                uiState: uiState,
                sidebarCache: SidebarCacheAtom(),
                inboxSidebarState: InboxSidebarStateAtom(),
                workspacePaneAtom: workspacePaneAtom,
                workspaceRepositoryTopologyAtom: WorkspaceRepositoryTopologyAtom(),
                repoCache: RepoCacheAtom(),
                dispatcher: CommandDispatcher.shared,
                onRefocusActivePane: { didRefocusActivePane = true }
            )
            .frame(width: 320, height: 420)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let otherResponder = NSView(frame: .zero)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        let focusBridge = try #require(
            inboxSidebarDescendant(
                in: hostingView,
                identifier: InboxNotificationSidebarView.focusTargetIdentifier.rawValue
            )
        )

        #expect(uiState.sidebarHasFocus == false)
        #expect(window.makeFirstResponder(focusBridge))
        await Task.yield()
        #expect(uiState.sidebarHasFocus == true)

        focusBridge.cancelOperation(nil)
        #expect(didRefocusActivePane == true)

        #expect(window.makeFirstResponder(otherResponder))
        await Task.yield()
        #expect(uiState.sidebarHasFocus == false)
    }

    @Test("activation resolver flashes stale rows instead of dispatching dead panes")
    func activationResolverFlashesStaleRows() {
        let notification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .agentRpc,
            title: "Done",
            body: nil,
            source: .pane(
                .init(
                    paneId: UUID(),
                    worktreeId: UUID(),
                    worktreeName: "main"
                )
            ),
            isRead: false,
            isDismissedFromPaneInbox: false
        )

        let outcome = InboxSidebarActivationResolver.resolve(
            notification: notification,
            workspacePaneAtom: WorkspacePaneAtom()
        )

        #expect(outcome == .flashRow(notification.id))
    }

    @Test("activation resolver focuses live pane rows")
    func activationResolverFocusesLivePane() {
        let paneId = PaneId()
        let notification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .agentRpc,
            title: "Done",
            body: nil,
            source: .pane(.init(paneId: paneId.uuid)),
            isRead: false,
            isDismissedFromPaneInbox: false
        )
        let workspacePaneAtom = WorkspacePaneAtom()
        workspacePaneAtom.addPane(
            Pane(
                id: paneId.uuid,
                content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
                metadata: PaneMetadata(
                    paneId: paneId,
                    contentType: .terminal,
                    source: .floating(launchDirectory: nil, title: nil),
                    title: "Pane"
                )
            )
        )

        let outcome = InboxSidebarActivationResolver.resolve(
            notification: notification,
            workspacePaneAtom: workspacePaneAtom
        )

        #expect(outcome == .focusPane(paneId.uuid))
    }

    @Test("activation resolver focuses live drawer child pane rows")
    func activationResolverFocusesLiveDrawerChildPane() {
        let parentPaneId = UUIDv7.generate()
        let drawerPaneId = UUIDv7.generate()
        let notification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .commandFinished,
            title: "Done",
            body: nil,
            source: .pane(.init(paneId: drawerPaneId)),
            isRead: false,
            isDismissedFromPaneInbox: false
        )
        let workspacePaneAtom = WorkspacePaneAtom()
        let parentPane = Pane(
            id: parentPaneId,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                paneId: PaneId(uuid: parentPaneId),
                contentType: .terminal,
                source: .floating(launchDirectory: nil, title: nil),
                title: "Parent"
            ),
            kind: .layout(drawer: Drawer(paneIds: [drawerPaneId]))
        )
        let drawerPane = Pane(
            id: drawerPaneId,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                paneId: PaneId(uuid: drawerPaneId),
                contentType: .terminal,
                source: .floating(launchDirectory: nil, title: nil),
                title: "Drawer"
            ),
            kind: .drawerChild(parentPaneId: parentPaneId)
        )
        workspacePaneAtom.addPane(parentPane)
        workspacePaneAtom.addPane(drawerPane)

        let outcome = InboxSidebarActivationResolver.resolve(
            notification: notification,
            workspacePaneAtom: workspacePaneAtom
        )

        #expect(outcome == .focusPane(drawerPaneId))
    }
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
            unreadOnly: false,
            sort: .newestFirst,
            groupingMenuOpen: $groupingMenuOpen,
            grouping: grouping,
            focusedField: $focusedField,
            sections: sections,
            flashingRowIds: [],
            actions: .init(
                onEscape: {},
                onToggleSort: {},
                onToggleUnreadOnly: {},
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
