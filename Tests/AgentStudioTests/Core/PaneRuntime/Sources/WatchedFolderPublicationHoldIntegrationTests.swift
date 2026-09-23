import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

/// The hold is proven against the production scanner and real Git: a linked worktree
/// created under a hold must not publish from any scan, and must publish from the
/// first scan after release.
@Suite("Watched-folder publication hold")
struct WatchedFolderPublicationHoldIntegrationTests {
    @Test("a held linked worktree stays unpublished until the hold is released and the folder rescanned")
    func heldLinkedWorktreePublishesOnlyAfterRelease() async throws {
        // Arrange
        let fixture = try await PublicationHoldFixture.make()
        defer { fixture.remove() }
        let filesystem = FilesystemActor(
            bus: EventBus<RuntimeEnvelope>(),
            fseventStreamClient: ControllableFSEventStreamClient()
        )
        let watchedPath = WatchedPath(path: fixture.watchedRoot)
        let initialSummary = await filesystem.refreshWatchedFolders([watchedPath])
        #expect(
            initialSummary.repoPaths(in: fixture.watchedRoot).map(canonicalPath)
                == [canonicalPath(fixture.repositoryPath)])

        let holdID = await filesystem.holdWatchedFolderPublication(of: fixture.destination)
        try await FilesystemTestGitRepo.runGit(
            at: fixture.repositoryPath,
            args: ["worktree", "add", "-b", "feature/held", fixture.destination.path]
        )

        // Act
        let heldSummary = await filesystem.refreshWatchedFolders([watchedPath])
        let heldReceipts = await filesystem.currentWatchedFolderObservationReceipts()
        await filesystem.releaseWatchedFolderPublicationHold(holdID)
        let releasedSummary = await filesystem.refreshWatchedFolders([watchedPath])

        // Assert
        #expect(!linkedWorktreePaths(heldSummary, fixture: fixture).contains(canonicalPath(fixture.destination)))
        #expect(
            heldReceipts.flatMap(\.observation.entries).allSatisfy {
                canonicalPath($0.path) != canonicalPath(fixture.destination)
            })
        #expect(linkedWorktreePaths(releasedSummary, fixture: fixture) == [canonicalPath(fixture.destination)])

        await filesystem.shutdown()
    }

    private func linkedWorktreePaths(_ summary: WatchedFolderRefreshSummary, fixture: PublicationHoldFixture)
        -> [String]
    {
        summary.linkedWorktreePaths(in: fixture.watchedRoot).map(canonicalPath)
    }
}

/// Canonical path text; URL equality would also compare a trailing slash that
/// `URL(fileURLWithPath:)` adds only once the directory exists.
private func canonicalPath(_ url: URL) -> String {
    FilesystemRootOwnership.canonicalizeKernelPath(url.standardizedFileURL.path)
}

private struct PublicationHoldFixture {
    let watchedRoot: URL
    let repositoryPath: URL
    let destination: URL

    static func make() async throws -> Self {
        let watchedRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "tmp/worktree-publication-hold-tests/\(UUIDv7.generate().uuidString)")
            .standardizedFileURL
        let repositoryPath = watchedRoot.appending(path: "repo")
        try FileManager.default.createDirectory(at: repositoryPath, withIntermediateDirectories: true)
        for args in [
            ["init"], ["symbolic-ref", "HEAD", "refs/heads/main"],
            ["config", "user.email", "luna-tests@example.com"], ["config", "user.name", "Luna Tests"],
            ["config", "commit.gpgsign", "false"], ["commit", "--allow-empty", "-m", "Initial commit"],
        ] {
            try await FilesystemTestGitRepo.runGit(at: repositoryPath, args: args)
        }
        return Self(
            watchedRoot: watchedRoot,
            repositoryPath: repositoryPath,
            destination: watchedRoot.appending(path: "repo.feature-held")
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: watchedRoot)
    }
}
