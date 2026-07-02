import AppKit
import Foundation

@MainActor
extension AppDelegate {
    #if DEBUG
        func runBridgeReviewObservabilitySmokeDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            recordBridgeReviewObservabilitySmokePhase("activation_started", action: action)
            NSApp.activate(ignoringOtherApps: true)
            mainWindowController?.window?.makeKeyAndOrderFront(nil)
            recordBridgeReviewObservabilitySmokePhase("window_ordered", action: action)
            await waitForStartupDiagnosticAppActivation()
            recordBridgeReviewObservabilitySmokePhase("activation_wait_finished", action: action)
            recordBridgeReviewObservabilitySmokePhase("bounds_wait_started", action: action)

            guard let terminalContainerBounds = await startupDiagnosticLaunchRestoreBounds() else {
                recordStartupDiagnosticSkipped(action: action, reason: "missing_bounds")
                return
            }
            recordBridgeReviewObservabilitySmokePhase("bounds_ready", action: action)

            if !launchRestoreObservationState.didComplete {
                recordBridgeReviewObservabilitySmokePhase("launch_restore_started", action: action)
                await finishLaunchRestore(
                    using: terminalContainerBounds,
                    source: "bridgeReviewObservabilitySmokePreflight"
                )
                recordBridgeReviewObservabilitySmokePhase("launch_restore_finished", action: action)
            }

            let realWorktreeId = bridgeReviewObservabilitySmokeWorktreeId()
            recordBridgeReviewObservabilitySmokePhase("pane_open_started", action: action)
            let pane: Pane?
            if let realWorktreeId {
                pane = workspaceSurfaceCoordinator.openBridgeReview(worktreeId: realWorktreeId)
            } else {
                pane = workspaceSurfaceCoordinator.openBridgeReviewObservabilitySmoke()
            }
            guard let pane else {
                recordStartupDiagnosticBlocked(action: action, reason: "bridge_pane_creation_failed")
                return
            }
            recordBridgeReviewObservabilitySmokePhase("pane_opened", action: action)

            recordBridgeReviewObservabilitySmokePhase("restore_views_started", action: action)
            workspaceSurfaceCoordinator.restoreVisiblePaneIfNeeded(pane.id, forceWhenBoundsExist: true)
            await Task.yield()
            recordBridgeReviewObservabilitySmokePhase("restore_views_finished", action: action)

            guard
                let bridgeView = viewRegistry.view(for: pane.id)?
                    .mountedContent(as: BridgePaneMountView.self)
            else {
                recordStartupDiagnosticBlocked(action: action, reason: "bridge_view_missing")
                return
            }
            recordBridgeReviewObservabilitySmokePhase("bridge_view_mounted", action: action)

            if realWorktreeId == nil {
                let commandId = UUIDv7.generate()
                recordBridgeReviewObservabilitySmokePhase("load_diff_started", action: action)
                let result = await bridgeView.controller.handleDiffCommand(
                    .loadDiff(
                        DiffArtifact(
                            diffId: BridgeObservabilitySmokeReviewSourceProvider.diffId,
                            worktreeId: BridgeObservabilitySmokeReviewSourceProvider.worktreeId,
                            patchData: Data()
                        )
                    ),
                    commandId: commandId,
                    correlationId: nil
                )
                recordBridgeReviewObservabilitySmokePhase("load_diff_finished", action: action)
                if case .failure = result, bridgeView.controller.paneState.diff.status == .error {
                    let renderProof = BridgeReviewObservabilitySmokeRenderProof.unavailable()
                    recordBridgeReviewObservabilitySmokeDiagnosticResult(
                        action: action,
                        outcome: "blocked",
                        renderProof: renderProof
                    )
                    return
                }
            }

            recordBridgeReviewObservabilitySmokePhase("render_proof_started", action: action)
            let renderProof = await waitForBridgeReviewObservabilitySmokeRenderProof(
                for: bridgeView.controller
            )
            recordBridgeReviewObservabilitySmokePhase("render_proof_finished", action: action)
            recordBridgeReviewObservabilitySmokeDiagnosticResult(
                action: action,
                outcome: renderProof.succeeded ? "succeeded" : "blocked",
                renderProof: renderProof
            )
        }

        private func recordStartupDiagnosticSkipped(
            action: AgentStudioStartupDiagnosticAction,
            reason: String
        ) {
            recordStartupDiagnosticUnavailable(action: action, outcome: "skipped", reason: reason)
        }

        private func recordStartupDiagnosticBlocked(
            action: AgentStudioStartupDiagnosticAction,
            reason: String
        ) {
            recordStartupDiagnosticUnavailable(action: action, outcome: "blocked", reason: reason)
        }

        private func recordStartupDiagnosticUnavailable(
            action: AgentStudioStartupDiagnosticAction,
            outcome: String,
            reason: String
        ) {
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.\(outcome)",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: startupDiagnosticTraceAttributes(for: action).merging([
                    "agentstudio.startup_diagnostic.skip_reason": .string(reason)
                ]) { _, newValue in newValue }
            )
        }

        private func bridgeReviewObservabilitySmokeWorktreeId() -> UUID? {
            guard let folderURL = AgentStudioStartupDiagnosticAction.watchFolderURL() else {
                return nil
            }
            return store.repositoryTopologyAtom.ensureMainWorktree(at: folderURL.standardizedFileURL).id
        }

        private func recordBridgeReviewObservabilitySmokePhase(
            _ phase: String,
            action: AgentStudioStartupDiagnosticAction
        ) {
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.bridge_smoke.\(phase)",
                phase: "startup_diagnostic_action",
                attributes: startupDiagnosticTraceAttributes(for: action)
            )
        }

        private func recordBridgeReviewObservabilitySmokeDiagnosticResult(
            action: AgentStudioStartupDiagnosticAction,
            outcome: String,
            renderProof: BridgeReviewObservabilitySmokeRenderProof
        ) {
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.command_exercised",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: startupDiagnosticTraceAttributes(for: action).merging(
                    renderProof.attributes
                ) { _, newValue in newValue }
            )
            startupTraceRecorder.recordAppStartup(
                outcome == "succeeded"
                    ? "app.startup_diagnostic_action.completed"
                    : "app.startup_diagnostic_action.blocked",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: startupDiagnosticTraceAttributes(for: action).merging(
                    renderProof.attributes
                ) { _, newValue in newValue }
            )
        }

        private func waitForBridgeReviewObservabilitySmokeRenderProof(
            for controller: BridgePaneController
        ) async -> BridgeReviewObservabilitySmokeRenderProof {
            let clock = ContinuousClock()
            let start = clock.now
            var proof = await bridgeReviewObservabilitySmokeRenderProof(for: controller)
            while !proof.succeeded
                && start.duration(to: clock.now) < AppPolicies.StartupDiagnostic.ipcTerminalSmokeReadinessTimeout
            {
                try? await Task.sleep(nanoseconds: Duration.milliseconds(50).nanosecondsForTaskSleep)
                proof = await bridgeReviewObservabilitySmokeRenderProof(for: controller)
            }
            return proof
        }

        private func bridgeReviewObservabilitySmokeRenderProof(
            for controller: BridgePaneController
        ) async -> BridgeReviewObservabilitySmokeRenderProof {
            do {
                let result = try await controller.page.callJavaScript(
                    Self.bridgeReviewObservabilitySmokeRenderStateJavaScript)
                guard let json = result as? String,
                    let data = json.data(using: .utf8)
                else {
                    return .unavailable()
                }
                let snapshot = try JSONDecoder().decode(
                    BridgeReviewObservabilitySmokeRenderSnapshot.self,
                    from: data
                )
                return BridgeReviewObservabilitySmokeRenderProof(
                    snapshot: snapshot,
                    expectedVisiblePaneCount: 1,
                    expectedReviewItemCount: controller.paneState.diff.packageMetadata?.orderedItemIds.count ?? 0
                )
            } catch {
                return .unavailable()
            }
        }

    #endif
}
