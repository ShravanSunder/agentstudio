import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Observation

@MainActor
@Observable
final class CommandBarResultSession {
    private struct RootItemSnapshotCacheIdentity: Equatable {
        let scope: CommandBarScope
        let focusedPane: WorkspaceFocusedPane?
        let commandContext: CommandContext
        let rootSessionGeneration: Int
        let queryState: CommandBarRootQueryState
    }

    private struct CachedRootItemSnapshot {
        let identity: RootItemSnapshotCacheIdentity
        let snapshot: CommandBarItemSnapshot
    }

    @ObservationIgnored private let store: WorkspaceStore
    @ObservationIgnored private let repoCache: RepoCacheAtom
    @ObservationIgnored private let dispatcher: any AppCommandDispatching
    @ObservationIgnored private let notificationInboxCommands: InboxNotificationCommands?
    @ObservationIgnored private let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    @ObservationIgnored private let repoScopeItemCache = CommandBarRepoScopeItemCache()
    @ObservationIgnored private var cachedRootItemSnapshot: CachedRootItemSnapshot?
    @ObservationIgnored private var lastDisplayedItemIDs: [String] = []
    @ObservationIgnored private var isRootItemSnapshotInvalidated = false
    @ObservationIgnored private var rootItemSnapshotObservationGeneration = 0
    private(set) var rootItemSnapshotInvalidationRevision = 0

    @ObservationIgnored
    private(set) var rootItemSnapshotBuildCount = 0
    @ObservationIgnored
    private(set) var rootItemSnapshotCacheHitCount = 0

    @ObservationIgnored
    var repoScopeItemBuildCount: Int { repoScopeItemCache.buildCount }

    init(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        dispatcher: any AppCommandDispatching,
        notificationInboxCommands: InboxNotificationCommands? = nil,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) {
        self.store = store
        self.repoCache = repoCache
        self.dispatcher = dispatcher
        self.notificationInboxCommands = notificationInboxCommands
        self.performanceTraceRecorder = performanceTraceRecorder
    }

    func snapshot(state: CommandBarState) -> CommandBarResultSnapshot {
        _ = rootItemSnapshotInvalidationRevision
        let focusedPane = currentFocusedPane()
        let commandContext = currentCommandContext(focusedPane: focusedPane)
        let canOpenWorktreeInCurrentTab = canOpenWorktreeInCurrentTab()
        let itemSnapshot = buildItemSnapshot(
            state: state,
            focusedPane: focusedPane,
            commandContext: commandContext
        )
        let searchDocument = CommandBarSearchDocument(
            items: itemSnapshot.items,
            query: state.isNested ? state.searchQuery : state.normalizedRootQuery,
            recentIds: state.recentItemIds
        )
        let filteredItems = CommandBarSearch.filter(
            items: searchDocument.items,
            query: searchDocument.query,
            recentIds: searchDocument.recentIds,
            performanceTraceRecorder: performanceTraceRecorder
        )
        let groups = CommandBarDataSource.grouped(filteredItems)
        let displayedItems = CommandBarDataSource.displayItems(from: groups)
        let selectedIndex = reconciledSelectedIndex(
            requestedIndex: state.selectedIndex,
            displayedItems: displayedItems
        )
        if state.selectedIndex != selectedIndex {
            state.selectedIndex = selectedIndex
        }
        lastDisplayedItemIDs = displayedItems.map(\.id)
        let selectedItem = Self.selectedItem(
            selectedIndex: selectedIndex,
            displayedItems: displayedItems
        )

        return CommandBarResultSnapshot(
            itemSnapshot: itemSnapshot,
            searchDocument: searchDocument,
            allItems: itemSnapshot.items,
            filteredItems: filteredItems,
            groups: groups,
            displayedItems: displayedItems,
            selectedItem: selectedItem,
            dimmedItemIds: dimmedItemIds(for: displayedItems),
            footerHints: FooterHintBuilder.hints(
                for: selectedItem,
                isNested: state.isNested,
                canOpenInCurrentTab: canOpenWorktreeInCurrentTab,
                scope: state.currentScope
            ),
            canOpenWorktreeInCurrentTab: canOpenWorktreeInCurrentTab,
            currentMode: currentMode(),
            focusedPane: focusedPane,
            commandContext: commandContext
        )
    }

    private func buildItemSnapshot(
        state: CommandBarState,
        focusedPane: WorkspaceFocusedPane?,
        commandContext: CommandContext
    ) -> CommandBarItemSnapshot {
        if let level = state.currentLevel {
            return CommandBarItemSnapshot(
                scope: state.currentScope,
                isNested: true,
                items: level.items
            )
        }

        let queryState: CommandBarRootQueryState =
            state.hasMeaningfulRootQuery ? .meaningful : .empty
        let identity = RootItemSnapshotCacheIdentity(
            scope: state.activeScope,
            focusedPane: focusedPane,
            commandContext: commandContext,
            rootSessionGeneration: state.rootSessionGeneration,
            queryState: queryState
        )
        if let cachedRootItemSnapshot,
            cachedRootItemSnapshot.identity == identity,
            !isRootItemSnapshotInvalidated
        {
            rootItemSnapshotCacheHitCount += 1
            performanceTraceRecorder?.record(
                .commandBarCache,
                attributes: ["agentstudio.performance.commandbar.cache_outcome": .string("hit")]
            )
            return cachedRootItemSnapshot.snapshot
        }

        let invalidationReason = rootItemSnapshotInvalidationReason(for: identity)
        let snapshot = trackedRootItemSnapshot(
            scope: state.activeScope,
            queryState: queryState,
            recentCommands: state.recentCommands,
            focusedPane: focusedPane,
            commandContext: commandContext
        )
        cachedRootItemSnapshot = CachedRootItemSnapshot(identity: identity, snapshot: snapshot)
        isRootItemSnapshotInvalidated = false
        rootItemSnapshotBuildCount += 1
        performanceTraceRecorder?.record(
            .commandBarCache,
            attributes: [
                "agentstudio.performance.commandbar.cache_outcome": .string("miss"),
                "agentstudio.performance.commandbar.invalidation_reason": .string(invalidationReason),
            ]
        )
        return snapshot
    }

    private func rootItemSnapshotInvalidationReason(
        for identity: RootItemSnapshotCacheIdentity
    ) -> String {
        guard let cachedIdentity = cachedRootItemSnapshot?.identity else { return "open_generation" }
        if isRootItemSnapshotInvalidated { return "topology_observation" }
        if cachedIdentity.scope != identity.scope { return "scope_change" }
        if cachedIdentity.focusedPane != identity.focusedPane { return "focused_pane" }
        if cachedIdentity.commandContext != identity.commandContext { return "command_context" }
        if cachedIdentity.rootSessionGeneration != identity.rootSessionGeneration { return "open_generation" }
        return "query_meaningful_transition"
    }

    private func trackedRootItemSnapshot(
        scope: CommandBarScope,
        queryState: CommandBarRootQueryState,
        recentCommands: [AppCommand],
        focusedPane: WorkspaceFocusedPane?,
        commandContext: CommandContext
    ) -> CommandBarItemSnapshot {
        rootItemSnapshotObservationGeneration += 1
        let observationGeneration = rootItemSnapshotObservationGeneration
        return withObservationTracking {
            CommandBarItemSnapshot(
                scope: scope,
                isNested: false,
                items: CommandBarDataSource.items(
                    scope: scope,
                    rootQueryState: queryState,
                    recentCommands: recentCommands,
                    store: store,
                    repoCache: repoCache,
                    dispatcher: dispatcher,
                    focusedPane: focusedPane,
                    commandContext: commandContext,
                    notificationInboxCommands: notificationInboxCommands,
                    performanceTraceRecorder: performanceTraceRecorder,
                    repoScopeItemCache: repoScopeItemCache
                )
            )
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                self?.invalidateRootItemSnapshot(observationGeneration: observationGeneration)
            }
        }
    }

    private func invalidateRootItemSnapshot(observationGeneration: Int) {
        guard rootItemSnapshotObservationGeneration == observationGeneration else { return }
        isRootItemSnapshotInvalidated = true
        rootItemSnapshotInvalidationRevision += 1
    }

    private func dimmedItemIds(for displayedItems: [CommandBarItem]) -> Set<String> {
        var ids = Set<String>()
        for item in displayedItems {
            let isAvailable =
                switch item.action {
                case .dispatch(let command):
                    dispatcher.canDispatch(command)
                case .dispatchTargeted(let command, let target, let targetType):
                    dispatcher.canDispatch(command, target: target, targetType: targetType)
                case .navigate, .navigateRepo, .custom, .worktreeAction, .quickOpen, .activateRecent:
                    true
                }
            if !isAvailable {
                ids.insert(item.id)
            }
        }
        return ids
    }

    private func currentMode() -> CommandBarAppMode {
        atom(\.managementLayer).isActive ? .management : .normal
    }

    private func currentFocusedPane() -> WorkspaceFocusedPane? {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        return atom(\.workspaceFocusedPane).resolve(
            workspaceTab: workspaceTab,
            workspacePane: store.paneAtom,
            requestedOwner: atom(\.workspaceFocusOwner).owner
        )
    }

    private func currentCommandContext(
        focusedPane: WorkspaceFocusedPane?
    ) -> CommandContext {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        return atom(\.commandContext).currentContext(
            workspaceTab: workspaceTab,
            workspacePane: store.paneAtom,
            focusedPane: focusedPane,
            workspacePanePresentation: store.panePresentationAtom
        )
    }

    private func canOpenWorktreeInCurrentTab() -> Bool {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        guard
            let activeTabId = store.tabShellAtom.activeTabId,
            let activeTab = workspaceTab.tab(activeTabId),
            activeTab.activePaneId != nil
        else {
            return false
        }
        return true
    }

    private func reconciledSelectedIndex(
        requestedIndex: Int,
        displayedItems: [CommandBarItem]
    ) -> Int {
        guard !displayedItems.isEmpty else { return 0 }

        if lastDisplayedItemIDs.indices.contains(requestedIndex) {
            let selectedItemID = lastDisplayedItemIDs[requestedIndex]
            if let preservedIndex = displayedItems.firstIndex(where: { $0.id == selectedItemID }) {
                return preservedIndex
            }
        }

        return min(max(requestedIndex, 0), displayedItems.count - 1)
    }

    private static func selectedItem(
        selectedIndex: Int,
        displayedItems: [CommandBarItem]
    ) -> CommandBarItem? {
        guard selectedIndex >= 0, selectedIndex < displayedItems.count else { return nil }
        return displayedItems[selectedIndex]
    }
}
