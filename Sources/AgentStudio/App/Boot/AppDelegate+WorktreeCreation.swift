import AgentStudioCore
import AppKit
import Foundation

/// Shell execution owner for From Default and Fork. Creation is a Git and
/// filesystem side effect on a repository, not a pane action, so it needs no
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
        targetId: UUID,
        targetType: SearchItemType
    ) -> Bool {
        guard let kind = WorktreeCreationKind(command: command), let worktreeCreationCoordinator else { return false }
        switch kind {
        case .fromDefault:
            return targetType == .repo && worktreeCreationCoordinator.canCreate(inRepository: targetId)
        case .fork:
            return targetType == .worktree && worktreeCreationCoordinator.canCreate(fromWorktree: targetId)
        }
    }

    func executeWorktreeCreation(_ request: WorktreeCreationRequest) -> AppCommandExecutionOutcome {
        guard
            canExecuteWorktreeCreation(
                request.kind.command,
                targetId: request.targetId,
                targetType: request.targetType
            ),
            let worktreeCreationCoordinator
        else {
            return .unavailable(.featureUnavailable)
        }
        // fire-and-forget: the coordinator retains the task until publication or failure and exposes waitUntilIdle.
        _ = worktreeCreationCoordinator.startCreation(request)
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
