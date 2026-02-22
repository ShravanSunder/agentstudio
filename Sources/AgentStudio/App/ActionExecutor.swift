import Foundation

/// Executes validated PaneActions by delegating to `PaneCoordinator`.
/// This class remains the app-facing entry point and preserves historical action
/// API semantics while orchestration now lives in `PaneCoordinator`.
@MainActor
final class ActionExecutor {
    typealias SwitchArrangementTransitions = PaneCoordinator.SwitchArrangementTransitions

    private let coordinator: PaneCoordinator

    init(coordinator: PaneCoordinator) {
        self.coordinator = coordinator
    }

    static func computeSwitchArrangementTransitions(
        previousVisiblePaneIds: Set<UUID>,
        previouslyMinimizedPaneIds: Set<UUID>,
        newVisiblePaneIds: Set<UUID>
    ) -> SwitchArrangementTransitions {
        PaneCoordinator.computeSwitchArrangementTransitions(
            previousVisiblePaneIds: previousVisiblePaneIds,
            previouslyMinimizedPaneIds: previouslyMinimizedPaneIds,
            newVisiblePaneIds: newVisiblePaneIds
        )
    }

    var undoStack: [WorkspaceStore.CloseEntry] {
        coordinator.undoStack
    }

    // MARK: - High-Level Operations

    /// Open a terminal for a worktree. Creates pane + tab + view.
    /// Returns the pane if a new one was created, nil if already open.
    @discardableResult
    func openTerminal(for worktree: Worktree, in repo: Repo) -> Pane? {
        coordinator.openTerminal(for: worktree, in: repo)
    }

    /// Open a new terminal for a worktree, always creating a fresh pane+tab
    /// (never navigates to an existing one).
    @discardableResult
    func openNewTerminal(for worktree: Worktree, in repo: Repo) -> Pane? {
        coordinator.openNewTerminal(for: worktree, in: repo)
    }

    /// Open a new webview pane in a new tab. Loads about:blank with navigation bar visible.
    @discardableResult
    func openWebview(url: URL = URL(string: "about:blank")!) -> Pane? {
        coordinator.openWebview(url: url)
    }

    /// Undo the last close operation (tab or pane).
    func undoCloseTab() {
        coordinator.undoCloseTab()
    }

    /// Execute a resolved PaneAction.
    func execute(_ action: PaneAction) {
        coordinator.execute(action)
    }
}
