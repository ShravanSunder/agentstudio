import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

extension WebKitSerializedTests.WorkspaceSurfaceCoordinatorZoomLifecycleTests {
    @Test("Tab A to B to A preserves Zoom and suspends then resumes its companion")
    func tabRoundTripPreservesZoomAndCompanion() async throws {
        let context = makeTwoTabZoomLifecycleContext()
        let harness = context.harness
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        harness.controller.execute(
            .zoomPane,
            target: context.firstPane.id,
            targetType: .pane
        )

        let companionPaneId = try zoomLifecycleCompanionPaneId(
            for: context.firstPane.id,
            in: harness
        )
        let zoomPresentation = try #require(
            harness.store.panePresentationAtom.zoomPresentation(
                forTab: context.firstTab.id
            )
        )
        let hostIdentity = try zoomLifecycleHostIdentity(
            companionPaneId,
            in: harness
        )
        #expect(harness.coordinator.bridgePaneActivity(for: companionPaneId) == .foreground)

        harness.coordinator.execute(.selectTab(tabId: context.secondTab.id))
        harness.coordinator.refreshBridgePaneActivities()
        await harness.coordinator.drainBridgeGitReadActivityPropagation()

        #expect(
            harness.store.panePresentationAtom.zoomPresentation(
                forTab: context.firstTab.id
            ) == zoomPresentation
        )
        #expect(
            try zoomLifecycleHostIdentity(companionPaneId, in: harness)
                == hostIdentity
        )
        #expect(harness.coordinator.bridgePaneActivity(for: companionPaneId) == .loadedHidden)

        harness.coordinator.execute(.selectTab(tabId: context.firstTab.id))
        harness.coordinator.refreshBridgePaneActivities()
        await harness.coordinator.drainBridgeGitReadActivityPropagation()

        #expect(
            harness.store.panePresentationAtom.zoomPresentation(
                forTab: context.firstTab.id
            ) == zoomPresentation
        )
        #expect(
            try zoomLifecycleHostIdentity(companionPaneId, in: harness)
                == hostIdentity
        )
        #expect(harness.coordinator.bridgePaneActivity(for: companionPaneId) == .foreground)

        await harness.coordinator.shutdown()
    }

    @Test("durable arrangement selection preserves Zoom and its retained companion")
    func durableArrangementSelectionPreservesSelectedTabZoom() async throws {
        let context = makeTwoTabZoomLifecycleContext()
        let harness = context.harness
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        harness.controller.execute(
            .zoomPane,
            target: context.firstPane.id,
            targetType: .pane
        )
        let firstCompanionPaneId = try zoomLifecycleCompanionPaneId(
            for: context.firstPane.id,
            in: harness
        )
        let firstHostIdentity = try zoomLifecycleHostIdentity(
            firstCompanionPaneId,
            in: harness
        )
        let firstPresentation = try #require(
            harness.store.panePresentationAtom.zoomPresentation(
                forTab: context.firstTab.id
            )
        )
        harness.controller.execute(
            .zoomPane,
            target: context.secondPane.id,
            targetType: .pane
        )
        let secondPresentation = try #require(
            harness.store.panePresentationAtom.zoomPresentation(
                forTab: context.secondTab.id
            )
        )
        let secondCompanionPaneId = try zoomLifecycleCompanionPaneId(
            for: context.secondPane.id,
            in: harness
        )
        let selectedArrangementId = try #require(
            harness.store.createArrangement(
                name: "Layout 2",
                inTab: context.firstTab.id
            )
        )
        harness.coordinator.execute(.selectTab(tabId: context.firstTab.id))

        harness.coordinator.execute(
            .switchArrangement(
                tabId: context.firstTab.id,
                arrangementId: selectedArrangementId
            )
        )
        harness.coordinator.refreshBridgePaneActivities()
        await harness.coordinator.drainBridgeGitReadActivityPropagation()

        #expect(
            harness.store.panePresentationAtom.zoomPresentation(
                forTab: context.firstTab.id
            ) == firstPresentation
        )
        #expect(
            harness.store.panePresentationAtom.zoomPresentation(
                forTab: context.secondTab.id
            ) == secondPresentation
        )
        #expect(
            try zoomLifecycleHostIdentity(firstCompanionPaneId, in: harness)
                == firstHostIdentity
        )
        #expect(
            harness.coordinator.bridgePaneActivity(for: firstCompanionPaneId)
                == .foreground
        )
        #expect(
            harness.coordinator.bridgePaneActivity(for: secondCompanionPaneId)
                == .loadedHidden
        )

        await harness.coordinator.shutdown()
    }

    @Test("closing a tab retires all of its companions and preserves another tab companion")
    func closingTabRetiresOnlyItsZoomCompanions() async throws {
        let context = makeTwoTabZoomLifecycleContext()
        let harness = context.harness
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let firstTabSecondPane = makeZoomLifecycleSourcePane(
            in: harness.store,
            worktree: context.worktree
        )
        #expect(
            harness.store.insertPane(
                firstTabSecondPane.id,
                inTab: context.firstTab.id,
                at: context.firstPane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
        )

        harness.controller.execute(
            .zoomPane,
            target: context.firstPane.id,
            targetType: .pane
        )
        let firstCompanionPaneId = try zoomLifecycleCompanionPaneId(
            for: context.firstPane.id,
            in: harness
        )
        harness.controller.execute(
            .zoomPane,
            target: firstTabSecondPane.id,
            targetType: .pane
        )
        let secondCompanionPaneId = try zoomLifecycleCompanionPaneId(
            for: firstTabSecondPane.id,
            in: harness
        )
        harness.controller.execute(
            .zoomPane,
            target: context.secondPane.id,
            targetType: .pane
        )
        let retainedCompanionPaneId = try zoomLifecycleCompanionPaneId(
            for: context.secondPane.id,
            in: harness
        )
        let retainedHostIdentity = try zoomLifecycleHostIdentity(
            retainedCompanionPaneId,
            in: harness
        )

        harness.coordinator.execute(.closeTab(tabId: context.firstTab.id))
        await harness.coordinator.drainBridgePaneRetirements()
        await harness.coordinator.drainBridgeGitReadActivityPropagation()

        #expect(harness.store.tab(context.firstTab.id) == nil)
        expectZoomLifecycleResourcesRetired(firstCompanionPaneId, in: harness)
        expectZoomLifecycleResourcesRetired(secondCompanionPaneId, in: harness)
        #expect(
            harness.store.panePresentationAtom.zoomCompanion(
                forSourcePane: context.firstPane.id
            ) == nil
        )
        #expect(
            harness.store.panePresentationAtom.zoomCompanion(
                forSourcePane: firstTabSecondPane.id
            ) == nil
        )
        #expect(
            try zoomLifecycleHostIdentity(retainedCompanionPaneId, in: harness)
                == retainedHostIdentity
        )
        #expect(
            harness.store.panePresentationAtom.zoomCompanion(
                forSourcePane: context.secondPane.id
            )?.companionPaneId == retainedCompanionPaneId
        )
        #expect(
            harness.coordinator.bridgePaneActivity(for: retainedCompanionPaneId)
                == .foreground
        )

        await harness.coordinator.shutdown()
    }

    @Test("coordinator shutdown clears every Zoom resource and presentation")
    func shutdownClearsAllZoomResourcesAndPresentations() async throws {
        let context = makeTwoTabZoomLifecycleContext()
        let harness = context.harness
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let baselineRuntimeCount = harness.runtimeRegistry.count

        harness.controller.execute(
            .zoomPane,
            target: context.firstPane.id,
            targetType: .pane
        )
        let firstCompanionPaneId = try zoomLifecycleCompanionPaneId(
            for: context.firstPane.id,
            in: harness
        )
        harness.controller.execute(
            .zoomPane,
            target: context.secondPane.id,
            targetType: .pane
        )
        let secondCompanionPaneId = try zoomLifecycleCompanionPaneId(
            for: context.secondPane.id,
            in: harness
        )
        _ = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let unavailablePane = harness.store.createPane(
            launchDirectory: harness.tempDir.appending(path: "unavailable")
        )
        let unavailableTab = Tab(paneId: unavailablePane.id)
        harness.store.appendTab(unavailableTab)
        harness.controller.execute(
            .zoomPane,
            target: unavailablePane.id,
            targetType: .pane
        )
        #expect(
            harness.store.panePresentationAtom.zoomPresentation(
                forTab: unavailableTab.id
            )?.viewerPresentation == .unavailable
        )

        await harness.coordinator.shutdown()

        for companionPaneId in [firstCompanionPaneId, secondCompanionPaneId] {
            expectZoomLifecycleResourcesRetired(companionPaneId, in: harness)
        }
        #expect(harness.runtimeRegistry.count == baselineRuntimeCount)
        #expect(harness.store.panePresentationAtom.zoomCompanionsBySourcePaneId.isEmpty)
        #expect(harness.store.panePresentationAtom.zoomPresentationsByTabId.isEmpty)
    }
}

private struct TwoTabZoomLifecycleContext {
    let harness: PaneTabViewControllerCommandHarness
    let worktree: Worktree
    let firstPane: Pane
    let firstTab: Tab
    let secondPane: Pane
    let secondTab: Tab
}

@MainActor
private func makeTwoTabZoomLifecycleContext() -> TwoTabZoomLifecycleContext {
    let owningWindowId = UUID()
    let harness = makeHarness(workspaceWindowId: owningWindowId)
    let (_, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
    let firstPane = makeZoomLifecycleSourcePane(
        in: harness.store,
        worktree: worktree
    )
    let secondPane = makeZoomLifecycleSourcePane(
        in: harness.store,
        worktree: worktree
    )
    let firstTab = Tab(paneId: firstPane.id)
    let secondTab = Tab(paneId: secondPane.id)
    harness.store.appendTab(firstTab)
    harness.store.appendTab(secondTab)
    harness.store.setActiveTab(firstTab.id)
    harness.store.setActivePane(firstPane.id, inTab: firstTab.id)
    enterZoomLifecycleForegroundEnvironment(
        harness,
        owningWindowId: owningWindowId
    )
    return TwoTabZoomLifecycleContext(
        harness: harness,
        worktree: worktree,
        firstPane: firstPane,
        firstTab: firstTab,
        secondPane: secondPane,
        secondTab: secondTab
    )
}

@MainActor
private func zoomLifecycleCompanionPaneId(
    for sourcePaneId: UUID,
    in harness: PaneTabViewControllerCommandHarness
) throws -> UUID {
    try #require(
        harness.store.panePresentationAtom.zoomCompanion(
            forSourcePane: sourcePaneId
        )?.companionPaneId
    )
}

@MainActor
private func zoomLifecycleHostIdentity(
    _ companionPaneId: UUID,
    in harness: PaneTabViewControllerCommandHarness
) throws -> ObjectIdentifier {
    try #require(
        harness.viewRegistry.allBridgeViews[companionPaneId].map(
            ObjectIdentifier.init
        )
    )
}

@MainActor
private func expectZoomLifecycleResourcesRetired(
    _ companionPaneId: UUID,
    in harness: PaneTabViewControllerCommandHarness
) {
    #expect(harness.viewRegistry.allBridgeViews[companionPaneId] == nil)
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
