import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@Suite("Worktree creation failure messages")
struct WorktreeCreationFailureMessageTests {
    private static let destination = URL(filePath: "/Users/dev/project-dev/repo.topic", directoryHint: .isDirectory)

    struct MessageCase: Sendable, CustomTestStringConvertible {
        let failure: WorktreeCreationFailure
        let detail: String
        var testDescription: String { detail }
    }

    @Test(
        "each failure reads as one sentence under a single title",
        arguments: [
            MessageCase(
                failure: .sourceUnavailable, detail: "The repository or source worktree is no longer available."),
            MessageCase(
                failure: .noDefaultBranch,
                detail: "This repository has no origin/HEAD, local main, or local master branch."
            ),
            MessageCase(
                failure: .destinationRejected(.destinationExists(destination)),
                detail: "/Users/dev/project-dev/repo.topic already exists."
            ),
            MessageCase(
                failure: .destinationRejected(.undiscoverableDestination(destination)),
                detail:
                    "/Users/dev/project-dev/repo.topic is not inside a watched folder, so it would never appear in the sidebar."
            ),
            MessageCase(
                failure: .destinationRejected(.beyondScannerDepth(destination, maximumDepth: 4)),
                detail:
                    "/Users/dev/project-dev/repo.topic is more than 4 folders below its watched folder, so it would never appear in the sidebar."
            ),
            MessageCase(
                failure: .destinationRejected(.emptyFolderSlug),
                detail: "The branch name has no characters that can name a folder."
            ),
            MessageCase(
                failure: .gitFailure(.headUnavailable),
                detail: "The source worktree has no commit to branch from."
            ),
            MessageCase(
                failure: .gitFailure(
                    .libgit2Failure(code: -4, klass: 7, message: "a reference with that name already exists")),
                detail: "Git reported: a reference with that name already exists"
            ),
        ]
    )
    func failureMessages(_ testCase: MessageCase) {
        #expect(
            testCase.failure.message
                == WorktreeCreationFailureMessage(title: "Worktree not created", detail: testCase.detail))
    }

    @Test("a fork preflight rejection says nothing was changed")
    func forkRejectionSaysNothingChanged() {
        let message = WorktreeCreationFailure.forkFailure(.rejected(reason: .crossDevice)).message

        #expect(message.title == "Worktree Fork not created")
        #expect(message.detail == "Nothing was changed: the destination is on a different volume than the source.")
    }

    @Test("an incomplete fork cleanup lists what was left behind")
    func incompleteCleanupListsResidue() {
        let failure = WorktreeCreationFailure.forkFailure(
            .cleanupIncomplete(
                primary: .entryFailed(relativePath: "build/out", reason: .strictCloneFailed, errorNumber: 45),
                residue: [
                    GitWorktreeForkResidue(kind: .destinationContent, location: "build"),
                    GitWorktreeForkResidue(kind: .createdBranch, location: "refs/heads/fork/x"),
                ]
            ))

        #expect(
            failure.message.detail
                == "build/out could not be copied (strictCloneFailed). Cleanup is incomplete; left behind: "
                + "destinationContent build, createdBranch refs/heads/fork/x.")
    }

    @Test("every fork preflight reason has user-facing copy")
    func everyRejectionReasonHasCopy() {
        for reason in GitWorktreeForkRejectionReason.allCases {
            #expect(!WorktreeForkRejectionCopy.phrase(for: reason).isEmpty)
        }
    }
}
