import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct FilesystemActorShellGitIntegrationTests {
    @Test("shell git status provider reads tracked and untracked changes from tmp git repo")
    func shellGitStatusProviderReadsRealRepositoryState() async throws {
        let repoURL = try FilesystemTestGitRepo.create(named: "filesystem-actor-integration")
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repoURL)

        let provider = ShellGitStatusProvider(processExecutor: DefaultProcessExecutor(timeout: 5))
        let snapshot = try #require(await provider.status(for: repoURL))
        let summary = snapshot.summary

        #expect(snapshot.branch != nil)
        #expect(summary.changed >= 1)
        #expect(summary.untracked >= 1)
    }
}
