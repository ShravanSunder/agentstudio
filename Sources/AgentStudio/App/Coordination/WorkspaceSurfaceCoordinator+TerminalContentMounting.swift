import AppKit
import Foundation

@MainActor
extension WorkspaceSurfaceCoordinator {
    /// Mount a terminal selected by a steady-state user action.
    ///
    /// Steady-state creation may enrich the terminal from current repository
    /// topology. Prepared startup activation uses the topology-independent
    /// sibling below instead.
    @discardableResult
    func mountCurrentTerminalContent(
        pane: Pane,
        initialFrame: NSRect? = nil,
        treatAsRestoredSessionStart: Bool = false
    ) -> NSView? {
        guard case .terminal = pane.content else {
            preconditionFailure("nonterminal pane entered the terminal content owner")
        }
        viewRegistry.ensureSlot(for: pane.id)
        registerPaneFilesystemContextIfNeeded(for: pane)

        if let worktreeID = pane.worktreeId,
            let repoID = pane.repoId,
            let worktree = store.repositoryTopologyAtom.worktree(worktreeID),
            let repo = store.repositoryTopologyAtom.repo(repoID)
        {
            return createView(
                for: pane,
                worktree: worktree,
                repo: repo,
                initialFrame: initialFrame,
                treatAsRestoredSessionStart: treatAsRestoredSessionStart
            )
        }

        if let parentPaneID = pane.parentPaneId,
            let parentPane = store.paneAtom.pane(parentPaneID),
            let worktreeID = parentPane.worktreeId,
            let repoID = parentPane.repoId,
            let worktree = store.repositoryTopologyAtom.worktree(worktreeID),
            let repo = store.repositoryTopologyAtom.repo(repoID)
        {
            return createView(
                for: pane,
                worktree: worktree,
                repo: repo,
                initialFrame: initialFrame,
                treatAsRestoredSessionStart: treatAsRestoredSessionStart
            )
        }

        return createTopologyIndependentTerminalView(
            for: pane,
            initialFrame: initialFrame,
            treatAsRestoredSessionStart: treatAsRestoredSessionStart
        )
    }

    /// Mount a terminal from accepted composition without consulting repository
    /// topology or canonical atoms for identity, launch, or content selection.
    @discardableResult
    func mountPreparedTerminalContent(
        pane: Pane,
        initialFrame: NSRect?
    ) -> NSView? {
        guard case .terminal = pane.content else {
            preconditionFailure("nonterminal pane entered prepared terminal activation")
        }
        viewRegistry.ensureSlot(for: pane.id)
        return createTopologyIndependentTerminalView(
            for: pane,
            initialFrame: initialFrame,
            treatAsRestoredSessionStart: true
        )
    }
}
