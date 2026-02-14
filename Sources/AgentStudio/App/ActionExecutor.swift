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
            provider: .tmux,
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

        case .resizePaneByDelta(let tabId, let paneId, let direction, let amount):
            store.resizePaneByDelta(tabId: tabId, paneId: paneId, direction: direction, amount: amount)

        case .mergeTab(let sourceTabId, let targetTabId, let targetPaneId, let direction):
            executeMergeTab(
                sourceTabId: sourceTabId,
                targetTabId: targetTabId,
                targetPaneId: targetPaneId,
                direction: direction
            )

        case .expireUndoEntry(let paneId):
            // TODO: Phase 3 — remove pane from store, kill tmux, destroy surface
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

        // Teardown views for all panes in this tab
        if let tab = store.tab(tabId) {
            for paneId in tab.paneIds {
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
            // Remove panes that are not referenced by any tab's ownership list.
            // Use tab.panes (all owned panes) instead of tab.paneIds (active arrangement only)
            // to avoid GC'ing panes hidden in non-default arrangements.
            let allLayoutPaneIds = Set(store.tabs.flatMap(\.panes))
            for pane in expired.panes where !allLayoutPaneIds.contains(pane.id) {
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
        // Single-pane tab: escalate to closeTab for proper undo snapshot.
        // Must delegate before any teardown so the snapshot captures full state.
        if let tab = store.tab(tabId), tab.paneIds.count <= 1 {
            executeCloseTab(tabId)
            return
        }

        coordinator.teardownView(for: paneId)
        let tabNowEmpty = store.removePaneFromLayout(paneId, inTab: tabId)

        // The store returns true only if the tab became empty.
        // This shouldn't happen since we checked paneIds.count > 1 above.
        assert(!tabNowEmpty, "Tab unexpectedly empty after closePane — escalation to closeTab should have caught this")
        if tabNowEmpty {
            store.removeTab(tabId)
        }

        // If the pane is no longer in any tab's ownership list, remove it from the store.
        // Use tab.panes (all owned panes) instead of tab.paneIds (active arrangement only).
        let allLayoutPaneIds = Set(store.tabs.flatMap(\.panes))
        if !allLayoutPaneIds.contains(paneId) {
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
                provider: .tmux
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
            guard let pane = store.pane(paneId),
                  let worktreeId = pane.worktreeId,
                  let repoId = pane.repoId,
                  let worktree = store.worktree(worktreeId),
                  let repo = store.repo(repoId) else {
                executorLogger.warning("repair \(String(describing: repairAction)): pane has no worktree/repo context")
                return
            }
            coordinator.teardownView(for: paneId)
            coordinator.createView(for: pane, worktree: worktree, repo: repo)
            executorLogger.info("Repaired view for pane \(paneId)")

        case .reattachTmux, .markSessionFailed, .cleanupOrphan:
            // TODO: Phase 4 — implement remaining repair actions
            executorLogger.warning("repair: \(String(describing: repairAction)) — not yet implemented")
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
