import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
extension WorkspaceGeometryReevaluationIntegrationTests {
    @Test
    func heldPreviewDeferredBackgroundTargetRequeuesTrustedGeometryThroughPreparedOwner() async throws {
        try await withGeometryReevaluationHarness { harness in
            let activePane = harness.store.createPane(provider: .zmx)
            let deferredPane = harness.store.createPane(provider: .zmx)
            let activeTab = Tab(paneId: activePane.id, name: "Active")
            let deferredTab = Tab(paneId: deferredPane.id, name: "Deferred")
            harness.store.appendTab(activeTab)
            harness.store.appendTab(deferredTab)
            harness.store.setActiveTab(activeTab.id)
            harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
            let mounted = try await mountGeometryReevaluationCohort(
                coordinator: harness.coordinator,
                viewRegistry: harness.viewRegistry,
                entries: [
                    (activePane, .activeVisible, .tab(tabID: activeTab.id)),
                    (deferredPane, .hidden, .tab(tabID: deferredTab.id)),
                ],
                eligiblePaneIDs: [PaneId(existingUUID: activePane.id)],
                trustedBounds: trustedBounds
            )
            let deferredPaneID = PaneId(existingUUID: deferredPane.id)
            #expect(
                harness.viewRegistry.preparedContentMountState(
                    for: deferredPaneID,
                    generation: mounted.generation
                ) == .deferredGeometry(owner: .terminal)
            )

            var reevaluationCallCount = 0
            var reevaluatedFrames: [PaneId: NSRect] = [:]
            harness.coordinator.preparedTerminalGeometryReevaluationHandler = { framesByPaneID in
                reevaluationCallCount += 1
                reevaluatedFrames = framesByPaneID
            }
            let heldState = HeldPanePreviewState()
            harness.coordinator.bindHeldPanePreviewState(heldState)
            let target = ValidatedPanePreviewTarget(
                paneID: deferredPane.id,
                owningTabID: deferredTab.id,
                provider: deferredPane.provider,
                sessionID: deferredPane.terminalState?.zmxSessionID
            )
            #expect(heldState.beginSpaceHold(requestedTarget: target))

            let deferredReevaluation = try #require(
                harness.coordinator.prepareHeldPanePreview()
            )
            await deferredReevaluation.value

            #expect(reevaluationCallCount == 1)
            #expect(reevaluatedFrames[deferredPaneID] == trustedBounds)
            #expect(
                harness.viewRegistry.preparedContentMountState(
                    for: deferredPaneID,
                    generation: mounted.generation
                ) == .deferredGeometry(owner: .terminal)
            )
            #expect(harness.surfaceManager.createdPaneIds.contains(deferredPane.id) == false)
            withExtendedLifetime(mounted) {}
        }
    }

    @Test
    func heldPreviewDeferredGeometryDoesNotRequeueAReplacementGeneration() async throws {
        try await withGeometryReevaluationHarness { harness in
            let activePane = harness.store.createPane(provider: .zmx)
            let deferredPane = harness.store.createPane(provider: .zmx)
            let activeTab = Tab(paneId: activePane.id, name: "Active")
            let deferredTab = Tab(paneId: deferredPane.id, name: "Deferred")
            harness.store.appendTab(activeTab)
            harness.store.appendTab(deferredTab)
            harness.store.setActiveTab(activeTab.id)
            harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
            let mounted = try await mountGeometryReevaluationCohort(
                coordinator: harness.coordinator,
                viewRegistry: harness.viewRegistry,
                entries: [
                    (activePane, .activeVisible, .tab(tabID: activeTab.id)),
                    (deferredPane, .hidden, .tab(tabID: deferredTab.id)),
                ],
                eligiblePaneIDs: [PaneId(existingUUID: activePane.id)],
                trustedBounds: trustedBounds
            )
            let deferredPaneID = PaneId(existingUUID: deferredPane.id)
            var reevaluationCallCount = 0
            harness.coordinator.preparedTerminalGeometryReevaluationHandler = { _ in
                reevaluationCallCount += 1
            }
            let heldState = HeldPanePreviewState()
            harness.coordinator.bindHeldPanePreviewState(heldState)
            let target = ValidatedPanePreviewTarget(
                paneID: deferredPane.id,
                owningTabID: deferredTab.id,
                provider: deferredPane.provider,
                sessionID: deferredPane.terminalState?.zmxSessionID
            )
            #expect(heldState.beginSpaceHold(requestedTarget: target))
            let deferredReevaluation = try #require(
                harness.coordinator.prepareHeldPanePreview()
            )

            let successorGeneration = WorkspaceContentMountGeneration()
            let successorDescriptor = try geometryReevaluationTerminalDescriptor(
                pane: deferredPane,
                visibilityPriority: .hidden,
                hostPlacement: .tab(tabID: deferredTab.id)
            )
            harness.viewRegistry.installPreparedContentMountCohort(
                WorkspacePreparedContentMountCohort(
                    generation: successorGeneration,
                    terminalActivationInput: TerminalActivationInput(entries: [successorDescriptor]),
                    nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
                )
            )
            #expect(
                harness.viewRegistry.deferPreparedContentMount(
                    paneID: deferredPaneID,
                    owner: .terminal,
                    generation: successorGeneration
                )
            )
            harness.coordinator.acceptedPreparedContentMountGeneration = successorGeneration
            await deferredReevaluation.value

            #expect(reevaluationCallCount == 0)
            withExtendedLifetime(mounted) {}
        }
    }

    private func assertDeferredPreviewRequeueIsSuppressed(
        _ mutate:
            @MainActor (
                Harness,
                HeldPanePreviewState,
                ValidatedPanePreviewTarget
            ) -> Void
    ) async throws {
        try await withGeometryReevaluationHarness { harness in
            let activePane = harness.store.createPane(provider: .zmx)
            let deferredPane = harness.store.createPane(provider: .zmx)
            let activeTab = Tab(paneId: activePane.id, name: "Active")
            let deferredTab = Tab(paneId: deferredPane.id, name: "Deferred")
            harness.store.appendTab(activeTab)
            harness.store.appendTab(deferredTab)
            harness.store.setActiveTab(activeTab.id)
            harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
            let mounted = try await mountGeometryReevaluationCohort(
                coordinator: harness.coordinator,
                viewRegistry: harness.viewRegistry,
                entries: [
                    (activePane, .activeVisible, .tab(tabID: activeTab.id)),
                    (deferredPane, .hidden, .tab(tabID: deferredTab.id)),
                ],
                eligiblePaneIDs: [PaneId(existingUUID: activePane.id)],
                trustedBounds: trustedBounds
            )
            var reevaluationCallCount = 0
            harness.coordinator.preparedTerminalGeometryReevaluationHandler = { _ in
                reevaluationCallCount += 1
            }
            let heldState = HeldPanePreviewState()
            harness.coordinator.bindHeldPanePreviewState(heldState)
            let target = ValidatedPanePreviewTarget(
                paneID: deferredPane.id,
                owningTabID: deferredTab.id,
                provider: deferredPane.provider,
                sessionID: deferredPane.terminalState?.zmxSessionID
            )
            #expect(heldState.beginSpaceHold(requestedTarget: target))
            let deferredReevaluation = try #require(
                harness.coordinator.prepareHeldPanePreview()
            )

            mutate(harness, heldState, target)
            await deferredReevaluation.value

            #expect(reevaluationCallCount == 0)
            #expect(harness.surfaceManager.createdPaneIds.contains(deferredPane.id) == false)
            withExtendedLifetime(mounted) {}
        }
    }

    @Test
    func heldPreviewDeferredGeometryRejectsLateReleaseRequeue() async throws {
        try await assertDeferredPreviewRequeueIsSuppressed { _, heldState, _ in
            heldState.endSpaceHold()
        }
    }

    @Test
    func heldPreviewDeferredGeometryRejectsLateTargetIdentityRequeue() async throws {
        try await assertDeferredPreviewRequeueIsSuppressed { _, heldState, target in
            heldState.updateRequestedTarget(
                ValidatedPanePreviewTarget(
                    paneID: target.paneID,
                    owningTabID: target.owningTabID,
                    provider: .ghostty,
                    sessionID: nil
                )
            )
        }
    }

    @Test
    func heldPreviewDeferredGeometryRejectsLateBoundsRequeue() async throws {
        try await assertDeferredPreviewRequeueIsSuppressed { harness, _, _ in
            harness.windowLifecycleStore.recordTerminalContainerBounds(
                CGRect(x: 0, y: 0, width: 1200, height: 700)
            )
        }
    }

}
