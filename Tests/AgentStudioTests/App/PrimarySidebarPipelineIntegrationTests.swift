import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("PrimarySidebarPipeline")
struct PrimarySidebarPipelineIntegrationTests {
    @Test("filesystem -> git -> forge -> cache converges for two repos sharing one remote identity")
    func twoReposWithSharedRemoteIdentityConverge() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let forgeActor = ForgeActor(
            bus: bus,
            statusProvider: .stub { _, branches in
                var counts: [String: Int] = [:]
                for branch in branches {
                    counts[branch] = 1
                }
                return counts
            },
            providerName: "stub",
            pollInterval: .seconds(60)
        )
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            cacheStore: cacheStore,
            scopeSyncHandler: { change in
                switch change {
                case .registerForgeRepo(let repoId, let remote):
                    await forgeActor.register(repo: repoId, remote: remote)
                case .unregisterForgeRepo(let repoId):
                    await forgeActor.unregister(repo: repoId)
                case .refreshForgeRepo(let repoId, let correlationId):
                    await forgeActor.refresh(repo: repoId, correlationId: correlationId)
                }
            }
        )
        let projector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: .stub { _ in
                GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                    branch: "main",
                    origin: "git@github.com:askluna/agent-studio.git"
                )
            },
            coalescingWindow: .zero
        )

        coordinator.startConsuming()
        await projector.start()
        await forgeActor.start()
        defer { coordinator.stopConsuming() }

        let repoA = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/pipeline-repo-a"))
        let repoB = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/pipeline-repo-b"))
        let worktreeA = UUID()
        let worktreeB = UUID()

        _ = await bus.post(
            .system(
                SystemEnvelope.test(
                    event: .topology(
                        .worktreeRegistered(
                            worktreeId: worktreeA,
                            repoId: repoA.id,
                            rootPath: URL(fileURLWithPath: "/tmp/pipeline-repo-a")
                        )
                    ),
                    source: .builtin(.filesystemWatcher)
                )
            )
        )
        _ = await bus.post(
            .system(
                SystemEnvelope.test(
                    event: .topology(
                        .worktreeRegistered(
                            worktreeId: worktreeB,
                            repoId: repoB.id,
                            rootPath: URL(fileURLWithPath: "/tmp/pipeline-repo-b")
                        )
                    ),
                    source: .builtin(.filesystemWatcher)
                )
            )
        )

        _ = await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .branchChanged(
                            worktreeId: worktreeA,
                            repoId: repoA.id,
                            from: "seed",
                            to: "main"
                        )
                    ),
                    repoId: repoA.id,
                    worktreeId: worktreeA,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )
        _ = await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .branchChanged(
                            worktreeId: worktreeB,
                            repoId: repoB.id,
                            from: "seed",
                            to: "main"
                        )
                    ),
                    repoId: repoB.id,
                    worktreeId: worktreeB,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )

        let identityConverged = await eventually("repo identity should resolve for both repos") {
            guard case .some(.resolved(_, _, let identityA, _)) = cacheStore.repoEnrichmentByRepoId[repoA.id] else {
                return false
            }
            guard case .some(.resolved(_, _, let identityB, _)) = cacheStore.repoEnrichmentByRepoId[repoB.id] else {
                return false
            }
            return identityA.groupKey == "remote:askluna/agent-studio" && identityA.groupKey == identityB.groupKey
        }
        #expect(identityConverged)

        let pullRequestCountsConverged = await eventually("forge pull request counts should map to both worktrees") {
            cacheStore.pullRequestCountByWorktreeId[worktreeA] == 1
                && cacheStore.pullRequestCountByWorktreeId[worktreeB] == 1
        }
        #expect(pullRequestCountsConverged)

        await projector.shutdown()
        await forgeActor.shutdown()
    }

    @Test("origin change updates resolved identity grouping")
    func originChangeUpdatesResolvedIdentityGrouping() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/pipeline-origin-change"))

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .originChanged(repoId: repo.id, from: "", to: "git@github.com:org-a/repo.git")
                ),
                repoId: repo.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )
        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .originChanged(
                        repoId: repo.id,
                        from: "git@github.com:org-a/repo.git",
                        to: "git@github.com:org-b/repo.git"
                    )
                ),
                repoId: repo.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )

        guard case .some(.resolved(_, _, let identity, _)) = cacheStore.repoEnrichmentByRepoId[repo.id] else {
            Issue.record("Expected resolved enrichment")
            return
        }
        #expect(identity.groupKey == "remote:org-b/repo")
        #expect(identity.organizationName == "org-b")
    }

    private func makeWorkspaceStore() -> WorkspaceStore {
        let tempDir = FileManager.default.temporaryDirectory.appending(
            path: "primary-sidebar-pipeline-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        return WorkspaceStore(persistor: persistor)
    }

    private func eventually(
        _ description: String,
        maxAttempts: Int = 100,
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<maxAttempts {
            if await condition() {
                return true
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        Issue.record("\(description) timed out")
        return false
    }
}
