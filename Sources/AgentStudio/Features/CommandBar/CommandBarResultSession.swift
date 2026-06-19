import Foundation
import Observation

@MainActor
@Observable
final class CommandBarResultSession {
    private struct RootItemSnapshotCacheIdentity: Equatable {
        let scope: CommandBarScope
        let focus: WorkspacePaneFocus
        let rootSessionGeneration: Int
    }

    private struct CachedRootItemSnapshot {
        let identity: RootItemSnapshotCacheIdentity
        let snapshot: CommandBarItemSnapshot
    }

    @ObservationIgnored private let store: WorkspaceStore
    @ObservationIgnored private let repoCache: RepoCacheAtom
    @ObservationIgnored private let dispatcher: AppCommandDispatcher
    @ObservationIgnored private let notificationInboxCommands: InboxNotificationCommands?
    @ObservationIgnored private let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    @ObservationIgnored private var cachedRootItemSnapshot: CachedRootItemSnapshot?
    @ObservationIgnored private var isRootItemSnapshotInvalidated = false
    @ObservationIgnored private var rootItemSnapshotObservationGeneration = 0
    private(set) var rootItemSnapshotInvalidationRevision = 0

    @ObservationIgnored
    private(set) var rootItemSnapshotBuildCount = 0
    @ObservationIgnored
    private(set) var rootItemSnapshotCacheHitCount = 0

    init(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        dispatcher: AppCommandDispatcher,
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
        let currentContext = currentContext()
        let canOpenWorktreeInCurrentTab = canOpenWorktreeInCurrentTab()
        let itemSnapshot = buildItemSnapshot(state: state, focus: currentContext)
        let searchDocument = CommandBarSearchDocument(
            items: itemSnapshot.items,
            query: state.searchQuery,
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
        let selectedItem = Self.selectedItem(
            selectedIndex: state.selectedIndex,
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
            currentContext: currentContext
        )
    }

    private func buildItemSnapshot(
        state: CommandBarState,
        focus: WorkspacePaneFocus
    ) -> CommandBarItemSnapshot {
        if let level = state.currentLevel {
            return CommandBarItemSnapshot(
                scope: state.currentScope,
                isNested: true,
                items: level.items
            )
        }

        let identity = RootItemSnapshotCacheIdentity(
            scope: state.activeScope,
            focus: focus,
            rootSessionGeneration: state.rootSessionGeneration
        )
        if let cachedRootItemSnapshot,
            cachedRootItemSnapshot.identity == identity,
            !isRootItemSnapshotInvalidated
        {
            rootItemSnapshotCacheHitCount += 1
            return cachedRootItemSnapshot.snapshot
        }

        let snapshot = trackedRootItemSnapshot(scope: state.activeScope, focus: focus)
        cachedRootItemSnapshot = CachedRootItemSnapshot(identity: identity, snapshot: snapshot)
        isRootItemSnapshotInvalidated = false
        rootItemSnapshotBuildCount += 1
        return snapshot
    }

    private func trackedRootItemSnapshot(
        scope: CommandBarScope,
        focus: WorkspacePaneFocus
    ) -> CommandBarItemSnapshot {
        rootItemSnapshotObservationGeneration += 1
        let observationGeneration = rootItemSnapshotObservationGeneration
        return withObservationTracking {
            CommandBarItemSnapshot(
                scope: scope,
                isNested: false,
                items: CommandBarDataSource.items(
                    scope: scope,
                    store: store,
                    repoCache: repoCache,
                    dispatcher: dispatcher,
                    focus: focus,
                    notificationInboxCommands: notificationInboxCommands,
                    performanceTraceRecorder: performanceTraceRecorder
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
            if let command = item.command, !dispatcher.canDispatch(command) {
                ids.insert(item.id)
            }
        }
        return ids
    }

    private func currentMode() -> CommandBarAppMode {
        atom(\.managementLayer).isActive ? .management : .normal
    }

    private func currentContext() -> WorkspacePaneFocus {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        return atom(\.workspacePaneFocus).currentFocus(
            workspaceTab: workspaceTab,
            workspacePane: store.paneAtom,
            workspaceFocusOwner: atom(\.workspaceFocusOwner)
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

    private static func selectedItem(
        selectedIndex: Int,
        displayedItems: [CommandBarItem]
    ) -> CommandBarItem? {
        guard selectedIndex >= 0, selectedIndex < displayedItems.count else { return nil }
        return displayedItems[selectedIndex]
    }
}
