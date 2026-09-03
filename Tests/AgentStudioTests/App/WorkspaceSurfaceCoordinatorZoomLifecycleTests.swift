import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct WorkspaceSurfaceCoordinatorZoomLifecycleTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("closing a Zoom source terminally retires every companion resource")
        func closingZoomSourceRetiresCompanionResources() async throws {
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
            let (_, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
            let sourcePane = makeZoomLifecycleSourcePane(
                in: harness.store,
                worktree: worktree
            )
            let sourceTab = Tab(paneId: sourcePane.id)
            harness.store.appendTab(sourceTab)
            harness.store.setActiveTab(sourceTab.id)
            harness.store.setActivePane(sourcePane.id, inTab: sourceTab.id)
            enterZoomLifecycleForegroundEnvironment(
                harness,
                owningWindowId: owningWindowId
            )
            let runtimeCountBeforeZoom = harness.runtimeRegistry.count
            let slotPaneIdsBeforeZoom = harness.viewRegistry.slotPaneIdsForTesting

            harness.controller.execute(.zoomPane)

            let companionPaneId = try #require(
                harness.store.panePresentationAtom.zoomCompanion(
                    forSourcePane: sourcePane.id
                )?.companionPaneId
            )
            #expect(harness.viewRegistry.allBridgeViews[companionPaneId] != nil)
            #expect(harness.viewRegistry.peekSlotForTesting(companionPaneId) != nil)
            #expect(
                harness.runtimeRegistry.runtime(
                    for: PaneId(existingUUID: companionPaneId)
                ) != nil
            )
            #expect(
                harness.coordinator.bridgePaneActivityAuthorityIdentity(
                    for: companionPaneId
                ) != nil
            )
            #expect(
                harness.coordinator.bridgePaneActivity(for: companionPaneId)
                    == .foreground
            )
            await harness.coordinator.drainBridgeGitReadActivityPropagation()

            harness.coordinator.execute(
                .closePane(tabId: sourceTab.id, paneId: sourcePane.id)
            )
            await harness.coordinator.drainBridgePaneRetirements()
            await harness.coordinator.drainBridgeGitReadActivityPropagation()

            expectZoomLifecycleCompanionRetired(
                ZoomLifecycleCompanionCleanupExpectation(
                    sourcePaneId: sourcePane.id,
                    sourceTabId: sourceTab.id,
                    companionPaneId: companionPaneId,
                    runtimeCountBeforeZoom: runtimeCountBeforeZoom,
                    slotPaneIdsBeforeZoom: slotPaneIdsBeforeZoom
                ),
                in: harness
            )

            _ = try await scheduler.read(
                request: makeBridgeGitReadRequest(
                    worktree: worktree.stableKey,
                    operationClass: .selectedVisibleContent,
                    key: "zoom-companion-after-source-close"
                )
            ) {
                "after-close"
            }
            let startedRead = try #require(
                eventProbe.events.last {
                    $0.kind == .started
                        && $0.operationClass == .selectedVisibleContent
                }
            )
            #expect(startedRead.activityRank == .unranked)

            await harness.coordinator.shutdown()
        }

        @Test("moving a canceled Zoom source keeps its companion and transfers tab ownership")
        func movingCanceledZoomSourceTransfersCompanionOwnership() async throws {
            let owningWindowId = UUID()
            let harness = makeHarness(workspaceWindowId: owningWindowId)
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            let (_, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
            let sourcePane = makeZoomLifecycleSourcePane(
                in: harness.store,
                worktree: worktree
            )
            let sourceSiblingPane = makeZoomLifecycleSourcePane(
                in: harness.store,
                worktree: worktree
            )
            let destinationPane = makeZoomLifecycleSourcePane(
                in: harness.store,
                worktree: worktree
            )
            let sourceTab = Tab(paneId: sourcePane.id)
            harness.store.appendTab(sourceTab)
            #expect(
                harness.store.insertPane(
                    sourceSiblingPane.id,
                    inTab: sourceTab.id,
                    at: sourcePane.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )
            )
            let destinationTab = Tab(paneId: destinationPane.id)
            harness.store.appendTab(destinationTab)
            harness.store.setActiveTab(sourceTab.id)
            harness.store.setActivePane(sourcePane.id, inTab: sourceTab.id)
            enterZoomLifecycleForegroundEnvironment(
                harness,
                owningWindowId: owningWindowId
            )

            harness.controller.execute(.zoomPane)

            let companionPaneId = try #require(
                harness.store.panePresentationAtom.zoomCompanion(
                    forSourcePane: sourcePane.id
                )?.companionPaneId
            )
            let retainedHostIdentity = try #require(
                harness.viewRegistry.allBridgeViews[companionPaneId].map(
                    ObjectIdentifier.init
                )
            )

            harness.controller.execute(.zoomPane)

            #expect(
                harness.store.panePresentationAtom.zoomPresentation(
                    forTab: sourceTab.id
                ) == nil
            )
            #expect(
                harness.coordinator.bridgePaneActivity(for: companionPaneId)
                    == .loadedHidden
            )

            harness.coordinator.execute(
                .movePaneAcrossTabs(
                    CrossTabPaneMoveRequest(
                        paneId: sourcePane.id,
                        sourceTabId: sourceTab.id,
                        destTabId: destinationTab.id,
                        targetPaneId: destinationPane.id,
                        direction: .horizontal,
                        position: .after
                    )
                )
            )
            harness.coordinator.refreshBridgePaneActivities()
            await harness.coordinator.drainBridgeGitReadActivityPropagation()

            try expectZoomLifecycleCompanionMoved(
                ZoomLifecycleCompanionMoveExpectation(
                    sourcePaneId: sourcePane.id,
                    sourceTabId: sourceTab.id,
                    destinationTabId: destinationTab.id,
                    companionPaneId: companionPaneId,
                    retainedHostIdentity: retainedHostIdentity
                ),
                in: harness
            )

            await harness.coordinator.shutdown()
        }

        @Test("moving the only canceled Zoom source removes its tab and retains its companion")
        func movingOnlyCanceledZoomSourceRetainsCompanionAfterSourceTabRemoval() async throws {
            let owningWindowId = UUID()
            let harness = makeHarness(workspaceWindowId: owningWindowId)
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            let (_, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
            let sourcePane = makeZoomLifecycleSourcePane(
                in: harness.store,
                worktree: worktree
            )
            let destinationPane = makeZoomLifecycleSourcePane(
                in: harness.store,
                worktree: worktree
            )
            let sourceTab = Tab(paneId: sourcePane.id)
            let destinationTab = Tab(paneId: destinationPane.id)
            harness.store.appendTab(sourceTab)
            harness.store.appendTab(destinationTab)
            harness.store.setActiveTab(sourceTab.id)
            harness.store.setActivePane(sourcePane.id, inTab: sourceTab.id)
            enterZoomLifecycleForegroundEnvironment(
                harness,
                owningWindowId: owningWindowId
            )

            harness.controller.execute(.zoomPane)

            let companionPaneId = try #require(
                harness.store.panePresentationAtom.zoomCompanion(
                    forSourcePane: sourcePane.id
                )?.companionPaneId
            )
            let retainedHostIdentity = try #require(
                harness.viewRegistry.allBridgeViews[companionPaneId].map(
                    ObjectIdentifier.init
                )
            )

            harness.controller.execute(.zoomPane)
            #expect(
                harness.coordinator.bridgePaneActivity(for: companionPaneId)
                    == .loadedHidden
            )

            harness.coordinator.execute(
                .movePaneAcrossTabs(
                    CrossTabPaneMoveRequest(
                        paneId: sourcePane.id,
                        sourceTabId: sourceTab.id,
                        destTabId: destinationTab.id,
                        targetPaneId: destinationPane.id,
                        direction: .horizontal,
                        position: .after
                    )
                )
            )
            harness.coordinator.refreshBridgePaneActivities()
            await harness.coordinator.drainBridgeGitReadActivityPropagation()

            #expect(harness.store.tab(sourceTab.id) == nil)
            #expect(
                harness.store.tab(destinationTab.id)?.allPaneIds
                    .contains(sourcePane.id) == true
            )
            let retainedCompanion = try #require(
                harness.store.panePresentationAtom.zoomCompanion(
                    forSourcePane: sourcePane.id
                )
            )
            #expect(retainedCompanion.companionPaneId == companionPaneId)
            #expect(retainedCompanion.owningTabId == destinationTab.id)
            #expect(
                harness.viewRegistry.allBridgeViews[companionPaneId].map(
                    ObjectIdentifier.init
                ) == retainedHostIdentity
            )
            #expect(
                harness.coordinator.bridgePaneActivity(for: companionPaneId)
                    == .loadedHidden
            )

            await harness.coordinator.shutdown()
        }

        @Test("backgrounding a Zoom source retires its companion but keeps the source pane")
        func backgroundingZoomSourceRetiresCompanionAndKeepsSourcePane() async throws {
            // Arrange
            let owningWindowId = UUID()
            let harness = makeHarness(workspaceWindowId: owningWindowId)
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            let (_, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
            let sourcePane = makeZoomLifecycleSourcePane(
                in: harness.store,
                worktree: worktree
            )
            let sourceTab = Tab(paneId: sourcePane.id)
            harness.store.appendTab(sourceTab)
            harness.store.setActiveTab(sourceTab.id)
            harness.store.setActivePane(sourcePane.id, inTab: sourceTab.id)
            enterZoomLifecycleForegroundEnvironment(
                harness,
                owningWindowId: owningWindowId
            )
            let runtimeCountBeforeZoom = harness.runtimeRegistry.count
            let slotPaneIdsBeforeZoom = harness.viewRegistry.slotPaneIdsForTesting
            harness.controller.execute(.zoomPane)
            let companionPaneId = try #require(
                harness.store.panePresentationAtom.zoomCompanion(
                    forSourcePane: sourcePane.id
                )?.companionPaneId
            )

            // Act
            harness.coordinator.execute(.backgroundPane(paneId: sourcePane.id))
            await harness.coordinator.drainBridgePaneRetirements()
            await harness.coordinator.drainBridgeGitReadActivityPropagation()

            // Assert
            #expect(harness.store.pane(sourcePane.id)?.residency == .backgrounded)
            #expect(harness.store.tab(sourceTab.id) == nil)
            expectZoomLifecycleCompanionRetired(
                ZoomLifecycleCompanionCleanupExpectation(
                    sourcePaneId: sourcePane.id,
                    sourceTabId: sourceTab.id,
                    companionPaneId: companionPaneId,
                    runtimeCountBeforeZoom: runtimeCountBeforeZoom,
                    slotPaneIdsBeforeZoom: slotPaneIdsBeforeZoom
                ),
                in: harness
            )

            await harness.coordinator.shutdown()
        }

        @Test("purging a backgrounded Zoom source retires its companion and removes the source")
        func purgingBackgroundedZoomSourceRetiresCompanionAndRemovesSource() async throws {
            // Arrange
            let owningWindowId = UUID()
            let harness = makeHarness(workspaceWindowId: owningWindowId)
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            let (_, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
            let sourcePane = makeZoomLifecycleSourcePane(
                in: harness.store,
                worktree: worktree
            )
            let siblingPane = makeZoomLifecycleSourcePane(
                in: harness.store,
                worktree: worktree
            )
            let sourceTab = Tab(paneId: sourcePane.id)
            harness.store.appendTab(sourceTab)
            #expect(
                harness.store.insertPane(
                    siblingPane.id,
                    inTab: sourceTab.id,
                    at: sourcePane.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )
            )
            harness.store.setActiveTab(sourceTab.id)
            harness.store.setActivePane(sourcePane.id, inTab: sourceTab.id)
            enterZoomLifecycleForegroundEnvironment(
                harness,
                owningWindowId: owningWindowId
            )
            let runtimeCountBeforeZoom = harness.runtimeRegistry.count
            let slotPaneIdsBeforeZoom = harness.viewRegistry.slotPaneIdsForTesting
            harness.controller.execute(.zoomPane)
            let companionPaneId = try #require(
                harness.store.panePresentationAtom.zoomCompanion(
                    forSourcePane: sourcePane.id
                )?.companionPaneId
            )
            harness.controller.execute(.zoomPane)
            #expect(harness.store.mutationCoordinator.backgroundPane(sourcePane.id))
            #expect(harness.store.pane(sourcePane.id)?.residency == .backgrounded)
            #expect(
                harness.store.panePresentationAtom.zoomCompanion(
                    forSourcePane: sourcePane.id
                )?.companionPaneId == companionPaneId
            )

            // Act
            harness.coordinator.execute(.purgeOrphanedPane(paneId: sourcePane.id))
            await harness.coordinator.drainBridgePaneRetirements()
            await harness.coordinator.drainBridgeGitReadActivityPropagation()

            // Assert
            #expect(harness.store.pane(sourcePane.id) == nil)
            #expect(
                harness.store.tab(sourceTab.id)?.allPaneIds
                    == [siblingPane.id]
            )
            expectZoomLifecycleCompanionRetired(
                ZoomLifecycleCompanionCleanupExpectation(
                    sourcePaneId: sourcePane.id,
                    sourceTabId: sourceTab.id,
                    companionPaneId: companionPaneId,
                    runtimeCountBeforeZoom: runtimeCountBeforeZoom,
                    slotPaneIdsBeforeZoom: slotPaneIdsBeforeZoom
                ),
                in: harness
            )

            await harness.coordinator.shutdown()
        }
    }
}

private struct ZoomLifecycleCompanionCleanupExpectation {
    let sourcePaneId: UUID
    let sourceTabId: UUID
    let companionPaneId: UUID
    let runtimeCountBeforeZoom: Int
    let slotPaneIdsBeforeZoom: Set<UUID>
}

private struct ZoomLifecycleCompanionMoveExpectation {
    let sourcePaneId: UUID
    let sourceTabId: UUID
    let destinationTabId: UUID
    let companionPaneId: UUID
    let retainedHostIdentity: ObjectIdentifier
}

@MainActor
private func expectZoomLifecycleCompanionRetired(
    _ expectation: ZoomLifecycleCompanionCleanupExpectation,
    in harness: PaneTabViewControllerCommandHarness
) {
    #expect(harness.viewRegistry.allBridgeViews[expectation.companionPaneId] == nil)
    #expect(harness.viewRegistry.peekSlotForTesting(expectation.companionPaneId) == nil)
    #expect(
        harness.runtimeRegistry.runtime(
            for: PaneId(existingUUID: expectation.companionPaneId)
        ) == nil
    )
    #expect(harness.runtimeRegistry.count == expectation.runtimeCountBeforeZoom)
    #expect(
        harness.viewRegistry.slotPaneIdsForTesting
            == expectation.slotPaneIdsBeforeZoom
    )
    #expect(
        harness.coordinator.bridgePaneActivityAuthorityIdentity(
            for: expectation.companionPaneId
        ) == nil
    )
    #expect(
        harness.coordinator.bridgePaneActivity(for: expectation.companionPaneId)
            == nil
    )
    #expect(
        harness.store.panePresentationAtom.zoomCompanion(
            forSourcePane: expectation.sourcePaneId
        ) == nil
    )
    #expect(
        harness.store.panePresentationAtom.zoomPresentation(
            forTab: expectation.sourceTabId
        ) == nil
    )
}

@MainActor
private func expectZoomLifecycleCompanionMoved(
    _ expectation: ZoomLifecycleCompanionMoveExpectation,
    in harness: PaneTabViewControllerCommandHarness
) throws {
    #expect(
        harness.store.tab(expectation.sourceTabId)?.allPaneIds
            .contains(expectation.sourcePaneId) == false
    )
    #expect(
        harness.store.tab(expectation.destinationTabId)?.allPaneIds
            .contains(expectation.sourcePaneId) == true
    )
    let movedCompanion = try #require(
        harness.store.panePresentationAtom.zoomCompanion(
            forSourcePane: expectation.sourcePaneId
        )
    )
    #expect(movedCompanion.companionPaneId == expectation.companionPaneId)
    #expect(movedCompanion.owningTabId == expectation.destinationTabId)
    #expect(
        harness.viewRegistry.allBridgeViews[expectation.companionPaneId].map(
            ObjectIdentifier.init
        ) == expectation.retainedHostIdentity
    )
    #expect(
        harness.runtimeRegistry.runtime(
            for: PaneId(existingUUID: expectation.companionPaneId)
        ) != nil
    )
    #expect(
        harness.coordinator.bridgePaneActivity(for: expectation.companionPaneId)
            == .loadedHidden
    )
    #expect(
        harness.store.panePresentationAtom.zoomPresentation(
            forTab: expectation.sourceTabId
        ) == nil
    )
    #expect(
        harness.store.panePresentationAtom.zoomPresentation(
            forTab: expectation.destinationTabId
        ) == nil
    )
}

@MainActor
func makeZoomLifecycleSourcePane(
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
func enterZoomLifecycleForegroundEnvironment(
    _ harness: PaneTabViewControllerCommandHarness,
    owningWindowId: UUID
) {
    harness.coordinator.startBridgePaneActivityObservation()
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
