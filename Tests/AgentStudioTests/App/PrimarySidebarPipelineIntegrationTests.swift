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
        let repoCache = WorkspaceRepoCache()
        let (forgeActor, coordinator, projector) = makePipelineActors(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache
        )

        coordinator.startConsuming()
        await projector.start()
        await forgeActor.start()
        defer { coordinator.stopConsuming() }

        let repoA = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/pipeline-repo-a"))
        let repoB = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/pipeline-repo-b"))
        let worktreeA = UUID()
        let worktreeB = UUID()

        await postWorktreeRegistered(bus: bus, worktreeId: worktreeA, repoId: repoA.id, rootPath: repoA.repoPath)
        await postWorktreeRegistered(bus: bus, worktreeId: worktreeB, repoId: repoB.id, rootPath: repoB.repoPath)

        await postBranchChanged(bus: bus, worktreeId: worktreeA, repoId: repoA.id, from: "seed", to: "main")
        await postBranchChanged(bus: bus, worktreeId: worktreeB, repoId: repoB.id, from: "seed", to: "main")

        let identityConverged = await eventually("repo identity should resolve for both repos") {
            guard case .some(.resolvedRemote(_, _, let identityA, _)) = repoCache.repoEnrichmentByRepoId[repoA.id] else {
                return false
            }
            guard case .some(.resolvedRemote(_, _, let identityB, _)) = repoCache.repoEnrichmentByRepoId[repoB.id] else {
                return false
            }
            return identityA.groupKey == "remote:askluna/agent-studio" && identityA.groupKey == identityB.groupKey
        }
        #expect(identityConverged)

        let pullRequestCountsConverged = await eventually("forge pull request counts should map to both worktrees") {
            repoCache.pullRequestCountByWorktreeId[worktreeA] == 1
                && repoCache.pullRequestCountByWorktreeId[worktreeB] == 1
        }
        #expect(pullRequestCountsConverged)

        await projector.shutdown()
        await forgeActor.shutdown()
    }

    @Test("message-driven repo discovery seeds unresolved enrichment before origin resolves")
    func messageDrivenRepoDiscoverySeedsUnresolvedBeforeResolution() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let (forgeActor, coordinator, projector) = makePipelineActors(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache
        )

        coordinator.startConsuming()
        await projector.start()
        await forgeActor.start()
        defer { coordinator.stopConsuming() }

        let repoPath = URL(fileURLWithPath: "/tmp/pipeline-discovered-\(UUID().uuidString)")
        await postRepoDiscovered(bus: bus, repoPath: repoPath)

        let unresolvedSeeded = await eventually("repo discovery should seed unresolved enrichment") {
            guard let repo = workspaceStore.repos.first(where: { $0.repoPath == repoPath }) else {
                return false
            }
            return repoCache.repoEnrichmentByRepoId[repo.id] == .awaitingOrigin(repoId: repo.id)
        }
        #expect(unresolvedSeeded)

        guard let repo = workspaceStore.repos.first(where: { $0.repoPath == repoPath }),
            let worktreeId = repo.worktrees.first?.id
        else {
            Issue.record("Expected discovered repo with a main worktree")
            await projector.shutdown()
            await forgeActor.shutdown()
            return
        }

        await postWorktreeRegistered(
            bus: bus,
            worktreeId: worktreeId,
            repoId: repo.id,
            rootPath: repoPath
        )

        let resolvedIdentity = await eventually("worktree registration should converge unresolved to resolved identity")
        {
            guard case .some(.resolvedRemote(_, let raw, let identity, _)) = repoCache.repoEnrichmentByRepoId[repo.id]
            else {
                return false
            }
            return raw.origin == "git@github.com:askluna/agent-studio.git"
                && identity.groupKey == "remote:askluna/agent-studio"
        }
        #expect(resolvedIdentity)

        await projector.shutdown()
        await forgeActor.shutdown()
    }

    @Test("message-driven origin and branch events trigger a single forge path per event")
    func messageDrivenOriginAndBranchEventsDoNotDoubleInvokeForge() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let callCounter = ForgeProviderCallCounter()
        let forgeActor = ForgeActor(
            bus: bus,
            statusProvider: .stub { _, branches in
                await callCounter.increment()
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
            repoCache: repoCache,
            scopeSyncHandler: { change in
                switch change {
                case .registerForgeRepo(let repoId, let remote):
                    await forgeActor.register(repo: repoId, remote: remote)
                case .unregisterForgeRepo(let repoId):
                    await forgeActor.unregister(repo: repoId)
                case .refreshForgeRepo(let repoId, let correlationId):
                    await forgeActor.refresh(repo: repoId, correlationId: correlationId)
                case .updateWatchedFolders:
                    break
                }
            }
        )

        coordinator.startConsuming()
        await forgeActor.start()
        defer { coordinator.stopConsuming() }

        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/pipeline-forge-dedupe"))
        let worktreeId = UUID()
        await postOriginChanged(
            bus: bus,
            repoId: repo.id,
            worktreeId: worktreeId,
            from: "",
            to: "git@github.com:askluna/agent-studio.git"
        )
        await postBranchChanged(bus: bus, worktreeId: worktreeId, repoId: repo.id, from: "seed", to: "main")

        let reachedExpectedCalls = await eventually("forge provider should be invoked for origin+branch once each") {
            await callCounter.value() >= 2
        }
        #expect(reachedExpectedCalls)

        try? await Task.sleep(for: .milliseconds(120))
        #expect(await callCounter.value() == 2)

        await forgeActor.shutdown()
    }

    @Test("origin change updates resolved identity grouping")
    func originChangeUpdatesResolvedIdentityGrouping() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
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

        guard case .some(.resolvedRemote(_, _, let identity, _)) = repoCache.repoEnrichmentByRepoId[repo.id] else {
            Issue.record("Expected resolved enrichment")
            return
        }
        #expect(identity.groupKey == "remote:org-b/repo")
        #expect(identity.organizationName == "org-b")
    }

    @Test("project-dev shape converges remote grouping and PR enrichment across sibling checkouts")
    func projectDevShapeConvergesGroupingAndPullRequestCounts() async throws {
        let tempRoot = try makeProjectDevShapeFixture()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let discoveredRepoPaths = RepoScanner().scanForGitRepos(in: tempRoot, maxDepth: 4)
        let discoveredPathSet = Set(discoveredRepoPaths.map(canonicalPath(_:)))

        #expect(discoveredPathSet.contains(canonicalPath(tempRoot.appending(path: "askluna-project/askluna-finance"))))
        #expect(
            discoveredPathSet.contains(
                canonicalPath(tempRoot.appending(path: "-worktrees/askluna-finance/transaction-table-3"))
            )
        )
        #expect(
            discoveredPathSet.contains(
                canonicalPath(tempRoot.appending(path: "-worktrees/askluna-finance/rlvr-forking"))
            )
        )
        #expect(!discoveredPathSet.contains(canonicalPath(tempRoot.appending(path: "-worktrees"))))

        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let financeRemote = "git@github.com:askluna/askluna-finance.git"
        let pathStatusByRootPath = makePathStatusByRootPath(
            root: tempRoot,
            financeRemote: financeRemote
        )

        let (forgeActor, coordinator, projector) = makePipelineActors(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            gitStatusByRootPath: pathStatusByRootPath
        )

        coordinator.startConsuming()
        await projector.start()
        await forgeActor.start()
        defer {
            coordinator.stopConsuming()
        }

        var financeWorktreeIdByBranch: [String: UUID] = [:]
        var financeRepoIds: [UUID] = []
        for repoPath in discoveredRepoPaths {
            let repo = workspaceStore.addRepo(at: repoPath)
            guard let worktree = repo.worktrees.first else { continue }
            let normalizedPath = repoPath.standardizedFileURL.path
            if pathStatusByRootPath[normalizedPath]?.origin == financeRemote {
                financeRepoIds.append(repo.id)
                if let branch = pathStatusByRootPath[normalizedPath]?.branch {
                    financeWorktreeIdByBranch[branch] = worktree.id
                }
            }
            await postWorktreeRegistered(bus: bus, worktreeId: worktree.id, repoId: repo.id, rootPath: repoPath)
        }

        let identityConverged = await eventually("all finance repos should share one remote group key") {
            guard !financeRepoIds.isEmpty else { return false }
            for repoId in financeRepoIds {
                guard case .some(.resolvedRemote(_, _, let identity, _)) = repoCache.repoEnrichmentByRepoId[repoId] else {
                    return false
                }
                guard identity.groupKey == "remote:askluna/askluna-finance" else { return false }
            }
            return true
        }
        #expect(identityConverged)

        let pullRequestCountsConverged = await eventually("finance branches should receive forge PR counts") {
            guard let primaryBranchId = financeWorktreeIdByBranch["master"],
                let transactionTableId = financeWorktreeIdByBranch["transaction-table-3"],
                let rlvrForkingId = financeWorktreeIdByBranch["rlvr-forking"]
            else {
                return false
            }
            return
                repoCache.pullRequestCountByWorktreeId[primaryBranchId] == 1
                && repoCache.pullRequestCountByWorktreeId[transactionTableId] == 2
                && repoCache.pullRequestCountByWorktreeId[rlvrForkingId] == 3
        }
        #expect(pullRequestCountsConverged)

        let sidebarRepos = workspaceStore.repos.map(SidebarRepo.init(repo:))
        let metadata = RepoSidebarContentView.buildRepoMetadata(
            repos: sidebarRepos,
            repoEnrichmentByRepoId: repoCache.repoEnrichmentByRepoId
        )
        let groups = SidebarRepoGrouping.buildGroups(
            repos: sidebarRepos,
            metadataByRepoId: metadata
        )
        let financeGroup = groups.first { $0.id == "remote:askluna/askluna-finance" }
        #expect(financeGroup != nil)
        #expect((financeGroup?.repos.count ?? 0) >= 3)

        await projector.shutdown()
        await forgeActor.shutdown()
    }

    private func makeWorkspaceStore() -> WorkspaceStore {
        let tempDir = FileManager.default.temporaryDirectory.appending(
            path: "primary-sidebar-pipeline-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        return WorkspaceStore(persistor: persistor)
    }

    private func makePipelineActors(
        bus: EventBus<RuntimeEnvelope>,
        workspaceStore: WorkspaceStore,
        repoCache: WorkspaceRepoCache,
        gitStatusByRootPath: [String: GitWorkingTreeStatus]? = nil
    ) -> (ForgeActor, WorkspaceCacheCoordinator, GitWorkingDirectoryProjector) {
        let forgeActor = ForgeActor(
            bus: bus,
            statusProvider: .stub { _, branches in
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
            providerName: "stub",
            pollInterval: .seconds(60)
        )
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { change in
                switch change {
                case .registerForgeRepo(let repoId, let remote):
                    await forgeActor.register(repo: repoId, remote: remote)
                case .unregisterForgeRepo(let repoId):
                    await forgeActor.unregister(repo: repoId)
                case .refreshForgeRepo(let repoId, let correlationId):
                    await forgeActor.refresh(repo: repoId, correlationId: correlationId)
                case .updateWatchedFolders:
                    break
                }
            }
        )
        let projector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: .stub { rootPath in
                if let gitStatusByRootPath {
                    return gitStatusByRootPath[rootPath.standardizedFileURL.path]
                }
                return GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                    branch: "main",
                    origin: "git@github.com:askluna/agent-studio.git"
                )
            },
            coalescingWindow: .zero
        )

        return (forgeActor, coordinator, projector)
    }

    private func makeProjectDevShapeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "project-dev-shape-\(UUID().uuidString)")

        let repoPaths = [
            "-worktrees/askluna-finance/transaction-table-3",
            "-worktrees/askluna-finance/rlvr-forking",
            "askluna-project/askluna-finance",
            "askluna-project/askluna",
        ]

        for path in repoPaths {
            try initializeGitRepository(at: root.appending(path: path))
        }

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

    private func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func makePathStatusByRootPath(
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
            root.appending(path: "-worktrees/askluna-finance/transaction-table-3").standardizedFileURL.path:
                status(branch: "transaction-table-3", origin: financeRemote),
            root.appending(path: "-worktrees/askluna-finance/rlvr-forking").standardizedFileURL.path:
                status(branch: "rlvr-forking", origin: financeRemote),
            root.appending(path: "askluna-project/askluna-finance").standardizedFileURL.path:
                status(branch: "master", origin: financeRemote),
            root.appending(path: "askluna-project/askluna").standardizedFileURL.path:
                status(branch: "main", origin: "git@github.com:askluna/askluna.git"),
        ]
    }

    private func postWorktreeRegistered(
        bus: EventBus<RuntimeEnvelope>,
        worktreeId: UUID,
        repoId: UUID,
        rootPath: URL
    ) async {
        _ = await bus.post(
            .system(
                SystemEnvelope.test(
                    event: .topology(
                        .worktreeRegistered(
                            worktreeId: worktreeId,
                            repoId: repoId,
                            rootPath: rootPath
                        )
                    ),
                    source: .builtin(.filesystemWatcher)
                )
            )
        )
    }

    private func postRepoDiscovered(
        bus: EventBus<RuntimeEnvelope>,
        repoPath: URL
    ) async {
        _ = await bus.post(
            .system(
                SystemEnvelope.test(
                    event: .topology(
                        .repoDiscovered(
                            repoPath: repoPath,
                            parentPath: repoPath.deletingLastPathComponent()
                        )
                    ),
                    source: .builtin(.filesystemWatcher)
                )
            )
        )
    }

    private func postBranchChanged(
        bus: EventBus<RuntimeEnvelope>,
        worktreeId: UUID,
        repoId: UUID,
        from: String,
        to: String
    ) async {
        _ = await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .branchChanged(
                            worktreeId: worktreeId,
                            repoId: repoId,
                            from: from,
                            to: to
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )
    }

    private func postOriginChanged(
        bus: EventBus<RuntimeEnvelope>,
        repoId: UUID,
        worktreeId: UUID,
        from: String,
        to: String
    ) async {
        _ = await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .originChanged(repoId: repoId, from: from, to: to)
                    ),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )
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

private actor ForgeProviderCallCounter {
    private var calls = 0

    func increment() {
        calls += 1
    }

    func value() -> Int {
        calls
    }
}
