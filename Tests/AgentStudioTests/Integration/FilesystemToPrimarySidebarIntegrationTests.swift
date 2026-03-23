import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct FilesystemToPrimarySidebarIntegrationTests {
    @Test("filesystem-to-primary-sidebar pipeline converges project-dev-shaped grouping and PR enrichment")
    func filesystemToPrimarySidebarPipelineConverges() async throws {
        let fixtureRoot = try makeProjectDevShapeFixture()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let discoveredRepoPaths = RepoScanner().scanForGitRepos(in: fixtureRoot, maxDepth: 4)
        assertScannerOutput(discoveredRepoPaths: discoveredRepoPaths, fixtureRoot: fixtureRoot)

        let financeRemote = "git@github.com:askluna/askluna-finance.git"
        let statusByRootPath = makeStatusByRootPath(root: fixtureRoot, financeRemote: financeRemote)
        let testSystem = makeIntegratedTestSystem(statusByRootPath: statusByRootPath)
        await withStartedIntegratedTestSystem(testSystem) {
            let intake = await registerDiscoveredRepos(
                discoveredRepoPaths: discoveredRepoPaths,
                workspaceStore: testSystem.workspaceStore,
                pipeline: testSystem.pipeline,
                statusByRootPath: statusByRootPath,
                financeRemote: financeRemote
            )

            let enrichmentConverged = await eventually("remote identity enrichment should converge for finance repos") {
                guard !intake.financeRepoIds.isEmpty else { return false }
                for repoId in intake.financeRepoIds {
                    guard
                        case .some(.resolvedRemote(_, _, let identity, _)) = testSystem.repoCache
                            .repoEnrichmentByRepoId[
                                repoId]
                    else {
                        return false
                    }
                    guard identity.groupKey == "remote:askluna/askluna-finance" else { return false }
                }
                return true
            }
            #expect(enrichmentConverged)

            let prCountsConverged = await eventually("forge PR counts should converge for known finance branches") {
                guard let primaryBranchId = intake.financeWorktreeIdByBranch["master"],
                    let transactionTableId = intake.financeWorktreeIdByBranch["transaction-table-3"],
                    let rlvrForkingId = intake.financeWorktreeIdByBranch["rlvr-forking"]
                else {
                    return false
                }
                return
                    testSystem.repoCache.pullRequestCountByWorktreeId[primaryBranchId] == 1
                    && testSystem.repoCache.pullRequestCountByWorktreeId[transactionTableId] == 2
                    && testSystem.repoCache.pullRequestCountByWorktreeId[rlvrForkingId] == 3
            }
            #expect(prCountsConverged)

            let sidebarRepos = testSystem.workspaceStore.repos.map(SidebarRepo.init(repo:))
            let metadataByRepoId = RepoSidebarContentView.buildRepoMetadata(
                repos: sidebarRepos,
                repoEnrichmentByRepoId: testSystem.repoCache.repoEnrichmentByRepoId
            )
            let groups = SidebarRepoGrouping.buildGroups(
                repos: sidebarRepos,
                metadataByRepoId: metadataByRepoId
            )

            let financeGroup = groups.first { $0.id == "remote:askluna/askluna-finance" }
            #expect(financeGroup != nil)
            #expect((financeGroup?.repos.count ?? 0) >= 3)

            // Branch labels should be sourced from enrichment/canonical branch data, not detached fallback.
            if let financeGroup {
                let allFinanceWorktrees = financeGroup.repos.flatMap(\.worktrees)
                let visibleBranchLabels = allFinanceWorktrees.map {
                    PaneDisplayProjector.resolvedBranchName(
                        worktree: $0,
                        enrichment: testSystem.repoCache.worktreeEnrichmentByWorktreeId[$0.id]
                    )
                }
                #expect(visibleBranchLabels.contains("master"))
                #expect(visibleBranchLabels.contains("transaction-table-3"))
                #expect(visibleBranchLabels.contains("rlvr-forking"))
            }

            // Search model should still find grouped finance checkouts.
            let filtered = SidebarFilter.filter(repos: sidebarRepos, query: "rlvr")
            #expect(!filtered.isEmpty)
        }
    }

    private struct IntegratedTestSystem {
        let bus: EventBus<RuntimeEnvelope>
        let workspaceStore: WorkspaceStore
        let repoCache: WorkspaceRepoCache
        let coordinator: WorkspaceCacheCoordinator
        let pipeline: FilesystemGitPipeline
    }

    private struct FinanceIntake {
        let financeRepoIds: [UUID]
        let financeWorktreeIdByBranch: [String: UUID]
    }

    private func makeIntegratedTestSystem(
        statusByRootPath: [String: GitWorkingTreeStatus]
    ) -> IntegratedTestSystem {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let pipeline = FilesystemGitPipeline(
            bus: bus,
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider.stub { rootPath in
                statusByRootPath[rootPath.standardizedFileURL.path]
                    ?? GitWorkingTreeStatus(
                        summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                        branch: "main",
                        origin: nil
                    )
            },
            forgeStatusProvider: StubForgeStatusProvider.stub { _, branches in
                var counts: [String: Int] = [:]
                for branch in branches {
                    switch branch {
                    case "master":
                        counts[branch] = 1
                    case "transaction-table-3":
                        counts[branch] = 2
                    case "rlvr-forking":
                        counts[branch] = 3
                    default:
                        counts[branch] = 1
                    }
                }
                return counts
            },
            gitCoalescingWindow: .zero
        )
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { [weak pipeline] scopeChange in
                guard let pipeline else { return }
                await pipeline.applyScopeChange(scopeChange)
            }
        )
        return IntegratedTestSystem(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            coordinator: coordinator,
            pipeline: pipeline
        )
    }

    private func registerDiscoveredRepos(
        discoveredRepoPaths: [URL],
        workspaceStore: WorkspaceStore,
        pipeline: FilesystemGitPipeline,
        statusByRootPath: [String: GitWorkingTreeStatus],
        financeRemote: String
    ) async -> FinanceIntake {
        var financeRepoIds: [UUID] = []
        var financeWorktreeIdByBranch: [String: UUID] = [:]

        for discoveredPath in discoveredRepoPaths {
            let repo = workspaceStore.addRepo(at: discoveredPath)
            guard let worktree = repo.worktrees.first else { continue }
            if statusByRootPath[discoveredPath.standardizedFileURL.path]?.origin == financeRemote {
                financeRepoIds.append(repo.id)
                if let branch = statusByRootPath[discoveredPath.standardizedFileURL.path]?.branch {
                    financeWorktreeIdByBranch[branch] = worktree.id
                }
            }
            await pipeline.register(
                worktreeId: worktree.id,
                repoId: repo.id,
                rootPath: discoveredPath
            )
        }

        return FinanceIntake(
            financeRepoIds: financeRepoIds,
            financeWorktreeIdByBranch: financeWorktreeIdByBranch
        )
    }

    private func assertScannerOutput(discoveredRepoPaths: [URL], fixtureRoot: URL) {
        let discoveredPathSet = Set(discoveredRepoPaths.map { $0.standardizedFileURL.path })
        #expect(!discoveredPathSet.contains(fixtureRoot.appending(path: "-worktrees").path))
        #expect(!discoveredPathSet.contains(fixtureRoot.appending(path: "agent-studio.window-system").path))
        #expect(
            discoveredPathSet.contains(fixtureRoot.appending(path: "askluna-project/askluna-finance").path))
        #expect(
            discoveredPathSet.contains(
                fixtureRoot.appending(path: "-worktrees/askluna-finance/rlvr-forking").path))
        #expect(
            discoveredPathSet.contains(
                fixtureRoot.appending(path: "-worktrees/askluna-finance/transaction-table-3").path))
    }

    private func makeWorkspaceStore() -> WorkspaceStore {
        let workspaceDir = FileManager.default.temporaryDirectory
            .appending(path: "filesystem-primary-sidebar-store-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: workspaceDir)
        persistor.ensureDirectory()
        return WorkspaceStore(persistor: persistor)
    }

    private func makeProjectDevShapeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "project-dev-shape-e2e-\(UUID().uuidString)")
        let fm = FileManager.default

        let repoPaths = [
            "-worktrees/askluna-finance/transaction-table-3",
            "-worktrees/askluna-finance/rlvr-forking",
            "askluna-project/askluna-finance",
            "askluna-project/askluna",
            "askluna-project/askluna-agent-design",
        ]

        for path in repoPaths {
            try initializeGitRepository(at: root.appending(path: path))
        }

        // Real-world stale worktree path shape: has a `.git` marker but is not a valid worktree.
        let invalidWorktreePath = root.appending(path: "agent-studio.window-system")
        try fm.createDirectory(at: invalidWorktreePath, withIntermediateDirectories: true)
        try "gitdir: /tmp/non-existent/.git/worktrees/agent-studio.window-system\n".write(
            to: invalidWorktreePath.appending(path: ".git"),
            atomically: true,
            encoding: .utf8
        )

        return root
    }

    private func initializeGitRepository(at path: URL) throws {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", path.path, "init"]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    private func makeStatusByRootPath(
        root: URL,
        financeRemote: String
    ) -> [String: GitWorkingTreeStatus] {
        func status(branch: String, origin: String) -> GitWorkingTreeStatus {
            GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                branch: branch,
                origin: origin
            )
        }

        return [
            root.appending(path: "askluna-project/askluna-finance").standardizedFileURL.path:
                status(branch: "master", origin: financeRemote),
            root.appending(path: "-worktrees/askluna-finance/transaction-table-3").standardizedFileURL.path:
                status(branch: "transaction-table-3", origin: financeRemote),
            root.appending(path: "-worktrees/askluna-finance/rlvr-forking").standardizedFileURL.path:
                status(branch: "rlvr-forking", origin: financeRemote),
            root.appending(path: "askluna-project/askluna").standardizedFileURL.path:
                status(branch: "main", origin: "git@github.com:askluna/askluna.git"),
            root.appending(path: "askluna-project/askluna-agent-design").standardizedFileURL.path:
                status(branch: "main", origin: "git@github.com:askluna/askluna-agent-design.git"),
        ]
    }

    private func eventually(
        _ description: String,
        maxTurns: Int = 200,
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        Issue.record("\(description) timed out")
        return false
    }

    private func withStartedIntegratedTestSystem(
        _ testSystem: IntegratedTestSystem,
        operation: @MainActor () async throws -> Void
    ) async rethrows {
        await testSystem.pipeline.start()
        testSystem.coordinator.startConsuming()
        do {
            try await operation()
            await testSystem.pipeline.shutdown()
            await testSystem.coordinator.shutdown()
            let busDrained = await eventually("filesystem-to-sidebar world should leave no subscribers behind") {
                await testSystem.bus.subscriberCount == 0
            }
            #expect(busDrained)
        } catch {
            await testSystem.pipeline.shutdown()
            await testSystem.coordinator.shutdown()
            throw error
        }
    }
}
