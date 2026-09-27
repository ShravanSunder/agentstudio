import AgentStudioCore
import AgentStudioInfrastructure
import Dispatch
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
    @ObservationIgnored private var rowGenerationValue: UInt64 = 0
    @ObservationIgnored private var preparedSearch: CommandBarPreparedSearch?
    @ObservationIgnored private var preparedLevelVisitRevision: Int?
    @ObservationIgnored private var lastPresentationSnapshot: CommandBarResultSnapshot?
    @ObservationIgnored private var lastTopologyInvalidatedAtNanoseconds: UInt64?
    private(set) var rootItemSnapshotInvalidationRevision = 0

    var currentRowGeneration: SearchDocumentGeneration {
        SearchDocumentGeneration(rowGenerationValue)
    }

    func navigationChanged() {
        advanceRowGeneration()
        preparedLevelVisitRevision = nil
        lastPresentationSnapshot = nil
    }

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
        if !searchQuery(for: state).isEmpty, let applied = state.appliedSearchResult {
            return appliedSnapshot(state: state, applied: applied)
        }
        if !searchQuery(for: state).isEmpty, let previous = lastPresentationSnapshot {
            return pendingSnapshot(state: state, previous: previous)
        }

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
            query: searchQuery(for: state),
            recentIds: state.recentItemIds
        )
        let filteredItems = searchDocument.query.isEmpty ? searchDocument.items : []
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

        let snapshot = CommandBarResultSnapshot(
            itemSnapshot: itemSnapshot,
            searchDocument: searchDocument,
            allItems: itemSnapshot.items,
            filteredItems: filteredItems,
            groups: groups,
            titleMatchesByItemId: [:],
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
        lastPresentationSnapshot = snapshot
        return snapshot
    }

    private func appliedSnapshot(
        state: CommandBarState,
        applied: CommandBarAppliedSearchResult
    ) -> CommandBarResultSnapshot {
        let selectedItem = Self.selectedItem(
            selectedIndex: state.selectedIndex,
            displayedItems: applied.displayedItems
        )
        let snapshot = CommandBarResultSnapshot(
            itemSnapshot: applied.itemSnapshot,
            searchDocument: CommandBarSearchDocument(
                items: applied.itemSnapshot.items,
                query: searchQuery(for: state),
                recentIds: state.recentItemIds
            ),
            allItems: applied.itemSnapshot.items,
            filteredItems: applied.displayedItems,
            groups: applied.groups,
            titleMatchesByItemId: applied.titleMatchesByItemId,
            displayedItems: applied.displayedItems,
            selectedItem: selectedItem,
            dimmedItemIds: applied.dimmedItemIds,
            footerHints: FooterHintBuilder.hints(
                for: selectedItem,
                isNested: state.isNested,
                canOpenInCurrentTab: applied.canOpenWorktreeInCurrentTab,
                scope: state.currentScope
            ),
            canOpenWorktreeInCurrentTab: applied.canOpenWorktreeInCurrentTab,
            currentMode: currentMode(),
            focusedPane: applied.focusedPane,
            commandContext: applied.commandContext
        )
        lastPresentationSnapshot = snapshot
        return snapshot
    }

    private func pendingSnapshot(
        state: CommandBarState,
        previous: CommandBarResultSnapshot
    ) -> CommandBarResultSnapshot {
        let selectedItem = Self.selectedItem(
            selectedIndex: state.selectedIndex,
            displayedItems: previous.displayedItems
        )
        let pending = CommandBarResultSnapshot(
            itemSnapshot: previous.itemSnapshot,
            searchDocument: CommandBarSearchDocument(
                items: previous.allItems,
                query: searchQuery(for: state),
                recentIds: state.recentItemIds
            ),
            allItems: previous.allItems,
            filteredItems: previous.filteredItems,
            groups: previous.groups,
            titleMatchesByItemId: previous.titleMatchesByItemId,
            displayedItems: previous.displayedItems,
            selectedItem: selectedItem,
            dimmedItemIds: previous.dimmedItemIds,
            footerHints: FooterHintBuilder.hints(
                for: selectedItem,
                isNested: state.isNested,
                canOpenInCurrentTab: previous.canOpenWorktreeInCurrentTab,
                scope: state.currentScope
            ),
            canOpenWorktreeInCurrentTab: previous.canOpenWorktreeInCurrentTab,
            currentMode: currentMode(),
            focusedPane: previous.focusedPane,
            commandContext: previous.commandContext
        )
        self.lastPresentationSnapshot = pending
        return pending
    }

    func prepareSearch(state: CommandBarState) -> CommandBarPreparedSearch {
        let focusedPane = currentFocusedPane()
        let commandContext = currentCommandContext(focusedPane: focusedPane)
        let itemSnapshot = buildItemSnapshot(
            state: state,
            focusedPane: focusedPane,
            commandContext: commandContext
        )
        if state.isNested, preparedLevelVisitRevision != state.levelVisitRevision {
            advanceRowGeneration()
        } else if !state.isNested, preparedLevelVisitRevision != nil {
            advanceRowGeneration()
        }
        preparedLevelVisitRevision = state.isNested ? state.levelVisitRevision : nil

        if let preparedSearch, preparedSearch.documentSet.generation == currentRowGeneration {
            return preparedSearch
        }

        var rowsById: [SearchItemId: CommandBarItem] = [:]
        var documents: [SearchDocument] = []
        var groups: [SearchGroup] = []
        var seenGroupIds: Set<String> = []
        for item in itemSnapshot.items {
            guard let itemId = SearchItemId(item.id), rowsById[itemId] == nil else { continue }
            rowsById[itemId] = item
            documents.append(
                SearchDocument(
                    itemId: itemId,
                    kind: searchKind(for: item.kind),
                    groupId: item.group,
                    title: item.title,
                    fields: item.searchFields
                )
            )
            if seenGroupIds.insert(item.group).inserted {
                groups.append(SearchGroup(id: item.group, priority: item.groupPriority))
            }
        }
        let documentSet = SearchDocumentSet(
            generation: currentRowGeneration,
            groups: groups,
            documents: documents
        )
        let prepared = CommandBarPreparedSearch(
            documentSet: documentSet,
            itemSnapshot: itemSnapshot,
            rowsById: rowsById,
            canOpenWorktreeInCurrentTab: canOpenWorktreeInCurrentTab(),
            focusedPane: focusedPane,
            commandContext: commandContext,
            topologyInvalidatedAtNanoseconds: lastTopologyInvalidatedAtNanoseconds
        )
        preparedSearch = prepared
        return prepared
    }

    func reconcileSelection(displayedItems: [CommandBarItem], state: CommandBarState) {
        state.selectedIndex = reconciledSelectedIndex(
            requestedIndex: state.selectedIndex,
            displayedItems: displayedItems
        )
        lastDisplayedItemIDs = displayedItems.map(\.id)
    }

    func dimmedItemIds(in displayedItems: [CommandBarItem]) -> Set<String> {
        dimmedItemIds(for: displayedItems)
    }

    private func searchKind(for itemKind: CommandBarItemKind) -> SearchKind {
        switch itemKind {
        case .repo: .repo
        case .worktree: .worktree
        case .pane: .pane
        case .tab: .tab
        case .command: .command
        case .other: .other
        }
    }

    private func advanceRowGeneration() {
        rowGenerationValue += 1
        preparedSearch = nil
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
                items: level.textEntry.map { textEntry in
                    textEntry.rowsForInput(
                        CommandBarTextEntryInput(
                            text: state.searchQuery
                        ))
                } ?? level.items
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
        advanceRowGeneration()
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

    /// A text-entry level's field is input, not a filter, so its rows are never filtered by it.
    private func searchQuery(for state: CommandBarState) -> String {
        guard state.isNested else { return state.normalizedRootQuery }
        return state.currentLevel?.textEntry == nil ? state.searchQuery : ""
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
        lastTopologyInvalidatedAtNanoseconds = DispatchTime.now().uptimeNanoseconds
        advanceRowGeneration()
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
                case .createWorktree(let draft):
                    CommandBarWorktreeCreationResolver.isActionable(draft, dispatcher: dispatcher)
                case .navigate, .navigateRepo, .custom, .worktreeAction, .quickOpen, .activateRecent:
                    true
                }
            if !isAvailable || !item.isEnabled {
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

    func canOpenWorktreeInCurrentTab() -> Bool {
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
