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
            MessageCase(failure: .sourceUnavailable, detail: "The source worktree is no longer available."),
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
            MessageCase(failure: .forkUnavailable, detail: "Worktree Fork is not available yet."),
        ]
    )
    func failureMessages(_ testCase: MessageCase) {
        #expect(
            testCase.failure.message
                == WorktreeCreationFailureMessage(title: "Worktree not created", detail: testCase.detail))
    }
}
