import AgentStudioCore
import AgentStudioTerminal
import AppKit
import Foundation

#if DEBUG
    enum RendererLifecycleSoakSchedule {
        static let surfaceCount = 20
        static let transitionCycleCount = 20
        static let immediateUndoCount = 10
        static let expiryCount = 10
        static let warmupDuration = Duration.seconds(610)
        static let finalWindowDuration = Duration.seconds(1815)

        static let transitionScenarios = [
            "tab_switch",
            "drawer_toggle",
            "arrangement_switch",
            "background_reactivate",
            "zoom_retarget",
            "parent_minimize",
            "drawer_minimize",
            "window_minimize",
            "window_occlusion",
        ]
    }

    @MainActor
    extension AppDelegate {
        func runRendererLifecycleSoakDiagnostic(
            action: AgentStudioStartupDiagnosticAction,
            fixture: RendererLifecycleContinuityFixture,
            initialSurfaceIDs: [UUID: UUID],
            initialSessionIDs: [UUID: ZmxSessionID]
        ) async {
            guard fixture.paneIDs.count == RendererLifecycleSoakSchedule.surfaceCount,
                fixture.expiryPaneIDs.count == RendererLifecycleSoakSchedule.expiryCount,
                Set(initialSurfaceIDs.values).count == RendererLifecycleSoakSchedule.surfaceCount,
                Set(initialSessionIDs.values).count == RendererLifecycleSoakSchedule.surfaceCount,
                await prepareRendererLifecycleSoakOutput(fixture, initialSurfaceIDs: initialSurfaceIDs)
            else {
                finishRendererLifecycleSoak(action: action, succeeded: false, reason: "soak_fixture_invalid")
                return
            }

            recordRendererLifecycleDiagnosticProgress(action: action, stage: "fixture_ready")
            let deliveryCardinalityResult = await verifyRendererLifecycleSoakDeliveryCardinality(
                fixture,
                action: action,
                surfaceIDs: initialSurfaceIDs
            )
            guard deliveryCardinalityResult.succeeded else {
                finishRendererLifecycleSoak(
                    action: action,
                    succeeded: false,
                    reason: deliveryCardinalityResult.reason
                )
                return
            }
            recordRendererLifecycleDiagnosticProgress(action: action, stage: "warmup_started")
            guard await waitRendererLifecycleSoakDuration(RendererLifecycleSoakSchedule.warmupDuration) else {
                finishRendererLifecycleSoak(action: action, succeeded: false, reason: "warmup_cancelled")
                return
            }
            recordRendererLifecycleDiagnosticProgress(action: action, stage: "warmup_completed")

            let transitionResult = await exerciseRendererLifecycleSoakTransitionCycles(
                fixture,
                action: action,
                surfaceIDs: initialSurfaceIDs
            )
            guard transitionResult.succeeded else {
                finishRendererLifecycleSoak(action: action, succeeded: false, reason: transitionResult.reason)
                return
            }

            let repairResult = await exerciseRendererLifecycleRepairs(fixture)
            guard repairResult.succeeded else {
                finishRendererLifecycleSoak(action: action, succeeded: false, reason: repairResult.reason)
                return
            }
            recordRendererLifecycleDiagnosticProgress(
                action: action,
                stage: "scenario_completed",
                scenario: "repair_recreate",
                completedCount: RendererLifecycleSoakSchedule.transitionCycleCount,
                expectedCount: RendererLifecycleSoakSchedule.transitionCycleCount
            )

            let immediateUndoResult = await exerciseRendererLifecycleImmediateUndoCycles(
                fixture,
                expectedSessionID: initialSessionIDs[fixture.retentionPaneID],
                count: RendererLifecycleSoakSchedule.immediateUndoCount
            )
            guard immediateUndoResult.succeeded else {
                finishRendererLifecycleSoak(action: action, succeeded: false, reason: immediateUndoResult.reason)
                return
            }
            recordRendererLifecycleDiagnosticProgress(
                action: action,
                stage: "scenario_completed",
                scenario: "close_immediate_undo",
                completedCount: RendererLifecycleSoakSchedule.immediateUndoCount,
                expectedCount: RendererLifecycleSoakSchedule.immediateUndoCount
            )

            let expiryResult = await exerciseRendererLifecycleExpiryCohort(
                fixture,
                expectedSessionIDs: initialSessionIDs
            )
            guard expiryResult.succeeded else {
                finishRendererLifecycleSoak(action: action, succeeded: false, reason: expiryResult.reason)
                return
            }
            recordRendererLifecycleDiagnosticProgress(
                action: action,
                stage: "scenario_completed",
                scenario: "close_expiry",
                completedCount: RendererLifecycleSoakSchedule.expiryCount,
                expectedCount: RendererLifecycleSoakSchedule.expiryCount
            )

            guard verifyRendererLifecycleSoakSettlement(fixture, expectedSessionIDs: initialSessionIDs) else {
                finishRendererLifecycleSoak(action: action, succeeded: false, reason: "soak_not_settled")
                return
            }
            recordRendererLifecycleDiagnosticProgress(action: action, stage: "final_window_started")
            guard await waitRendererLifecycleSoakDuration(RendererLifecycleSoakSchedule.finalWindowDuration) else {
                finishRendererLifecycleSoak(action: action, succeeded: false, reason: "final_window_cancelled")
                return
            }
            guard verifyRendererLifecycleSoakSettlement(fixture, expectedSessionIDs: initialSessionIDs) else {
                finishRendererLifecycleSoak(action: action, succeeded: false, reason: "final_window_not_settled")
                return
            }
            recordRendererLifecycleDiagnosticProgress(action: action, stage: "final_window_completed")
            finishRendererLifecycleSoak(action: action, succeeded: true, reason: "none")
        }

        private func prepareRendererLifecycleSoakOutput(
            _ fixture: RendererLifecycleContinuityFixture,
            initialSurfaceIDs: [UUID: UUID]
        ) async -> Bool {
            let marker = "renderer-soak-output-quiesced"
            for paneID in fixture.paneIDs {
                guard
                    case .success = SurfaceManager.shared.sendInput(
                        "printf 'renderer-soak-output-quiesced\\n'\n",
                        toPaneId: paneID
                    )
                else { return false }
            }
            return await waitForRendererLifecycleCondition(timeout: .seconds(20)) {
                fixture.paneIDs.allSatisfy { paneID in
                    guard let surfaceID = initialSurfaceIDs[paneID] else { return false }
                    return SurfaceManager.shared.readViewportTrailingText(forSurfaceID: surfaceID)?.contains(marker)
                        == true
                }
            }
        }

        private func waitRendererLifecycleSoakDuration(_ duration: Duration) async -> Bool {
            do {
                try await Task.sleep(nanoseconds: duration.nanosecondsForTaskSleep)
                return !Task.isCancelled
            } catch {
                return false
            }
        }

        private func verifyRendererLifecycleSoakSettlement(
            _ fixture: RendererLifecycleContinuityFixture,
            expectedSessionIDs: [UUID: ZmxSessionID]
        ) -> Bool {
            let snapshot = performanceTraceRecorder.rendererLifecycleSnapshot()
            return fixture.paneIDs.allSatisfy { store.paneAtom.pane($0) != nil }
                && rendererLifecycleSurfaceIDs(for: fixture.paneIDs).count == fixture.paneIDs.count
                && rendererLifecycleSessionIDs(for: fixture.paneIDs) == expectedSessionIDs
                && snapshot.managerOwnedCurrent == fixture.paneIDs.count
                && snapshot.liveCurrent == fixture.paneIDs.count
                && snapshot.closeUndoCurrent == 0
                && snapshot.orphanCandidateCurrent == 0
                && snapshot.isValid
        }

        private func finishRendererLifecycleSoak(
            action: AgentStudioStartupDiagnosticAction,
            succeeded: Bool,
            reason: String
        ) {
            recordRendererLifecycleDiagnosticResult(
                action: action,
                succeeded: succeeded,
                reason: reason,
                paneCount: RendererLifecycleSoakSchedule.surfaceCount
            )
            NSApp.terminate(nil)
        }
    }
#endif
