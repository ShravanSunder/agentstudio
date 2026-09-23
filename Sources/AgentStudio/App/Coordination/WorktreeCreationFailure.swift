import AgentStudioCore
import AgentStudioGit
import Foundation

/// Why a worktree was not created. Every case is shown to the user once, as a modal
/// alert; nothing here is retried.
enum WorktreeCreationFailure: Error, Equatable, Sendable {
    case sourceUnavailable
    case destinationRejected(WorktreeDestinationRejection)
    case alreadyInProgress(destination: URL)
    /// Worktree Fork execution lands with the SDK's `forkWorktree`.
    case forkUnavailable
    case gitFailure(GitDataPlaneError)
}

struct WorktreeCreationFailureMessage: Equatable, Sendable {
    let title: String
    let detail: String
}

extension WorktreeCreationFailure {
    var message: WorktreeCreationFailureMessage {
        WorktreeCreationFailureMessage(title: "Worktree not created", detail: detail)
    }

    private var detail: String {
        switch self {
        case .sourceUnavailable:
            "The source worktree is no longer available."
        case .destinationRejected(.emptyFolderSlug):
            "The branch name has no characters that can name a folder."
        case .destinationRejected(.undiscoverableDestination(let destination)):
            "\(destination.path) is not inside a watched folder, so it would never appear in the sidebar."
        case .destinationRejected(.destinationExists(let destination)):
            "\(destination.path) already exists."
        case .alreadyInProgress(let destination):
            "A worktree is already being created at \(destination.path)."
        case .forkUnavailable:
            "Worktree Fork is not available yet."
        case .gitFailure(let error):
            Self.gitFailureDetail(error)
        }
    }

    private static func gitFailureDetail(_ error: GitDataPlaneError) -> String {
        switch error {
        case .headUnavailable:
            "The source worktree has no commit to branch from."
        case .repositoryNotFound(let path):
            "No Git repository was found at \(path.path)."
        case .revisionUnavailable(let target):
            "The start commit \(target.name) could not be resolved."
        case .locked(let message):
            "The repository is locked: \(message)"
        case .libgit2Failure(_, _, let message):
            "Git reported: \(message)"
        case .unsupported(let message):
            message
        case .worktreeNotFound, .worktreeNotPrunable, .unsafeWorktreeRemoval, .contentTooLarge,
            .pathEscapesRepository, .requiredObjectNotFound, .noSharedHistory, .multipleBestMergeBases,
            .processFailed, .processTimedOut, .processCancelled, .processOutputTooLarge,
            .remoteRefTransactionIndeterminate:
            "Git could not create the worktree (\(error))."
        }
    }
}
