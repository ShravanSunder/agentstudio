import Foundation
import Observation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@Suite(.serialized)
@MainActor
final class WorkspaceCacheCoordinatorIntegrationTests {

    @Test("non-git CWD registration never admits status work")
    func nonGitCWDRegistrationNeverAdmitsStatusWork() async throws {
        let statusCalls = StatusCallCount()
        let pipeline = FilesystemGitPipeline(
            gitWorkingTreeProvider: .stub { _ in
                await statusCalls.recordCall()
                return GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                    branch: "unexpected",
                    origin: nil
                )
            },
            forgeStatusProvider: .stub { _ in .complete([]) },
            gitCoalescingWindow: .zero
        )
        let nonGitCWD = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-non-git-cwd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: nonGitCWD, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: nonGitCWD) }

        await pipeline.start()
        await pipeline.register(worktreeId: UUID(), repoId: UUID(), rootPath: nonGitCWD)

        // "Never admits status work" is a negative, so it needs a barrier rather than a
        // longer look: `shutdown()` awaits every actor in the pipeline, so once it returns
        // no provider call can still arrive and this single read covers the whole run.
        await pipeline.shutdown()
        #expect(await statusCalls.value == 0)
    }

    private func makeWorkspaceStore() -> WorkspaceStore {
        WorkspaceStore()
    }

    // MARK: - Integration: Add Folder Convergence

    @Test
    func integration_addFolderTopologyConvergesToResolvedRemoteIdentity() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let recordedScopeChanges = RecordedScopeChanges()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { change in
                await recordedScopeChanges.record(change)
            },
            enrichmentApplyTickCadence: .zero
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

        await withStartedCoordinatorAndProjector(bus: bus, coordinator: coordinator, projector: projector) {
            let repoPath = URL(fileURLWithPath: "/tmp/luna-converge-remote")
            let repo = workspaceStore.addRepo(at: repoPath)
            let worktreeId = repo.worktrees[0].id
            await projector.assertTopology(
                FilesystemTopologyAssertion(
                    generation: workspaceStore.repositoryTopologyAtom.worktreePathIndexGeneration,
                    contextsByWorktreeId: Dictionary(
                        uniqueKeysWithValues: repo.worktrees.map {
                            ($0.id, WorktreeFilesystemContext(repoId: repo.id, rootPath: $0.path))
                        }),
                    repositoryLifetimes: workspaceStore.repositoryTopologyAtom.repositoryObservationLifetimes,
                    worktreeLifetimes: workspaceStore.repositoryTopologyAtom.worktreeObservationLifetimes
                ))
            let posted = await bus.post(
                .system(
                    SystemEnvelope.test(
                        event: .topology(
                            .worktreeRegistered(worktreeId: worktreeId, repoId: repo.id, rootPath: repoPath)
                        ),
                        source: .builtin(.filesystemWatcher)
                    )
                )
            )
            #expect(posted.subscriberCount > 0)
            await projector.setRepositoryFactAttention(
                activePaneWorktreeId: worktreeId,
                sidebarAttendedWorktreeIds: [worktreeId],
                visibleActiveTabWorktreeIds: [],
                openWorktreeIds: [worktreeId],
                backgroundOnlyAutomaticWorktreeIds: []
            )

            let resolved = await waitUntilObserved("repo enrichment should resolve from projector origin") {
                guard case .some(.resolvedRemote(_, _, let identity, _)) = repoCache.repoEnrichmentByRepoId[repo.id]
                else {
                    return false
                }
                return identity.groupKey == "remote:askluna/agent-studio"
            }
            #expect(resolved)
        } afterQuiescence: {
            let scopeSynced = await recordedScopeChanges.values.isEmpty
            #expect(scopeSynced)
        }
    }

    @Test
    func integration_addFolderTopologyConvergesToResolvedLocalIdentityWhenRemoteMissing() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let recordedScopeChanges = RecordedScopeChanges()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { change in
                await recordedScopeChanges.record(change)
            },
            enrichmentApplyTickCadence: .zero
        )
        let projector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: .stub { _ in
                GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                    branch: "main",
                    originResolution: .confirmedAbsent
                )
            },
            coalescingWindow: .zero
        )

        await withStartedCoordinatorAndProjector(bus: bus, coordinator: coordinator, projector: projector) {
            let repoPath = URL(fileURLWithPath: "/tmp/luna-converge-local")
            let repo = workspaceStore.addRepo(at: repoPath)
            let worktreeId = repo.worktrees[0].id
            await projector.assertTopology(
                FilesystemTopologyAssertion(
                    generation: workspaceStore.repositoryTopologyAtom.worktreePathIndexGeneration,
                    contextsByWorktreeId: Dictionary(
                        uniqueKeysWithValues: repo.worktrees.map {
                            ($0.id, WorktreeFilesystemContext(repoId: repo.id, rootPath: $0.path))
                        }),
                    repositoryLifetimes: workspaceStore.repositoryTopologyAtom.repositoryObservationLifetimes,
                    worktreeLifetimes: workspaceStore.repositoryTopologyAtom.worktreeObservationLifetimes
                ))
            _ = await bus.post(
                .system(
                    SystemEnvelope.test(
                        event: .topology(
                            .worktreeRegistered(worktreeId: worktreeId, repoId: repo.id, rootPath: repoPath)
                        ),
                        source: .builtin(.filesystemWatcher)
                    )
                )
            )
            await projector.setRepositoryFactAttention(
                activePaneWorktreeId: worktreeId,
                sidebarAttendedWorktreeIds: [worktreeId],
                visibleActiveTabWorktreeIds: [],
                openWorktreeIds: [worktreeId],
                backgroundOnlyAutomaticWorktreeIds: []
            )

            let resolved = await waitUntilObserved("local-only repo enrichment should resolve") {
                guard case .some(.resolvedLocal(_, let identity, _)) = repoCache.repoEnrichmentByRepoId[repo.id]
                else {
                    return false
                }
                return identity.groupKey == "local:\(repo.name)"
            }
            #expect(resolved)
        } afterQuiescence: {
            let scopeSynced = await recordedScopeChanges.values.isEmpty
            #expect(scopeSynced)
        }
    }

    // MARK: - User-Initiated Repo Removal

    @Test
    func removeRepo_cleansUpCacheAndForgeScope() async {
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

        let repoPath = URL(fileURLWithPath: "/tmp/removal-test-repo")
        let repo = workspaceStore.addRepo(at: repoPath)
        let worktreeId = repo.worktrees.first!.id

        // Seed cache with enrichment data
        repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktreeId, repoId: repo.id, branch: "main")
        )
        let mainBranchKey = RepoBranchKey(repoId: repo.id, branch: "main")!
        repoCache.applyPullRequestFacts([
            mainBranchKey: PullRequestFacts(openCount: 3, exactOpenURL: nil)
        ])

        // User-initiated removal
        coordinator.handleRepoRemoval(repoId: repo.id)

        // Repo should be hard-deleted from store
        #expect(workspaceStore.repos.isEmpty)

        // All cache entries should be pruned
        #expect(repoCache.repoEnrichmentByRepoId[repo.id] == nil)
        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId] == nil)
        #expect(repoCache.pullRequestFactsByBranch.isEmpty)

        // Forge scope should be unregistered. The recorder signals the moment the matching
        // change lands, so this is a barrier on the owner rather than a repeated look.
        let removedRepoId = repo.id
        await recordedScopeChanges.waitForChange {
            if case .unregisterForgeRepo(let id, _) = $0 { return id == removedRepoId }
            return false
        }
        let changes = await recordedScopeChanges.values
        let converged = changes.contains {
            if case .unregisterForgeRepo(let id, _) = $0 { return id == repo.id }
            return false
        }
        #expect(converged)
    }

    // MARK: - Lifecycle Integration

    @Test
    func integration_fullRepoLifecycle_addEnrichRemove() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let recordedScopeChanges = RecordedScopeChanges()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { change in
                await recordedScopeChanges.record(change)
            },
            enrichmentApplyTickCadence: .zero
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

        await withStartedCoordinatorAndProjector(bus: bus, coordinator: coordinator, projector: projector) {
            // Phase 1: Discover repo
            let repoPath = URL(fileURLWithPath: "/tmp/lifecycle-test-repo")
            coordinator.handleTopology(
                SystemEnvelope.test(
                    event: .topology(
                        .repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent())
                    )
                )
            )
            #expect(workspaceStore.repos.count == 1)
            let repo = workspaceStore.repos[0]

            // Phase 2: Register worktree -> triggers enrichment via projector
            let worktreeId = repo.worktrees[0].id
            await projector.assertTopology(
                FilesystemTopologyAssertion(
                    generation: workspaceStore.repositoryTopologyAtom.worktreePathIndexGeneration,
                    contextsByWorktreeId: Dictionary(
                        uniqueKeysWithValues: repo.worktrees.map {
                            ($0.id, WorktreeFilesystemContext(repoId: repo.id, rootPath: $0.path))
                        }),
                    repositoryLifetimes: workspaceStore.repositoryTopologyAtom.repositoryObservationLifetimes,
                    worktreeLifetimes: workspaceStore.repositoryTopologyAtom.worktreeObservationLifetimes
                ))
            await projector.setRepositoryFactAttention(
                activePaneWorktreeId: worktreeId,
                sidebarAttendedWorktreeIds: [worktreeId],
                visibleActiveTabWorktreeIds: [],
                openWorktreeIds: [worktreeId],
                backgroundOnlyAutomaticWorktreeIds: []
            )
            _ = await bus.post(
                .system(
                    SystemEnvelope.test(
                        event: .topology(
                            .worktreeRegistered(worktreeId: worktreeId, repoId: repo.id, rootPath: repoPath)
                        ),
                        source: .builtin(.filesystemWatcher)
                    ),
                )
            )

            let enriched = await waitUntilObserved("enrichment should resolve") {
                guard case .some(.resolvedRemote(_, _, let identity, _)) = repoCache.repoEnrichmentByRepoId[repo.id]
                else {
                    return false
                }
                return identity.groupKey == "remote:askluna/agent-studio"
                    && repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main"
            }
            #expect(enriched)

            // Phase 3: User removes repo
            coordinator.handleRepoRemoval(repoId: repo.id)

            // Repo gone
            #expect(workspaceStore.repos.isEmpty)

            // Cache fully pruned
            #expect(repoCache.repoEnrichmentByRepoId[repo.id] == nil)
            #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId] == nil)

            // Forge unregistered — barrier on the recorder's own signal, then read once.
            let removedRepoId = repo.id
            await recordedScopeChanges.waitForChange {
                if case .unregisterForgeRepo(let id, _) = $0 { return id == removedRepoId }
                return false
            }
            let changes = await recordedScopeChanges.values
            let unregistered = changes.contains {
                if case .unregisterForgeRepo(let id, _) = $0 { return id == repo.id }
                return false
            }
            #expect(unregistered)
        }
    }

    @Test
    func integration_notScannedRepoReplay_preservesUnavailableState() async {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        // Setup: add repo, mark unavailable (simulating filesystem disappearance)
        let repoPath = URL(fileURLWithPath: "/tmp/re-add-test-repo")
        let repo = workspaceStore.addRepo(at: repoPath)
        workspaceStore.markRepoUnavailable(repo.id)
        #expect(workspaceStore.isRepoUnavailable(repo.id))

        // A path-only replay does not prove that the missing main worktree exists.
        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(
                    .repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent())
                )
            )
        )

        // The stored family remains intact, but degradation is preserved until a scanned result heals it.
        #expect(workspaceStore.isRepoUnavailable(repo.id))
        #expect(workspaceStore.repos.count == 1)
        #expect(workspaceStore.repos[0].id == repo.id)
        #expect(repoCache.repoEnrichmentByRepoId[repo.id] == .awaitingOrigin(repoId: repo.id))
    }

    @Test("authoritative scan healing availability preserves pane residency")
    func authoritativeScanAvailabilityHealPreservesPaneResidency() throws {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let effectHandler = RecordingTopologyEffectHandler()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            topologyEffectHandler: effectHandler,
            scopeSyncHandler: { _ in }
        )
        let repoPath = URL(filePath: "/tmp/availability-only-scan-heal")
        let repo = workspaceStore.addRepo(at: repoPath)
        let layoutPane = workspaceStore.createPane(
            launchDirectory: repoPath,
            zmxSessionID: .generateUUIDv7(),
            facets: PaneContextFacets(cwd: repoPath)
        )
        let backgroundPane = workspaceStore.createPane(
            launchDirectory: repoPath,
            zmxSessionID: .generateUUIDv7(),
            facets: PaneContextFacets(cwd: repoPath)
        )
        workspaceStore.appendTab(Tab(paneId: layoutPane.id))
        workspaceStore.markRepoUnavailable(repo.id)
        workspaceStore.setResidency(.backgrounded, for: backgroundPane.id)

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(
                    .repoDiscovered(
                        repoPath: repoPath,
                        parentPath: repoPath.deletingLastPathComponent(),
                        linkedWorktrees: .scanned([])
                    )
                )
            )
        )

        #expect(!workspaceStore.isRepoUnavailable(repo.id))
        #expect(effectHandler.deltas.count == 1)
        #expect(effectHandler.deltas.single?.didChange == true)
        #expect(workspaceStore.pane(layoutPane.id)?.residency == .active)
        #expect(workspaceStore.pane(backgroundPane.id)?.residency == .backgrounded)
    }

    // MARK: - Watched Folder Scope Change

    @Test
    func scopeSync_updateWatchedFolders_forwardsExactModelsToHandler() async throws {
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

        let watchedPath = WatchedPath(
            id: try #require(UUID(uuidString: "3AB7C03F-162A-416A-A40B-D7DE72C48670")),
            path: URL(fileURLWithPath: "/projects"),
            addedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        await coordinator.syncScope(
            .updateWatchedFolders(watchedPaths: [watchedPath], restoringRepositories: [], membershipRevision: 0))

        let changes = await recordedScopeChanges.values
        #expect(changes.count == 1)
        if case .updateWatchedFolders(let watchedPaths, _, _) = changes.first {
            #expect(watchedPaths == [watchedPath])
        } else {
            Issue.record("Expected updateWatchedFolders scope change")
        }
    }

    // MARK: - Bus Pathway Tests

    @Test
    func topology_repoDiscoveredViaBus_processedBySubscription() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        await withStartedCoordinator(bus: bus, coordinator: coordinator) {
            let repoPath = URL(fileURLWithPath: "/tmp/bus-topology-test")
            let postResult = await bus.post(
                .system(
                    SystemEnvelope.test(
                        event: .topology(
                            .repoDiscovered(
                                repoPath: repoPath,
                                parentPath: repoPath.deletingLastPathComponent()
                            )
                        )
                    )
                )
            )
            #expect(postResult.subscriberCount > 0)

            let converged = await waitUntilObserved("repo should appear via bus subscription") {
                workspaceStore.repos.contains { $0.repoPath == repoPath }
            }
            #expect(converged)
            #expect(workspaceStore.repos.count == 1)
        }
    }

    @Test
    func topology_bootReplayAndRescan_idempotentViaBus() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        await withStartedCoordinator(bus: bus, coordinator: coordinator) {
            let repoPath = URL(fileURLWithPath: "/tmp/boot-rescan-dedup")

            // Simulate boot replay posting .repoDiscovered
            await bus.post(
                .system(
                    SystemEnvelope.test(
                        event: .topology(
                            .repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent())
                        ),
                        source: .builtin(.coordinator)
                    ),
                )
            )

            let bootConverged = await waitUntilObserved("boot replay should add repo") {
                workspaceStore.repos.count == 1
            }
            #expect(bootConverged)

            // Simulate FSEvents rescan posting the same .repoDiscovered
            await bus.post(
                .system(
                    SystemEnvelope.test(
                        event: .topology(
                            .repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent())
                        ),
                        source: .builtin(.filesystemWatcher)
                    ),
                )
            )

            // Dedup is a negative: nothing changes, so there is no state to observe and a
            // longer look would prove nothing. Post a distinct repo AFTER the duplicate and
            // wait for it instead. The coordinator subscribes `.criticalUnbounded`, which
            // delivers in order without dropping, so once the later repo has landed the
            // duplicate ahead of it must already have been consumed. Waiting for quiescence
            // instead would be vacuous: `shutdown()` cancels the consume task and could
            // discard the duplicate unread, passing even if dedup were broken.
            let sentinelPath = URL(fileURLWithPath: "/tmp/boot-rescan-dedup-sentinel")
            await bus.post(
                .system(
                    SystemEnvelope.test(
                        event: .topology(
                            .repoDiscovered(
                                repoPath: sentinelPath,
                                parentPath: sentinelPath.deletingLastPathComponent()
                            )
                        ),
                        source: .builtin(.filesystemWatcher)
                    ),
                )
            )
            let sentinelConsumed = await waitUntilObserved("repo posted after the duplicate should arrive") {
                workspaceStore.repos.contains { $0.repoPath == sentinelPath }
            }
            #expect(sentinelConsumed)

            let remainedDeduplicated = workspaceStore.repos.count { $0.repoPath == repoPath } == 1
            #expect(remainedDeduplicated)
        }
    }

    @Test
    func topology_repoRemovedBurstBeyondStandardLossyLimitConvergesViaCriticalSubscription() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        await withStartedCoordinator(bus: bus, coordinator: coordinator) {
            let burstCount = BusSubscriberPolicy.standardLossyBufferLimit + 1
            let repoPaths = (0..<burstCount).map { index in
                URL(fileURLWithPath: "/tmp/topology-critical-remove-\(index)")
            }
            for repoPath in repoPaths {
                _ = workspaceStore.addRepo(at: repoPath)
            }
            #expect(workspaceStore.repos.count == burstCount)

            let removalBurst = repoPaths.enumerated().map { index, repoPath in
                RuntimeEnvelope.system(
                    SystemEnvelope.test(
                        event: .topology(.repoRemoved(repoPath: repoPath)),
                        source: .builtin(.filesystemWatcher),
                        seq: UInt64(index + 1)
                    )
                )
            }
            let postResult = await bus.post(contentsOf: removalBurst)
            #expect(postResult.subscriberCount > 0)
            #expect(postResult.droppedCount == 0)

            // Wait on the store, which is the observable end of the burst; the bus counter
            // is an actor read and cannot be observed, so it is checked once afterwards
            // rather than sampled in a loop. Every repo being unavailable already implies
            // the critical subscriber consumed the whole burst.
            let converged = await waitUntilObserved("critical subscriber should consume full removal burst") {
                workspaceStore.repos.allSatisfy { workspaceStore.isRepoUnavailable($0.id) }
            }
            #expect(converged)

            let burstDiagnostics = await bus.diagnosticsSnapshot()
            let burstSubscriber = burstDiagnostics.activeSubscribers.first {
                $0.subscriberName == "WorkspaceCacheCoordinator"
            }
            #expect(burstSubscriber?.consumedCount ?? 0 >= UInt64(burstCount))

            let diagnostics = await bus.diagnosticsSnapshot()
            let subscriber = diagnostics.activeSubscribers.first {
                $0.subscriberName == "WorkspaceCacheCoordinator"
            }
            #expect(subscriber?.policy == .criticalUnbounded)
            #expect(subscriber?.liveDroppedCount == 0)
            #expect(subscriber?.failureClasses.contains(.criticalDrop) == false)
            #expect(subscriber?.failureClasses.contains(.criticalPressure) == false)
        }
    }

    @Test
    func topology_repoDiscoveredScannedLinkedWorktrees_createsGroupedWorktrees() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        let repoPath = URL(fileURLWithPath: "/tmp/grouped-topology-repo")
        let featurePath = URL(fileURLWithPath: "/tmp/grouped-topology-repo-feature")
        let hotfixPath = URL(fileURLWithPath: "/tmp/grouped-topology-repo-hotfix")

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(
                    .repoDiscovered(
                        repoPath: repoPath,
                        parentPath: repoPath.deletingLastPathComponent(),
                        linkedWorktrees: .scanned([featurePath, hotfixPath])
                    )
                )
            )
        )

        #expect(workspaceStore.repos.count == 1)
        let discoveredPaths = Set(workspaceStore.repos[0].worktrees.map(\.path))
        #expect(discoveredPaths == Set([repoPath, featurePath, hotfixPath]))
    }

    @Test
    func topology_repoDiscoveredScannedUpdate_removesMissingWorktreeAndPrunesCache() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let effectHandler = RecordingTopologyEffectHandler()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            topologyEffectHandler: effectHandler,
            scopeSyncHandler: { _ in }
        )

        let repoPath = URL(fileURLWithPath: "/tmp/reconciled-topology-repo")
        let keepPath = URL(fileURLWithPath: "/tmp/reconciled-topology-repo-keep")
        let removedPath = URL(fileURLWithPath: "/tmp/reconciled-topology-repo-removed")

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(
                    .repoDiscovered(
                        repoPath: repoPath,
                        parentPath: repoPath.deletingLastPathComponent(),
                        linkedWorktrees: .scanned([keepPath, removedPath])
                    )
                )
            )
        )

        let repo = try! #require(workspaceStore.repos.first)
        let removedWorktreeId = try! #require(
            repo.worktrees.first(where: { $0.path == removedPath })?.id
        )
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: removedWorktreeId, repoId: repo.id, branch: "removed")
        )
        let removedBranchKey = RepoBranchKey(repoId: repo.id, branch: "removed")!
        repoCache.applyPullRequestFacts([
            removedBranchKey: PullRequestFacts(openCount: 7, exactOpenURL: nil)
        ])

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(
                    .repoDiscovered(
                        repoPath: repoPath,
                        parentPath: repoPath.deletingLastPathComponent(),
                        linkedWorktrees: .scanned([keepPath])
                    )
                )
            )
        )

        let remainingPaths = Set(try! #require(workspaceStore.repos.first).worktrees.map(\.path))
        #expect(remainingPaths == Set([repoPath, keepPath]))
        #expect(repoCache.worktreeEnrichmentByWorktreeId[removedWorktreeId] == nil)
        #expect(repoCache.pullRequestFacts(for: removedBranchKey)?.openCount == 7)
        #expect(effectHandler.deltas.count == 2)
        let lastDelta = try! #require(effectHandler.deltas.last)
        #expect(lastDelta.repoId == repo.id)
        #expect(lastDelta.removedWorktrees.map { $0.id } == [removedWorktreeId])
        #expect(lastDelta.removedWorktrees.map { $0.path } == [removedPath])
        #expect(lastDelta.addedWorktreeIds.isEmpty)
        #expect(lastDelta.didChange)
    }

    @Test
    func topology_repoDiscoveredScannedEmpty_removesAllLinkedWorktrees() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        let repoPath = URL(fileURLWithPath: "/tmp/empty-topology-repo")
        let featurePath = URL(fileURLWithPath: "/tmp/empty-topology-repo-feature")
        let hotfixPath = URL(fileURLWithPath: "/tmp/empty-topology-repo-hotfix")

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(
                    .repoDiscovered(
                        repoPath: repoPath,
                        parentPath: repoPath.deletingLastPathComponent(),
                        linkedWorktrees: .scanned([featurePath, hotfixPath])
                    )
                )
            )
        )

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(
                    .repoDiscovered(
                        repoPath: repoPath,
                        parentPath: repoPath.deletingLastPathComponent(),
                        linkedWorktrees: .scanned([])
                    )
                )
            )
        )

        #expect(workspaceStore.repos.count == 1)
        #expect(workspaceStore.repos[0].worktrees.map(\.path) == [repoPath])
    }

    @Test
    func topology_repoDiscoveredNotScanned_preservesExistingLinkedWorktrees() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        let repoPath = URL(fileURLWithPath: "/tmp/not-scanned-topology-repo")
        let featurePath = URL(fileURLWithPath: "/tmp/not-scanned-topology-repo-feature")
        let hotfixPath = URL(fileURLWithPath: "/tmp/not-scanned-topology-repo-hotfix")

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(
                    .repoDiscovered(
                        repoPath: repoPath,
                        parentPath: repoPath.deletingLastPathComponent(),
                        linkedWorktrees: .scanned([featurePath, hotfixPath])
                    )
                )
            )
        )

        let pathsBeforeBootReplay = Set(workspaceStore.repos[0].worktrees.map(\.path))

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(
                    .repoDiscovered(
                        repoPath: repoPath,
                        parentPath: repoPath.deletingLastPathComponent(),
                        linkedWorktrees: .notScanned
                    )
                )
            )
        )

        let pathsAfterBootReplay = Set(workspaceStore.repos[0].worktrees.map(\.path))
        #expect(pathsAfterBootReplay == pathsBeforeBootReplay)
    }

    @Test
    func shutdown_removesBusSubscriberBeforeReturning() async {
        let bus = EventBus<RuntimeEnvelope>()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: makeWorkspaceStore(),
            repoCache: RepoCacheAtom(),
            scopeSyncHandler: { _ in }
        )

        await coordinator.startConsuming()
        #expect(await bus.subscriberCount == 1)

        await coordinator.shutdown()

        #expect(await bus.subscriberCount == 0)
    }

    // MARK: - Helpers

    /// Waits until the owner's observed state satisfies `predicate`, then returns true.
    ///
    /// There is no turn budget and no clock here on purpose: the verdict is a function of
    /// what the coordinator actually published, never of how many yields a 3-vCPU runner
    /// could fit into an arbitrary budget. The lane's inactivity watchdog is the only hang
    /// bound. `Observations` re-evaluates the predicate whenever any `@Observable` state it
    /// read changes, so a real projector origin resolution wakes this wait exactly once.
    ///
    /// Returns false only if the observation stream ends before the state converges, which
    /// is a genuine failure and is recorded as one.
    @discardableResult
    private func waitUntilObserved(
        _ description: String,
        _ predicate: @escaping @MainActor () -> Bool
    ) async -> Bool {
        if predicate() {
            return true
        }
        let satisfiedValues = Observations { predicate() }
        for await satisfied in satisfiedValues where satisfied {
            return true
        }
        Issue.record("\(description): observation ended before the state converged")
        return false
    }

    private func withStartedCoordinator(
        bus: EventBus<RuntimeEnvelope>,
        coordinator: WorkspaceCacheCoordinator,
        operation: @MainActor () async throws -> Void,
        afterQuiescence: @MainActor () async -> Void = {}
    ) async rethrows {
        await coordinator.startConsuming()
        do {
            try await operation()
            await coordinator.shutdown()
            // `shutdown()` awaits the consume task, so the subscription is gone by the time
            // it returns and this is a settled read rather than a sampled one.
            #expect(await bus.subscriberCount == 0)
            await afterQuiescence()
        } catch {
            await coordinator.shutdown()
            throw error
        }
    }

    private func withStartedCoordinatorAndProjector(
        bus: EventBus<RuntimeEnvelope>,
        coordinator: WorkspaceCacheCoordinator,
        projector: GitWorkingDirectoryProjector,
        operation: @MainActor () async throws -> Void,
        afterQuiescence: @MainActor () async -> Void = {}
    ) async rethrows {
        await coordinator.startConsuming()
        await projector.start()
        do {
            try await operation()
            await projector.shutdown()
            await coordinator.shutdown()
            #expect(await bus.subscriberCount == 0)
            // Both shutdowns await their in-flight work, so nothing can record a scope
            // change after this point. Negative claims belong here: read once against a
            // world that has stopped, which is a total claim rather than a sample.
            await afterQuiescence()
        } catch {
            await projector.shutdown()
            await coordinator.shutdown()
            throw error
        }
    }
}

private actor StatusCallCount {
    private(set) var value = 0

    func recordCall() {
        value += 1
    }
}

private actor RecordedScopeChanges {
    private typealias MatchWaiter = (
        predicate: @Sendable (ScopeChange) -> Bool, continuation: CheckedContinuation<Void, Never>
    )

    private var scopeChanges: [ScopeChange] = []
    private var matchWaiters: [MatchWaiter] = []

    func record(_ change: ScopeChange) {
        scopeChanges.append(change)
        var stillWaiting: [MatchWaiter] = []
        for waiter in matchWaiters {
            if waiter.predicate(change) {
                waiter.continuation.resume()
            } else {
                stillWaiting.append(waiter)
            }
        }
        matchWaiters = stillWaiting
    }

    /// Returns once a matching change has been recorded. The recorder is the owner of this
    /// fact, so it signals directly instead of being sampled: no budget, no clock, and the
    /// already-recorded case returns without suspending.
    func waitForChange(matching predicate: @Sendable @escaping (ScopeChange) -> Bool) async {
        if scopeChanges.contains(where: predicate) {
            return
        }
        await withCheckedContinuation { continuation in
            matchWaiters.append((predicate, continuation))
        }
    }

    var count: Int {
        scopeChanges.count
    }

    var values: [ScopeChange] {
        scopeChanges
    }
}

@MainActor
private final class RecordingTopologyEffectHandler: TopologyEffectHandler {
    private(set) var deltas: [WorktreeTopologyDelta] = []

    func topologyDidChange(_ delta: WorktreeTopologyDelta) {
        deltas.append(delta)
    }
}
