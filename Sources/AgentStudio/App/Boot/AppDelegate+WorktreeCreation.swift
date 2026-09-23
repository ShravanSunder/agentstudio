import AgentStudioCore
import AppKit
import Foundation

/// Shell execution owner for New Worktree and Worktree Fork. Creation is a Git and
/// filesystem side effect on a source worktree, not a pane action, so it needs no
/// pane focus; topology still changes only through watched-folder discovery.
extension AppDelegate {
    func installWorktreeCreationCoordinator(publication: any WorktreePublicationHolding) {
        worktreeCreationCoordinator = WorktreeCreationCoordinator(
            topology: store.repositoryTopologyAtom,
            gitClient: LibGit2WorktreeCreationGitClient(),
            publication: publication,
            presentFailure: { [weak self] failure in
                self?.presentWorktreeCreationFailure(failure)
            }
        )
    }

    func canExecuteWorktreeCreation(
        _ command: AppCommand,
        sourceWorktreeId: UUID,
        targetType: SearchItemType
    ) -> Bool {
        // Worktree Fork execution lands with the SDK's forkWorktree; until then only the
        // clean checkout is executable.
        guard targetType == .worktree,
            case .cleanCheckout = WorktreeCreationKind(command: command),
            let worktreeCreationCoordinator
        else { return false }
        return worktreeCreationCoordinator.canCreate(fromWorktree: sourceWorktreeId)
    }

    func executeWorktreeCreation(_ request: WorktreeCreationRequest) -> AppCommandExecutionOutcome {
        guard
            canExecuteWorktreeCreation(
                request.kind.command,
                sourceWorktreeId: request.sourceWorktreeId,
                targetType: .worktree
            ),
            let worktreeCreationCoordinator
        else {
            return .unavailable(.featureUnavailable)
        }
        worktreeCreationCoordinator.create(request)
        return .accepted(operationId: nil)
    }

    /// Thin AppKit adapter over the pure `WorktreeCreationFailure.message` mapping: a
    /// sheet attached to the workspace window, never an app-modal alert.
    private func presentWorktreeCreationFailure(_ failure: WorktreeCreationFailure) {
        appLogger.warning("Worktree creation failed: \(String(describing: failure), privacy: .private)")
        guard let workspaceWindow = mainWindowController?.window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = failure.message.title
        alert.informativeText = failure.message.detail
        alert.beginSheetModal(for: workspaceWindow)
    }
}
