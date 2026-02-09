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

    init(store: WorkspaceStore, viewRegistry: ViewRegistry, coordinator: TerminalViewCoordinator) {
        self.store = store
        self.viewRegistry = viewRegistry
        self.coordinator = coordinator
    }

    // MARK: - High-Level Operations

    /// Open a terminal for a worktree. Creates session + tab + view.
    /// Returns the session if a new one was created, nil if already open.
    @discardableResult
    func openTerminal(for worktree: Worktree, in repo: Repo) -> TerminalSession? {
        // Check if worktree already has an active session in the current view
        if let existingTab = store.activeTabs.first(where: { tab in
            tab.sessionIds.contains { sessionId in
                store.session(sessionId)?.worktreeId == worktree.id
            }
        }) {
            store.setActiveTab(existingTab.id)
            return nil
        }

        // Create session
        let session = store.createSession(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            title: worktree.name,
            provider: .ghostty,
            lifetime: .persistent,
            residency: .active
        )

        // Create tab with single session
        let tab = Tab(sessionId: session.id)
        store.appendTab(tab)

        // Create view via coordinator
        coordinator.createView(for: session, worktree: worktree, repo: repo)

        // Select the new tab
        store.setActiveTab(tab.id)

        executorLogger.info("Opened terminal for worktree: \(worktree.name)")
        return session
    }

    /// Undo the last close operation.
    func undoCloseTab() {
        guard let snapshot = undoStack.popLast() else {
            executorLogger.info("No tabs to restore from undo stack")
            return
        }

        // Restore tab + sessions in store
        store.restoreFromSnapshot(snapshot)

        // Restore views via coordinator
        for session in snapshot.sessions {
            guard let worktreeId = session.worktreeId,
                  let repoId = session.repoId,
                  let worktree = store.worktree(worktreeId),
                  let repo = store.repo(repoId) else {
                executorLogger.warning("Could not find worktree/repo for session \(session.id)")
                continue
            }
            coordinator.restoreView(for: session, worktree: worktree, repo: repo)
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
            executeClosePane(tabId: tabId, sessionId: paneId)

        case .extractPaneToTab(let tabId, let paneId):
            _ = store.extractSession(paneId, fromTab: tabId)

        case .focusPane(let tabId, let paneId):
            store.setActiveSession(paneId, inTab: tabId)

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

        case .mergeTab(let sourceTabId, let targetTabId, let targetPaneId, let direction):
            executeMergeTab(
                sourceTabId: sourceTabId,
                targetTabId: targetTabId,
                targetPaneId: targetPaneId,
                direction: direction
            )

        case .expireUndoEntry(let sessionId):
            // Phase 3: remove session from store, kill tmux, destroy surface
            executorLogger.debug("expireUndoEntry: \(sessionId) — stub, full impl in Phase 3")

        case .repair(let repairAction):
            // Phase 4: route repair actions to TerminalViewCoordinator
            executorLogger.debug("repair: \(String(describing: repairAction)) — stub, full impl in Phase 4")
        }
    }

    // MARK: - Private Execution

    private func executeCloseTab(_ tabId: UUID) {
        // Snapshot for undo before closing
        if let snapshot = store.snapshotForClose(tabId: tabId) {
            undoStack.append(snapshot)
        }

        // Teardown views for all sessions in this tab
        if let tab = store.tab(tabId) {
            for sessionId in tab.sessionIds {
                coordinator.teardownView(for: sessionId)
            }
        }

        store.removeTab(tabId)
    }

    private func executeBreakUpTab(_ tabId: UUID) {
        let newTabs = store.breakUpTab(tabId)
        if newTabs.isEmpty {
            executorLogger.debug("breakUpTab: tab has single session, no-op")
        }
    }

    private func executeClosePane(tabId: UUID, sessionId: UUID) {
        coordinator.teardownView(for: sessionId)
        store.removeSessionFromLayout(sessionId, inTab: tabId)
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
            // This handles both same-tab reposition and cross-tab moves.
            store.removeSessionFromLayout(paneId, inTab: sourceTabId)
            store.insertSession(
                paneId, inTab: targetTabId, at: targetPaneId,
                direction: layoutDirection, position: position
            )

        case .newTerminal:
            // Look up worktree/repo from the target session
            let targetSession = store.session(targetPaneId)
            let worktreeId = targetSession?.worktreeId
            let repoId = targetSession?.repoId

            let source: TerminalSource
            if let wId = worktreeId, let rId = repoId {
                source = .worktree(worktreeId: wId, repoId: rId)
            } else {
                source = .floating(workingDirectory: nil, title: nil)
            }

            // Create a new session and insert it
            let session = store.createSession(source: source)

            // Create view if worktree/repo are available
            if let wId = worktreeId, let rId = repoId,
               let worktree = store.worktree(wId),
               let repo = store.repo(rId) {
                coordinator.createView(for: session, worktree: worktree, repo: repo)
            }

            store.insertSession(
                session.id, inTab: targetTabId, at: targetPaneId,
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

    /// Bridge SplitNewDirection → Layout.SplitDirection.
    private func bridgeDirection(_ direction: SplitNewDirection) -> Layout.SplitDirection {
        switch direction {
        case .left, .right: return .horizontal
        case .up, .down: return .vertical
        }
    }
}
