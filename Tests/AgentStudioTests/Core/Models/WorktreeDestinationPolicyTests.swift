import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("Worktree destination policy")
struct WorktreeDestinationPolicyTests {
    private static let watchedRoot = URL(filePath: "/Users/dev/project-dev", directoryHint: .isDirectory)
    private static let repositoryPath = watchedRoot.appending(path: "agent-studio", directoryHint: .isDirectory)

    struct BranchNameCase: Sendable, CustomTestStringConvertible {
        let text: String
        let expected: Result<String, WorktreeBranchNameRejection>
        var testDescription: String { "\"\(text)\"" }
    }

    @Test(
        "branch names follow the typed subset of git check-ref-format",
        arguments: [
            BranchNameCase(text: "feat/worktree-commands", expected: .success("feat/worktree-commands")),
            BranchNameCase(text: "fix-123", expected: .success("fix-123")),
            BranchNameCase(text: "", expected: .failure(.empty)),
            BranchNameCase(text: "has space", expected: .failure(.containsWhitespaceOrControlCharacter)),
            BranchNameCase(text: "a~b", expected: .failure(.containsForbiddenCharacter("~"))),
            BranchNameCase(text: "a:b", expected: .failure(.containsForbiddenCharacter(":"))),
            BranchNameCase(text: "a..b", expected: .failure(.containsForbiddenSequence(".."))),
            BranchNameCase(text: "a@{b", expected: .failure(.containsForbiddenSequence("@{"))),
            BranchNameCase(text: "a//b", expected: .failure(.containsForbiddenSequence("//"))),
            BranchNameCase(text: "-leading", expected: .failure(.invalidComponentBoundary)),
            BranchNameCase(text: "trailing/", expected: .failure(.invalidComponentBoundary)),
            BranchNameCase(text: "feat/.hidden", expected: .failure(.invalidComponentBoundary)),
            BranchNameCase(text: "name.lock", expected: .failure(.invalidComponentBoundary)),
            BranchNameCase(text: "@", expected: .failure(.invalidComponentBoundary)),
        ]
    )
    func branchNameValidation(_ testCase: BranchNameCase) {
        #expect(WorktreeBranchName.validated(testCase.text).map(\.rawValue) == testCase.expected)
    }

    @Test("an overlong branch name is rejected with the policy limit")
    func overlongBranchNameIsRejected() {
        let limit = AppPolicies.WorktreeCreation.maximumBranchNameLength
        let text = String(repeating: "a", count: limit + 1)

        #expect(WorktreeBranchName.validated(text).map(\.rawValue) == .failure(.tooLong(maximumLength: limit)))
    }

    struct SlugCase: Sendable, CustomTestStringConvertible {
        let branch: String
        let slug: String?
        var testDescription: String { "\(branch) -> \(slug ?? "nil")" }
    }

    @Test(
        "branch names map to folder-safe slugs",
        arguments: [
            SlugCase(branch: "feat/worktree-commands", slug: "feat-worktree-commands"),
            SlugCase(branch: "feature/a/b", slug: "feature-a-b"),
            SlugCase(branch: "release_1.2", slug: "release_1.2"),
            SlugCase(branch: "émoji-ünicode", slug: "moji-nicode"),
            SlugCase(branch: "日本", slug: nil),
        ]
    )
    func folderSlugs(_ testCase: SlugCase) throws {
        let branchName = try WorktreeBranchName.validated(testCase.branch).get()

        #expect(WorktreeDestinationPolicy.folderSlug(for: branchName) == testCase.slug)
    }

    @Test("the destination is a sibling of the main checkout inside the watched folder that discovers it")
    func destinationIsSiblingInsideWatchedFolder() throws {
        let watchedPath = WatchedPath(path: Self.watchedRoot)
        let branchName = try WorktreeBranchName.validated("feat/worktree-commands").get()

        let destination = try WorktreeDestinationPolicy.resolve(
            repositoryPath: Self.repositoryPath,
            branchName: branchName,
            watchedPaths: [watchedPath],
            pathExists: { _ in false }
        ).get()

        #expect(destination.path.path == "/Users/dev/project-dev/agent-studio.feat-worktree-commands")
        #expect(destination.watchedPath == watchedPath)
    }

    @Test("the deepest containing watched folder owns publication")
    func deepestWatchedFolderWins() throws {
        let outer = WatchedPath(path: URL(filePath: "/Users/dev", directoryHint: .isDirectory))
        let inner = WatchedPath(path: Self.watchedRoot)
        let branchName = try WorktreeBranchName.validated("topic").get()

        let destination = try WorktreeDestinationPolicy.resolve(
            repositoryPath: Self.repositoryPath,
            branchName: branchName,
            watchedPaths: [outer, inner],
            pathExists: { _ in false }
        ).get()

        #expect(destination.watchedPath == inner)
    }

    @Test("private tmp aliases resolve to the same watched folder")
    func privateTmpAliasIsContained() throws {
        let watchedPath = WatchedPath(path: URL(filePath: "/private/tmp/watch", directoryHint: .isDirectory))
        let branchName = try WorktreeBranchName.validated("topic").get()

        let destination = try WorktreeDestinationPolicy.resolve(
            repositoryPath: URL(filePath: "/tmp/watch/repo", directoryHint: .isDirectory),
            branchName: branchName,
            watchedPaths: [watchedPath],
            pathExists: { _ in false }
        ).get()

        #expect(destination.watchedPath == watchedPath)
    }

    @Test("a destination no watched folder discovers is rejected before creation")
    func undiscoverableDestinationIsRejected() throws {
        let branchName = try WorktreeBranchName.validated("topic").get()
        let unrelated = WatchedPath(path: URL(filePath: "/Users/elsewhere", directoryHint: .isDirectory))
        let hiddenParent = WatchedPath(path: URL(filePath: "/Users", directoryHint: .isDirectory))
        let expectedDestination = URL(filePath: "/Users/dev/.hidden/repo.topic", directoryHint: .isDirectory)

        let outside = WorktreeDestinationPolicy.resolve(
            repositoryPath: Self.repositoryPath,
            branchName: branchName,
            watchedPaths: [unrelated],
            pathExists: { _ in false }
        )
        let hidden = WorktreeDestinationPolicy.resolve(
            repositoryPath: URL(filePath: "/Users/dev/.hidden/repo", directoryHint: .isDirectory),
            branchName: branchName,
            watchedPaths: [hiddenParent],
            pathExists: { _ in false }
        )

        guard case .failure(.undiscoverableDestination) = outside else {
            Issue.record("expected an outside destination to be rejected, got \(outside)")
            return
        }
        #expect(hidden == .failure(.undiscoverableDestination(expectedDestination.standardizedFileURL)))
    }

    @Test("an existing destination is rejected as a collision")
    func existingDestinationIsRejected() throws {
        let branchName = try WorktreeBranchName.validated("topic").get()
        let expectedDestination = Self.watchedRoot.appending(path: "agent-studio.topic", directoryHint: .isDirectory)

        let result = WorktreeDestinationPolicy.resolve(
            repositoryPath: Self.repositoryPath,
            branchName: branchName,
            watchedPaths: [WatchedPath(path: Self.watchedRoot)],
            pathExists: { $0 == expectedDestination.standardizedFileURL }
        )

        #expect(result == .failure(.destinationExists(expectedDestination.standardizedFileURL)))
    }

    @Test("a branch with no folder-safe characters is rejected")
    func emptySlugIsRejected() throws {
        let branchName = try WorktreeBranchName.validated("日本").get()

        let result = WorktreeDestinationPolicy.resolve(
            repositoryPath: Self.repositoryPath,
            branchName: branchName,
            watchedPaths: [WatchedPath(path: Self.watchedRoot)],
            pathExists: { _ in false }
        )

        #expect(result == .failure(.emptyFolderSlug))
    }
}
