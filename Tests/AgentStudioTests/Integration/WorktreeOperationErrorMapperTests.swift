import AgentStudioGit
import AgentStudioWorktreeOperations
import Foundation
import Testing

@Suite("Worktree operation SDK error mapping")
struct WorktreeOperationErrorMapperTests {
    @Test("all GitDataPlaneError cases project to a closed, redacted kind")
    func projectsEveryGitDataPlaneErrorCase() {
        let repositoryPath = URL(fileURLWithPath: "/tmp/worktree-error-mapping")
        let worktreeID = GitWorktreeID(rawValue: "repository|worktree:fixture")
        let processFailure = GitRemoteProcessFailure(
            executable: "git",
            redactedArguments: ["status"],
            exitCode: 1,
            redactedStderr: "private detail"
        )
        let errors: [(WorktreeGitErrorKind, GitDataPlaneError)] = [
            (.repositoryNotFound, .repositoryNotFound(path: repositoryPath)),
            (.worktreeNotFound, .worktreeNotFound(id: worktreeID)),
            (.locked, .locked(message: "private detail")),
            (.worktreeNotPrunable, .worktreeNotPrunable(id: worktreeID, reason: .liveWorktree)),
            (.unsafeWorktreeRemoval, .unsafeWorktreeRemoval(reason: .dirtyTrackedChanges)),
            (.contentTooLarge, .contentTooLarge(path: "large.bin", sizeBytes: 2, maxSizeBytes: 1)),
            (.pathEscapesRepository, .pathEscapesRepository(path: "../outside")),
            (.revisionUnavailable, .revisionUnavailable(target: GitRevisionTarget.named("missing-ref"))),
            (.headUnavailable, .headUnavailable),
            (.requiredObjectNotFound, .requiredObjectNotFound(oid: "missing-oid")),
            (.noSharedHistory, .noSharedHistory(targetOID: "target", headOID: "head")),
            (.multipleBestMergeBases, .multipleBestMergeBases(targetOID: "target", headOID: "head", count: 2)),
            (.processFailed, .processFailed(processFailure)),
            (.processTimedOut, .processTimedOut(processFailure)),
            (.processCancelled, .processCancelled(processFailure)),
            (.processOutputTooLarge, .processOutputTooLarge(stream: .stderr, sizeBytes: 2, maxSizeBytes: 1)),
            (.remoteRefTransactionIndeterminate, .remoteRefTransactionIndeterminate(message: "private detail")),
            (.libgit2Failure, .libgit2Failure(code: 1, klass: 2, message: "private detail")),
            (.unsupported, .unsupported(message: "private detail")),
        ]

        #expect(errors.count == 19)
        for (expectedKind, error) in errors {
            #expect(WorktreeOperationErrorMapper.gitErrorKind(for: error) == expectedKind)
        }
    }

    @Test("read and create errors report their distinct cleanup knowledge")
    func distinguishesReadAndCreateFailureLeftovers() {
        let gitError = GitDataPlaneError.libgit2Failure(code: 9, klass: 3, message: "private detail")

        #expect(
            WorktreeOperationErrorMapper.readFailure(gitError)
                == WorktreeOperationFailure(failure: .readFailed(.libgit2Failure), leftovers: .notNeeded))
        #expect(
            WorktreeOperationErrorMapper.createFailure(gitError)
                == WorktreeOperationFailure(failure: .createFailed(.libgit2Failure), leftovers: .unverified))
    }

    @Test("every typed fork rejection maps to its refusal without losing the SDK reason")
    func mapsEveryForkRejectionReason() {
        let destination = URL(fileURLWithPath: "/tmp/worktree-error-mapping/repo.feature")
        let parent = destination.deletingLastPathComponent()
        let branch = "feature/example"

        for reason in GitWorktreeForkRejectionReason.allCases {
            let expectedRefusal: WorktreeOperationRefusal
            switch reason {
            case .destinationExists:
                expectedRefusal = .destinationExists(destination)
            case .destinationParentMissing:
                expectedRefusal = .destinationParentMissing(parent)
            case .invalidBranchName:
                expectedRefusal = .invalidBranchName(.rejectedByGit)
            case .branchAlreadyExists:
                expectedRefusal = .branchAlreadyExists(branch)
            default:
                expectedRefusal = .forkUnavailable(reason)
            }

            #expect(
                WorktreeOperationErrorMapper.forkRejection(
                    reason,
                    destinationPath: destination,
                    branchName: branch
                ) == expectedRefusal)
            #expect(
                WorktreeOperationErrorMapper.forkOutcome(
                    .rejected(reason: reason),
                    destinationPath: destination,
                    branchName: branch
                ) == .refused(expectedRefusal))
        }
    }

    @Test("compensated fork failures say no leftovers and preserve typed details")
    func mapsCompensatedForkFailures() {
        let errors: [(GitWorktreeForkError, WorktreeFailureKind)] = [
            (.cancelled, .cancelled),
            (.gitFailure(.unsupported(message: "private detail")), .forkGitFailed(.unsupported)),
            (
                .sourceChanged(relativePath: "tracked.txt", reason: .entryIdentityChanged),
                .sourceChanged(relativePath: "tracked.txt", reason: .entryIdentityChanged)
            ),
            (
                .entryFailed(relativePath: "nested/file.txt", reason: .unreadableEntry, errorNumber: 13),
                .entryFailed(relativePath: "nested/file.txt", reason: .unreadableEntry, errno: 13)
            ),
            (
                .validationFailed(reason: .entryCountMismatch, relativePath: "nested"),
                .validationFailed(reason: .entryCountMismatch, relativePath: "nested")
            ),
        ]

        for (error, expectedFailure) in errors {
            #expect(
                WorktreeOperationErrorMapper.forkFailure(error)
                    == WorktreeOperationFailure(failure: expectedFailure, leftovers: .noLeftovers))
        }
    }

    @Test("cleanup residue kinds keep their relative base and primary failure")
    func mapsEveryCleanupResidueKind() {
        let residueLocations: [(GitWorktreeForkResidueKind, String, WorktreeLeftoverBase)] = [
            (.destinationContent, "nested/file.txt", .destination),
            (.linkedWorktreeAdministration, "worktrees/repo.feature", .repositoryGitDirectory),
            (.nestedAdministration, "modules/nested/worktrees/repo", .repositoryGitDirectory),
            (.createdBranch, "refs/heads/feature/example", .branchReference),
            (.temporaryArtifact, "worktrees/.temporary-artifact", .temporary),
        ]

        for (kind, location, base) in residueLocations {
            let residue = GitWorktreeForkResidue(kind: kind, location: location)
            let error = GitWorktreeForkError.cleanupIncomplete(primary: .cancelled, residue: [residue])
            #expect(
                WorktreeOperationErrorMapper.forkFailure(error)
                    == WorktreeOperationFailure(
                        failure: .cancelled,
                        leftovers: .incomplete([
                            WorktreeCleanupLeftover(kind: kind, location: location, base: base)
                        ])
                    ))
        }
    }
}
