import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests.WorkspaceSurfaceCoordinatorZoomLifecycleTests {
    @Test("moving an active Zoom source cancels Zoom and transfers retained companion ownership")
    func movePaneCancelsActiveZoomAndTransfersRetainedCompanionOwnership() async throws {
        let context = try makeActiveZoomOwnershipTransitionContext()
        let harness = context.harness
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let destinationPane = makeZoomLifecycleSourcePane(
            in: harness.store,
            worktree: context.worktree
        )
        let destinationTab = Tab(paneId: destinationPane.id)
        harness.store.appendTab(destinationTab)

        harness.coordinator.execute(
            .movePaneAcrossTabs(
                CrossTabPaneMoveRequest(
                    paneId: context.sourcePane.id,
                    sourceTabId: context.sourceTab.id,
                    destTabId: destinationTab.id,
                    targetPaneId: destinationPane.id,
                    direction: .horizontal,
                    position: .after
                )
            )
        )

        let destinationTabId = try await expectZoomOwnershipTransition(
            context,
            in: harness
        )
        #expect(destinationTabId == destinationTab.id)
        #expect(harness.store.tab(context.sourceTab.id) != nil)

        await harness.coordinator.shutdown()
    }

    @Test("extracting an active Zoom source cancels Zoom and transfers retained companion ownership")
    func extractPaneCancelsActiveZoomAndTransfersRetainedCompanionOwnership() async throws {
        let context = try makeActiveZoomOwnershipTransitionContext()
        let harness = context.harness
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        harness.coordinator.execute(
            .extractPaneToTab(
                tabId: context.sourceTab.id,
                paneId: context.sourcePane.id
            )
        )

        let destinationTabId = try await expectZoomOwnershipTransition(
            context,
            in: harness
        )
        #expect(destinationTabId != context.sourceTab.id)
        #expect(harness.store.tab(context.sourceTab.id) != nil)

        await harness.coordinator.shutdown()
    }

    @Test("breaking up an active Zoom tab cancels Zoom and transfers retained companion ownership")
    func breakUpTabCancelsActiveZoomAndTransfersRetainedCompanionOwnership() async throws {
        let context = try makeActiveZoomOwnershipTransitionContext()
        let harness = context.harness
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        harness.coordinator.execute(.breakUpTab(tabId: context.sourceTab.id))

        let destinationTabId = try await expectZoomOwnershipTransition(
            context,
            in: harness
        )
        #expect(destinationTabId != context.sourceTab.id)
        #expect(harness.store.tab(context.sourceTab.id) == nil)

        await harness.coordinator.shutdown()
    }

    @Test("merging an active Zoom tab cancels Zoom and transfers retained companion ownership")
    func mergeTabCancelsActiveZoomAndTransfersRetainedCompanionOwnership() async throws {
        let context = try makeActiveZoomOwnershipTransitionContext()
        let harness = context.harness
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let targetPane = makeZoomLifecycleSourcePane(
            in: harness.store,
            worktree: context.worktree
        )
        let targetTab = Tab(paneId: targetPane.id)
        harness.store.appendTab(targetTab)

        harness.coordinator.execute(
            .mergeTab(
                sourceTabId: context.sourceTab.id,
                targetTabId: targetTab.id,
                targetPaneId: targetPane.id,
                direction: .right
            )
        )

        let destinationTabId = try await expectZoomOwnershipTransition(
            context,
            in: harness
        )
        #expect(destinationTabId == targetTab.id)
        #expect(harness.store.tab(context.sourceTab.id) == nil)

        await harness.coordinator.shutdown()
    }

    @Test("extracting a canceled Zoom source transfers its retained companion ownership")
    func extractPaneTransfersRetainedZoomCompanionOwnership() async throws {
        let context = try makeCanceledZoomOwnershipTransitionContext()
        let harness = context.harness
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        harness.coordinator.execute(
            .extractPaneToTab(
                tabId: context.sourceTab.id,
                paneId: context.sourcePane.id
            )
        )

        let destinationTabId = try await expectZoomOwnershipTransition(
            context,
            in: harness
        )
        #expect(destinationTabId != context.sourceTab.id)
        #expect(harness.store.tab(context.sourceTab.id) != nil)

        await harness.coordinator.shutdown()
    }

    @Test("breaking up a canceled Zoom tab transfers retained companion ownership")
    func breakUpTabTransfersRetainedZoomCompanionOwnership() async throws {
        let context = try makeCanceledZoomOwnershipTransitionContext()
        let harness = context.harness
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        harness.coordinator.execute(.breakUpTab(tabId: context.sourceTab.id))

        let destinationTabId = try await expectZoomOwnershipTransition(
            context,
            in: harness
        )
        #expect(destinationTabId != context.sourceTab.id)
        #expect(harness.store.tab(context.sourceTab.id) == nil)

        await harness.coordinator.shutdown()
    }

    @Test("merging a canceled Zoom tab transfers retained companion ownership")
    func mergeTabTransfersRetainedZoomCompanionOwnership() async throws {
        let context = try makeCanceledZoomOwnershipTransitionContext()
        let harness = context.harness
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let targetPane = makeZoomLifecycleSourcePane(
            in: harness.store,
            worktree: context.worktree
        )
        let targetTab = Tab(paneId: targetPane.id)
        harness.store.appendTab(targetTab)

        harness.coordinator.execute(
            .mergeTab(
                sourceTabId: context.sourceTab.id,
                targetTabId: targetTab.id,
                targetPaneId: targetPane.id,
                direction: .right
            )
        )

        let destinationTabId = try await expectZoomOwnershipTransition(
            context,
            in: harness
        )
        #expect(destinationTabId == targetTab.id)
        #expect(harness.store.tab(context.sourceTab.id) == nil)

        await harness.coordinator.shutdown()
    }
}

private struct ZoomOwnershipTransitionContext {
    let harness: PaneTabViewControllerCommandHarness
    let worktree: Worktree
    let sourcePane: Pane
    let sourceTab: Tab
    let companionPaneId: UUID
    let companionHostIdentity: ObjectIdentifier
}

@MainActor
private func makeActiveZoomOwnershipTransitionContext() throws
    -> ZoomOwnershipTransitionContext
{
    try makeZoomOwnershipTransitionContext(cancelZoomBeforeTransition: false)
}

@MainActor
private func makeCanceledZoomOwnershipTransitionContext() throws
    -> ZoomOwnershipTransitionContext
{
    try makeZoomOwnershipTransitionContext(cancelZoomBeforeTransition: true)
}

@MainActor
private func makeZoomOwnershipTransitionContext(
    cancelZoomBeforeTransition: Bool
) throws -> ZoomOwnershipTransitionContext {
    let owningWindowId = UUID()
    let harness = makeHarness(workspaceWindowId: owningWindowId)
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

    harness.controller.execute(
        .zoomPane,
        target: sourcePane.id,
        targetType: .pane
    )
    let companionPaneId = try #require(
        harness.store.panePresentationAtom.zoomCompanion(
            forSourcePane: sourcePane.id
        )?.companionPaneId
    )
    let companionHostIdentity = try #require(
        harness.viewRegistry.allBridgeViews[companionPaneId].map(
            ObjectIdentifier.init
        )
    )
    if cancelZoomBeforeTransition {
        harness.controller.execute(
            .zoomPane,
            target: sourcePane.id,
            targetType: .pane
        )
        #expect(
            harness.store.panePresentationAtom.zoomPresentation(
                forTab: sourceTab.id
            ) == nil
        )
        #expect(
            harness.coordinator.bridgePaneActivity(for: companionPaneId)
                == .loadedHidden
        )
    } else {
        let presentation = try #require(
            harness.store.panePresentationAtom.zoomPresentation(
                forTab: sourceTab.id
            )
        )
        #expect(presentation.sourcePaneId == sourcePane.id)
        #expect(
            presentation.viewerPresentation.companionPaneId
                == companionPaneId
        )
    }

    return ZoomOwnershipTransitionContext(
        harness: harness,
        worktree: worktree,
        sourcePane: sourcePane,
        sourceTab: sourceTab,
        companionPaneId: companionPaneId,
        companionHostIdentity: companionHostIdentity
    )
}

@MainActor
private func expectZoomOwnershipTransition(
    _ context: ZoomOwnershipTransitionContext,
    in harness: PaneTabViewControllerCommandHarness
) async throws -> UUID {
    harness.coordinator.refreshBridgePaneActivities()
    await harness.coordinator.drainBridgeGitReadActivityPropagation()

    #expect(harness.store.paneAtom.pane(context.sourcePane.id) != nil)
    let destinationTabId = try #require(
        harness.store.tabLayoutAtom.tabContaining(
            paneId: context.sourcePane.id
        )?.id
    )
    let retainedCompanion = try #require(
        harness.store.panePresentationAtom.zoomCompanion(
            forSourcePane: context.sourcePane.id
        )
    )
    #expect(retainedCompanion.companionPaneId == context.companionPaneId)
    #expect(retainedCompanion.owningTabId == destinationTabId)
    #expect(
        harness.viewRegistry.allBridgeViews[context.companionPaneId].map(
            ObjectIdentifier.init
        ) == context.companionHostIdentity
    )
    #expect(
        harness.runtimeRegistry.runtime(
            for: PaneId(existingUUID: context.companionPaneId)
        ) != nil
    )
    #expect(
        harness.coordinator.bridgePaneActivity(
            for: context.companionPaneId
        ) == .loadedHidden
    )
    #expect(
        harness.store.panePresentationAtom.zoomPresentation(
            forTab: context.sourceTab.id
        ) == nil
    )
    #expect(
        harness.store.panePresentationAtom.zoomPresentation(
            forTab: destinationTabId
        ) == nil
    )
    for (tabId, presentation) in harness.store.panePresentationAtom.zoomPresentationsByTabId {
        #expect(
            harness.store.tabLayoutAtom.tabContaining(
                paneId: presentation.sourcePaneId
            )?.id == tabId
        )
    }
    return destinationTabId
}
