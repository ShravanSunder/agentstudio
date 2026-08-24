import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioRepoExplorer
@testable import AgentStudioTestSupport

@MainActor
@Suite("PrimarySidebarPipeline")
struct PrimarySidebarPipelineIntegrationTests {
    @Test("filesystem -> git -> forge -> cache converges for two repos sharing one remote identity")
    func twoReposWithSharedRemoteIdentityConverge() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let (forgeActor, coordinator, projector) = makePipelineActors(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache
        )

        await withStartedPipelineActors(
            bus: bus,
            coordinator: coordinator,
            projector: projector,
            forgeActor: forgeActor
        ) {
            let repoA = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/pipeline-repo-a"))
            let repoB = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/pipeline-repo-b"))
            guard let worktreeA = repoA.worktrees.first?.id,
                let worktreeB = repoB.worktrees.first?.id
            else {
                Issue.record("Expected each repository to have its primary worktree")
                return
            }
            let repoARefreshSubscription = await bus.subscribe(
                policy: .lossyNewest(BusSubscriberPolicy.standardLossyBufferLimit),
                subscriberName: "PrimarySidebarPipeline.repoARefresh"
            )
            let repoBRefreshSubscription = await bus.subscribe(
                policy: .lossyNewest(BusSubscriberPolicy.standardLossyBufferLimit),
                subscriberName: "PrimarySidebarPipeline.repoBRefresh"
            )
            let repoARefresh = Task<[String: PullRequestFacts]?, Never> {
                for await envelope in repoARefreshSubscription {
                    guard case .worktree(let worktreeEnvelope) = envelope,
                        case .forge(
                            .pullRequestRepositoryProjectionChanged(
                                let repoId,
                                .stable(.ready(let factsByBranch)),
                                _
                            )
                        ) = worktreeEnvelope.event,
                        repoId == repoA.id
                    else { continue }
                    return factsByBranch
                }
                return nil
            }
            let repoBRefresh = Task<[String: PullRequestFacts]?, Never> {
                for await envelope in repoBRefreshSubscription {
                    guard case .worktree(let worktreeEnvelope) = envelope,
                        case .forge(
                            .pullRequestRepositoryProjectionChanged(
                                let repoId,
                                .stable(.ready(let factsByBranch)),
                                _
                            )
                        ) = worktreeEnvelope.event,
                        repoId == repoB.id
                    else { continue }
                    return factsByBranch
                }
                return nil
            }

            await registerForgeWorktree(worktreeA, repository: repoA, forgeActor: forgeActor)
            await registerForgeWorktree(worktreeB, repository: repoB, forgeActor: forgeActor)
            await attendRepositoryFacts(
                worktreeIds: [worktreeA, worktreeB],
                activePaneWorktreeId: worktreeA,
                projector: projector
            )
            await forgeActor.setDemand(worktreeIds: [worktreeA, worktreeB])
            await postWorktreeRegistered(bus: bus, worktreeId: worktreeA, repoId: repoA.id, rootPath: repoA.repoPath)
            await postWorktreeRegistered(bus: bus, worktreeId: worktreeB, repoId: repoB.id, rootPath: repoB.repoPath)

            await postBranchChanged(bus: bus, worktreeId: worktreeA, repoId: repoA.id, from: "seed", to: "main")
            await postBranchChanged(bus: bus, worktreeId: worktreeB, repoId: repoB.id, from: "seed", to: "main")

            #expect(await repoARefresh.value?["main"]?.openCount == 1)
            #expect(await repoBRefresh.value?["main"]?.openCount == 1)

            let identityConverged = await eventually("repo identity should resolve for both repos") {
                guard case .some(.resolvedRemote(_, _, let identityA, _)) = repoCache.repoEnrichmentByRepoId[repoA.id]
                else {
                    return false
                }
                guard case .some(.resolvedRemote(_, _, let identityB, _)) = repoCache.repoEnrichmentByRepoId[repoB.id]
                else {
                    return false
                }
                return identityA.groupKey == "remote:askluna/agent-studio" && identityA.groupKey == identityB.groupKey
            }
            #expect(identityConverged)

            let pullRequestCountsConverged = await eventually("forge pull request counts should map to both worktrees")
            {
                repoCache.pullRequestFactsForTest(worktreeId: worktreeA)?.openCount == 1
                    && repoCache.pullRequestFactsForTest(worktreeId: worktreeB)?.openCount == 1
            }
            #expect(pullRequestCountsConverged)
        }
    }

    @Test("message-driven repo discovery seeds unresolved enrichment before origin resolves")
    func messageDrivenRepoDiscoverySeedsUnresolvedBeforeResolution() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let (forgeActor, coordinator, projector) = makePipelineActors(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache
        )

        await withStartedPipelineActors(
            bus: bus,
            coordinator: coordinator,
            projector: projector,
            forgeActor: forgeActor
        ) {
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
                return
            }

            await attendRepositoryFacts(
                worktreeIds: [worktreeId],
                activePaneWorktreeId: worktreeId,
                projector: projector
            )

            await postWorktreeRegistered(
                bus: bus,
                worktreeId: worktreeId,
                repoId: repo.id,
                rootPath: repoPath
            )

            let resolvedIdentity = await eventually(
                "worktree registration should converge unresolved to resolved identity"
            ) {
                guard
                    case .some(.resolvedRemote(_, let raw, let identity, _)) = repoCache.repoEnrichmentByRepoId[
                        repo.id]
                else {
                    return false
                }
                return raw.origin == "git@github.com:askluna/agent-studio.git"
                    && identity.groupKey == "remote:askluna/agent-studio"
            }
            #expect(resolvedIdentity)
        }
    }

    @Test("message-driven origin and branch events trigger one admitted repository refresh")
    func messageDrivenOriginAndBranchEventsTriggerOneAdmittedRefresh() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let callCounter = ForgeProviderCallCounter()
        let forgeActor = ForgeActor(
            bus: bus,
            statusProvider: .stub { _ in
                await callCounter.increment()
                return .complete([
                    ForgePullRequest(
                        headRefName: "main",
                        url: URL(string: "https://github.com/askluna/agent-studio/pull/1")!
                    )
                ])
            },
            providerName: "stub",
            monotonicNow: { .zero }
        )
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { change in
                switch change {
                case .registerForgeRepo(let repoId, let remote):
                    await forgeActor.setOrigin(repo: repoId, remote: remote)
                case .unregisterForgeRepo(let repoId):
                    await forgeActor.removeRepository(repo: repoId)
                case .refreshForgeRepo(let repoId, let correlationId):
                    await forgeActor.refresh(repo: repoId, correlationId: correlationId)
                case .updateWatchedFolders:
                    break
                }
            },
            enrichmentApplyTickCadence: .zero
        )

        await withStartedForgeScopeCoordinator(bus: bus, coordinator: coordinator, forgeActor: forgeActor) {
            let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/pipeline-forge-dedupe"))
            let worktreeId = UUID()
            await forgeActor.register(
                worktreeId: worktreeId,
                repoId: repo.id,
                rootPath: repo.repoPath
            )
            await forgeActor.setDemand(worktreeIds: [worktreeId])
            await postOriginChanged(
                bus: bus,
                repoId: repo.id,
                worktreeId: worktreeId,
                from: "",
                to: "git@github.com:askluna/agent-studio.git"
            )
            await postBranchChanged(bus: bus, worktreeId: worktreeId, repoId: repo.id, from: "seed", to: "main")

            let reachedExpectedCalls = await eventually(
                "forge provider should be invoked once after origin and branch resolve"
            ) {
                await callCounter.value() == 1
            }
            #expect(reachedExpectedCalls)
        }

        #expect(await callCounter.value() == 1)
    }

    @Test("origin change updates resolved identity grouping")
    func originChangeUpdatesResolvedIdentityGrouping() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
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

        let discoveredRepoPaths = await RepoScanner().scanForGitRepos(in: tempRoot, maxDepth: 4)
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
        let repoCache = RepoCacheAtom()
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

        await withStartedPipelineActors(
            bus: bus,
            coordinator: coordinator,
            projector: projector,
            forgeActor: forgeActor
        ) {
            var financeWorktreeIdByBranch: [String: UUID] = [:]
            var financeRepoIds: [UUID] = []
            var registeredWorktreeIds: Set<UUID> = []
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
                await forgeActor.register(
                    worktreeId: worktree.id,
                    repoId: repo.id,
                    rootPath: repoPath
                )
                registeredWorktreeIds.insert(worktree.id)
                await postWorktreeRegistered(bus: bus, worktreeId: worktree.id, repoId: repo.id, rootPath: repoPath)
            }
            await attendRepositoryFacts(worktreeIds: registeredWorktreeIds, projector: projector)
            await forgeActor.setDemand(worktreeIds: registeredWorktreeIds)

            let identityConverged = await eventually("all finance repos should share one remote group key") {
                guard !financeRepoIds.isEmpty else { return false }
                for repoId in financeRepoIds {
                    guard case .some(.resolvedRemote(_, _, let identity, _)) = repoCache.repoEnrichmentByRepoId[repoId]
                    else {
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
                    repoCache.pullRequestFactsForTest(worktreeId: primaryBranchId)?.openCount == 1
                    && repoCache.pullRequestFactsForTest(worktreeId: transactionTableId)?.openCount == 2
                    && repoCache.pullRequestFactsForTest(worktreeId: rlvrForkingId)?.openCount == 3
            }
            #expect(pullRequestCountsConverged)

            let sidebarRepos = makeRepoPresentationItems(repositories: workspaceStore.repos)
            let metadata = RepoExplorerView.buildRepoMetadata(
                repos: sidebarRepos,
                repoEnrichmentByRepoId: repoCache.repoEnrichmentByRepoId
            )
            let groups = RepoPresentationGrouping.buildGroups(
                repos: sidebarRepos,
                metadataByRepoId: metadata
            )
            let financeGroup = groups.first { $0.id == "remote:askluna/askluna-finance" }
            #expect(financeGroup != nil)
            #expect((financeGroup?.repos.count ?? 0) >= 3)
        }
    }

    private func makeRepoPresentationItems(repositories: [Repo]) -> [RepoPresentationItem] {
        repositories.map { repo in
            RepoPresentationItem(
                repo: repo,
                stableKey: repo.stableKey,
                worktreeStableKeysByID: Dictionary(
                    uniqueKeysWithValues: repo.worktrees.map { ($0.id, $0.stableKey) }
                )
            )
        }
    }

    private func attendRepositoryFacts(
        worktreeIds: Set<UUID>,
        activePaneWorktreeId: UUID? = nil,
        projector: GitWorkingDirectoryProjector
    ) async {
        await projector.setRepositoryFactAttention(
            activePaneWorktreeId: activePaneWorktreeId,
            sidebarAttendedWorktreeIds: worktreeIds,
            visibleActiveTabWorktreeIds: [],
            openWorktreeIds: worktreeIds
        )
    }

    private func registerForgeWorktree(
        _ worktreeId: UUID,
        repository: Repo,
        forgeActor: ForgeActor
    ) async {
        await forgeActor.register(
            worktreeId: worktreeId,
            repoId: repository.id,
            rootPath: repository.repoPath
        )
    }

    private func makeWorkspaceStore() -> WorkspaceStore {
        WorkspaceStore()
    }

    private func makePipelineActors(
        bus: EventBus<RuntimeEnvelope>,
        workspaceStore: WorkspaceStore,
        repoCache: RepoCacheAtom,
        gitStatusByRootPath: [String: GitWorkingTreeStatus]? = nil
    ) -> (ForgeActor, WorkspaceCacheCoordinator, GitWorkingDirectoryProjector) {
        let forgeActor = ForgeActor(
            bus: bus,
            statusProvider: .stub { _ in
                .complete([
                    ForgePullRequest(
                        headRefName: "main",
                        url: URL(string: "https://github.com/askluna/agent-studio/pull/1")!
                    ),
                    ForgePullRequest(
                        headRefName: "master",
                        url: URL(string: "https://github.com/askluna/askluna-finance/pull/1")!
                    ),
                    ForgePullRequest(
                        headRefName: "transaction-table-3",
                        url: URL(string: "https://github.com/askluna/askluna-finance/pull/2")!
                    ),
                    ForgePullRequest(
                        headRefName: "transaction-table-3",
                        url: URL(string: "https://github.com/askluna/askluna-finance/pull/3")!
                    ),
                    ForgePullRequest(
                        headRefName: "rlvr-forking",
                        url: URL(string: "https://github.com/askluna/askluna-finance/pull/4")!
                    ),
                    ForgePullRequest(
                        headRefName: "rlvr-forking",
                        url: URL(string: "https://github.com/askluna/askluna-finance/pull/5")!
                    ),
                    ForgePullRequest(
                        headRefName: "rlvr-forking",
                        url: URL(string: "https://github.com/askluna/askluna-finance/pull/6")!
                    ),
                ])
            },
            providerName: "stub",
            monotonicNow: { .zero }
        )
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { change in
                switch change {
                case .registerForgeRepo(let repoId, let remote):
                    await forgeActor.setOrigin(repo: repoId, remote: remote)
                case .unregisterForgeRepo(let repoId):
                    await forgeActor.removeRepository(repo: repoId)
                case .refreshForgeRepo(let repoId, let correlationId):
                    await forgeActor.refresh(repo: repoId, correlationId: correlationId)
                case .updateWatchedFolders:
                    break
                }
            },
            enrichmentApplyTickCadence: .zero
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
        maxTurns: Int = 100,
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

    private func withStartedPipelineActors(
        bus: EventBus<RuntimeEnvelope>,
        coordinator: WorkspaceCacheCoordinator,
        projector: GitWorkingDirectoryProjector,
        forgeActor: ForgeActor,
        operation: @MainActor () async throws -> Void
    ) async rethrows {
        await coordinator.startConsuming()
        await projector.start()
        await forgeActor.start()
        do {
            try await operation()
            await projector.shutdown()
            await forgeActor.shutdown()
            await coordinator.shutdown()
            let busDrained = await eventually("primary sidebar pipeline world should leave no subscribers behind") {
                await bus.subscriberCount == 0
            }
            #expect(busDrained)
        } catch {
            await projector.shutdown()
            await forgeActor.shutdown()
            await coordinator.shutdown()
            throw error
        }
    }

    private func withStartedForgeScopeCoordinator(
        bus: EventBus<RuntimeEnvelope>,
        coordinator: WorkspaceCacheCoordinator,
        forgeActor: ForgeActor,
        operation: @MainActor () async throws -> Void
    ) async rethrows {
        await coordinator.startConsuming()
        await forgeActor.start()
        do {
            try await operation()
            await forgeActor.shutdown()
            await coordinator.shutdown()
            let busDrained = await eventually("forge scope test world should leave no subscribers behind") {
                await bus.subscriberCount == 0
            }
            #expect(busDrained)
        } catch {
            await forgeActor.shutdown()
            await coordinator.shutdown()
            throw error
        }
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
