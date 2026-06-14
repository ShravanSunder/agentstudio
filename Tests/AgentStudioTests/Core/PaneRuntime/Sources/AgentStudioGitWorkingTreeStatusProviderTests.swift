import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct AgentStudioGitWorkingTreeStatusProviderTests {
    @Test("SDK status snapshot maps into AgentStudio working-tree status")
    func sdkStatusSnapshotMapsIntoAgentStudioWorkingTreeStatus() async throws {
        let provider = AgentStudioGitWorkingTreeStatusProvider(
            statusReader: { _, _ in
                makeSnapshot(
                    head: AgentStudioGit.GitHeadSnapshot(
                        kind: .branch,
                        oid: "abc123",
                        shortName: "feature/sdk"
                    ),
                    originResolution: .resolved(
                        AgentStudioGit.GitRemoteSnapshot(
                            name: "origin",
                            url: URL(string: "git@example.com:askluna/agent-studio.git")!,
                            rawURL: "git@example.com:askluna/agent-studio.git"
                        )
                    ),
                    summary: makeSummary(
                        stagedFileCount: 2,
                        unstagedFileCount: 3,
                        untrackedFileCount: 1,
                        linesAdded: 8,
                        linesDeleted: 4,
                        aheadCount: 1,
                        behindCount: 2,
                        hasUpstream: true
                    )
                )
            }
        )

        let status = try #require(await provider.status(for: URL(fileURLWithPath: "/tmp/repo")))

        #expect(status.branch == "feature/sdk")
        #expect(status.summary.changed == 3)
        #expect(status.summary.staged == 2)
        #expect(status.summary.untracked == 1)
        #expect(status.summary.linesAdded == 8)
        #expect(status.summary.linesDeleted == 4)
        #expect(status.summary.aheadCount == 1)
        #expect(status.summary.behindCount == 2)
        #expect(status.summary.hasUpstream == true)
        #expect(status.originResolution == .resolved("git@example.com:askluna/agent-studio.git"))
    }

    @Test("SDK origin states preserve AgentStudio origin-resolution semantics")
    func sdkOriginStatesPreserveAgentStudioOriginResolutionSemantics() async throws {
        let awaitingProvider = AgentStudioGitWorkingTreeStatusProvider(
            statusReader: { _, _ in makeSnapshot(originResolution: .awaitingResolution) }
        )
        let absentProvider = AgentStudioGitWorkingTreeStatusProvider(
            statusReader: { _, _ in makeSnapshot(originResolution: .confirmedAbsent) }
        )
        let credentialedRemoteProvider = AgentStudioGitWorkingTreeStatusProvider(
            statusReader: { _, _ in
                makeSnapshot(
                    originResolution: .resolved(
                        AgentStudioGit.GitRemoteSnapshot(
                            name: "origin",
                            url: URL(string: "https://example.com/org/repo.git")!,
                            rawURL: "https://example.com/org/repo.git"
                        )
                    )
                )
            }
        )

        let awaiting = try #require(await awaitingProvider.status(for: URL(fileURLWithPath: "/tmp/repo")))
        let absent = try #require(await absentProvider.status(for: URL(fileURLWithPath: "/tmp/repo")))
        let credentialed = try #require(
            await credentialedRemoteProvider.status(for: URL(fileURLWithPath: "/tmp/repo"))
        )

        #expect(awaiting.originResolution == .awaitingResolution)
        #expect(absent.originResolution == .confirmedAbsent)
        #expect(credentialed.originResolution == .resolved("https://example.com/org/repo.git"))
    }

    @Test("detached and unborn SDK heads map to branchless sync-unknown status")
    func detachedAndUnbornSDKHeadsMapToBranchlessSyncUnknownStatus() async throws {
        let detachedProvider = AgentStudioGitWorkingTreeStatusProvider(
            statusReader: { _, _ in
                makeSnapshot(
                    head: AgentStudioGit.GitHeadSnapshot(kind: .detached, oid: "abc123", shortName: nil),
                    summary: makeSummary(hasUpstream: false)
                )
            }
        )
        let unbornProvider = AgentStudioGitWorkingTreeStatusProvider(
            statusReader: { _, _ in
                makeSnapshot(
                    head: AgentStudioGit.GitHeadSnapshot(kind: .unborn, oid: nil, shortName: "main"),
                    summary: makeSummary(hasUpstream: false)
                )
            }
        )

        let detached = try #require(await detachedProvider.status(for: URL(fileURLWithPath: "/tmp/repo")))
        let unborn = try #require(await unbornProvider.status(for: URL(fileURLWithPath: "/tmp/repo")))

        #expect(detached.branch == nil)
        #expect(detached.summary.aheadCount == nil)
        #expect(detached.summary.behindCount == nil)
        #expect(detached.summary.hasUpstream == nil)
        #expect(unborn.branch == nil)
        #expect(unborn.summary.aheadCount == nil)
        #expect(unborn.summary.behindCount == nil)
        #expect(unborn.summary.hasUpstream == nil)
    }

    @Test("SDK status failure returns nil")
    func sdkStatusFailureReturnsNil() async {
        let provider = AgentStudioGitWorkingTreeStatusProvider(
            statusReader: { _, _ in throw AgentStudioGit.GitDataPlaneError.unsupported(message: "boom") }
        )

        let status = await provider.status(for: URL(fileURLWithPath: "/tmp/not-a-repo"))

        #expect(status == nil)
    }

    @Test("SDK status timeout returns nil")
    func sdkStatusTimeoutReturnsNil() async {
        let provider = AgentStudioGitWorkingTreeStatusProvider(timeout: .milliseconds(1)) { _, _ in
            try await Task.sleep(for: .seconds(60))
            return makeSnapshot()
        }

        let status = await provider.status(for: URL(fileURLWithPath: "/tmp/slow-repo"))

        #expect(status == nil)
    }

    @Test("real SDK provider matches shell provider for current status shape")
    func realSDKProviderMatchesShellProviderForCurrentStatusShape() async throws {
        let repoURL = try FilesystemTestGitRepo.create(named: "agentstudio-git-status-provider")
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repoURL)

        let shellProvider = ShellGitWorkingTreeStatusProvider(processExecutor: DefaultProcessExecutor(timeout: 5))
        let sdkProvider = AgentStudioGitWorkingTreeStatusProvider()

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
    func realSDKProviderReturnsNilForInvalidWorktreeLikeShellProvider() async throws {
        let invalidURL = URL(fileURLWithPath: "/tmp/agentstudio-invalid-status-\(UUID().uuidString)")
        let shellProvider = ShellGitWorkingTreeStatusProvider(processExecutor: DefaultProcessExecutor(timeout: 5))
        let sdkProvider = AgentStudioGitWorkingTreeStatusProvider()

        #expect(await shellProvider.status(for: invalidURL) == nil)
        #expect(await sdkProvider.status(for: invalidURL) == nil)
    }

    @Test("real SDK provider keeps unborn worktrees branchless instead of shell placeholder branch")
    func realSDKProviderKeepsUnbornWorktreesBranchlessInsteadOfShellPlaceholderBranch() async throws {
        let repoURL = try FilesystemTestGitRepo.create(named: "agentstudio-git-status-unborn")
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        let shellProvider = ShellGitWorkingTreeStatusProvider(processExecutor: DefaultProcessExecutor(timeout: 5))
        let sdkProvider = AgentStudioGitWorkingTreeStatusProvider()

        let shellStatus = try #require(await shellProvider.status(for: repoURL))
        let sdkStatus = try #require(await sdkProvider.status(for: repoURL))

        #expect(shellStatus.branch != nil)
        #expect(sdkStatus.branch == nil)
        #expect(sdkStatus.summary.hasUpstream == nil)
    }
}

private func assertSDKMatchesShell(_ repoURL: URL) async throws {
    let shellProvider = ShellGitWorkingTreeStatusProvider(processExecutor: DefaultProcessExecutor(timeout: 5))
    let sdkProvider = AgentStudioGitWorkingTreeStatusProvider()

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

private func makeSnapshot(
    head: AgentStudioGit.GitHeadSnapshot = AgentStudioGit.GitHeadSnapshot(
        kind: .branch,
        oid: "abc123",
        shortName: "main"
    ),
    originResolution: AgentStudioGit.GitOriginResolution = .confirmedAbsent,
    summary: AgentStudioGit.GitStatusSummary = makeSummary()
) -> AgentStudioGit.GitStatusSnapshot {
    AgentStudioGit.GitStatusSnapshot(
        repositoryRoot: URL(fileURLWithPath: "/tmp/repo"),
        worktreePath: URL(fileURLWithPath: "/tmp/repo"),
        generatedAtUnixMilliseconds: 1,
        head: head,
        originResolution: originResolution,
        summary: summary,
        entries: []
    )
}

private func makeSummary(
    changedFileCount: Int = 0,
    stagedFileCount: Int = 0,
    unstagedFileCount: Int = 0,
    untrackedFileCount: Int = 0,
    ignoredFileCount: Int = 0,
    linesAdded: Int = 0,
    linesDeleted: Int = 0,
    aheadCount: Int = 0,
    behindCount: Int = 0,
    hasUpstream: Bool = false
) -> AgentStudioGit.GitStatusSummary {
    AgentStudioGit.GitStatusSummary(
        changedFileCount: changedFileCount,
        stagedFileCount: stagedFileCount,
        unstagedFileCount: unstagedFileCount,
        untrackedFileCount: untrackedFileCount,
        ignoredFileCount: ignoredFileCount,
        linesAdded: linesAdded,
        linesDeleted: linesDeleted,
        aheadCount: aheadCount,
        behindCount: behindCount,
        hasUpstream: hasUpstream
    )
}
