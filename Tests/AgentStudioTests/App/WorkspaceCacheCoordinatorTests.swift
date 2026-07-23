import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
final class WorkspaceCacheCoordinatorTests {

    private func makeWorkspaceStore() -> WorkspaceStore {
        WorkspaceStore()
    }

    private func makeCoordinator(
        workspaceStore: WorkspaceStore,
        repoCache: RepoCacheAtom,
        welcomeAtom: WelcomeAtom
    ) -> WorkspaceCacheCoordinator {
        WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            welcomeAtom: welcomeAtom,
            scopeSyncHandler: { _ in }
        )
    }

    @Test
    func topology_repoDiscovered_addsRepoToWorkspaceStore() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = makeCoordinator(
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            welcomeAtom: WelcomeAtom()
        )

        let repoPath = URL(fileURLWithPath: "/tmp/luna-repo")
        let envelope = SystemEnvelope.test(
            event: .topology(.repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent()))
        )

        coordinator.handleTopology(envelope)

        guard let repo = workspaceStore.repos.first(where: { $0.repoPath == repoPath }) else {
            Issue.record("Expected discovered repo to be added")
            return
        }
        #expect(repoCache.repoEnrichmentByRepoId[repo.id] == .awaitingOrigin(repoId: repo.id))
    }

    @Test
    func topology_worktreeRegistered_unknownRepo_isIgnored() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = makeCoordinator(
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            welcomeAtom: WelcomeAtom()
        )

        let repoCountBefore = workspaceStore.repos.count
        let envelope = SystemEnvelope.test(
            event: .topology(
                .worktreeRegistered(
                    worktreeId: UUID(),
                    repoId: UUID(),
                    rootPath: URL(fileURLWithPath: "/tmp/unknown-repo")
                )
            )
        )

        coordinator.handleTopology(envelope)

        #expect(workspaceStore.repos.count == repoCountBefore)
    }

    @Test
    func topology_repoDiscovered_duplicatePath_doesNotDuplicateRepo() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = makeCoordinator(
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            welcomeAtom: WelcomeAtom()
        )

        let repoPath = URL(fileURLWithPath: "/tmp/luna-duplicate-repo")
        let envelope = SystemEnvelope.test(
            event: .topology(.repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent()))
        )

        coordinator.handleTopology(envelope)
        coordinator.handleTopology(envelope)

        #expect(workspaceStore.repos.count == 1)
    }

    @Test("rejected discovered topology preserves live state and emits no effects")
    func rejectedDiscoveredTopologyPreservesLiveStateAndEmitsNoEffects() throws {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let firstRepoPath = URL(fileURLWithPath: "/tmp/luna-reconcile-rejection-first")
        let secondRepoPath = URL(fileURLWithPath: "/tmp/luna-reconcile-rejection-second")
        let firstRepo = workspaceStore.addRepo(at: firstRepoPath)
        _ = workspaceStore.addRepo(at: secondRepoPath)
        let firstWorktree = try #require(workspaceStore.repositoryTopologyAtom.repo(firstRepo.id)?.worktrees.single)
        let pane = workspaceStore.createPane(
            launchDirectory: firstRepoPath,
            facets: .init(repoId: firstRepo.id, worktreeId: firstWorktree.id, cwd: firstRepoPath)
        )
        workspaceStore.appendTab(Tab(paneId: pane.id))
        workspaceStore.markRepoUnavailable(firstRepo.id)
        _ = workspaceStore.orphanPanesForRepo(firstRepo.id)
        repoCache.setRepoEnrichment(.awaitingOrigin(repoId: firstRepo.id))
        let effectRecorder = RejectedReconciliationTopologyEffectRecorder()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            welcomeAtom: WelcomeAtom(),
            topologyEffectHandler: effectRecorder,
            scopeSyncHandler: { _ in }
        )
        let topologyBeforeRejection = workspaceStore.repositoryTopologyAtom.repos
        let unavailableRepoIdsBeforeRejection = workspaceStore.repositoryTopologyAtom.unavailableRepoIds
        let generationBeforeRejection = workspaceStore.repositoryTopologyAtom.worktreePathIndexGeneration

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(
                    .repoDiscovered(
                        repoPath: firstRepoPath,
                        parentPath: firstRepoPath.deletingLastPathComponent(),
                        linkedWorktrees: .scanned([secondRepoPath])
                    )
                )
            )
        )

        #expect(workspaceStore.repositoryTopologyAtom.repos == topologyBeforeRejection)
        #expect(workspaceStore.repositoryTopologyAtom.unavailableRepoIds == unavailableRepoIdsBeforeRejection)
        #expect(workspaceStore.repositoryTopologyAtom.worktreePathIndexGeneration == generationBeforeRejection)
        #expect(effectRecorder.deltas.isEmpty)
        #expect(repoCache.repoEnrichment(for: firstRepo.id) == .awaitingOrigin(repoId: firstRepo.id))
        #expect(workspaceStore.pane(pane.id)?.residency.isOrphaned == true)
    }

    @Test
    func topology_repoRemoved_matchesSymlinkStoredRepoByStableKey() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "workspace-cache-symlink-remove-\(UUID().uuidString)")
        let realRoot = tmp.appending(path: "real")
        let linkedRoot = tmp.appending(path: "linked")
        let realRepoPath = realRoot.appending(path: "app")
        let linkedRepoPath = linkedRoot.appending(path: "app")
        try FileManager.default.createDirectory(at: realRepoPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createSymbolicLink(atPath: linkedRoot.path, withDestinationPath: realRoot.path)

        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = makeCoordinator(
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            welcomeAtom: WelcomeAtom()
        )
        let repo = workspaceStore.addRepo(at: linkedRepoPath)
        let worktreeId = repo.worktrees.first!.id
        repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktreeId, repoId: repo.id, branch: "main")
        )
        repoCache.setPullRequestCount(2, for: worktreeId)

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(.repoRemoved(repoPath: realRepoPath))
            )
        )

        #expect(workspaceStore.repositoryTopologyAtom.isRepoUnavailable(repo.id))
        #expect(repoCache.repoEnrichmentByRepoId[repo.id] == nil)
        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId] == nil)
        #expect(repoCache.pullRequestCountByWorktreeId[worktreeId] == nil)
    }

    @Test
    func topology_worktreeUnregistered_unknownRepo_isIgnored() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = makeCoordinator(
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            welcomeAtom: WelcomeAtom()
        )

        let envelope = SystemEnvelope.test(
            event: .topology(
                .worktreeUnregistered(
                    worktreeId: UUID(),
                    repoId: UUID()
                )
            )
        )

        coordinator.handleTopology(envelope)

        #expect(workspaceStore.repos.isEmpty)
    }

    @Test
    func topology_worktreeUnregistered_prunesWorktreeCaches() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = makeCoordinator(
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            welcomeAtom: WelcomeAtom()
        )

        let repoPath = URL(fileURLWithPath: "/tmp/luna-unregister-prune")
        let repo = workspaceStore.addRepo(at: repoPath)
        guard let worktreeId = workspaceStore.repos.first(where: { $0.id == repo.id })?.worktrees.first?.id else {
            Issue.record("Expected repo to have a main worktree")
            return
        }

        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: worktreeId,
                repoId: repo.id,
                branch: "main"
            )
        )
        repoCache.setPullRequestCount(5, for: worktreeId)

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(
                    .worktreeUnregistered(worktreeId: worktreeId, repoId: repo.id)
                )
            )
        )

        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId] == nil)
        #expect(repoCache.pullRequestCountByWorktreeId[worktreeId] == nil)
    }

    @Test
    func workspaceActivity_recentTargetOpened_recordsRecentTargetInCache() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = makeCoordinator(
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            welcomeAtom: WelcomeAtom()
        )

        let repoId = UUID()
        let worktreeId = UUID()
        let target = RecentWorkspaceTarget.forWorktree(
            path: URL(fileURLWithPath: "/tmp/agent-studio"),
            worktree: Worktree(
                id: worktreeId,
                repoId: repoId,
                name: "agent-studio",
                path: URL(fileURLWithPath: "/tmp/agent-studio"),
                isMainWorktree: true
            ),
            repo: Repo(
                id: repoId,
                name: "agent-studio",
                repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
                worktrees: [],
                createdAt: Date()
            ),
            displayTitle: "agent-studio",
            subtitle: "main",
            lastOpenedAt: Date(timeIntervalSince1970: 1_700_000_456)
        )

        coordinator.consume(
            .system(
                .test(event: .workspaceActivity(.recentTargetOpened(target)))
            )
        )

        #expect(repoCache.recentTargets.first == target)
    }

    @Test
    func workspaceActivity_folderScanFinishedWithZeroRepos_updatesWorkspaceStoreToEmptyState() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let welcomeAtom = WelcomeAtom()
        let coordinator = makeCoordinator(
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            welcomeAtom: welcomeAtom
        )
        let rootPath = URL(fileURLWithPath: "/tmp/empty-folder-scan")

        welcomeAtom.beginFolderScan(rootPath)
        coordinator.consume(
            .system(
                .test(
                    event: .workspaceActivity(
                        .folderScanFinished(rootPath: rootPath, discoveredRepoCount: 0)
                    )
                )
            )
        )

        #expect(welcomeAtom.folderScanState == .empty(rootPath: rootPath))
    }

    @Test
    func workspaceActivity_folderScanFinishedWithRepos_clearsWorkspaceStoreScanState() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let welcomeAtom = WelcomeAtom()
        let coordinator = makeCoordinator(
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            welcomeAtom: welcomeAtom
        )
        let rootPath = URL(fileURLWithPath: "/tmp/non-empty-folder-scan")

        welcomeAtom.beginFolderScan(rootPath)
        coordinator.consume(
            .system(
                .test(
                    event: .workspaceActivity(
                        .folderScanFinished(rootPath: rootPath, discoveredRepoCount: 2)
                    )
                )
            )
        )

        #expect(welcomeAtom.folderScanState == .idle)
    }

    @Test
    func enrichment_snapshotChanged_updatesWorktreeCache() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        let repoId = UUID()
        let worktreeId = UUID()
        let snapshot = GitWorkingTreeSnapshot(
            worktreeId: worktreeId,
            repoId: repoId,
            rootPath: URL(fileURLWithPath: "/tmp/repo"),
            summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
            branch: "main"
        )

        let envelope = WorktreeEnvelope.test(
            event: .gitWorkingDirectory(.snapshotChanged(snapshot: snapshot)),
            repoId: repoId,
            worktreeId: worktreeId,
            source: .system(.builtin(.gitWorkingDirectoryProjector))
        )

        coordinator.handleEnrichment(envelope)

        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main")
        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.repoId == repoId)
    }

    @Test
    func startConsuming_coalescesSnapshotChangedBurstBeforeApplyingWorktreeCache() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let clock = TestPushClock()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in },
            enrichmentApplierFlushInterval: .milliseconds(25),
            enrichmentApplierClock: clock
        )

        let repoId = UUID()
        let worktreeId = UUID()
        coordinator.startConsuming()
        await waitForSubscriber(bus: bus)

        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .snapshotChanged(
                            snapshot: GitWorkingTreeSnapshot(
                                worktreeId: worktreeId,
                                repoId: repoId,
                                rootPath: URL(fileURLWithPath: "/tmp/repo"),
                                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                                branch: "old"
                            )
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector)),
                    seq: 1
                )
            )
        )
        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .snapshotChanged(
                            snapshot: GitWorkingTreeSnapshot(
                                worktreeId: worktreeId,
                                repoId: repoId,
                                rootPath: URL(fileURLWithPath: "/tmp/repo"),
                                summary: GitWorkingTreeSummary(changed: 2, staged: 0, untracked: 0),
                                branch: "new"
                            )
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector)),
                    seq: 2
                )
            )
        )

        let didScheduleFlush = await waitUntilYielding {
            clock.pendingSleepCount == 1
        }
        #expect(didScheduleFlush)
        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId] == nil)

        clock.advance(by: .milliseconds(25))
        let didApplyNewestSnapshot = await eventually("newest snapshot should apply after coalesced flush") {
            repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "new"
        }

        await coordinator.shutdown()

        #expect(didApplyNewestSnapshot)
        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.snapshot?.summary.changed == 2)
    }

    @Test("termination drains pending enrichment before the first persistence flush")
    func terminationDrainsPendingEnrichmentBeforeFirstPersistenceFlush() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let clock = TestPushClock()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in },
            enrichmentApplierFlushInterval: .milliseconds(25),
            enrichmentApplierClock: clock
        )
        let repoId = UUID()
        let worktreeId = UUID()
        coordinator.startConsuming()
        await waitForSubscriber(bus: bus)

        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .branchChanged(
                            worktreeId: worktreeId,
                            repoId: repoId,
                            from: "main",
                            to: "termination-branch"
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )

        let didScheduleFlush = await waitUntilYielding {
            clock.pendingSleepCount == 1
        }
        #expect(didScheduleFlush)
        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId] == nil)

        var branchObservedByFirstPersistenceFlush: String?
        await runFirstPersistenceFlushAfterWorkspaceCacheShutdown(
            workspaceCacheCoordinator: coordinator
        ) {
            branchObservedByFirstPersistenceFlush = repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch
        }

        #expect(branchObservedByFirstPersistenceFlush == "termination-branch")

        var didRunSecondPersistenceFlush = false
        await runFirstPersistenceFlushAfterWorkspaceCacheShutdown(
            workspaceCacheCoordinator: coordinator
        ) {
            didRunSecondPersistenceFlush = true
        }
        #expect(didRunSecondPersistenceFlush)
    }

    @Test
    func enrichment_branchChanged_preservesExistingSnapshot() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        let repoId = UUID()
        let worktreeId = UUID()
        let snapshot = GitWorkingTreeSnapshot(
            worktreeId: worktreeId,
            repoId: repoId,
            rootPath: URL(fileURLWithPath: "/tmp/repo"),
            summary: GitWorkingTreeSummary(changed: 2, staged: 1, untracked: 3),
            branch: "main"
        )
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: worktreeId,
                repoId: repoId,
                branch: "main",
                snapshot: snapshot
            )
        )

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .branchChanged(worktreeId: worktreeId, repoId: repoId, from: "main", to: "feature/new")
                ),
                repoId: repoId,
                worktreeId: worktreeId,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )

        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "feature/new")
        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.snapshot == snapshot)
    }

    @Test
    func enrichment_pullRequestCountsChanged_mapsByBranch() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        let repoId = UUID()
        let worktreeId = UUID()
        let otherRepoId = UUID()
        let otherWorktreeId = UUID()
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: worktreeId,
                repoId: repoId,
                branch: "feature/runtime"
            )
        )
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: otherWorktreeId,
                repoId: otherRepoId,
                branch: "feature/runtime"
            )
        )

        let envelope = WorktreeEnvelope.test(
            event: .forge(.pullRequestCountsChanged(repoId: repoId, countsByBranch: ["feature/runtime": 3])),
            repoId: repoId,
            worktreeId: nil,
            source: .system(.service(.gitForge(provider: "github")))
        )

        coordinator.handleEnrichment(envelope)

        #expect(repoCache.pullRequestCountByWorktreeId[worktreeId] == 3)
        #expect(repoCache.pullRequestCountByWorktreeId[otherWorktreeId] == nil)
    }

    @Test
    func enrichment_originChanged_validRemoteDerivesResolvedIdentity() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/luna-origin-identity"))

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .originChanged(
                        repoId: repo.id,
                        from: "",
                        to: "git@github.com:askluna/agent-studio.git"
                    )
                ),
                repoId: repo.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )

        guard case .some(.resolvedRemote(_, let raw, let identity, _)) = repoCache.repoEnrichmentByRepoId[repo.id]
        else {
            Issue.record("Expected resolved enrichment")
            return
        }
        #expect(raw.origin == "git@github.com:askluna/agent-studio.git")
        #expect(identity.groupKey == "remote:askluna/agent-studio")
        #expect(identity.remoteSlug == "askluna/agent-studio")
        #expect(identity.organizationName == "askluna")
        #expect(identity.displayName == "agent-studio")
    }

    @Test
    func enrichment_originChanged_emptyOriginDoesNotResolveLocalIdentity() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/luna-empty-origin"))
        repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .originChanged(
                        repoId: repo.id,
                        from: "",
                        to: ""
                    )
                ),
                repoId: repo.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )

        #expect(repoCache.repoEnrichmentByRepoId[repo.id] == .awaitingOrigin(repoId: repo.id))
    }

    @Test
    func enrichment_originUnavailableDerivesLocalIdentity() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/MyProject"))

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .originUnavailable(repoId: repo.id)
                ),
                repoId: repo.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )

        guard case .some(.resolvedLocal(_, let identity, _)) = repoCache.repoEnrichmentByRepoId[repo.id] else {
            Issue.record("Expected resolved local enrichment")
            return
        }
        #expect(repoCache.repoEnrichmentByRepoId[repo.id]?.raw?.origin == nil)
        #expect(identity.groupKey == "local:MyProject")
        #expect(identity.remoteSlug == nil)
    }

    @Test
    func scopeSync_originAndBranchDoNotInvokeForgeCommands_repoRemoved_unregisters() async {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let recordedScopeChanges = RecordedScopeChanges()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { change in
                await recordedScopeChanges.record(change)
            }
        )

        let repoPath = URL(fileURLWithPath: "/tmp/luna-scope-repo")
        let repo = workspaceStore.addRepo(at: repoPath)
        let worktree = Worktree(repoId: repo.id, name: "main", path: repoPath, isMainWorktree: true)
        workspaceStore.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .originChanged(
                        repoId: repo.id,
                        from: "",
                        to: "git@github.com:askluna/agent-studio.git"
                    )
                ),
                repoId: repo.id,
                worktreeId: worktree.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .branchChanged(
                        worktreeId: worktree.id,
                        repoId: repo.id,
                        from: "main",
                        to: "feature/runtime"
                    )
                ),
                repoId: repo.id,
                worktreeId: worktree.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(.repoRemoved(repoPath: repoPath))
            )
        )

        let completed = await eventually("scope changes should be recorded") {
            let count = await recordedScopeChanges.count
            return count >= 1
        }
        #expect(completed)

        let changes = await recordedScopeChanges.values
        #expect(
            changes.contains {
                if case .unregisterForgeRepo(let repoId) = $0 {
                    return repoId == repo.id
                }
                return false
            }
        )
        #expect(
            changes.contains {
                if case .registerForgeRepo = $0 { return true }
                return false
            } == false
        )
        #expect(
            changes.contains {
                if case .refreshForgeRepo = $0 { return true }
                return false
            } == false
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

    private func waitForSubscriber(bus: EventBus<RuntimeEnvelope>, maxTurns: Int = 50) async {
        for _ in 0..<maxTurns {
            if await bus.subscriberCount > 0 { return }
            await Task.yield()
        }
    }

    private func waitUntilYielding(
        maxTurns: Int = 10_000,
        condition: @escaping @Sendable () -> Bool
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }
}

@MainActor
private final class RejectedReconciliationTopologyEffectRecorder: TopologyEffectHandler {
    private(set) var deltas: [WorktreeTopologyDelta] = []

    func topologyDidChange(_ delta: WorktreeTopologyDelta) {
        deltas.append(delta)
    }
}

private actor RecordedScopeChanges {
    private var scopeChanges: [ScopeChange] = []

    func record(_ change: ScopeChange) {
        scopeChanges.append(change)
    }

    var count: Int {
        scopeChanges.count
    }

    var values: [ScopeChange] {
        scopeChanges
    }
}
