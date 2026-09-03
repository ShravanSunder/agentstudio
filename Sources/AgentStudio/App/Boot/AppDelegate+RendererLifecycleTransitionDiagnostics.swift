import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTerminal
import AppKit
import Foundation
import GhosttyKit

#if DEBUG
    private func rendererLifecycleViewportReadContains(
        _ result: TerminalViewportTextReadResult,
        marker: String
    ) -> Bool {
        guard case .value(let text) = result else { return false }
        return text.contains(marker)
    }

    struct RendererLifecycleDeliveryValidation {
        static func isExact(
            before: [UUID: Bool],
            after: [UUID: Bool],
            desired: [UUID: Bool],
            visibilityDeliveryDelta: Int,
            projectionChangedSurfaceDelta: Int
        ) -> Bool {
            guard before.keys == desired.keys,
                after == desired
            else { return false }
            let expectedChangedCount = desired.count { paneID, desiredVisibility in
                before[paneID] != desiredVisibility
            }
            return expectedChangedCount > 0
                && visibilityDeliveryDelta == expectedChangedCount
                && projectionChangedSurfaceDelta == expectedChangedCount
        }
    }

    @MainActor
    extension AppDelegate {
        func exerciseRendererLifecycleTransitions(
            _ fixture: RendererLifecycleContinuityFixture,
            initialSurfaceIDs: [UUID: UUID],
            initialSessionIDs: [UUID: ZmxSessionID]
        ) async -> (succeeded: Bool, reason: String) {
            var result = await exerciseRendererLifecycleHiddenOutput(
                fixture,
                initialSurfaceIDs: initialSurfaceIDs
            )
            guard result.succeeded else { return result }
            result = await exerciseRendererLifecycleStructuralProjection(fixture)
            guard result.succeeded else { return result }
            result = await exerciseRendererLifecycleZoom(fixture)
            guard result.succeeded else { return result }
            result = verifyRendererLifecycleTemporarySurfaceIdentity(
                fixture,
                initialSurfaceIDs: initialSurfaceIDs
            )
            guard result.succeeded else { return result }
            result = await exerciseRendererLifecycleWindowTransitions(
                fixture,
                initialSurfaceIDs: initialSurfaceIDs,
                initialSessionIDs: initialSessionIDs
            )
            guard result.succeeded else { return result }
            result = await exerciseRendererLifecycleRepairs(fixture)
            guard result.succeeded else { return result }
            result = await exerciseRendererLifecycleCloseRetention(
                fixture,
                expectedSessionID: initialSessionIDs[fixture.retentionPaneID]
            )
            guard result.succeeded else { return result }
            result = verifyRendererLifecycleFinalState(fixture, initialSessionIDs: initialSessionIDs)
            guard result.succeeded else { return result }
            return (true, "none")
        }

        private func exerciseRendererLifecycleHiddenOutput(
            _ fixture: RendererLifecycleContinuityFixture,
            initialSurfaceIDs: [UUID: UUID]
        ) async -> (succeeded: Bool, reason: String) {
            let projectionBaseline = performanceTraceRecorder.rendererLifecycleSnapshot().projectionEvaluationTotal
            guard executor.execute(.selectTab(tabId: fixture.secondTabID)) else {
                return (false, "tab_hide_failed")
            }
            guard
                await waitForRendererLifecycleCondition(
                    timeout: .seconds(10),
                    {
                        self.performanceTraceRecorder.rendererLifecycleSnapshot().projectionEvaluationTotal
                            > projectionBaseline
                    })
            else { return (false, "tab_hide_not_reconciled") }
            let hiddenOutputMarker = "renderer-hidden-output-complete"
            guard let hiddenSurfaceID = initialSurfaceIDs[fixture.repairPaneID] else {
                return (false, "hidden_surface_identity_missing")
            }
            guard
                viewRegistry.terminalView(for: fixture.repairPaneID)?.ghosttySurface?
                    .requestManagedFocus(true) == false
            else { return (false, "hidden_focus_was_granted") }
            guard
                case .success = SurfaceManager.shared.sendInput(
                    "printf 'cmVuZGVyZXItaGlkZGVuLW91dHB1dC1jb21wbGV0ZQ==' | /usr/bin/base64 -D; printf '\\n'\n",
                    toPaneId: fixture.repairPaneID
                )
            else { return (false, "hidden_output_send_failed") }
            guard
                await waitForRendererLifecycleCondition(
                    timeout: .seconds(10),
                    {
                        rendererLifecycleViewportReadContains(
                            SurfaceManager.shared.readViewportTrailingText(forSurfaceID: hiddenSurfaceID),
                            marker: hiddenOutputMarker
                        )
                    })
            else { return (false, "hidden_output_not_observed") }
            let revealSnapshot = performanceTraceRecorder.rendererLifecycleSnapshot()
            guard executor.execute(.selectTab(tabId: fixture.firstTabID)) else {
                return (false, "tab_reveal_failed")
            }
            guard
                await waitForRendererLifecycleProjection(
                    after: revealSnapshot.projectionEvaluationTotal,
                    requiringVisibilityDeliveryAfter: revealSnapshot.visibilityDeliveryTotal
                )
            else { return (false, "tab_reveal_not_reconciled") }
            guard viewRegistry.terminalView(for: fixture.repairPaneID)?.surfaceId == hiddenSurfaceID else {
                return (false, "tab_surface_identity_changed")
            }
            guard
                rendererLifecycleViewportReadContains(
                    SurfaceManager.shared.readViewportTrailingText(forSurfaceID: hiddenSurfaceID),
                    marker: hiddenOutputMarker
                )
            else { return (false, "hidden_output_readback_failed") }
            return (true, "none")
        }

        private func exerciseRendererLifecycleStructuralProjection(
            _ fixture: RendererLifecycleContinuityFixture
        ) async -> (succeeded: Bool, reason: String) {
            guard !store.paneAtom.isDrawerExpanded(for: fixture.drawerParentID) else {
                return (false, "drawer_fixture_initially_expanded")
            }
            let actions: [(name: String, command: WorkspaceActionCommand)] = [
                ("drawer_open", .toggleDrawer(paneId: fixture.drawerParentID)),
                ("drawer_close", .toggleDrawer(paneId: fixture.drawerParentID)),
                ("drawer_reopen", .toggleDrawer(paneId: fixture.drawerParentID)),
                (
                    "arrangement_alternate",
                    .switchArrangement(tabId: fixture.firstTabID, arrangementId: fixture.secondArrangementID)
                ),
                (
                    "arrangement_default",
                    .switchArrangement(tabId: fixture.firstTabID, arrangementId: fixture.firstArrangementID)
                ),
                ("pane_minimize", .minimizePane(tabId: fixture.firstTabID, paneId: fixture.zoomPaneIDs[0])),
                ("pane_expand", .expandPane(tabId: fixture.firstTabID, paneId: fixture.zoomPaneIDs[0])),
                (
                    "drawer_pane_minimize",
                    .minimizeDrawerPane(
                        parentPaneId: fixture.drawerParentID,
                        drawerPaneId: fixture.drawerPaneIDs[0]
                    )
                ),
                (
                    "drawer_pane_expand",
                    .expandDrawerPane(
                        parentPaneId: fixture.drawerParentID,
                        drawerPaneId: fixture.drawerPaneIDs[0]
                    )
                ),
            ]
            for action in actions {
                let snapshot = performanceTraceRecorder.rendererLifecycleSnapshot()
                guard executor.execute(action.command) else {
                    return (false, "projection_action_rejected_\(action.name)")
                }
                guard
                    await waitForRendererLifecycleCondition(
                        timeout: .seconds(5),
                        {
                            self.rendererLifecycleProjectionAdvanced(after: snapshot)
                        })
                else {
                    return (false, "projection_action_not_reconciled_\(action.name)")
                }
            }
            guard store.paneAtom.isDrawerExpanded(for: fixture.drawerParentID) else {
                return (false, "drawer_fixture_not_expanded")
            }
            guard
                await executeRendererLifecycleSoakAction(
                    .backgroundPane(paneId: fixture.backgroundPaneID),
                    until: {
                        self.store.paneAtom.pane(fixture.backgroundPaneID)?.residency == .backgrounded
                    })
            else {
                return (false, "background_failed")
            }
            guard
                await executeRendererLifecycleSoakAction(
                    .reactivatePane(
                        paneId: fixture.backgroundPaneID,
                        targetTabId: fixture.firstTabID,
                        targetPaneId: fixture.zoomPaneIDs[0],
                        direction: .right
                    ),
                    until: {
                        self.store.paneAtom.pane(fixture.backgroundPaneID)?.residency == .active
                    })
            else { return (false, "reactivate_failed") }
            return (true, "none")
        }

        private func exerciseRendererLifecycleZoom(
            _ fixture: RendererLifecycleContinuityFixture
        ) async -> (succeeded: Bool, reason: String) {
            guard let controller = paneTabViewController() else { return (false, "tab_controller_missing") }
            var snapshot = performanceTraceRecorder.rendererLifecycleSnapshot()
            controller.execute(.zoomPane, target: fixture.zoomPaneIDs[0], targetType: .pane)
            guard
                await waitForRendererLifecycleProjection(
                    after: snapshot.projectionEvaluationTotal,
                    requiringVisibilityDeliveryAfter: snapshot.visibilityDeliveryTotal
                ),
                store.panePresentationAtom.zoomCompanion(forSourcePane: fixture.zoomPaneIDs[0]) != nil
            else {
                return (false, "zoom_companion_missing")
            }
            snapshot = performanceTraceRecorder.rendererLifecycleSnapshot()
            controller.execute(.zoomPane, target: fixture.zoomPaneIDs[1], targetType: .pane)
            guard
                await waitForRendererLifecycleProjection(
                    after: snapshot.projectionEvaluationTotal,
                    requiringVisibilityDeliveryAfter: snapshot.visibilityDeliveryTotal
                ),
                store.panePresentationAtom.zoomCompanion(forSourcePane: fixture.zoomPaneIDs[1]) != nil
            else {
                return (false, "zoom_retarget_companion_missing")
            }
            snapshot = performanceTraceRecorder.rendererLifecycleSnapshot()
            controller.execute(.zoomPane, target: fixture.zoomPaneIDs[1], targetType: .pane)
            guard
                await waitForRendererLifecycleProjection(
                    after: snapshot.projectionEvaluationTotal,
                    requiringVisibilityDeliveryAfter: snapshot.visibilityDeliveryTotal
                )
            else { return (false, "zoom_exit_not_reconciled") }
            return (true, "none")
        }

        private func verifyRendererLifecycleTemporarySurfaceIdentity(
            _ fixture: RendererLifecycleContinuityFixture,
            initialSurfaceIDs: [UUID: UUID]
        ) -> (succeeded: Bool, reason: String) {
            let currentSurfaceIDs = rendererLifecycleSurfaceIDs(for: fixture.paneIDs)
            guard currentSurfaceIDs.count == fixture.paneIDs.count else {
                return (false, "transition_surface_identity_missing")
            }
            guard fixture.paneIDs.allSatisfy({ currentSurfaceIDs[$0] == initialSurfaceIDs[$0] }) else {
                return (false, "temporary_transition_replaced_surface")
            }
            return (true, "none")
        }

        private func exerciseRendererLifecycleWindowTransitions(
            _ fixture: RendererLifecycleContinuityFixture,
            initialSurfaceIDs: [UUID: UUID],
            initialSessionIDs: [UUID: ZmxSessionID]
        ) async -> (succeeded: Bool, reason: String) {
            guard let window = mainWindowController?.window else { return (false, "window_missing") }
            guard windowLifecycleStore.registeredWindowIds.count == 1,
                let workspaceWindowID = windowLifecycleStore.registeredWindowIds.first
            else { return (false, "workspace_window_identity_missing") }
            guard var checkpoint = rendererLifecycleDeliveryCheckpoint(initialSurfaceIDs),
                let initialFacts = windowLifecycleStore.presentationFacts(for: workspaceWindowID)
            else { return (false, "window_checkpoint_missing") }
            let identitiesAreStable = {
                self.rendererLifecycleSurfaceIDs(for: fixture.paneIDs) == initialSurfaceIDs
                    && self.rendererLifecycleSessionIDs(for: fixture.paneIDs) == initialSessionIDs
            }
            window.orderOut(nil)
            guard
                let postOrderOutFacts = windowLifecycleStore.presentationFacts(for: workspaceWindowID),
                !postOrderOutFacts.isVisible,
                postOrderOutFacts.isMiniaturized == initialFacts.isMiniaturized,
                identitiesAreStable()
            else { return (false, "order_out_not_observed") }
            guard
                await waitForExactRendererLifecycleDelivery(
                    checkpoint,
                    surfaceIDs: initialSurfaceIDs,
                    until: {
                        guard let facts = self.windowLifecycleStore.presentationFacts(for: workspaceWindowID) else {
                            return false
                        }
                        return !facts.isVisible
                            && facts.isMiniaturized == initialFacts.isMiniaturized
                            && identitiesAreStable()
                    })
            else { return (false, "order_out_not_observed") }
            guard let orderFrontCheckpoint = rendererLifecycleDeliveryCheckpoint(initialSurfaceIDs) else {
                return (false, "window_checkpoint_missing")
            }
            checkpoint = orderFrontCheckpoint
            window.orderFront(nil)
            guard
                let postOrderFrontFacts = windowLifecycleStore.presentationFacts(for: workspaceWindowID),
                postOrderFrontFacts.isVisible,
                postOrderFrontFacts.isMiniaturized == initialFacts.isMiniaturized,
                identitiesAreStable()
            else { return (false, "order_front_not_observed") }
            guard
                await waitForExactRendererLifecycleDelivery(
                    checkpoint,
                    surfaceIDs: initialSurfaceIDs,
                    until: {
                        guard let facts = self.windowLifecycleStore.presentationFacts(for: workspaceWindowID) else {
                            return false
                        }
                        return facts.isVisible
                            && facts.isMiniaturized == initialFacts.isMiniaturized
                            && facts.isOccluded == initialFacts.isOccluded
                            && identitiesAreStable()
                    })
            else { return (false, "order_front_not_observed") }
            guard let minimizeCheckpoint = rendererLifecycleDeliveryCheckpoint(initialSurfaceIDs) else {
                return (false, "window_checkpoint_missing")
            }
            checkpoint = minimizeCheckpoint
            window.miniaturize(nil)
            guard
                await waitForExactRendererLifecycleDelivery(
                    checkpoint,
                    surfaceIDs: initialSurfaceIDs,
                    until: {
                        self.windowLifecycleStore.presentationFacts(for: workspaceWindowID)?.isMiniaturized == true
                            && identitiesAreStable()
                    })
            else { return (false, "miniaturize_not_observed") }
            guard let restoreCheckpoint = rendererLifecycleDeliveryCheckpoint(initialSurfaceIDs) else {
                return (false, "window_checkpoint_missing")
            }
            checkpoint = restoreCheckpoint
            window.deminiaturize(nil)
            guard
                await waitForExactRendererLifecycleDelivery(
                    checkpoint,
                    surfaceIDs: initialSurfaceIDs,
                    until: {
                        self.windowLifecycleStore.presentationFacts(for: workspaceWindowID)?.isMiniaturized == false
                            && identitiesAreStable()
                    })
            else { return (false, "deminiaturize_not_observed") }
            return (true, "none")
        }

        func exerciseRendererLifecycleSoakTransitionCycles(
            _ fixture: RendererLifecycleContinuityFixture,
            action: AgentStudioStartupDiagnosticAction,
            surfaceIDs: [UUID: UUID]
        ) async -> (succeeded: Bool, reason: String) {
            for scenario in RendererLifecycleSoakSchedule.transitionScenarios {
                for completedCount in 1...RendererLifecycleSoakSchedule.transitionCycleCount {
                    let result = await exerciseRendererLifecycleSoakTransition(
                        scenario,
                        fixture: fixture,
                        surfaceIDs: surfaceIDs
                    )
                    guard result.succeeded else { return result }
                    recordRendererLifecycleDiagnosticProgress(
                        action: action,
                        stage: "scenario_progress",
                        scenario: scenario,
                        completedCount: completedCount,
                        expectedCount: RendererLifecycleSoakSchedule.transitionCycleCount
                    )
                }
                recordRendererLifecycleDiagnosticProgress(
                    action: action,
                    stage: "scenario_completed",
                    scenario: scenario,
                    completedCount: RendererLifecycleSoakSchedule.transitionCycleCount,
                    expectedCount: RendererLifecycleSoakSchedule.transitionCycleCount
                )
            }
            return (true, "none")
        }

        func verifyRendererLifecycleSoakDeliveryCardinality(
            _ fixture: RendererLifecycleContinuityFixture,
            action: AgentStudioStartupDiagnosticAction,
            surfaceIDs: [UUID: UUID]
        ) async -> (succeeded: Bool, reason: String) {
            let equalBaseline = performanceTraceRecorder.rendererLifecycleSnapshot()
            let equalResult = workspaceSurfaceCoordinator.surfaceManager.reconcileAttachedVisibility { paneID in
                self.workspaceSurfaceCoordinator.effectiveRendererVisibility(forAttachedPaneID: paneID)
            }
            let equalSnapshot = performanceTraceRecorder.rendererLifecycleSnapshot()
            guard equalResult.applied == 0,
                equalResult.equal == RendererLifecycleSoakSchedule.surfaceCount,
                equalResult.missing == 0,
                equalResult.failed == 0,
                equalSnapshot.visibilityDeliveryTotal == equalBaseline.visibilityDeliveryTotal,
                equalSnapshot.visibilityEqualSuppressedTotal - equalBaseline.visibilityEqualSuppressedTotal
                    == RendererLifecycleSoakSchedule.surfaceCount
            else { return (false, "equal_reconciliation_cardinality_failed") }
            recordRendererLifecycleDiagnosticProgress(
                action: action,
                stage: "equal_reconciliation_verified",
                completedCount: RendererLifecycleSoakSchedule.surfaceCount,
                expectedCount: RendererLifecycleSoakSchedule.surfaceCount
            )

            guard
                let firstChangedCount = await verifyRendererLifecycleTabSwitchDeliveryCardinality(
                    to: fixture.secondTabID,
                    fixture: fixture,
                    surfaceIDs: surfaceIDs
                ),
                let secondChangedCount = await verifyRendererLifecycleTabSwitchDeliveryCardinality(
                    to: fixture.firstTabID,
                    fixture: fixture,
                    surfaceIDs: surfaceIDs
                )
            else { return (false, "changed_delivery_cardinality_failed") }
            let totalChangedCount = firstChangedCount + secondChangedCount
            let expectedChangedCount = RendererLifecycleSoakSchedule.surfaceCount * 2
            guard totalChangedCount == expectedChangedCount else {
                return (false, "changed_delivery_total_failed")
            }
            recordRendererLifecycleDiagnosticProgress(
                action: action,
                stage: "changed_delivery_verified",
                completedCount: totalChangedCount,
                expectedCount: expectedChangedCount
            )
            return (true, "none")
        }

        private func verifyRendererLifecycleTabSwitchDeliveryCardinality(
            to tabID: UUID,
            fixture: RendererLifecycleContinuityFixture,
            surfaceIDs: [UUID: UUID]
        ) async -> Int? {
            guard let before = rendererLifecycleDeliveredVisibilityByPaneID(surfaceIDs) else {
                return nil
            }
            let baseline = performanceTraceRecorder.rendererLifecycleSnapshot()
            guard executor.execute(.selectTab(tabId: tabID)) else { return nil }
            guard
                await waitForRendererLifecycleCondition(
                    timeout: .seconds(5),
                    {
                        self.store.tabLayoutAtom.activeTabId == tabID
                            && self.performanceTraceRecorder.rendererLifecycleSnapshot().projectionEvaluationTotal
                                > baseline.projectionEvaluationTotal
                    })
            else { return nil }
            guard let after = rendererLifecycleDeliveredVisibilityByPaneID(surfaceIDs) else {
                return nil
            }
            let expectedChangedCount = fixture.paneIDs.count { paneID in
                before[paneID] != after[paneID]
            }
            let current = performanceTraceRecorder.rendererLifecycleSnapshot()
            guard expectedChangedCount == RendererLifecycleSoakSchedule.surfaceCount,
                current.visibilityDeliveryTotal - baseline.visibilityDeliveryTotal == expectedChangedCount,
                current.projectionChangedSurfaceTotal - baseline.projectionChangedSurfaceTotal
                    == expectedChangedCount,
                after.allSatisfy({ paneID, visible in
                    visible
                        == self.workspaceSurfaceCoordinator.effectiveRendererVisibility(
                            forAttachedPaneID: paneID
                        )
                })
            else { return nil }
            return expectedChangedCount
        }

        private func rendererLifecycleDeliveredVisibilityByPaneID(
            _ surfaceIDs: [UUID: UUID]
        ) -> [UUID: Bool]? {
            var visibilityByPaneID: [UUID: Bool] = [:]
            for (paneID, surfaceID) in surfaceIDs {
                guard let visible = SurfaceManager.shared.lastDeliveredVisibility(for: surfaceID) else {
                    return nil
                }
                visibilityByPaneID[paneID] = visible
            }
            return visibilityByPaneID
        }

        private func exerciseRendererLifecycleSoakTransition(
            _ scenario: String,
            fixture: RendererLifecycleContinuityFixture,
            surfaceIDs: [UUID: UUID]
        ) async -> (succeeded: Bool, reason: String) {
            switch scenario {
            case "tab_switch":
                return await exerciseRendererLifecycleSoakTabSwitchCycle(
                    fixture,
                    surfaceIDs: surfaceIDs
                )
            case "drawer_toggle":
                guard
                    await executeRendererLifecycleSoakAction(
                        .toggleDrawer(paneId: fixture.drawerParentID),
                        surfaceIDs: surfaceIDs,
                        until: {
                            self.store.paneAtom.pane(fixture.drawerParentID)?.drawer?.isExpanded == false
                        }),
                    await executeRendererLifecycleSoakAction(
                        .toggleDrawer(paneId: fixture.drawerParentID),
                        surfaceIDs: surfaceIDs,
                        until: {
                            self.store.paneAtom.pane(fixture.drawerParentID)?.drawer?.isExpanded == true
                        })
                else { return (false, "soak_drawer_toggle_failed") }
            case "arrangement_switch":
                guard
                    await executeRendererLifecycleSoakAction(
                        .switchArrangement(
                            tabId: fixture.firstTabID,
                            arrangementId: fixture.secondArrangementID
                        ),
                        surfaceIDs: surfaceIDs,
                        until: {
                            self.store.tabLayoutAtom.tab(fixture.firstTabID)?.activeArrangementId
                                == fixture.secondArrangementID
                        }),
                    await executeRendererLifecycleSoakAction(
                        .switchArrangement(
                            tabId: fixture.firstTabID,
                            arrangementId: fixture.firstArrangementID
                        ),
                        surfaceIDs: surfaceIDs,
                        until: {
                            self.store.tabLayoutAtom.tab(fixture.firstTabID)?.activeArrangementId
                                == fixture.firstArrangementID
                        })
                else { return (false, "soak_arrangement_switch_failed") }
            case "background_reactivate":
                guard
                    await executeRendererLifecycleSoakAction(
                        .backgroundPane(paneId: fixture.backgroundPaneID),
                        surfaceIDs: surfaceIDs,
                        until: {
                            self.store.paneAtom.pane(fixture.backgroundPaneID)?.residency == .backgrounded
                        }),
                    await executeRendererLifecycleSoakAction(
                        .reactivatePane(
                            paneId: fixture.backgroundPaneID,
                            targetTabId: fixture.firstTabID,
                            targetPaneId: fixture.zoomPaneIDs[0],
                            direction: .right
                        ),
                        surfaceIDs: surfaceIDs,
                        until: {
                            self.store.paneAtom.pane(fixture.backgroundPaneID)?.residency == .active
                        })
                else { return (false, "soak_background_reactivate_failed") }
            case "zoom_retarget":
                return await exerciseRendererLifecycleSoakZoomCycle(fixture, surfaceIDs: surfaceIDs)
            case "parent_minimize":
                guard
                    await executeRendererLifecycleSoakAction(
                        .minimizePane(tabId: fixture.firstTabID, paneId: fixture.zoomPaneIDs[0]),
                        surfaceIDs: surfaceIDs,
                        until: {
                            self.store.tabLayoutAtom.tab(fixture.firstTabID)?.activeMinimizedPaneIds.contains(
                                fixture.zoomPaneIDs[0]) == true
                        }),
                    await executeRendererLifecycleSoakAction(
                        .expandPane(tabId: fixture.firstTabID, paneId: fixture.zoomPaneIDs[0]),
                        surfaceIDs: surfaceIDs,
                        until: {
                            self.store.tabLayoutAtom.tab(fixture.firstTabID)?.activeMinimizedPaneIds.contains(
                                fixture.zoomPaneIDs[0]) == false
                        })
                else { return (false, "soak_parent_minimize_failed") }
            case "drawer_minimize":
                return await exerciseRendererLifecycleSoakDrawerMinimizeCycle(fixture, surfaceIDs: surfaceIDs)
            case "window_minimize":
                return await exerciseRendererLifecycleSoakWindowMinimizeCycle(surfaceIDs: surfaceIDs)
            case "window_occlusion":
                return await exerciseRendererLifecycleSoakOcclusionCycle(surfaceIDs: surfaceIDs)
            default:
                return (false, "soak_unknown_scenario")
            }
            return (true, "none")
        }

        private func exerciseRendererLifecycleSoakTabSwitchCycle(
            _ fixture: RendererLifecycleContinuityFixture,
            surfaceIDs: [UUID: UUID]
        ) async -> (succeeded: Bool, reason: String) {
            guard
                await executeRendererLifecycleSoakAction(
                    .selectTab(tabId: fixture.secondTabID),
                    surfaceIDs: surfaceIDs,
                    until: { self.store.tabLayoutAtom.activeTabId == fixture.secondTabID }),
                await executeRendererLifecycleSoakAction(
                    .selectTab(tabId: fixture.firstTabID),
                    surfaceIDs: surfaceIDs,
                    until: { self.store.tabLayoutAtom.activeTabId == fixture.firstTabID })
            else { return (false, "soak_tab_switch_failed") }
            return (true, "none")
        }

        private func executeRendererLifecycleSoakAction(
            _ action: WorkspaceActionCommand,
            until condition: @escaping @MainActor () -> Bool
        ) async -> Bool {
            let snapshot = performanceTraceRecorder.rendererLifecycleSnapshot()
            guard executor.execute(action) else { return false }
            return await waitForRendererLifecycleCondition(timeout: .seconds(5)) {
                condition() && self.rendererLifecycleProjectionAdvanced(after: snapshot)
            }
        }

        private func executeRendererLifecycleSoakAction(
            _ action: WorkspaceActionCommand,
            surfaceIDs: [UUID: UUID],
            until condition: @escaping @MainActor () -> Bool
        ) async -> Bool {
            guard let checkpoint = rendererLifecycleDeliveryCheckpoint(surfaceIDs) else { return false }
            guard executor.execute(action) else { return false }
            return await waitForExactRendererLifecycleDelivery(
                checkpoint,
                surfaceIDs: surfaceIDs,
                until: condition
            )
        }

        private struct RendererLifecycleDeliveryCheckpoint {
            let performance: RendererLifecyclePerformanceSnapshot
            let deliveredVisibilityByPaneID: [UUID: Bool]
        }

        private func rendererLifecycleDeliveryCheckpoint(
            _ surfaceIDs: [UUID: UUID]
        ) -> RendererLifecycleDeliveryCheckpoint? {
            guard let deliveredVisibilityByPaneID = rendererLifecycleDeliveredVisibilityByPaneID(surfaceIDs) else {
                return nil
            }
            return RendererLifecycleDeliveryCheckpoint(
                performance: performanceTraceRecorder.rendererLifecycleSnapshot(),
                deliveredVisibilityByPaneID: deliveredVisibilityByPaneID
            )
        }

        private func waitForExactRendererLifecycleDelivery(
            _ checkpoint: RendererLifecycleDeliveryCheckpoint,
            surfaceIDs: [UUID: UUID],
            until condition: @escaping @MainActor () -> Bool
        ) async -> Bool {
            await waitForRendererLifecycleCondition(timeout: .seconds(5)) {
                guard condition(),
                    let after = self.rendererLifecycleDeliveredVisibilityByPaneID(surfaceIDs)
                else { return false }
                let current = self.performanceTraceRecorder.rendererLifecycleSnapshot()
                guard current.projectionEvaluationTotal > checkpoint.performance.projectionEvaluationTotal else {
                    return false
                }
                let desired = Dictionary(
                    uniqueKeysWithValues: surfaceIDs.keys.map { paneID in
                        (
                            paneID,
                            self.workspaceSurfaceCoordinator.effectiveRendererVisibility(
                                forAttachedPaneID: paneID
                            )
                        )
                    }
                )
                return RendererLifecycleDeliveryValidation.isExact(
                    before: checkpoint.deliveredVisibilityByPaneID,
                    after: after,
                    desired: desired,
                    visibilityDeliveryDelta: current.visibilityDeliveryTotal
                        - checkpoint.performance.visibilityDeliveryTotal,
                    projectionChangedSurfaceDelta: current.projectionChangedSurfaceTotal
                        - checkpoint.performance.projectionChangedSurfaceTotal
                )
            }
        }

        private func rendererLifecycleProjectionAdvanced(
            after snapshot: RendererLifecyclePerformanceSnapshot
        ) -> Bool {
            let current = performanceTraceRecorder.rendererLifecycleSnapshot()
            return current.projectionEvaluationTotal > snapshot.projectionEvaluationTotal
                && current.visibilityDeliveryTotal > snapshot.visibilityDeliveryTotal
        }

        private func waitForRendererLifecycleProjection(
            after projectionEvaluationTotal: Int,
            requiringVisibilityDeliveryAfter visibilityDeliveryTotal: Int
        ) async -> Bool {
            await waitForRendererLifecycleCondition(timeout: .seconds(5)) {
                let current = self.performanceTraceRecorder.rendererLifecycleSnapshot()
                return current.projectionEvaluationTotal > projectionEvaluationTotal
                    && current.visibilityDeliveryTotal > visibilityDeliveryTotal
            }
        }

        private func exerciseRendererLifecycleSoakZoomCycle(
            _ fixture: RendererLifecycleContinuityFixture,
            surfaceIDs: [UUID: UUID]
        ) async -> (succeeded: Bool, reason: String) {
            guard let controller = paneTabViewController() else { return (false, "soak_tab_controller_missing") }
            guard var checkpoint = rendererLifecycleDeliveryCheckpoint(surfaceIDs) else {
                return (false, "soak_zoom_checkpoint_missing")
            }
            controller.execute(.zoomPane, target: fixture.zoomPaneIDs[0], targetType: .pane)
            guard
                await waitForExactRendererLifecycleDelivery(
                    checkpoint,
                    surfaceIDs: surfaceIDs,
                    until: {
                        self.store.panePresentationAtom.zoomCompanion(forSourcePane: fixture.zoomPaneIDs[0]) != nil
                    })
            else { return (false, "soak_zoom_enter_failed") }
            guard let nextCheckpoint = rendererLifecycleDeliveryCheckpoint(surfaceIDs) else {
                return (false, "soak_zoom_checkpoint_missing")
            }
            checkpoint = nextCheckpoint
            controller.execute(.zoomPane, target: fixture.zoomPaneIDs[1], targetType: .pane)
            guard
                await waitForExactRendererLifecycleDelivery(
                    checkpoint,
                    surfaceIDs: surfaceIDs,
                    until: {
                        self.store.panePresentationAtom.zoomCompanion(forSourcePane: fixture.zoomPaneIDs[1]) != nil
                    })
            else { return (false, "soak_zoom_retarget_failed") }
            guard let exitCheckpoint = rendererLifecycleDeliveryCheckpoint(surfaceIDs) else {
                return (false, "soak_zoom_checkpoint_missing")
            }
            controller.execute(.zoomPane, target: fixture.zoomPaneIDs[1], targetType: .pane)
            guard
                await waitForExactRendererLifecycleDelivery(
                    exitCheckpoint,
                    surfaceIDs: surfaceIDs,
                    until: {
                        self.store.panePresentationAtom.zoomPresentation(forTab: fixture.firstTabID) == nil
                    })
            else { return (false, "soak_zoom_exit_failed") }
            return (true, "none")
        }

        private func exerciseRendererLifecycleSoakDrawerMinimizeCycle(
            _ fixture: RendererLifecycleContinuityFixture,
            surfaceIDs: [UUID: UUID]
        ) async -> (succeeded: Bool, reason: String) {
            guard let drawerID = store.paneAtom.pane(fixture.drawerParentID)?.drawer?.drawerId else {
                return (false, "soak_drawer_identity_missing")
            }
            guard
                await executeRendererLifecycleSoakAction(
                    .minimizeDrawerPane(
                        parentPaneId: fixture.drawerParentID,
                        drawerPaneId: fixture.drawerPaneIDs[0]
                    ),
                    surfaceIDs: surfaceIDs,
                    until: {
                        self.store.tabLayoutAtom.tab(fixture.firstTabID)?.activeArrangement.drawerViews[drawerID]?
                            .minimizedPaneIds.contains(fixture.drawerPaneIDs[0]) == true
                    }),
                await executeRendererLifecycleSoakAction(
                    .expandDrawerPane(
                        parentPaneId: fixture.drawerParentID,
                        drawerPaneId: fixture.drawerPaneIDs[0]
                    ),
                    surfaceIDs: surfaceIDs,
                    until: {
                        self.store.tabLayoutAtom.tab(fixture.firstTabID)?.activeArrangement.drawerViews[drawerID]?
                            .minimizedPaneIds.contains(fixture.drawerPaneIDs[0]) == false
                    })
            else { return (false, "soak_drawer_minimize_failed") }
            return (true, "none")
        }

        private func exerciseRendererLifecycleSoakWindowMinimizeCycle(surfaceIDs: [UUID: UUID]) async -> (
            succeeded: Bool, reason: String
        ) {
            guard let window = mainWindowController?.window else { return (false, "soak_window_missing") }
            guard var checkpoint = rendererLifecycleDeliveryCheckpoint(surfaceIDs) else {
                return (false, "soak_window_checkpoint_missing")
            }
            window.miniaturize(nil)
            guard
                await waitForExactRendererLifecycleDelivery(
                    checkpoint,
                    surfaceIDs: surfaceIDs,
                    until: { window.isMiniaturized })
            else {
                return (false, "soak_window_minimize_failed")
            }
            guard let restoreCheckpoint = rendererLifecycleDeliveryCheckpoint(surfaceIDs) else {
                return (false, "soak_window_checkpoint_missing")
            }
            checkpoint = restoreCheckpoint
            window.deminiaturize(nil)
            guard
                await waitForExactRendererLifecycleDelivery(
                    checkpoint,
                    surfaceIDs: surfaceIDs,
                    until: { !window.isMiniaturized })
            else {
                return (false, "soak_window_restore_failed")
            }
            return (true, "none")
        }

        private func exerciseRendererLifecycleSoakOcclusionCycle(
            surfaceIDs: [UUID: UUID]
        ) async -> (succeeded: Bool, reason: String) {
            guard let workspaceWindow = mainWindowController?.window else { return (false, "soak_window_missing") }
            let coverWindow = NSWindow(
                contentRect: workspaceWindow.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            coverWindow.backgroundColor = .black
            coverWindow.isOpaque = true
            coverWindow.level = .screenSaver
            coverWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            guard var checkpoint = rendererLifecycleDeliveryCheckpoint(surfaceIDs) else {
                return (false, "soak_window_checkpoint_missing")
            }
            coverWindow.orderFrontRegardless()
            guard
                await waitForExactRendererLifecycleDelivery(
                    checkpoint,
                    surfaceIDs: surfaceIDs,
                    until: {
                        !workspaceWindow.occlusionState.contains(.visible)
                    })
            else {
                coverWindow.orderOut(nil)
                return (false, "soak_window_occlusion_not_observed")
            }
            guard let revealCheckpoint = rendererLifecycleDeliveryCheckpoint(surfaceIDs) else {
                coverWindow.orderOut(nil)
                return (false, "soak_window_checkpoint_missing")
            }
            checkpoint = revealCheckpoint
            coverWindow.orderOut(nil)
            guard
                await waitForExactRendererLifecycleDelivery(
                    checkpoint,
                    surfaceIDs: surfaceIDs,
                    until: {
                        workspaceWindow.occlusionState.contains(.visible)
                    })
            else { return (false, "soak_window_reveal_not_observed") }
            return (true, "none")
        }

        func exerciseRendererLifecycleRepairs(
            _ fixture: RendererLifecycleContinuityFixture
        ) async -> (succeeded: Bool, reason: String) {
            let freeBaseline = performanceTraceRecorder.rendererLifecycleSnapshot().deinitializedFreeTotal
            for _ in 0..<20 {
                weak var retiredMountView: TerminalPaneMountView?
                weak var retiredSurfaceView: Ghostty.SurfaceView?
                let oldSurfaceID: UUID
                do {
                    guard let mountView = viewRegistry.terminalView(for: fixture.repairPaneID),
                        let surfaceID = mountView.surfaceId,
                        let surfaceView = mountView.ghosttySurface
                    else { return (false, "repair_old_surface_missing") }
                    retiredMountView = mountView
                    retiredSurfaceView = surfaceView
                    oldSurfaceID = surfaceID
                }
                let iterationFreeBaseline = performanceTraceRecorder.rendererLifecycleSnapshot().deinitializedFreeTotal
                let repairAccepted = autoreleasepool {
                    executor.execute(.repair(.recreateSurface(paneId: fixture.repairPaneID)))
                }
                guard repairAccepted else {
                    return (false, "repair_rejected")
                }
                mainWindowController?.syncVisibleTerminalGeometry(reason: "rendererLifecycleRepair")
                let instanceReleased = await waitForRendererLifecycleCondition(
                    timeout: .seconds(10),
                    {
                        guard let replacementView = self.viewRegistry.terminalView(for: fixture.repairPaneID),
                            let replacementID = replacementView.surfaceId
                        else { return false }
                        return replacementID != oldSurfaceID && replacementView.ghosttySurface != nil
                            && retiredMountView == nil && retiredSurfaceView == nil
                            && self.performanceTraceRecorder.rendererLifecycleSnapshot().deinitializedFreeTotal
                                == iterationFreeBaseline + 1
                    })
                guard instanceReleased else {
                    if retiredMountView != nil {
                        return (false, "repair_mount_retained")
                    }
                    if retiredSurfaceView != nil {
                        return (false, "repair_surface_retained")
                    }
                    return (false, "repair_free_not_recorded")
                }
            }
            guard
                await waitForRendererLifecycleCondition(
                    timeout: .seconds(20),
                    {
                        let snapshot = self.performanceTraceRecorder.rendererLifecycleSnapshot()
                        return snapshot.deinitializedFreeTotal == freeBaseline + 20
                            && snapshot.orphanCandidateCurrent == 0
                    })
            else { return (false, "repair_free_not_settled") }
            return (true, "none")
        }

        private func verifyRendererLifecycleFinalState(
            _ fixture: RendererLifecycleContinuityFixture,
            initialSessionIDs: [UUID: ZmxSessionID]
        ) -> (succeeded: Bool, reason: String) {
            guard rendererLifecycleSessionIDs(for: fixture.paneIDs) == initialSessionIDs else {
                return (false, "zmx_identity_changed")
            }
            guard fixture.paneIDs.allSatisfy({ store.paneAtom.pane($0) != nil }) else {
                return (false, "canonical_pane_missing")
            }
            guard fixture.paneIDs.allSatisfy({ viewRegistry.terminalView(for: $0) != nil }) else {
                return (false, "mounted_content_missing")
            }
            let snapshot = performanceTraceRecorder.rendererLifecycleSnapshot()
            guard snapshot.managerOwnedCurrent == fixture.paneIDs.count,
                snapshot.liveCurrent == fixture.paneIDs.count,
                snapshot.closeUndoCurrent == 0,
                snapshot.orphanCandidateCurrent == 0,
                snapshot.isValid
            else { return (false, "lifecycle_conservation_failed") }
            return (true, "none")
        }
    }
#endif
