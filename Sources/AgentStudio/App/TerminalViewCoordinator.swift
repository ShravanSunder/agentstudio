import Foundation

@MainActor
final class TerminalViewCoordinator {
    let paneCoordinator: PaneCoordinator

    init(store: WorkspaceStore, viewRegistry: ViewRegistry, runtime: SessionRuntime) {
        paneCoordinator = PaneCoordinator(store: store, viewRegistry: viewRegistry, runtime: runtime)
    }

    // MARK: - Create View (content-type dispatch)

    /// Create a view for any pane content type. Dispatches to the appropriate factory.
    /// Returns the created PaneView, or nil on failure.
    @discardableResult
    func createViewForContent(pane: Pane) -> PaneView? {
        paneCoordinator.createViewForContent(pane: pane)
    }

    /// Create a terminal view for a pane, including surface and runtime setup.
    /// Registers the view in the ViewRegistry.
    @discardableResult
    func createView(for pane: Pane, worktree: Worktree, repo: Repo) -> AgentStudioTerminalView? {
        paneCoordinator.createView(for: pane, worktree: worktree, repo: repo)
    }

    /// Teardown a view — detach surface (if terminal), unregister.
    func teardownView(for paneId: UUID) {
        paneCoordinator.teardownView(for: paneId)
    }

    /// Detach a pane's surface for a view switch (hide, not destroy).
    func detachForViewSwitch(paneId: UUID) {
        paneCoordinator.detachForViewSwitch(paneId: paneId)
    }

    /// Reattach a pane's surface after a view switch.
    func reattachForViewSwitch(paneId: UUID) {
        paneCoordinator.reattachForViewSwitch(paneId: paneId)
    }

    /// Restore a view from an undo close. Tries to reuse the undone surface; creates fresh if expired.
    @discardableResult
    func restoreView(for pane: Pane, worktree: Worktree, repo: Repo) -> AgentStudioTerminalView? {
        paneCoordinator.restoreView(for: pane, worktree: worktree, repo: repo)
    }

    /// Recreate views for all restored panes in all tabs, including drawer panes.
    /// Called once at launch after store.restore() populates persisted state.
    func restoreAllViews() {
        paneCoordinator.restoreAllViews()
    }
}
