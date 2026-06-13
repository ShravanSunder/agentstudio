import Foundation

@MainActor
final class CommandBarResultSession {
    private let store: WorkspaceStore
    private let repoCache: RepoCacheAtom
    private let dispatcher: CommandDispatcher
    private let notificationInboxCommands: InboxNotificationCommands?
    private let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?

    init(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        dispatcher: CommandDispatcher,
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

        return CommandBarItemSnapshot(
            scope: state.activeScope,
            isNested: false,
            items: CommandBarDataSource.items(
                scope: state.activeScope,
                store: store,
                repoCache: repoCache,
                dispatcher: dispatcher,
                focus: focus,
                notificationInboxCommands: notificationInboxCommands,
                performanceTraceRecorder: performanceTraceRecorder
            )
        )
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
