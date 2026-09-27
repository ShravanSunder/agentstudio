import AgentStudioGit
import Foundation

package enum WorktreeOperationErrorMapper {
    package static func readFailure(_ error: GitDataPlaneError) -> WorktreeOperationFailure {
        WorktreeOperationFailure(failure: .readFailed(gitErrorKind(for: error)), leftovers: .notNeeded)
    }

    package static func createFailure(_ error: GitDataPlaneError) -> WorktreeOperationFailure {
        WorktreeOperationFailure(failure: .createFailed(gitErrorKind(for: error)), leftovers: .unverified)
    }

    package static func gitErrorKind(for error: GitDataPlaneError) -> WorktreeGitErrorKind {
        switch error {
        case .repositoryNotFound:
            .repositoryNotFound
        case .worktreeNotFound:
            .worktreeNotFound
        case .locked:
            .locked
        case .worktreeNotPrunable:
            .worktreeNotPrunable
        case .unsafeWorktreeRemoval:
            .unsafeWorktreeRemoval
        case .contentTooLarge:
            .contentTooLarge
        case .pathEscapesRepository:
            .pathEscapesRepository
        case .revisionUnavailable:
            .revisionUnavailable
        case .headUnavailable:
            .headUnavailable
        case .requiredObjectNotFound:
            .requiredObjectNotFound
        case .noSharedHistory:
            .noSharedHistory
        case .multipleBestMergeBases:
            .multipleBestMergeBases
        case .processFailed:
            .processFailed
        case .processTimedOut:
            .processTimedOut
        case .processCancelled:
            .processCancelled
        case .processOutputTooLarge:
            .processOutputTooLarge
        case .remoteRefTransactionIndeterminate:
            .remoteRefTransactionIndeterminate
        case .libgit2Failure:
            .libgit2Failure
        case .unsupported:
            .unsupported
        }
    }

    package static func forkRejection(
        _ reason: GitWorktreeForkRejectionReason,
        destinationPath: URL,
        branchName: String
    ) -> WorktreeOperationRefusal {
        switch reason {
        case .destinationExists:
            .destinationExists(destinationPath)
        case .destinationParentMissing:
            .destinationParentMissing(destinationPath.deletingLastPathComponent())
        case .invalidBranchName:
            .invalidBranchName(.rejectedByGit)
        case .branchAlreadyExists:
            .branchAlreadyExists(branchName)
        default:
            .forkUnavailable(reason)
        }
    }

    package static func forkFailure(_ error: GitWorktreeForkError) -> WorktreeOperationFailure {
        switch error {
        case .rejected:
            preconditionFailure("pre-mutation fork rejection must be mapped to a refusal")
        case .cleanupIncomplete(let primary, let residue):
            return WorktreeOperationFailure(
                failure: cleanupPrimaryFailureKind(primary),
                leftovers: .incomplete(residue.map(cleanupLeftover))
            )
        case .cancelled, .gitFailure, .sourceChanged, .entryFailed, .validationFailed:
            return WorktreeOperationFailure(failure: forkFailureKind(error), leftovers: .noLeftovers)
        }
    }

    package static func forkOutcome(
        _ error: GitWorktreeForkError,
        destinationPath: URL,
        branchName: String
    ) -> WorktreeOperationOutcome {
        switch error {
        case .rejected(let reason):
            .refused(forkRejection(reason, destinationPath: destinationPath, branchName: branchName))
        case .cancelled, .gitFailure, .sourceChanged, .entryFailed, .validationFailed, .cleanupIncomplete:
            .failed(forkFailure(error))
        }
    }

    private static func cleanupPrimaryFailureKind(_ error: GitWorktreeForkError) -> WorktreeFailureKind {
        switch error {
        case .rejected:
            // The pinned SDK runs preflight before entering its rollback catch, so a rejection cannot be
            // the primary error attached to a cleanup residue.
            preconditionFailure("a fork cleanup primary must follow the first mutation")
        case .cleanupIncomplete:
            // The SDK creates this case only around a leaf failure from execute, never recursively.
            preconditionFailure("agentstudio-git reports the primary failure directly, not recursively")
        case .cancelled, .gitFailure, .sourceChanged, .entryFailed, .validationFailed:
            forkFailureKind(error)
        }
    }

    private static func forkFailureKind(_ error: GitWorktreeForkError) -> WorktreeFailureKind {
        switch error {
        case .rejected:
            preconditionFailure("pre-mutation fork rejection is a refusal, not a failure")
        case .gitFailure(let gitError):
            .forkGitFailed(gitErrorKind(for: gitError))
        case .sourceChanged(let relativePath, let reason):
            .sourceChanged(relativePath: relativePath, reason: reason)
        case .entryFailed(let relativePath, let reason, let errorNumber):
            .entryFailed(relativePath: relativePath, reason: reason, errno: errorNumber)
        case .cancelled:
            .cancelled
        case .validationFailed(let reason, let relativePath):
            .validationFailed(reason: reason, relativePath: relativePath)
        case .cleanupIncomplete:
            preconditionFailure("cleanup residue is represented separately from the primary failure")
        }
    }

    private static func cleanupLeftover(_ residue: GitWorktreeForkResidue) -> WorktreeCleanupLeftover {
        let base: WorktreeLeftoverBase
        switch residue.kind {
        case .destinationContent:
            base = .destination
        case .linkedWorktreeAdministration, .nestedAdministration:
            base = .repositoryGitDirectory
        case .createdBranch:
            base = .branchReference
        case .temporaryArtifact:
            base = .temporary
        }
        return WorktreeCleanupLeftover(kind: residue.kind, location: residue.location, base: base)
    }
}
