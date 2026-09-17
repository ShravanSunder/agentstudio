import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@Suite("Filesystem projection observation lifetime")
struct FilesystemProjectionObservationLifetimeTests {
    @Test("equal Git snapshots only coalesce within the same observation lifetime")
    func equalSnapshotsRemainObservableAfterLifetimeReplacement() async {
        let index = FilesystemProjectionIndex()
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let epoch = UUIDv7.generate()
        let snapshot = GitWorkingTreeSnapshot(
            worktreeId: worktreeID, repoId: repositoryID,
            rootPath: URL(fileURLWithPath: "/tmp/projection-lifetime"),
            summary: .init(changed: 1, staged: 0, untracked: 0), branch: "main")
        func request(_ revision: UInt64) -> PaneFilesystemProjectionRequest {
            .init(
                requestGeneration: revision, paneContextGeneration: 0, topologyGeneration: 0,
                envelope: RuntimeEnvelopeHarness.gitEnvelope(
                    event: .snapshotChanged(snapshot: snapshot), repoId: repositoryID, worktreeId: worktreeID,
                    observationLifetime: .worktree(.init(launchEpoch: epoch, revision: revision))))
        }
        let first = await index.projectPaneFilesystem(request(1))
        let repeated = await index.projectPaneFilesystem(request(1))
        let returned = await index.projectPaneFilesystem(request(2))
        #expect(first.derivedInputCount == 1)
        #expect(repeated.derivedInputCount == 0)
        #expect(repeated.skippedUnchangedInputCount == 1)
        #expect(returned.derivedInputCount == 1)
        #expect(returned.skippedUnchangedInputCount == 0)
        await index.shutdown()
    }
}

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct RepositoryBridgeObservationLifetimeTests {
        @Test("automatic checkout absence retires the zoom viewer while preserving its source terminal")
        func automaticAbsenceRetiresZoomViewer() async throws {
            try await withAsyncTestCoreAtoms { atoms in
                let harness = makeHarness()
                defer { try? FileManager.default.removeItem(at: harness.tempDir) }
                try await withWorkspaceCommandHarness(harness) {
                    let (_, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
                    let sourcePane = makeZoomLifecycleSourcePane(in: harness.store, worktree: worktree)
                    let sourceTab = Tab(paneId: sourcePane.id)
                    harness.store.appendTab(sourceTab)
                    harness.store.setActiveTab(sourceTab.id)
                    harness.store.setActivePane(sourcePane.id, inTab: sourceTab.id)
                    harness.controller.execute(.zoomPane)
                    let companionID = try #require(
                        harness.store.panePresentationAtom.zoomCompanion(forSourcePane: sourcePane.id)?.companionPaneId)
                    #expect(harness.viewRegistry.allBridgeViews[companionID] != nil)
                    let observation = try absenceObservation(store: harness.store, root: harness.tempDir)
                    let cacheCoordinator = WorkspaceCacheCoordinator(
                        workspaceStore: harness.store, repoCache: atoms.repoCache,
                        topologyEffectHandler: harness.coordinator,
                        validateSourceObservations: { _ in true }, scopeSyncHandler: { _ in })

                    await cacheCoordinator.consumeWatchedFolderObservation(observation, sequence: 1)
                    await harness.coordinator.drainBridgePaneRetirements()
                    await harness.coordinator.drainBridgeGitReadActivityPropagation()
                    await cacheCoordinator.shutdown()

                    #expect(harness.store.pane(sourcePane.id)?.repoId == nil)
                    #expect(harness.store.pane(sourcePane.id)?.worktreeId == nil)
                    #expect(harness.store.pane(sourcePane.id)?.content == sourcePane.content)
                    #expect(harness.store.tab(sourceTab.id)?.allPaneIds == [sourcePane.id])
                    #expect(harness.store.tabLayoutAtom.activeTabId == sourceTab.id)
                    #expect(harness.store.panePresentationAtom.zoomCompanion(forSourcePane: sourcePane.id) == nil)
                    #expect(harness.viewRegistry.allBridgeViews[companionID] == nil)
                    #expect(harness.runtimeRegistry.runtime(for: PaneId(existingUUID: companionID)) == nil)
                    #expect(harness.coordinator.bridgePaneActivityAuthorityIdentity(for: companionID) == nil)
                }
            }
        }

        private func absenceObservation(store: WorkspaceStore, root: URL) throws -> WatchedFolderTopologyObservation {
            let watch = try #require(store.mutationCoordinator.addWatchedPath(root))
            return WatchedFolderTopologyObservation(
                root: root,
                registration: .init(
                    sourceID: .init(kind: .watchedParentMembership, rootID: watch.id),
                    registrationGeneration: 1, rootGeneration: 1),
                entries: [], otherObservedPaths: [],
                coverage: .authoritative(
                    .init(utc: Date(timeIntervalSince1970: 1000), bootID: "fixture", uptimeNanoseconds: 1)),
                baselineMembershipRevision: store.repositoryTopologyAtom.worktreePathIndexGeneration,
                incompleteOtherScopes: [])
        }

        @Test("old Git snapshots cannot cross same-ID return into Bridge publication", arguments: [true, false])
        func oldSnapshotCannotReachBridge(suspendProjection: Bool) async throws {
            installTestCoreAtomsIfNeeded()
            let index = RefreshGateableFilesystemProjectionIndex()
            let setup = try makeWorkspaceRefreshTestSetup(projectionIndex: index)
            let harness = setup.harness
            do {
                harness.store.paneAtom.setResidency(.backgrounded, for: setup.bridgePane.id)
                await assertEventuallyMain("Bridge refresh gate is loaded-hidden") {
                    setup.controller.refreshAdmissionCoordinator.diagnosticSnapshot.activity == .loadedHidden
                }
                await harness.coordinator.syncFilesystemRootsAndActivityUntilIdle()
                let topology = harness.store.repositoryTopologyAtom
                let oldLifetime = try #require(topology.worktreeObservationLifetimes[setup.worktree.id])
                let envelope = gitSnapshot(setup: setup, lifetime: oldLifetime, branch: "retired")
                let operation: Task<Bool, Never>?
                if suspendProjection {
                    await index.pauseNextProjection()
                    operation = Task { await harness.coordinator.handleFilesystemEnvelopeIfNeeded(envelope) }
                    await index.waitForPausedProjection()
                } else {
                    operation = nil
                }
                #expect(
                    harness.store.mutationCoordinator.recordRepositoryAbsence(
                        setup.repoId,
                        at: .init(utc: Date(timeIntervalSince1970: 1000), bootID: "fixture", uptimeNanoseconds: 1)))
                #expect(harness.store.mutationCoordinator.restoreObservedWorktrees([setup.worktree.id]))
                #expect(topology.worktreeObservationLifetimes[setup.worktree.id] != oldLifetime)
                if let operation {
                    await index.resumePausedProjection()
                    _ = await operation.value
                } else {
                    _ = await harness.coordinator.handleFilesystemEnvelopeIfNeeded(envelope)
                }

                #expect(
                    setup.controller.refreshAdmissionCoordinator.diagnosticSnapshot.dirtyFact?.latestFileStatus == nil)

                let current = try #require(topology.worktreeObservationLifetimes[setup.worktree.id])
                _ = await harness.coordinator.handleFilesystemEnvelopeIfNeeded(
                    gitSnapshot(setup: setup, lifetime: current, branch: "current"))
                #expect(
                    setup.controller.refreshAdmissionCoordinator.diagnosticSnapshot.dirtyFact?.latestFileStatus?.branch
                        == "current")
            } catch {
                await harness.finish()
                throw error
            }
            await harness.finish()
        }

        private func gitSnapshot(
            setup: WorkspaceRefreshTestSetup, lifetime: WorktreeObservationLifetime, branch: String
        ) -> RuntimeEnvelope {
            .worktree(
                .test(
                    event: .gitWorkingDirectory(
                        .snapshotChanged(
                            snapshot: .init(
                                worktreeId: setup.worktree.id, repoId: setup.repoId, rootPath: setup.worktree.path,
                                summary: .init(changed: 7, staged: 0, untracked: 0), branch: branch))),
                    repoId: setup.repoId, worktreeId: setup.worktree.id, eventId: UUIDv7.generate(),
                    observationLifetime: .worktree(lifetime)))
        }
    }
}
