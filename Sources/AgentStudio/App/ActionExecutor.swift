import Foundation
import os.log

private let executorLogger = Logger(subsystem: "com.agentstudio", category: "ActionExecutor")

/// Executes validated PaneActions by coordinating WorkspaceStore,
/// ViewRegistry, TerminalViewCoordinator, and surface lifecycle.
///
/// This is the action dispatch hub — replaces the giant switch statement
/// in TerminalTabViewController. All state mutations flow through here.
@MainActor
final class ActionExecutor {
    private let store: WorkspaceStore
    private let viewRegistry: ViewRegistry
    private let coordinator: TerminalViewCoordinator

    /// In-memory undo stack for close snapshots.
    private(set) var undoStack: [WorkspaceStore.CloseSnapshot] = []

    /// Maximum undo stack entries before oldest are garbage-collected.
    private let maxUndoStackSize = 10

    init(store: WorkspaceStore, viewRegistry: ViewRegistry, coordinator: TerminalViewCoordinator) {
        self.store = store
        self.viewRegistry = viewRegistry
        self.coordinator = coordinator
    }

    // MARK: - High-Level Operations

    /// Open a terminal for a worktree. Creates pane + tab + view.
    /// Returns the pane if a new one was created, nil if already open.
    @discardableResult
    func openTerminal(for worktree: Worktree, in repo: Repo) -> Pane? {
        // Check if worktree already has an active pane in any tab
        if let existingTab = store.tabs.first(where: { tab in
            tab.paneIds.contains { paneId in
                store.pane(paneId)?.worktreeId == worktree.id
            }
        }) {
            store.setActiveTab(existingTab.id)
            return nil
        }

        return createTerminalTab(for: worktree, in: repo)
    }

    /// Open a new terminal for a worktree, always creating a fresh pane+tab
    /// (never navigates to an existing one).
    @discardableResult
    func openNewTerminal(for worktree: Worktree, in repo: Repo) -> Pane? {
        createTerminalTab(for: worktree, in: repo)
    }

    /// Common path: create pane + view + tab for a worktree.
    private func createTerminalTab(for worktree: Worktree, in repo: Repo) -> Pane? {
        let pane = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            title: worktree.name,
            provider: .zmx,
            lifetime: .persistent,
            residency: .active
        )

        guard coordinator.createView(for: pane, worktree: worktree, repo: repo) != nil else {
            executorLogger.error("Surface creation failed for worktree '\(worktree.name)' — rolling back pane \(pane.id)")
            store.removePane(pane.id)
            return nil
        }

        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        executorLogger.info("Opened terminal for worktree: \(worktree.name)")
        return pane
    }

    /// Undo the last close operation.
    func undoCloseTab() {
        guard let snapshot = undoStack.popLast() else {
            executorLogger.info("No tabs to restore from undo stack")
            return
        }

        // Restore tab + panes in store
        store.restoreFromSnapshot(snapshot)

        // Restore views via coordinator — iterate in reverse to match the LIFO
        // order of SurfaceManager's undo stack (panes were pushed in forward
        // order during close, so the last pane is on top of the stack).
        for pane in snapshot.panes.reversed() {
            guard let worktreeId = pane.worktreeId,
                  let repoId = pane.repoId,
                  let worktree = store.worktree(worktreeId),
                  let repo = store.repo(repoId) else {
                executorLogger.warning("Could not find worktree/repo for pane \(pane.id)")
                continue
            }
            coordinator.restoreView(for: pane, worktree: worktree, repo: repo)
        }
    }

    // MARK: - PaneAction Execution

    /// Execute a resolved PaneAction.
    func execute(_ action: PaneAction) {
        executorLogger.debug("Executing: \(String(describing: action))")

        switch action {
        case .selectTab(let tabId):
            store.setActiveTab(tabId)

        case .closeTab(let tabId):
            executeCloseTab(tabId)

        case .breakUpTab(let tabId):
            executeBreakUpTab(tabId)

        case .closePane(let tabId, let paneId):
            executeClosePane(tabId: tabId, paneId: paneId)

        case .extractPaneToTab(let tabId, let paneId):
            _ = store.extractPane(paneId, fromTab: tabId)

        case .focusPane(let tabId, let paneId):
            // Auto-expand if focusing a minimized pane
            if let tab = store.tab(tabId), tab.minimizedPaneIds.contains(paneId) {
                store.expandPane(paneId, inTab: tabId)
                coordinator.reattachForViewSwitch(paneId: paneId)
            }
            store.setActivePane(paneId, inTab: tabId)

        case .insertPane(let source, let targetTabId, let targetPaneId, let direction):
            executeInsertPane(
                source: source,
                targetTabId: targetTabId,
                targetPaneId: targetPaneId,
                direction: direction
            )

        case .resizePane(let tabId, let splitId, let ratio):
            store.resizePane(tabId: tabId, splitId: splitId, ratio: ratio)

        case .equalizePanes(let tabId):
            store.equalizePanes(tabId: tabId)

        case .toggleSplitZoom(let tabId, let paneId):
            store.toggleZoom(paneId: paneId, inTab: tabId)

        case .moveTab(let tabId, let delta):
            store.moveTabByDelta(tabId: tabId, delta: delta)

        case .minimizePane(let tabId, let paneId):
            coordinator.detachForViewSwitch(paneId: paneId)
            store.minimizePane(paneId, inTab: tabId)

        case .expandPane(let tabId, let paneId):
            store.expandPane(paneId, inTab: tabId)
            coordinator.reattachForViewSwitch(paneId: paneId)

        case .resizePaneByDelta(let tabId, let paneId, let direction, let amount):
            store.resizePaneByDelta(tabId: tabId, paneId: paneId, direction: direction, amount: amount)

        case .mergeTab(let sourceTabId, let targetTabId, let targetPaneId, let direction):
            executeMergeTab(
                sourceTabId: sourceTabId,
                targetTabId: targetTabId,
                targetPaneId: targetPaneId,
                direction: direction
            )

        case .createArrangement(let tabId, let name, let paneIds):
            _ = store.createArrangement(name: name, paneIds: paneIds, inTab: tabId)

        case .removeArrangement(let tabId, let arrangementId):
            store.removeArrangement(arrangementId, inTab: tabId)

        case .switchArrangement(let tabId, let arrangementId):
            // Capture visible panes BEFORE switching
            let previousVisiblePaneIds: Set<UUID>
            if let tab = store.tab(tabId) {
                previousVisiblePaneIds = tab.activeArrangement.visiblePaneIds
            } else {
                previousVisiblePaneIds = []
            }

            // Switch arrangement in store
            store.switchArrangement(to: arrangementId, inTab: tabId)

            // Get newly visible panes AFTER switching
            guard let tab = store.tab(tabId),
                  let arrangement = tab.arrangements.first(where: { $0.id == arrangementId }) else { break }
            let newVisiblePaneIds = arrangement.visiblePaneIds

            // Detach surfaces for panes that were visible but are now hidden
            let hiddenPaneIds = previousVisiblePaneIds.subtracting(newVisiblePaneIds)
            for paneId in hiddenPaneIds {
                coordinator.detachForViewSwitch(paneId: paneId)
            }

            // Reattach surfaces for panes that are now visible but were hidden
            let revealedPaneIds = newVisiblePaneIds.subtracting(previousVisiblePaneIds)
            for paneId in revealedPaneIds {
                coordinator.reattachForViewSwitch(paneId: paneId)
            }

        case .renameArrangement(let tabId, let arrangementId, let name):
            store.renameArrangement(arrangementId, name: name, inTab: tabId)

        case .backgroundPane(let paneId):
            store.backgroundPane(paneId)

        case .reactivatePane(let paneId, let targetTabId, let targetPaneId, let direction):
            let layoutDirection = bridgeDirection(direction)
            let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after
            store.reactivatePane(paneId, inTab: targetTabId, at: targetPaneId,
                                 direction: layoutDirection, position: position)
            // After reactivation, ensure the pane has a view.
            // Backgrounded panes lose their view on restart (restoreAllViews skips them).
            if viewRegistry.view(for: paneId) == nil, let pane = store.pane(paneId) {
                coordinator.createViewForContent(pane: pane)
            }

        case .purgeOrphanedPane(let paneId):
            // Only teardown if the pane is actually backgrounded — prevents destroying
            // views for live panes if this action is dispatched incorrectly.
            guard let pane = store.pane(paneId), pane.residency == .backgrounded else { break }
            coordinator.teardownView(for: paneId)
            store.purgeOrphanedPane(paneId)

        case .addDrawerPane(let parentPaneId, let content, let metadata):
            if let drawerPane = store.addDrawerPane(to: parentPaneId, content: content, metadata: metadata) {
                if coordinator.createViewForContent(pane: drawerPane) == nil {
                    executorLogger.warning("addDrawerPane: view creation failed for \(drawerPane.id) — panel will show placeholder")
                }
            }

        case .removeDrawerPane(let parentPaneId, let drawerPaneId):
            coordinator.teardownView(for: drawerPaneId)
            store.removeDrawerPane(drawerPaneId, from: parentPaneId)

        case .toggleDrawer(let paneId):
            store.toggleDrawer(for: paneId)

        case .setActiveDrawerPane(let parentPaneId, let drawerPaneId):
            store.setActiveDrawerPane(drawerPaneId, in: parentPaneId)

        case .expireUndoEntry(let paneId):
            // TODO: Phase 3 — remove pane from store, kill zmx, destroy surface
            executorLogger.warning("expireUndoEntry: \(paneId) — stub, full impl in Phase 3")

        case .repair(let repairAction):
            executeRepair(repairAction)
        }
    }

    // MARK: - Private Execution

    private func executeCloseTab(_ tabId: UUID) {
        // Snapshot for undo before closing
        if let snapshot = store.snapshotForClose(tabId: tabId) {
            undoStack.append(snapshot)
        }

        // Teardown views for all panes in this tab (including drawer panes)
        if let tab = store.tab(tabId) {
            for paneId in tab.paneIds {
                teardownDrawerPanes(for: paneId)
                coordinator.teardownView(for: paneId)
            }
        }

        store.removeTab(tabId)

        // GC oldest undo entries to prevent pane accumulation
        expireOldUndoEntries()
    }

    /// Remove oldest undo entries beyond the limit, cleaning up their orphaned panes.
    private func expireOldUndoEntries() {
        while undoStack.count > maxUndoStackSize {
            let expired = undoStack.removeFirst()
            // Remove panes that are not owned by any tab (across all arrangements).
            // Use tab.panes (ownership list) instead of tab.paneIds (active arrangement only)
            // to avoid GC'ing panes hidden in non-active arrangements.
            let allOwnedPaneIds = Set(store.tabs.flatMap(\.panes))
            for pane in expired.panes where !allOwnedPaneIds.contains(pane.id) {
                store.removePane(pane.id)
                executorLogger.debug("GC'd orphaned pane \(pane.id) from expired undo entry")
            }
        }
    }

    private func executeBreakUpTab(_ tabId: UUID) {
        let newTabs = store.breakUpTab(tabId)
        if newTabs.isEmpty {
            executorLogger.debug("breakUpTab: tab has single pane, no-op")
        }
    }

    private func executeClosePane(tabId: UUID, paneId: UUID) {
        teardownDrawerPanes(for: paneId)
        coordinator.teardownView(for: paneId)
        let tabNowEmpty = store.removePaneFromLayout(paneId, inTab: tabId)

        if tabNowEmpty {
            // Last pane removed — escalate to close tab (with undo support)
            executeCloseTab(tabId)
        }

        // If the pane is no longer owned by any tab, remove it from the store.
        let allOwnedPaneIds = Set(store.tabs.flatMap(\.panes))
        if !allOwnedPaneIds.contains(paneId) {
            store.removePane(paneId)
        }
    }

    private func executeInsertPane(
        source: PaneSource,
        targetTabId: UUID,
        targetPaneId: UUID,
        direction: SplitNewDirection
    ) {
        let layoutDirection = bridgeDirection(direction)
        let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after

        switch source {
        case .existingPane(let paneId, let sourceTabId):
            // Always remove from source layout first to prevent duplicate IDs.
            let sourceTabEmpty = store.removePaneFromLayout(paneId, inTab: sourceTabId)
            store.insertPane(
                paneId, inTab: targetTabId, at: targetPaneId,
                direction: layoutDirection, position: position
            )
            if sourceTabEmpty {
                store.removeTab(sourceTabId)
            }

        case .newTerminal:
            // Look up worktree/repo from the target pane.
            let targetPane = store.pane(targetPaneId)
            guard let worktreeId = targetPane?.worktreeId,
                  let repoId = targetPane?.repoId,
                  let worktree = store.worktree(worktreeId),
                  let repo = store.repo(repoId) else {
                executorLogger.warning("Cannot insert new terminal pane — target pane has no worktree/repo context")
                return
            }

            let pane = store.createPane(
                source: .worktree(worktreeId: worktreeId, repoId: repoId),
                provider: .zmx
            )

            // Create view — rollback if surface creation fails
            guard coordinator.createView(for: pane, worktree: worktree, repo: repo) != nil else {
                executorLogger.error("Surface creation failed for new pane — rolling back pane \(pane.id)")
                store.removePane(pane.id)
                return
            }

            store.insertPane(
                pane.id, inTab: targetTabId, at: targetPaneId,
                direction: layoutDirection, position: position
            )
        }
    }

    private func executeMergeTab(
        sourceTabId: UUID,
        targetTabId: UUID,
        targetPaneId: UUID,
        direction: SplitNewDirection
    ) {
        let layoutDirection = bridgeDirection(direction)
        let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after

        store.mergeTab(
            sourceId: sourceTabId,
            intoTarget: targetTabId,
            at: targetPaneId,
            direction: layoutDirection,
            position: position
        )
    }

    private func executeRepair(_ repairAction: RepairAction) {
        switch repairAction {
        case .recreateSurface(let paneId), .createMissingView(let paneId):
            guard let pane = store.pane(paneId) else {
                executorLogger.warning("repair \(String(describing: repairAction)): pane not in store")
                return
            }
            coordinator.teardownView(for: paneId)
            coordinator.createViewForContent(pane: pane)
            executorLogger.info("Repaired view for pane \(paneId)")

        case .reattachZmx, .markSessionFailed, .cleanupOrphan:
            // TODO: Phase 4 — implement remaining repair actions
            executorLogger.warning("repair: \(String(describing: repairAction)) — not yet implemented")
        }
    }

    /// Teardown views for all drawer panes owned by a parent pane.
    private func teardownDrawerPanes(for parentPaneId: UUID) {
        guard let pane = store.pane(parentPaneId),
              let drawer = pane.drawer else { return }
        for drawerPaneId in drawer.paneIds {
            coordinator.teardownView(for: drawerPaneId)
        }
    }

    /// Bridge SplitNewDirection → Layout.SplitDirection.
    private func bridgeDirection(_ direction: SplitNewDirection) -> Layout.SplitDirection {
        switch direction {
        case .left, .right: return .horizontal
        case .up, .down: return .vertical
        }
    }
}
