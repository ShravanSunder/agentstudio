import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct FilesystemActorShellGitIntegrationTests {
    @Test("shell git status provider disables optional locks for every git subprocess")
    func shellGitWorkingTreeStatusProviderPassesOptionalLocksEnvironment() async throws {
        let executor = MockProcessExecutor()
        executor.enqueueSuccess("## main\n")
        executor.enqueueSuccess(" 1 file changed, 2 insertions(+), 1 deletion(-)")
        executor.enqueueSuccess("git@github.com:askluna/agent-studio.git")
        let provider = ShellGitWorkingTreeStatusProvider(processExecutor: executor)

        let snapshot = try #require(
            await provider.status(for: URL(fileURLWithPath: "/tmp/provider-env-\(UUID().uuidString)"))
        )

        #expect(snapshot.branch == "main")
        #expect(snapshot.summary.linesAdded == 2)
        #expect(snapshot.summary.linesDeleted == 1)
        #expect(executor.calls.count == 3)
        for call in executor.calls {
            #expect(call.environment?["GIT_OPTIONAL_LOCKS"] == "0")
        }
    }

    @Test("shell git status provider reads tracked and untracked changes from tmp git repo")
    func shellGitWorkingTreeStatusProviderReadsRealRepositoryState() async throws {
        let repoURL = try FilesystemTestGitRepo.create(named: "filesystem-actor-integration")
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repoURL)

        let provider = ShellGitWorkingTreeStatusProvider(processExecutor: DefaultProcessExecutor(timeout: 5))
        let snapshot = try #require(await provider.status(for: repoURL))
        let summary = snapshot.summary

        #expect(snapshot.branch != nil)
        #expect(summary.changed >= 1)
        #expect(summary.untracked >= 1)
        #expect(summary.linesAdded + summary.linesDeleted >= 1)
        #expect(summary.hasUpstream == false)
    }
}
