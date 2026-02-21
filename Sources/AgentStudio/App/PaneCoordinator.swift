import AppKit
import Foundation
import GhosttyKit
import os.log

// swiftlint:disable file_length type_body_length
private let paneCoordinatorLogger = Logger(subsystem: "com.agentstudio", category: "PaneCoordinator")

@MainActor
final class PaneCoordinator {
    struct SwitchArrangementTransitions: Equatable {
        let hiddenPaneIds: Set<UUID>
        let paneIdsToReattach: Set<UUID>
    }

    private let store: WorkspaceStore
    private let viewRegistry: ViewRegistry
    private let runtime: SessionRuntime
    private lazy var sessionConfig = SessionConfiguration.detect()
    private var cwdChangesTask: Task<Void, Never>?

    /// Unified undo stack — holds both tab and pane close entries, chronologically ordered.
    /// NOTE: Undo stack owned here (not in a store) because undo is fundamentally
    /// orchestration logic: it coordinates across WorkspaceStore, ViewRegistry, and
    /// SessionRuntime. Future: extract to UndoEngine when undo requirements grow.
    private(set) var undoStack: [WorkspaceStore.CloseEntry] = []

    /// Maximum undo stack entries before oldest are garbage-collected.
    private let maxUndoStackSize = 10

    init(store: WorkspaceStore, viewRegistry: ViewRegistry, runtime: SessionRuntime) {
        self.store = store
        self.viewRegistry = viewRegistry
        self.runtime = runtime
        subscribeToCWDChanges()
        setupPrePersistHook()
    }

    deinit {
        cwdChangesTask?.cancel()
    }

    // MARK: - CWD Propagation

    private func subscribeToCWDChanges() {
        cwdChangesTask = Task { @MainActor [weak self] in
            for await event in SurfaceManager.shared.surfaceCWDChanges {
                if Task.isCancelled { break }
                self?.onSurfaceCWDChanged(event)
            }
        }
    }

    private func onSurfaceCWDChanged(_ event: SurfaceManager.SurfaceCWDChangeEvent) {
        guard let paneId = event.paneId else { return }
        store.updatePaneCWD(paneId, cwd: event.cwd)
    }

    // MARK: - Webview State Sync

    private func setupPrePersistHook() {
        store.prePersistHook = { [weak self] in
            self?.syncWebviewStates()
        }
    }

    /// Sync runtime webview tab state back to persisted pane model.
    /// Uses syncPaneWebviewState (not updatePaneWebviewState) to avoid
    /// marking dirty during an in-flight persist, which would cause a save-loop.
    private func syncWebviewStates() {
        for (paneId, webviewView) in viewRegistry.allWebviewViews {
            store.syncPaneWebviewState(paneId, state: webviewView.currentState())
        }
    }

    // MARK: - Switch Arrangement Helpers

    static func computeSwitchArrangementTransitions(
        previousVisiblePaneIds: Set<UUID>,
        previouslyMinimizedPaneIds: Set<UUID>,
        newVisiblePaneIds: Set<UUID>
    ) -> PaneCoordinator.SwitchArrangementTransitions {
        let hiddenPaneIds = previousVisiblePaneIds.subtracting(newVisiblePaneIds)
        let revealedPaneIds = newVisiblePaneIds.subtracting(previousVisiblePaneIds)
        let unminimizedPaneIds = previouslyMinimizedPaneIds.intersection(newVisiblePaneIds)
        return SwitchArrangementTransitions(
            hiddenPaneIds: hiddenPaneIds,
            paneIdsToReattach: revealedPaneIds.union(unminimizedPaneIds)
        )
    }

    // MARK: - High-Level Operations

    /// Open a terminal for a worktree. Creates pane + tab + view.
    /// Returns the pane if a new one was created, nil if already open.
    @discardableResult
    func openTerminal(for worktree: Worktree, in repo: Repo) -> Pane? {
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

        guard createView(for: pane, worktree: worktree, repo: repo) != nil else {
            paneCoordinatorLogger.error(
                "Surface creation failed for worktree '\(worktree.name)' — rolling back pane \(pane.id)")
            store.removePane(pane.id)
            return nil
        }

        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        paneCoordinatorLogger.info("Opened terminal for worktree: \(worktree.name)")
        return pane
    }

    /// Open a new webview pane in a new tab. Loads about:blank with navigation bar visible.
    @discardableResult
    func openWebview(url: URL = URL(string: "about:blank")!) -> Pane? {
        let state = WebviewState(url: url, showNavigation: true)
        let host = url.host() ?? "New Tab"
        let pane = store.createPane(
            content: .webview(state),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: host), title: host)
        )

        guard createViewForContent(pane: pane) != nil else {
            paneCoordinatorLogger.error("Webview creation failed — rolling back pane \(pane.id)")
            store.removePane(pane.id)
            return nil
        }

        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        paneCoordinatorLogger.info("Opened webview pane \(pane.id)")
        return pane
    }

    /// Undo the last close operation (tab or pane).
    func undoCloseTab() {
        while let entry = undoStack.popLast() {
            switch entry {
            case .tab(let snapshot):
                undoTabClose(snapshot)
                return

            case .pane(let snapshot):
                guard store.tab(snapshot.tabId) != nil else {
                    paneCoordinatorLogger.info("undoClose: tab \(snapshot.tabId) gone — skipping pane entry")
                    continue
                }
                if snapshot.pane.isDrawerChild,
                    let parentId = snapshot.anchorPaneId,
                    store.pane(parentId) == nil
                {
                    paneCoordinatorLogger.info("undoClose: parent pane \(parentId) gone — skipping drawer child entry")
                    continue
                }
                undoPaneClose(snapshot)
                return
            }
        }
        paneCoordinatorLogger.info("No entries to restore from undo stack")
    }

    private func undoTabClose(_ snapshot: WorkspaceStore.TabCloseSnapshot) {
        store.restoreFromSnapshot(snapshot)
        var failedPaneIds: [UUID] = []

        // Restore views via lifecycle layer — iterate in reverse to match the LIFO
        // order of SurfaceManager's undo stack (panes were pushed in forward
        // order during close, so the last pane is on top of the stack).
        for pane in snapshot.panes.reversed() {
            let restored = restoreUndoPane(
                pane,
                worktree: nil,
                repo: nil,
                label: "Tab"
            )
            if !restored {
                failedPaneIds.append(pane.id)
            }
        }

        for paneId in failedPaneIds {
            paneCoordinatorLogger.warning(
                "undoTabClose: removing broken pane \(paneId) from tab \(snapshot.tab.id)"
            )
            teardownView(for: paneId)
        }

        store.setActiveTab(snapshot.tab.id)

        if !failedPaneIds.isEmpty {
            paneCoordinatorLogger.warning(
                "undoTabClose: tab \(snapshot.tab.id) restored with \(failedPaneIds.count) failed panes"
            )
        }
    }

    private func undoPaneClose(_ snapshot: WorkspaceStore.PaneCloseSnapshot) {
        store.restoreFromPaneSnapshot(snapshot)
        var failedPaneIds: [UUID] = []

        // Restore views for the pane and its drawer children.
        // Use the same restoration path as undoTabClose: attempt surface undo
        // via SurfaceManager to preserve scrollback, fall back to fresh creation.
        let allPanes = [snapshot.pane] + snapshot.drawerChildPanes
        for pane in allPanes.reversed() {
            guard viewRegistry.view(for: pane.id) == nil else { continue }
            let worktree = pane.worktreeId.flatMap(store.worktree)
            let repo = pane.repoId.flatMap { store.repo($0) }
            let restored = restoreUndoPane(
                pane,
                worktree: worktree,
                repo: repo,
                label: "Pane"
            )
            if !restored {
                failedPaneIds.append(pane.id)
            }
        }

        for paneId in failedPaneIds {
            paneCoordinatorLogger.warning(
                "undoPaneClose: removing broken pane \(paneId) in tab \(snapshot.tabId)"
            )
            teardownView(for: paneId)
        }

        store.setActiveTab(snapshot.tabId)
    }

    private func restoreUndoPane(
        _ pane: Pane,
        worktree: Worktree?,
        repo: Repo?,
        label: String
    ) -> Bool {
        switch pane.content {
        case .terminal:
            if let worktree, let repo {
                if restoreView(for: pane, worktree: worktree, repo: repo) != nil {
                    return true
                }
                paneCoordinatorLogger.error("Failed to restore terminal pane \(pane.id)")
            } else if createViewForContent(pane: pane) != nil {
                return true
            } else {
                paneCoordinatorLogger.error("Failed to recreate terminal pane \(pane.id)")
            }
            return false

        case .webview, .codeViewer, .bridgePanel:
            if createViewForContent(pane: pane) != nil {
                return true
            }
            paneCoordinatorLogger.error("Failed to recreate \(label.lowercased()) pane \(pane.id)")
            return false

        case .unsupported:
            paneCoordinatorLogger.warning("Cannot restore unsupported pane \(pane.id)")
            return true
        }
    }

    // MARK: - PaneAction Execution

    // swiftlint:disable cyclomatic_complexity function_body_length
    /// Execute a resolved PaneAction.
    func execute(_ action: PaneAction) {
        paneCoordinatorLogger.debug("Executing: \(String(describing: action))")

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
                reattachForViewSwitch(paneId: paneId)
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
            if store.minimizePane(paneId, inTab: tabId) {
                detachForViewSwitch(paneId: paneId)
            }

        case .expandPane(let tabId, let paneId):
            store.expandPane(paneId, inTab: tabId)
            reattachForViewSwitch(paneId: paneId)

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
            guard let tab = store.tab(tabId) else {
                paneCoordinatorLogger.warning("Cannot switch arrangement: tab \(tabId) not found")
                break
            }
            guard let arrangement = tab.arrangements.first(where: { $0.id == arrangementId }) else {
                paneCoordinatorLogger.warning(
                    "Cannot switch arrangement: arrangement \(arrangementId) not found in tab \(tabId)"
                )
                break
            }

            // Capture visible panes and minimized set BEFORE switching.
            // Minimized panes are detached but still in visiblePaneIds,
            // so we must track them separately for reattachment.
            let previousVisiblePaneIds: Set<UUID>
            let previouslyMinimizedPaneIds: Set<UUID>
            previousVisiblePaneIds = tab.activeArrangement.visiblePaneIds
            previouslyMinimizedPaneIds = tab.minimizedPaneIds

            // Switch arrangement in store (clears minimizedPaneIds)
            store.switchArrangement(to: arrangementId, inTab: tabId)

            // Get newly visible panes AFTER switching
            let newVisiblePaneIds = arrangement.visiblePaneIds

            let transitions = Self.computeSwitchArrangementTransitions(
                previousVisiblePaneIds: previousVisiblePaneIds,
                previouslyMinimizedPaneIds: previouslyMinimizedPaneIds,
                newVisiblePaneIds: newVisiblePaneIds
            )

            // Detach surfaces for panes that were visible but are now hidden
            for paneId in transitions.hiddenPaneIds {
                detachForViewSwitch(paneId: paneId)
            }

            // Reattach newly revealed panes, plus panes that were minimized in the
            // previous arrangement and remain visible after the switch.
            for paneId in transitions.paneIdsToReattach {
                reattachForViewSwitch(paneId: paneId)
            }

        case .renameArrangement(let tabId, let arrangementId, let name):
            store.renameArrangement(arrangementId, name: name, inTab: tabId)

        case .backgroundPane(let paneId):
            store.backgroundPane(paneId)

        case .reactivatePane(let paneId, let targetTabId, let targetPaneId, let direction):
            let layoutDirection = bridgeDirection(direction)
            let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after
            store.reactivatePane(
                paneId,
                inTab: targetTabId,
                at: targetPaneId,
                direction: layoutDirection,
                position: position
            )
            // After reactivation, ensure the pane has a view.
            // Backgrounded panes lose their view on restart (restoreAllViews skips them).
            if viewRegistry.view(for: paneId) == nil, let pane = store.pane(paneId) {
                createViewForContent(pane: pane)
            }

        case .purgeOrphanedPane(let paneId):
            // Only teardown if the pane is actually backgrounded — prevents destroying
            // views for live panes if this action is dispatched incorrectly.
            guard let pane = store.pane(paneId), pane.residency == .backgrounded else { break }
            teardownView(for: paneId)
            store.purgeOrphanedPane(paneId)

        case .addDrawerPane(let parentPaneId):
            if let drawerPane = store.addDrawerPane(to: parentPaneId) {
                if createViewForContent(pane: drawerPane) == nil {
                    paneCoordinatorLogger.warning(
                        "addDrawerPane: view creation failed for \(drawerPane.id) — panel will show placeholder")
                }
            }

        case .removeDrawerPane(let parentPaneId, let drawerPaneId):
            teardownView(for: drawerPaneId)
            store.removeDrawerPane(drawerPaneId, from: parentPaneId)

        case .toggleDrawer(let paneId):
            store.toggleDrawer(for: paneId)

        case .setActiveDrawerPane(let parentPaneId, let drawerPaneId):
            store.setActiveDrawerPane(drawerPaneId, in: parentPaneId)
            // Sync focus: drawer pane becomes the globally focused surface
            if let terminalView = viewRegistry.terminalView(for: drawerPaneId) {
                terminalView.window?.makeFirstResponder(terminalView)
                SurfaceManager.shared.syncFocus(activeSurfaceId: terminalView.surfaceId)
            }

        case .resizeDrawerPane(let parentPaneId, let splitId, let ratio):
            store.resizeDrawerPane(parentPaneId: parentPaneId, splitId: splitId, ratio: ratio)

        case .equalizeDrawerPanes(let parentPaneId):
            store.equalizeDrawerPanes(parentPaneId: parentPaneId)

        case .minimizeDrawerPane(let parentPaneId, let drawerPaneId):
            if store.minimizeDrawerPane(drawerPaneId, in: parentPaneId) {
                detachForViewSwitch(paneId: drawerPaneId)
            }

        case .expandDrawerPane(let parentPaneId, let drawerPaneId):
            store.expandDrawerPane(drawerPaneId, in: parentPaneId)
            reattachForViewSwitch(paneId: drawerPaneId)

        case .insertDrawerPane(let parentPaneId, let targetDrawerPaneId, let direction):
            executeInsertDrawerPane(
                parentPaneId: parentPaneId,
                targetDrawerPaneId: targetDrawerPaneId,
                direction: direction
            )

        case .expireUndoEntry(let paneId):
            // TODO: Phase 3 — remove pane from store, kill zmx, destroy surface
            paneCoordinatorLogger.warning("expireUndoEntry: \(paneId) — stub, full impl in Phase 3")

        case .repair(let repairAction):
            executeRepair(repairAction)
        }
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    // MARK: - Private Execution

    private func executeCloseTab(_ tabId: UUID) {
        // Sync live webview state back to the pane model before snapshotting,
        // so undo-close restores the actual page, not stale initial state.
        // Use the same sync path as persistence by delegating to the pre-persist hook
        // helper. This handles all registered webview views consistently.
        syncWebviewStates()

        // Snapshot for undo before closing
        if let snapshot = store.snapshotForClose(tabId: tabId) {
            undoStack.append(.tab(snapshot))
        }

        // Teardown views for all panes in this tab (including drawer panes).
        // Use tab.panes (all owned panes across arrangements), not tab.paneIds
        // (active arrangement only), to avoid leaking surfaces in non-active arrangements.
        if let tab = store.tab(tabId) {
            for paneId in tab.panes {
                teardownDrawerPanes(for: paneId)
                teardownView(for: paneId)
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

            // Collect all pane IDs currently owned (layout + drawer children)
            let allOwnedPaneIds = Set(
                store.tabs.flatMap { tab in
                    tab.panes.flatMap { paneId -> [UUID] in
                        var ids = [paneId]
                        if let drawer = store.pane(paneId)?.drawer {
                            ids.append(contentsOf: drawer.paneIds)
                        }
                        return ids
                    }
                })

            // Extract panes from the expired entry
            let expiredPanes: [Pane]
            switch expired {
            case .tab(let s): expiredPanes = s.panes
            case .pane(let s): expiredPanes = [s.pane] + s.drawerChildPanes
            }

            for pane in expiredPanes where !allOwnedPaneIds.contains(pane.id) {
                teardownView(for: pane.id)
                store.removePane(pane.id)
                paneCoordinatorLogger.debug("GC'd orphaned pane \(pane.id) from expired undo entry")
            }
        }
    }

    private func executeBreakUpTab(_ tabId: UUID) {
        let newTabs = store.breakUpTab(tabId)
        if newTabs.isEmpty {
            paneCoordinatorLogger.debug("breakUpTab: tab has single pane, no-op")
        }
    }

    private func executeClosePane(tabId: UUID, paneId: UUID) {
        // Check if this is the last pane — escalation rule:
        // closing the last pane escalates to tab close (only tab entry, no pane entry).
        if let tab = store.tab(tabId), tab.paneIds.count <= 1 {
            executeCloseTab(tabId)
            return
        }

        // Snapshot before teardown for pane-level undo
        if let snapshot = store.snapshotForPaneClose(paneId: paneId, inTab: tabId) {
            undoStack.append(.pane(snapshot))
        }

        // Capture drawer child IDs before any mutation — removePaneFromLayout may cascade
        // and remove the pane from the store, making drawer data inaccessible afterward.
        let drawerChildIds = store.pane(paneId)?.drawer?.paneIds ?? []

        // Teardown drawer panes first, then the pane itself
        teardownDrawerPanes(for: paneId)
        teardownView(for: paneId)
        let tabNowEmpty = store.removePaneFromLayout(paneId, inTab: tabId)

        if tabNowEmpty {
            // Shouldn't reach here due to escalation above, but handle defensively
            executeCloseTab(tabId)
            return
        }

        // Remove drawer children from store (using pre-captured IDs)
        for drawerPaneId in drawerChildIds {
            store.removePane(drawerPaneId)
        }

        // If the pane is no longer owned by any tab, remove it from the store.
        let allOwnedPaneIds = Set(store.tabs.flatMap(\.panes))
        if !allOwnedPaneIds.contains(paneId) {
            store.removePane(paneId)
        }

        // GC oldest undo entries
        expireOldUndoEntries()
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
                let repo = store.repo(repoId)
            else {
                paneCoordinatorLogger.warning(
                    "Cannot insert new terminal pane — target pane has no worktree/repo context")
                return
            }

            let pane = store.createPane(
                source: .worktree(worktreeId: worktreeId, repoId: repoId),
                provider: .zmx
            )

            guard createView(for: pane, worktree: worktree, repo: repo) != nil else {
                paneCoordinatorLogger.error("Surface creation failed for new pane — rolling back pane \(pane.id)")
                store.removePane(pane.id)
                return
            }

            store.insertPane(
                pane.id, inTab: targetTabId, at: targetPaneId,
                direction: layoutDirection, position: position
            )
        }
    }

    private func executeInsertDrawerPane(
        parentPaneId: UUID,
        targetDrawerPaneId: UUID,
        direction: SplitNewDirection
    ) {
        let layoutDirection = bridgeDirection(direction)
        let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after

        guard
            let drawerPane = store.insertDrawerPane(
                in: parentPaneId,
                at: targetDrawerPaneId,
                direction: layoutDirection,
                position: position
            )
        else { return }

        if createViewForContent(pane: drawerPane) == nil {
            paneCoordinatorLogger.warning("insertDrawerPane: view creation failed for \(drawerPane.id)")
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
                paneCoordinatorLogger.warning("repair \(String(describing: repairAction)): pane not in store")
                return
            }
            teardownView(for: paneId)
            createViewForContent(pane: pane)
            store.bumpViewRevision()
            paneCoordinatorLogger.info("Repaired view for pane \(paneId)")

        case .reattachZmx, .markSessionFailed, .cleanupOrphan:
            // TODO: Phase 4 — implement remaining repair actions
            paneCoordinatorLogger.warning("repair: \(String(describing: repairAction)) — not yet implemented")
        }
    }

    /// Teardown views for all drawer panes owned by a parent pane.
    private func teardownDrawerPanes(for parentPaneId: UUID) {
        guard let pane = store.pane(parentPaneId),
            let drawer = pane.drawer
        else { return }
        for drawerPaneId in drawer.paneIds {
            teardownView(for: drawerPaneId)
        }
    }

    /// Bridge SplitNewDirection → Layout.SplitDirection.
    private func bridgeDirection(_ direction: SplitNewDirection) -> Layout.SplitDirection {
        switch direction {
        case .left, .right: return .horizontal
        case .up, .down: return .vertical
        }
    }

    // MARK: - Create View (content-type dispatch)

    /// Create a view for any pane content type. Dispatches to the appropriate factory.
    /// Returns the created PaneView, or nil on failure.
    @discardableResult
    func createViewForContent(pane: Pane) -> PaneView? {
        switch pane.content {
        case .terminal:
            if let worktreeId = pane.worktreeId,
                let repoId = pane.repoId,
                let worktree = store.worktree(worktreeId),
                let repo = store.repo(repoId)
            {
                return createView(for: pane, worktree: worktree, repo: repo)

            } else if let parentPaneId = pane.parentPaneId,
                let parentPane = store.pane(parentPaneId),
                let worktreeId = parentPane.worktreeId,
                let repoId = parentPane.repoId,
                let worktree = store.worktree(worktreeId),
                let repo = store.repo(repoId)
            {
                return createView(for: pane, worktree: worktree, repo: repo)

            } else {
                return createFloatingTerminalView(for: pane)
            }

        case .webview(let state):
            let view = WebviewPaneView(paneId: pane.id, state: state)
            let paneId = pane.id
            view.controller.onTitleChange = { [weak self] title in
                self?.store.updatePaneTitle(paneId, title: title)
            }
            viewRegistry.register(view, for: pane.id)
            paneCoordinatorLogger.info("Created webview pane \(pane.id)")
            return view

        case .codeViewer(let state):
            let view = CodeViewerPaneView(paneId: pane.id, state: state)
            viewRegistry.register(view, for: pane.id)
            paneCoordinatorLogger.info("Created code viewer stub for pane \(pane.id)")
            return view

        case .bridgePanel(let state):
            let controller = BridgePaneController(paneId: pane.id, state: state)
            let view = BridgePaneView(paneId: pane.id, controller: controller)
            viewRegistry.register(view, for: pane.id)
            controller.loadApp()
            paneCoordinatorLogger.info("Created bridge panel view for pane \(pane.id)")
            return view

        case .unsupported:
            paneCoordinatorLogger.warning("Cannot create view for unsupported content type — pane \(pane.id)")
            return nil
        }
    }

    /// Create a terminal view for a pane, including surface and runtime setup.
    /// Registers the view in the ViewRegistry.
    @discardableResult
    func createView(
        for pane: Pane,
        worktree: Worktree,
        repo: Repo
    ) -> AgentStudioTerminalView? {
        let workingDir = worktree.path

        let shellCommand = "\(getDefaultShell()) -i -l"
        let startupStrategy: Ghostty.SurfaceStartupStrategy
        var environmentVariables: [String: String] = [:]
        switch pane.provider {
        case .zmx:
            if let zmxPath = sessionConfig.zmxPath {
                let attachCommand = buildZmxAttachCommand(
                    pane: pane,
                    worktree: worktree,
                    repo: repo,
                    zmxPath: zmxPath
                )
                // Start in shell mode and inject zmx attach after first sizing.
                startupStrategy = .deferredInShell(command: attachCommand)
                environmentVariables["ZMX_DIR"] = sessionConfig.zmxDir
            } else {
                paneCoordinatorLogger.error(
                    "zmx not found; using ephemeral session for \(pane.id) (state will not persist)"
                )
                startupStrategy = .surfaceCommand(shellCommand)
            }
        case .ghostty:
            startupStrategy = .surfaceCommand(shellCommand)
        case .none:
            paneCoordinatorLogger.error("Cannot create view for non-terminal pane \(pane.id)")
            return nil
        }

        let config = Ghostty.SurfaceConfiguration(
            workingDirectory: workingDir.path,
            startupStrategy: startupStrategy,
            environmentVariables: environmentVariables
        )

        let metadata = SurfaceMetadata(
            workingDirectory: workingDir,
            command: shellCommand,
            title: worktree.name,
            worktreeId: worktree.id,
            repoId: repo.id,
            paneId: pane.id
        )

        let result = SurfaceManager.shared.createSurface(config: config, metadata: metadata)

        switch result {
        case .success(let managed):
            RestoreTrace.log(
                "createView success pane=\(pane.id) surface=\(managed.id) initialSurfaceFrame=\(NSStringFromRect(managed.surface.frame))"
            )
            SurfaceManager.shared.attach(managed.id, to: pane.id)

            let view = AgentStudioTerminalView(
                worktree: worktree,
                repo: repo,
                restoredSurfaceId: managed.id,
                paneId: pane.id
            )
            view.displaySurface(managed.surface)

            viewRegistry.register(view, for: pane.id)
            runtime.markRunning(pane.id)
            RestoreTrace.log(
                "createView complete pane=\(pane.id) surface=\(managed.id) viewBounds=\(NSStringFromRect(view.bounds))"
            )

            paneCoordinatorLogger.info("Created view for pane \(pane.id) worktree: \(worktree.name)")
            return view

        case .failure(let error):
            RestoreTrace.log(
                "createSurface failure pane=\(pane.id) error=\(error.localizedDescription)"
            )
            paneCoordinatorLogger.error("Failed to create surface for pane \(pane.id): \(error.localizedDescription)")
            return nil
        }
    }

    /// Create a terminal view for a floating pane (drawers, standalone terminals).
    /// No worktree/repo context — uses home directory or pane's cwd.
    @discardableResult
    private func createFloatingTerminalView(for pane: Pane) -> AgentStudioTerminalView? {
        let workingDir = pane.metadata.cwd ?? FileManager.default.homeDirectoryForCurrentUser
        let cmd = "\(getDefaultShell()) -i -l"

        RestoreTrace.log(
            "createFloatingView pane=\(pane.id) cwd=\(workingDir.path) cmd=\(cmd)"
        )

        let config = Ghostty.SurfaceConfiguration(
            workingDirectory: workingDir.path,
            startupStrategy: .surfaceCommand(cmd)
        )

        let metadata = SurfaceMetadata(
            workingDirectory: workingDir,
            command: cmd,
            title: pane.metadata.title,
            paneId: pane.id
        )

        let result = SurfaceManager.shared.createSurface(config: config, metadata: metadata)

        switch result {
        case .success(let managed):
            RestoreTrace.log(
                "createFloatingSurface success pane=\(pane.id) surface=\(managed.id) initialSurfaceFrame=\(NSStringFromRect(managed.surface.frame))"
            )
            SurfaceManager.shared.attach(managed.id, to: pane.id)

            let view = AgentStudioTerminalView(
                restoredSurfaceId: managed.id,
                paneId: pane.id,
                title: pane.metadata.title
            )
            view.displaySurface(managed.surface)

            viewRegistry.register(view, for: pane.id)
            runtime.markRunning(pane.id)
            RestoreTrace.log("createFloatingView complete pane=\(pane.id) surface=\(managed.id)")

            paneCoordinatorLogger.info("Created floating terminal view for pane \(pane.id)")
            return view

        case .failure(let error):
            RestoreTrace.log(
                "createFloatingSurface failure pane=\(pane.id) error=\(error.localizedDescription)"
            )
            paneCoordinatorLogger.error(
                "Failed to create floating surface for pane \(pane.id): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Teardown View

    /// Teardown a view — detach surface (if terminal), unregister.
    func teardownView(for paneId: UUID) {
        if let terminal = viewRegistry.terminalView(for: paneId),
            let surfaceId = terminal.surfaceId
        {
            SurfaceManager.shared.detach(surfaceId, reason: .close)
        }

        if let bridgeView = viewRegistry.view(for: paneId) as? BridgePaneView {
            bridgeView.controller.teardown()
        }

        viewRegistry.unregister(paneId)

        paneCoordinatorLogger.debug("Tore down view for pane \(paneId)")
    }

    // MARK: - View Switch

    /// Detach a pane's surface for a view switch (hide, not destroy).
    func detachForViewSwitch(paneId: UUID) {
        if let terminal = viewRegistry.terminalView(for: paneId),
            let surfaceId = terminal.surfaceId
        {
            SurfaceManager.shared.detach(surfaceId, reason: .hide)
        }
        paneCoordinatorLogger.debug("Detached pane \(paneId) for view switch")
    }

    /// Reattach a pane's surface after a view switch.
    func reattachForViewSwitch(paneId: UUID) {
        if let terminal = viewRegistry.terminalView(for: paneId),
            let surfaceId = terminal.surfaceId
        {
            if let surfaceView = SurfaceManager.shared.attach(surfaceId, to: paneId) {
                terminal.displaySurface(surfaceView)
            }
        }
        paneCoordinatorLogger.debug("Reattached pane \(paneId) for view switch")
    }

    // MARK: - Undo Restore

    /// Restore a view from an undo close. Tries to reuse the undone surface; creates fresh if expired.
    @discardableResult
    func restoreView(
        for pane: Pane,
        worktree: Worktree,
        repo: Repo
    ) -> AgentStudioTerminalView? {
        if let undone = SurfaceManager.shared.undoClose() {
            if undone.metadata.paneId == pane.id {
                let view = AgentStudioTerminalView(
                    worktree: worktree,
                    repo: repo,
                    restoredSurfaceId: undone.id,
                    paneId: pane.id
                )
                SurfaceManager.shared.attach(undone.id, to: pane.id)
                view.displaySurface(undone.surface)
                viewRegistry.register(view, for: pane.id)
                runtime.markRunning(pane.id)
                paneCoordinatorLogger.info("Restored view from undo for pane \(pane.id)")
                return view
            } else {
                paneCoordinatorLogger.warning(
                    "Undo surface metadata mismatch: expected pane \(pane.id), got \(undone.metadata.paneId?.uuidString ?? "nil") — creating fresh"
                )
                SurfaceManager.shared.destroy(undone.id)
            }
        }

        paneCoordinatorLogger.info("Creating fresh view for pane \(pane.id)")
        return createView(for: pane, worktree: worktree, repo: repo)
    }

    // MARK: - Restore All Views

    /// Recreate views for all restored panes in all tabs, including drawer panes.
    /// Called once at launch after store.restore() populates persisted state.
    func restoreAllViews() {
        let paneIds = store.tabs.flatMap(\.panes)
        RestoreTrace.log(
            "restoreAllViews begin tabs=\(store.tabs.count) paneIds=\(paneIds.count) activeTab=\(store.activeTabId?.uuidString ?? "nil")"
        )
        guard !paneIds.isEmpty else {
            paneCoordinatorLogger.info("No panes to restore views for")
            RestoreTrace.log("restoreAllViews no panes")
            return
        }

        var restored = 0
        var drawerRestored = 0
        for paneId in paneIds {
            guard let pane = store.pane(paneId) else {
                paneCoordinatorLogger.warning("Skipping view restore for pane \(paneId) — not in store")
                RestoreTrace.log("restoreAllViews skip missing pane=\(paneId)")
                continue
            }
            RestoreTrace.log("restoreAllViews restoring pane=\(paneId) content=\(String(describing: pane.content))")
            if createViewForContent(pane: pane) != nil {
                restored += 1
            }

            if let drawer = pane.drawer {
                for drawerPaneId in drawer.paneIds {
                    guard let drawerPane = store.pane(drawerPaneId) else { continue }
                    RestoreTrace.log("restoreAllViews restoring drawer pane=\(drawerPaneId) parent=\(pane.id)")
                    if createViewForContent(pane: drawerPane) != nil {
                        drawerRestored += 1
                    }
                }
            }
        }
        paneCoordinatorLogger.info(
            "Restored \(restored)/\(paneIds.count) pane views, \(drawerRestored) drawer pane views")

        if let activeTab = store.activeTab,
            let activePaneId = activeTab.activePaneId,
            let terminalView = viewRegistry.terminalView(for: activePaneId)
        {
            SurfaceManager.shared.syncFocus(activeSurfaceId: terminalView.surfaceId)
            RestoreTrace.log(
                "restoreAllViews syncFocus activeTab=\(activeTab.id) activePane=\(activePaneId) activeSurface=\(terminalView.surfaceId?.uuidString ?? "nil")"
            )
        }
        RestoreTrace.log("restoreAllViews end restored=\(restored) drawerRestored=\(drawerRestored)")
    }

    // MARK: - Helpers

    private func buildZmxAttachCommand(pane: Pane, worktree: Worktree, repo: Repo, zmxPath: String) -> String {
        let zmxSessionName: String
        if let parentPaneId = pane.parentPaneId {
            zmxSessionName = ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: pane.id)
        } else {
            zmxSessionName = ZmxBackend.sessionId(
                repoStableKey: repo.stableKey,
                worktreeStableKey: worktree.stableKey,
                paneId: pane.id
            )
        }
        RestoreTrace.log(
            "buildZmxAttachCommand pane=\(pane.id) session=\(zmxSessionName) zmxPath=\(zmxPath) zmxDir=\(sessionConfig.zmxDir)"
        )
        return ZmxBackend.buildAttachCommand(
            zmxPath: zmxPath,
            sessionId: zmxSessionName,
            shell: getDefaultShell()
        )
    }

    private func getDefaultShell() -> String {
        SessionConfiguration.defaultShell()
    }
}
