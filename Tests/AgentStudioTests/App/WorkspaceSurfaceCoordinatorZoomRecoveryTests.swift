import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct WorkspaceSurfaceCoordinatorZoomRecoveryTests {
        enum UnexpectedCompanionLoss: CaseIterable, CustomTestStringConvertible {
            case host
            case runtime

            var testDescription: String {
                switch self {
                case .host:
                    "host loss"
                case .runtime:
                    "runtime loss"
                }
            }
        }

        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test(
            "unexpected companion loss retires stale ownership and leaves active Zoom retryable",
            arguments: UnexpectedCompanionLoss.allCases
        )
        func unexpectedCompanionLossLeavesZoomRetryable(
            _ unexpectedLoss: UnexpectedCompanionLoss
        ) async throws {
            // Arrange
            let owningWindowId = UUID()
            let harness = makeHarness(workspaceWindowId: owningWindowId)
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            let (_, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
            let sourcePane = makeZoomRecoverySourcePane(
                in: harness.store,
                worktree: worktree
            )
            let sourceTab = Tab(paneId: sourcePane.id)
            harness.store.appendTab(sourceTab)
            let baseline = ZoomRecoveryResourceBaseline(harness: harness)
            let companionPaneId = try installZoomRecoveryCompanion(
                sourcePane: sourcePane,
                sourceTab: sourceTab,
                owningWindowId: owningWindowId,
                in: harness
            )

            switch unexpectedLoss {
            case .host:
                harness.coordinator.unregisterHostedView(for: companionPaneId)
                #expect(harness.viewRegistry.allBridgeViews[companionPaneId] == nil)
                #expect(
                    harness.runtimeRegistry.runtime(
                        for: PaneId(existingUUID: companionPaneId)
                    ) == nil
                )
            case .runtime:
                _ = harness.coordinator.unregisterRuntime(
                    PaneId(existingUUID: companionPaneId)
                )
                #expect(harness.viewRegistry.allBridgeViews[companionPaneId] == nil)
                #expect(
                    harness.runtimeRegistry.runtime(
                        for: PaneId(existingUUID: companionPaneId)
                    ) == nil
                )
            }

            // Act
            await harness.coordinator.drainBridgePaneRetirements()
            await harness.coordinator.drainBridgeGitReadActivityPropagation()

            // Assert
            #expect(
                harness.store.panePresentationAtom.zoomPresentation(forTab: sourceTab.id)
                    == ZoomPresentation(
                        sourcePaneId: sourcePane.id,
                        viewerPresentation: .retryable,
                        transientSplitRatio: nil
                    )
            )
            #expect(
                harness.store.panePresentationAtom.zoomCompanion(
                    forSourcePane: sourcePane.id
                ) == nil
            )
            expectZoomRecoveryResourcesRetired(
                companionPaneId,
                baseline: baseline,
                in: harness
            )

            await harness.coordinator.shutdown()
        }

        @Test("source worktree change retires the stale companion before explicit replacement")
        func sourceWorktreeChangeRetiresBeforeReplacement() async throws {
            // Arrange
            let owningWindowId = UUID()
            let harness = makeHarness(workspaceWindowId: owningWindowId)
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            let (_, originalWorktree) = makeRepoAndWorktree(
                harness.store,
                root: harness.tempDir
            )
            let (_, replacementWorktree) = makeRepoAndWorktree(
                harness.store,
                root: harness.tempDir
            )
            let sourcePane = makeZoomRecoverySourcePane(
                in: harness.store,
                worktree: originalWorktree
            )
            let sourceTab = Tab(paneId: sourcePane.id)
            harness.store.appendTab(sourceTab)
            let baseline = ZoomRecoveryResourceBaseline(harness: harness)
            let staleCompanionPaneId = try installZoomRecoveryCompanion(
                sourcePane: sourcePane,
                sourceTab: sourceTab,
                owningWindowId: owningWindowId,
                in: harness
            )
            #expect(
                harness.store.paneAtom.updatePaneCWDAndResolvedContext(
                    sourcePane.id,
                    cwd: replacementWorktree.path,
                    resolvedContext: (
                        repo: try #require(
                            harness.store.repositoryTopologyAtom.repo(
                                containing: replacementWorktree.id
                            )
                        ),
                        worktree: replacementWorktree
                    )
                ) == .applied
            )
            var requestedReplacementPaneIds: [UUID] = []
            let replacementSurfaceRequest: @MainActor (BridgeProductSurface, UUID) -> Bool = { surface, paneId in
                #expect(surface == .file)
                requestedReplacementPaneIds.append(paneId)
                expectZoomRecoveryResourceIsAbsent(
                    staleCompanionPaneId,
                    in: harness
                )
                return true
            }

            // Act — mismatch recovery is terminal cleanup, not replacement.
            let recoveryPresentation = harness.coordinator.reconcileZoomCompanion(
                sourcePaneId: sourcePane.id,
                owningTabId: sourceTab.id,
                viewerSurfaceRequest: replacementSurfaceRequest
            )
            await harness.coordinator.drainBridgePaneRetirements()
            await harness.coordinator.drainBridgeGitReadActivityPropagation()

            // Assert
            #expect(recoveryPresentation == .retryable)
            #expect(requestedReplacementPaneIds.isEmpty)
            #expect(
                harness.store.panePresentationAtom.zoomPresentation(forTab: sourceTab.id)?
                    .viewerPresentation == .retryable
            )
            #expect(
                harness.store.panePresentationAtom.zoomCompanion(
                    forSourcePane: sourcePane.id
                ) == nil
            )
            expectZoomRecoveryResourcesRetired(
                staleCompanionPaneId,
                baseline: baseline,
                in: harness
            )

            guard recoveryPresentation == .retryable else {
                await harness.coordinator.shutdown()
                return
            }

            // Act — a later explicit retry may create the replacement context.
            let replacementPresentation = harness.coordinator.reconcileZoomCompanion(
                sourcePaneId: sourcePane.id,
                owningTabId: sourceTab.id,
                viewerSurfaceRequest: replacementSurfaceRequest
            )

            // Assert
            let replacementCompanionPaneId = try #require(
                replacementPresentation.companionPaneId
            )
            #expect(replacementCompanionPaneId != staleCompanionPaneId)
            #expect(requestedReplacementPaneIds == [replacementCompanionPaneId])
            expectZoomRecoveryReplacementInstalled(
                companionPaneId: replacementCompanionPaneId,
                sourcePaneId: sourcePane.id,
                sourceTabId: sourceTab.id,
                worktreeId: replacementWorktree.id,
                baseline: baseline,
                in: harness
            )

            await harness.coordinator.shutdown()
        }

        @Test("worktree removal makes Viewer unavailable and retires the stale companion")
        func worktreeRemovalMakesViewerUnavailable() async throws {
            // Arrange
            let owningWindowId = UUID()
            let eventProbe = BridgeGitReadSchedulerEventProbe()
            let scheduler = BridgeGitReadScheduler(
                topology: makeBridgeGitReadSchedulerTopology(),
                eventSink: eventProbe.eventSink
            )
            let harness = makeHarness(
                workspaceWindowId: owningWindowId,
                bridgeGitReadScheduler: scheduler
            )
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            let (repo, worktree) = makeRepoAndWorktree(
                harness.store,
                root: harness.tempDir
            )
            let (_, unrelatedWorktree) = makeRepoAndWorktree(
                harness.store,
                root: harness.tempDir
            )
            let sourcePane = makeZoomRecoverySourcePane(
                in: harness.store,
                worktree: worktree
            )
            let sourceTab = Tab(paneId: sourcePane.id)
            harness.store.appendTab(sourceTab)
            let baseline = ZoomRecoveryResourceBaseline(harness: harness)
            let companionPaneId = try installZoomRecoveryCompanion(
                sourcePane: sourcePane,
                sourceTab: sourceTab,
                owningWindowId: owningWindowId,
                in: harness
            )
            harness.store.reconcileDiscoveredWorktrees(
                repo.id,
                worktrees: []
            )
            #expect(
                harness.store.repositoryTopologyAtom.worktree(worktree.id)
                    == nil
            )
            #expect(
                harness.store.repositoryTopologyAtom.worktree(unrelatedWorktree.id)
                    != nil
            )

            // Act
            harness.coordinator.topologyDidChange(
                WorktreeTopologyDelta(
                    repoId: repo.id,
                    addedWorktreeIds: [],
                    removedWorktrees: [
                        RemovedWorktreeEntry(
                            id: worktree.id,
                            path: worktree.path
                        )
                    ],
                    preservedWorktreeIds: [],
                    didChange: true,
                    traceId: nil
                )
            )
            await harness.coordinator.drainBridgePaneRetirements()
            await harness.coordinator.drainBridgeGitReadActivityPropagation()

            // Assert
            #expect(
                harness.store.panePresentationAtom.zoomPresentation(forTab: sourceTab.id)
                    == ZoomPresentation(
                        sourcePaneId: sourcePane.id,
                        viewerPresentation: .unavailable,
                        transientSplitRatio: nil
                    )
            )
            #expect(
                harness.store.panePresentationAtom.zoomCompanion(
                    forSourcePane: sourcePane.id
                ) == nil
            )
            #expect(
                harness.store.pane(sourcePane.id)?.residency
                    == .orphaned(
                        reason: .worktreeNotFound(
                            path: worktree.path.path
                        )
                    )
            )
            #expect(
                harness.store.tab(sourceTab.id)?.allPaneIds.contains(sourcePane.id)
                    == true
            )
            expectZoomRecoveryResourcesRetired(
                companionPaneId,
                baseline: baseline,
                in: harness
            )
            try await expectZoomRecoveryGitReadIsUnranked(
                scheduler: scheduler,
                eventProbe: eventProbe,
                worktree: worktree
            )

            await harness.coordinator.shutdown()
        }
    }
}

private struct ZoomRecoveryResourceBaseline {
    let runtimeCount: Int
    let slotPaneIds: Set<UUID>

    @MainActor
    init(harness: PaneTabViewControllerCommandHarness) {
        runtimeCount = harness.runtimeRegistry.count
        slotPaneIds = harness.viewRegistry.slotPaneIdsForTesting
    }
}

@MainActor
private func installZoomRecoveryCompanion(
    sourcePane: Pane,
    sourceTab: Tab,
    owningWindowId: UUID,
    in harness: PaneTabViewControllerCommandHarness
) throws -> UUID {
    harness.store.setActiveTab(sourceTab.id)
    harness.store.setActivePane(sourcePane.id, inTab: sourceTab.id)
    enterZoomRecoveryForegroundEnvironment(
        harness,
        owningWindowId: owningWindowId
    )

    harness.controller.execute(.zoomPane)
    harness.coordinator.refreshBridgePaneActivities()

    let companionPaneId = try #require(
        harness.store.panePresentationAtom.zoomCompanion(
            forSourcePane: sourcePane.id
        )?.companionPaneId
    )
    _ = try #require(harness.viewRegistry.allBridgeViews[companionPaneId])
    _ = try #require(
        harness.runtimeRegistry.runtime(
            for: PaneId(existingUUID: companionPaneId)
        )
    )
    _ = try #require(
        harness.coordinator.bridgePaneActivityAuthorityIdentity(
            for: companionPaneId
        )
    )
    return companionPaneId
}

@MainActor
private func expectZoomRecoveryResourcesRetired(
    _ companionPaneId: UUID,
    baseline: ZoomRecoveryResourceBaseline,
    in harness: PaneTabViewControllerCommandHarness
) {
    #expect(harness.viewRegistry.allBridgeViews[companionPaneId] == nil)
    #expect(harness.viewRegistry.peekSlotForTesting(companionPaneId) == nil)
    #expect(
        harness.runtimeRegistry.runtime(
            for: PaneId(existingUUID: companionPaneId)
        ) == nil
    )
    #expect(harness.runtimeRegistry.count == baseline.runtimeCount)
    #expect(harness.viewRegistry.slotPaneIdsForTesting == baseline.slotPaneIds)
    #expect(
        harness.coordinator.bridgePaneActivityAuthorityIdentity(
            for: companionPaneId
        ) == nil
    )
    #expect(harness.coordinator.bridgePaneActivity(for: companionPaneId) == nil)
}

private func expectZoomRecoveryGitReadIsUnranked(
    scheduler: BridgeGitReadScheduler,
    eventProbe: BridgeGitReadSchedulerEventProbe,
    worktree: Worktree
) async throws {
    _ = try await scheduler.read(
        request: makeBridgeGitReadRequest(
            worktree: worktree.stableKey,
            operationClass: .selectedVisibleContent,
            key: "zoom-companion-after-worktree-removal"
        )
    ) {
        "after-worktree-removal"
    }
    let startedRead = try #require(
        eventProbe.events.last {
            $0.kind == .started
                && $0.operationClass == .selectedVisibleContent
        }
    )
    #expect(startedRead.activityRank == .unranked)
}

@MainActor
private func expectZoomRecoveryResourceIsAbsent(
    _ companionPaneId: UUID,
    in harness: PaneTabViewControllerCommandHarness
) {
    #expect(harness.viewRegistry.peekSlotForTesting(companionPaneId) == nil)
    #expect(
        harness.runtimeRegistry.runtime(
            for: PaneId(existingUUID: companionPaneId)
        ) == nil
    )
    #expect(
        harness.coordinator.bridgePaneActivityAuthorityIdentity(
            for: companionPaneId
        ) == nil
    )
}

@MainActor
private func expectZoomRecoveryReplacementInstalled(
    companionPaneId: UUID,
    sourcePaneId: UUID,
    sourceTabId: UUID,
    worktreeId: UUID,
    baseline: ZoomRecoveryResourceBaseline,
    in harness: PaneTabViewControllerCommandHarness
) {
    #expect(
        harness.store.panePresentationAtom.zoomCompanion(
            forSourcePane: sourcePaneId
        )
            == ZoomCompanionMetadata(
                owningTabId: sourceTabId,
                resolvedWorktreeId: worktreeId,
                companionPaneId: companionPaneId,
                lastZoomVisibility: .visible
            )
    )
    #expect(harness.viewRegistry.allBridgeViews[companionPaneId] != nil)
    #expect(
        harness.runtimeRegistry.runtime(
            for: PaneId(existingUUID: companionPaneId)
        ) != nil
    )
    #expect(harness.runtimeRegistry.count == baseline.runtimeCount + 1)
    #expect(
        harness.viewRegistry.slotPaneIdsForTesting
            == baseline.slotPaneIds.union([companionPaneId])
    )
}

@MainActor
private func makeZoomRecoverySourcePane(
    in store: WorkspaceStore,
    worktree: Worktree
) -> Pane {
    store.createPane(
        launchDirectory: worktree.path,
        facets: PaneContextFacets(
            repoId: worktree.repoId,
            worktreeId: worktree.id,
            cwd: worktree.path
        )
    )
}

@MainActor
private func enterZoomRecoveryForegroundEnvironment(
    _ harness: PaneTabViewControllerCommandHarness,
    owningWindowId: UUID
) {
    harness.coordinator.bindBridgePaneActivities(
        toOwningWindowId: owningWindowId
    )
    harness.appLifecycleStore.setActive(true)
    harness.windowLifecycleStore.recordWindowRegistered(owningWindowId)
    harness.windowLifecycleStore.recordWindowPresentation(
        WindowPresentationFacts(
            isVisible: true,
            isMiniaturized: false,
            isOccluded: false
        ),
        for: owningWindowId
    )
}
