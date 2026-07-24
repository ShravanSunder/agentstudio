import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct AgentStudioGitStatusProviderIntegrationTests {
    @Test("real SDK provider matches shell provider for current status shape")
    func realSDKProviderMatchesShellProviderForCurrentStatusShape() async throws {
        let repoURL = try FilesystemTestGitRepo.create(named: "agentstudio-git-status-provider")
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repoURL)

        let shellProvider = ShellGitWorkingTreeStatusProvider(processExecutor: DefaultProcessExecutor(timeout: 5))
        let sdkProvider = makeSDKProvider()

        let shellStatus = try #require(await shellProvider.status(for: repoURL))
        let sdkStatus = try #require(await sdkProvider.status(for: repoURL))

        #expect(sdkStatus.branch == shellStatus.branch)
        #expect(sdkStatus.summary.changed == shellStatus.summary.changed)
        #expect(sdkStatus.summary.staged == shellStatus.summary.staged)
        #expect(sdkStatus.summary.untracked == shellStatus.summary.untracked)
        #expect(sdkStatus.summary.linesAdded == shellStatus.summary.linesAdded)
        #expect(sdkStatus.summary.linesDeleted == shellStatus.summary.linesDeleted)
        #expect(sdkStatus.summary.aheadCount == shellStatus.summary.aheadCount)
        #expect(sdkStatus.summary.behindCount == shellStatus.summary.behindCount)
        #expect(sdkStatus.summary.hasUpstream == shellStatus.summary.hasUpstream)
        #expect(sdkStatus.originResolution == shellStatus.originResolution)
    }

    @Test("real SDK provider matches shell provider for staged status shape")
    func realSDKProviderMatchesShellProviderForStagedStatusShape() async throws {
        let repoURL = try FilesystemTestGitRepo.create(named: "agentstudio-git-status-staged")
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        try "base\n".write(to: repoURL.appending(path: "staged.txt"), atomically: true, encoding: .utf8)
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["add", "staged.txt"])
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["commit", "-m", "Seed staged parity"])
        try "base\nstaged\n".write(to: repoURL.appending(path: "staged.txt"), atomically: true, encoding: .utf8)
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["add", "staged.txt"])
        try "loose\n".write(to: repoURL.appending(path: "loose.txt"), atomically: true, encoding: .utf8)

        try await assertSDKMatchesShell(repoURL)
    }

    @Test("real SDK provider matches shell provider for local origin and upstream sync states")
    func realSDKProviderMatchesShellProviderForLocalOriginAndUpstreamSyncStates() async throws {
        let repoURL = try FilesystemTestGitRepo.create(named: "agentstudio-git-status-upstream")
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        try "base\n".write(to: repoURL.appending(path: "tracked.txt"), atomically: true, encoding: .utf8)
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["add", "tracked.txt"])
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["commit", "-m", "Seed upstream parity"])
        let remoteURL = repoURL.deletingLastPathComponent().appending(path: "origin.git")
        defer { FilesystemTestGitRepo.destroy(remoteURL) }
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["init", "--bare", remoteURL.path])
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["remote", "add", "origin", remoteURL.path])
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["push", "-u", "origin", "main"])

        try await assertSDKMatchesShell(repoURL)

        try "ahead\n".write(to: repoURL.appending(path: "ahead.txt"), atomically: true, encoding: .utf8)
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["add", "ahead.txt"])
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["commit", "-m", "Local ahead"])

        try await assertSDKMatchesShell(repoURL)
    }

    @Test("real SDK provider returns nil for invalid worktree like shell provider")
    func realSDKProviderReturnsNilForInvalidWorktreeLikeShellProvider() async {
        let invalidURL = URL(fileURLWithPath: "/tmp/agentstudio-invalid-status-\(UUID().uuidString)")
        let shellProvider = ShellGitWorkingTreeStatusProvider(processExecutor: DefaultProcessExecutor(timeout: 5))
        let sdkProvider = makeSDKProvider()

        #expect(await shellProvider.status(for: invalidURL) == nil)
        #expect(await sdkProvider.status(for: invalidURL) == nil)
    }

    @Test("real SDK provider keeps unborn worktrees branchless instead of shell placeholder branch")
    func realSDKProviderKeepsUnbornWorktreesBranchlessInsteadOfShellPlaceholderBranch() async throws {
        let repoURL = try FilesystemTestGitRepo.create(named: "agentstudio-git-status-unborn")
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        let shellProvider = ShellGitWorkingTreeStatusProvider(processExecutor: DefaultProcessExecutor(timeout: 5))
        let sdkProvider = makeSDKProvider()

        let shellStatus = try #require(await shellProvider.status(for: repoURL))
        let sdkStatus = try #require(await sdkProvider.status(for: repoURL))

        #expect(shellStatus.branch != nil)
        #expect(sdkStatus.branch == nil)
        #expect(sdkStatus.summary.hasUpstream == nil)
    }

    private func assertSDKMatchesShell(_ repoURL: URL) async throws {
        let shellProvider = ShellGitWorkingTreeStatusProvider(processExecutor: DefaultProcessExecutor(timeout: 5))
        let sdkProvider = makeSDKProvider()

        let shellStatus = try #require(await shellProvider.status(for: repoURL))
        let sdkStatus = try #require(await sdkProvider.status(for: repoURL))

        #expect(sdkStatus.branch == shellStatus.branch)
        #expect(sdkStatus.summary.changed == shellStatus.summary.changed)
        #expect(sdkStatus.summary.staged == shellStatus.summary.staged)
        #expect(sdkStatus.summary.untracked == shellStatus.summary.untracked)
        #expect(sdkStatus.summary.linesAdded == shellStatus.summary.linesAdded)
        #expect(sdkStatus.summary.linesDeleted == shellStatus.summary.linesDeleted)
        #expect(sdkStatus.summary.aheadCount == shellStatus.summary.aheadCount)
        #expect(sdkStatus.summary.behindCount == shellStatus.summary.behindCount)
        #expect(sdkStatus.summary.hasUpstream == shellStatus.summary.hasUpstream)
        #expect(sdkStatus.originResolution == shellStatus.originResolution)
    }

    private func makeSDKProvider() -> AgentStudioGitWorkingTreeStatusProvider {
        AgentStudioGitWorkingTreeStatusProvider(
            timeoutScheduler: NonFiringStatusTimeoutScheduler()
        )
    }
}

private struct NonFiringStatusTimeoutScheduler: AgentStudioGitStatusTimeoutScheduler {
    func scheduleTimeout(
        after _: Duration,
        _: @escaping @Sendable () -> Void
    ) -> AgentStudioGitScheduledTimeout {
        AgentStudioGitScheduledTimeout(cancel: {})
    }
}
