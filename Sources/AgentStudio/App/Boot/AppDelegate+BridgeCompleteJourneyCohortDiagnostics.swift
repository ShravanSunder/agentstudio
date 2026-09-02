import AgentStudioBridge
import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation

#if DEBUG
    enum BridgeCompleteJourneySurface: String {
        case file
        case review

        var openCommand: AppCommand {
            switch self {
            case .file: .openBridgeFilesInNewTab
            case .review: .openBridgeReviewInNewTab
            }
        }

        var switchCommand: AppCommand {
            switch self {
            case .file: .showBridgeFiles
            case .review: .showBridgeReview
            }
        }

        var panelKind: BridgePanelKind {
            switch self {
            case .file: .fileViewer
            case .review: .diffViewer
            }
        }
    }

    private enum BridgeCompleteJourneyConfigurationAdmission {
        case absent
        case invalid
        case enabled(configuration: BridgeCompleteJourneyConfiguration, receiptURL: URL)
    }

    @MainActor
    extension AppDelegate {
        func runBridgeCompleteJourneyCohortIfConfigured(
            action: AgentStudioStartupDiagnosticAction,
            worktreeId: UUID,
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) async -> Bool {
            switch Self.bridgeCompleteJourneyConfigurationAdmission(environment: environment) {
            case .absent:
                return false
            case .invalid:
                recordBridgeCompleteJourneyCohortResult(action: action, succeeded: false)
                return true
            case .enabled(let configuration, let receiptURL):
                guard let paneTabViewController = paneTabViewController() else {
                    recordBridgeCompleteJourneyCohortResult(action: action, succeeded: false)
                    return true
                }
                var attemptsByJourney = BridgeCompleteJourneyAttemptsByJourney(
                    firstFile: [],
                    firstReview: [],
                    fileToReview: [],
                    reviewToFile: []
                )
                var telemetryProof = BridgeCompleteJourneyTelemetryProof(
                    expectedAttemptCount: configuration.attemptCount * 4
                )
                for attemptIndex in 0..<configuration.attemptCount {
                    attemptsByJourney.firstFile.append(
                        await collectBridgeCompleteJourneyFirstPaneAttempt(
                            attemptId: "\(configuration.launchId)-firstFile-\(attemptIndex)",
                            surface: .file,
                            worktreeId: worktreeId,
                            paneTabViewController: paneTabViewController,
                            telemetryProof: &telemetryProof
                        )
                    )
                    attemptsByJourney.firstReview.append(
                        await collectBridgeCompleteJourneyFirstPaneAttempt(
                            attemptId: "\(configuration.launchId)-firstReview-\(attemptIndex)",
                            surface: .review,
                            worktreeId: worktreeId,
                            paneTabViewController: paneTabViewController,
                            telemetryProof: &telemetryProof
                        )
                    )
                    attemptsByJourney.fileToReview.append(
                        await collectBridgeCompleteJourneySwitchAttempt(
                            attemptId: "\(configuration.launchId)-fileToReview-\(attemptIndex)",
                            sourceSurface: .file,
                            targetSurface: .review,
                            worktreeId: worktreeId,
                            paneTabViewController: paneTabViewController,
                            telemetryProof: &telemetryProof
                        )
                    )
                    attemptsByJourney.reviewToFile.append(
                        await collectBridgeCompleteJourneySwitchAttempt(
                            attemptId: "\(configuration.launchId)-reviewToFile-\(attemptIndex)",
                            sourceSurface: .review,
                            targetSurface: .file,
                            worktreeId: worktreeId,
                            paneTabViewController: paneTabViewController,
                            telemetryProof: &telemetryProof
                        )
                    )
                }
                let receipt = BridgeCompleteJourneyNativeLaunchReceipt(
                    launchId: configuration.launchId,
                    attemptsByJourney: attemptsByJourney,
                    telemetryProof: telemetryProof
                )
                do {
                    try JSONEncoder().encode(receipt).write(to: receiptURL, options: .atomic)
                    recordBridgeCompleteJourneyCohortResult(action: action, succeeded: true)
                } catch {
                    recordBridgeCompleteJourneyCohortResult(action: action, succeeded: false)
                }
                return true
            }
        }

        private func collectBridgeCompleteJourneyFirstPaneAttempt(
            attemptId: String,
            surface: BridgeCompleteJourneySurface,
            worktreeId: UUID,
            paneTabViewController: PaneTabViewController,
            telemetryProof: inout BridgeCompleteJourneyTelemetryProof
        ) async -> BridgeCompleteJourneyAttempt {
            let paneIdsBeforeOpen = Set(store.paneAtom.paneSnapshot().keys)
            let startedAtEpochMilliseconds = Self.bridgeCompleteJourneyEpochMilliseconds()
            paneTabViewController.execute(surface.openCommand, target: worktreeId, targetType: .worktree)
            let openedPane = await waitForBridgeCompleteJourneyPane(
                excluding: paneIdsBeforeOpen,
                expectedSurface: surface,
                worktreeId: worktreeId
            )
            guard let openedPane else {
                telemetryProof.merge(.missing(drainFailed: false))
                await closeBridgeCompleteJourneyPanesCreatedAfter(
                    paneIdsBeforeOpen,
                    paneTabViewController: paneTabViewController
                )
                return Self.bridgeCompleteJourneyFailedAttempt(
                    attemptId: attemptId,
                    startedAtEpochMilliseconds: startedAtEpochMilliseconds,
                    failureReason: "pane_open_failed"
                )
            }
            let browserResult = await bridgeCompleteJourneyBrowserResult(
                controller: openedPane.controller,
                paneId: openedPane.paneId,
                surface: surface
            )
            var attempt = Self.bridgeCompleteJourneyAttempt(
                attemptId: attemptId,
                startedAtEpochMilliseconds: startedAtEpochMilliseconds,
                browserResult: browserResult
            )
            let telemetryObservation = await bridgeCompleteJourneyTelemetryProofObservation(
                controller: openedPane.controller
            )
            telemetryProof.merge(telemetryObservation)
            if let failureReason = telemetryObservation.attemptFailureReason {
                attempt = attempt.failing(reason: failureReason)
            }
            let cleanupSucceeded = await closeBridgeCompleteJourneyPane(
                paneId: openedPane.paneId,
                paneTabViewController: paneTabViewController
            )
            return cleanupSucceeded
                ? attempt
                : Self.bridgeCompleteJourneyFailedAttempt(
                    attemptId: attemptId,
                    startedAtEpochMilliseconds: startedAtEpochMilliseconds,
                    failureReason: "pane_cleanup_failed"
                )
        }

        private func collectBridgeCompleteJourneySwitchAttempt(
            attemptId: String,
            sourceSurface: BridgeCompleteJourneySurface,
            targetSurface: BridgeCompleteJourneySurface,
            worktreeId: UUID,
            paneTabViewController: PaneTabViewController,
            telemetryProof: inout BridgeCompleteJourneyTelemetryProof
        ) async -> BridgeCompleteJourneyAttempt {
            let paneIdsBeforeOpen = Set(store.paneAtom.paneSnapshot().keys)
            paneTabViewController.execute(sourceSurface.openCommand, target: worktreeId, targetType: .worktree)
            guard
                let sourcePane = await waitForBridgeCompleteJourneyPane(
                    excluding: paneIdsBeforeOpen,
                    expectedSurface: sourceSurface,
                    worktreeId: worktreeId
                )
            else {
                telemetryProof.merge(.missing(drainFailed: false))
                await closeBridgeCompleteJourneyPanesCreatedAfter(
                    paneIdsBeforeOpen,
                    paneTabViewController: paneTabViewController
                )
                return Self.bridgeCompleteJourneyFailedAttempt(
                    attemptId: attemptId,
                    startedAtEpochMilliseconds: Self.bridgeCompleteJourneyEpochMilliseconds(),
                    failureReason: "switch_source_open_failed"
                )
            }
            let sourceResult = await bridgeCompleteJourneyBrowserResult(
                controller: sourcePane.controller,
                paneId: sourcePane.paneId,
                surface: sourceSurface
            )
            guard sourceResult?.outcome == "succeeded" else {
                let telemetryObservation = await bridgeCompleteJourneyTelemetryProofObservation(
                    controller: sourcePane.controller
                )
                telemetryProof.merge(telemetryObservation)
                _ = await closeBridgeCompleteJourneyPane(
                    paneId: sourcePane.paneId,
                    paneTabViewController: paneTabViewController
                )
                return Self.bridgeCompleteJourneyFailedAttempt(
                    attemptId: attemptId,
                    startedAtEpochMilliseconds: Self.bridgeCompleteJourneyEpochMilliseconds(),
                    failureReason: telemetryObservation.attemptFailureReason
                        ?? "switch_source_not_usable"
                )
            }

            let startedAtEpochMilliseconds = Self.bridgeCompleteJourneyEpochMilliseconds()
            let paneIdsBeforeSwitch = Set(store.paneAtom.paneSnapshot().keys)
            paneTabViewController.execute(targetSurface.switchCommand, target: worktreeId, targetType: .worktree)
            let targetBrowserResult = await bridgeCompleteJourneyBrowserResult(
                controller: sourcePane.controller,
                paneId: sourcePane.paneId,
                surface: targetSurface
            )
            let telemetryObservation = await bridgeCompleteJourneyTelemetryProofObservation(
                controller: sourcePane.controller
            )
            telemetryProof.merge(telemetryObservation)
            let paneIdsAfterSwitch = Set(store.paneAtom.paneSnapshot().keys)
            let controllerWasReused =
                viewRegistry.allBridgeViews[sourcePane.paneId]?.controller
                === sourcePane.controller
            var attempt =
                controllerWasReused && paneIdsAfterSwitch == paneIdsBeforeSwitch
                ? Self.bridgeCompleteJourneyAttempt(
                    attemptId: attemptId,
                    startedAtEpochMilliseconds: startedAtEpochMilliseconds,
                    browserResult: targetBrowserResult
                )
                : Self.bridgeCompleteJourneyFailedAttempt(
                    attemptId: attemptId,
                    startedAtEpochMilliseconds: startedAtEpochMilliseconds,
                    failureReason: "switch_controller_replaced"
                )
            if let failureReason = telemetryObservation.attemptFailureReason {
                attempt = attempt.failing(reason: failureReason)
            }
            let cleanupSucceeded = await closeBridgeCompleteJourneyPane(
                paneId: sourcePane.paneId,
                paneTabViewController: paneTabViewController
            )
            return cleanupSucceeded
                ? attempt
                : Self.bridgeCompleteJourneyFailedAttempt(
                    attemptId: attemptId,
                    startedAtEpochMilliseconds: startedAtEpochMilliseconds,
                    failureReason: "pane_cleanup_failed"
                )
        }

        private func waitForBridgeCompleteJourneyPane(
            excluding paneIdsBeforeOpen: Set<UUID>,
            expectedSurface: BridgeCompleteJourneySurface,
            worktreeId: UUID
        ) async -> (paneId: UUID, controller: BridgePaneController)? {
            let deadline =
                ContinuousClock.now
                + AppPolicies.StartupDiagnostic.bridgeFileViewSmokeReadinessTimeout
            while ContinuousClock.now < deadline {
                let candidates = store.paneAtom.paneSnapshot().values.compactMap { pane -> UUID? in
                    guard !paneIdsBeforeOpen.contains(pane.id), pane.worktreeId == worktreeId,
                        case .bridgePanel(let state) = pane.content,
                        state.panelKind == expectedSurface.panelKind,
                        viewRegistry.allBridgeViews[pane.id] != nil
                    else { return nil }
                    return pane.id
                }
                if candidates.count > 1 { return nil }
                if let paneId = candidates.first,
                    let controller = viewRegistry.allBridgeViews[paneId]?.controller
                {
                    return (paneId, controller)
                }
                do {
                    try await Task.sleep(
                        nanoseconds: Duration.milliseconds(25).nanosecondsForTaskSleep
                    )
                } catch {
                    return nil
                }
            }
            return nil
        }

        private func bridgeCompleteJourneyBrowserResult(
            controller: BridgePaneController,
            paneId: UUID,
            surface: BridgeCompleteJourneySurface
        ) async -> BridgeCompleteJourneyBrowserResult? {
            var latestProbeResult: BridgeCompleteJourneyBrowserResult?
            var latestNativeActivity = workspaceSurfaceCoordinator.bridgePaneActivity(for: paneId)
            var observedForegroundActivity = latestNativeActivity == .foreground
            let deadline =
                ContinuousClock.now
                + AppPolicies.StartupDiagnostic.bridgeFileViewSmokeReadinessTimeout
            while ContinuousClock.now < deadline {
                latestNativeActivity = workspaceSurfaceCoordinator.bridgePaneActivity(for: paneId)
                observedForegroundActivity =
                    observedForegroundActivity || latestNativeActivity == .foreground
                do {
                    let result = try await controller.page.callJavaScript(
                        Self.bridgeCompleteJourneyUsablePaintJavaScript(surface: surface)
                    )
                    if let json = result as? String, let data = json.data(using: .utf8) {
                        let decoded = try JSONDecoder().decode(
                            BridgeCompleteJourneyBrowserResult.self,
                            from: data
                        )
                        if decoded.outcome == "pending" {
                            latestProbeResult = decoded
                        } else {
                            return decoded
                        }
                    }
                } catch {
                    // Cold WebKit may reject evaluation before the document admits it.
                }
                if ContinuousClock.now >= deadline { break }
                do {
                    try await Task.sleep(
                        nanoseconds: Duration.milliseconds(25).nanosecondsForTaskSleep
                    )
                } catch {
                    return nil
                }
            }
            return BridgeCompleteJourneyBrowserResult(
                outcome: "failed",
                failureReason: bridgeCompleteJourneyUsablePaintTimeoutFailureReason(
                    observedForegroundActivity: observedForegroundActivity,
                    latestActivity: latestNativeActivity
                ),
                pageApplicationEpochMilliseconds: latestProbeResult?.pageApplicationEpochMilliseconds,
                handshakeWorkerEpochMilliseconds: latestProbeResult?.handshakeWorkerEpochMilliseconds,
                sourceMetadataEpochMilliseconds: latestProbeResult?.sourceMetadataEpochMilliseconds,
                selectionContentEpochMilliseconds: latestProbeResult?.selectionContentEpochMilliseconds,
                commitPaintEpochMilliseconds: nil
            )
        }

        private func bridgeCompleteJourneyTelemetryProofObservation(
            controller: BridgePaneController
        ) async -> BridgeCompleteJourneyTelemetryProofObservation {
            do {
                let flushResult = try await controller.flushTelemetryForIPC()
                guard let report = flushResult.report else {
                    return .missing(drainFailed: true)
                }
                return BridgeCompleteJourneyTelemetryProofObservation(
                    drainFailed: flushResult.drained != true,
                    lossy: report.lossy,
                    missingReport: false,
                    nativeBatchSequenceGapCount: report.nativeBatchSequenceGapCount,
                    optionalLossCount: report.optionalLossCount,
                    proofEligible: report.proofEligible,
                    requiredLossCount: report.requiredLossCount,
                    workerSequenceGapCount: report.workerSequenceGapCount
                )
            } catch {
                return .missing(drainFailed: true)
            }
        }

        private func closeBridgeCompleteJourneyPane(
            paneId: UUID,
            paneTabViewController: PaneTabViewController
        ) async -> Bool {
            paneTabViewController.execute(.closePane, target: paneId, targetType: .pane)
            await workspaceSurfaceCoordinator.drainBridgePaneRetirements()
            return store.paneAtom.paneSnapshot()[paneId] == nil
                && viewRegistry.allBridgeViews[paneId] == nil
        }

        private func closeBridgeCompleteJourneyPanesCreatedAfter(
            _ paneIdsBeforeOpen: Set<UUID>,
            paneTabViewController: PaneTabViewController
        ) async {
            let createdPaneIds = Set(store.paneAtom.paneSnapshot().keys).subtracting(paneIdsBeforeOpen)
            for paneId in createdPaneIds {
                paneTabViewController.execute(.closePane, target: paneId, targetType: .pane)
            }
            await workspaceSurfaceCoordinator.drainBridgePaneRetirements()
        }

        private func recordBridgeCompleteJourneyCohortResult(
            action: AgentStudioStartupDiagnosticAction,
            succeeded: Bool
        ) {
            let outcome = succeeded ? "succeeded" : "blocked"
            let attributes = startupDiagnosticTraceAttributes(for: action).merging([
                "agentstudio.startup_diagnostic.render_proof.succeeded": .bool(succeeded)
            ]) { _, newValue in newValue }
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.command_exercised",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: attributes
            )
            startupTraceRecorder.recordAppStartup(
                succeeded
                    ? "app.startup_diagnostic_action.completed"
                    : "app.startup_diagnostic_action.blocked",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: attributes
            )
        }

        private nonisolated static func bridgeCompleteJourneyConfigurationAdmission(
            environment: [String: String]
        ) -> BridgeCompleteJourneyConfigurationAdmission {
            guard
                let rawDataDirectory = environment[AppDataPaths.dataDirectoryEnvironmentKey]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !rawDataDirectory.isEmpty
            else {
                return .absent
            }
            let dataDirectory = URL(fileURLWithPath: rawDataDirectory).standardizedFileURL
            let configURL = BridgeCompleteJourneyConfiguration.configURL(dataDirectory: dataDirectory)
            guard FileManager.default.fileExists(atPath: configURL.path) else { return .absent }
            do {
                return .enabled(
                    configuration: try BridgeCompleteJourneyConfiguration.decode(
                        Data(contentsOf: configURL)
                    ),
                    receiptURL: BridgeCompleteJourneyConfiguration.receiptURL(
                        dataDirectory: dataDirectory
                    )
                )
            } catch {
                return .invalid
            }
        }

        private nonisolated static func bridgeCompleteJourneyAttempt(
            attemptId: String,
            startedAtEpochMilliseconds: Double,
            browserResult: BridgeCompleteJourneyBrowserResult?
        ) -> BridgeCompleteJourneyAttempt {
            guard let browserResult else {
                return bridgeCompleteJourneyFailedAttempt(
                    attemptId: attemptId,
                    startedAtEpochMilliseconds: startedAtEpochMilliseconds,
                    failureReason: "browser_verifier_failed"
                )
            }
            let elapsed = bridgeCompleteJourneyPhaseCompletion(
                startedAtEpochMilliseconds: startedAtEpochMilliseconds,
                browserResult: browserResult
            )
            let durationMilliseconds =
                elapsed.commitPaint
                ?? min(15_000, max(0, bridgeCompleteJourneyEpochMilliseconds() - startedAtEpochMilliseconds))
            return BridgeCompleteJourneyAttempt(
                attemptId: attemptId,
                durationMilliseconds: durationMilliseconds,
                outcome: browserResult.outcome == "succeeded" ? .succeeded : .failed,
                phaseCompletionElapsedMilliseconds: elapsed,
                failureReason: browserResult.outcome == "succeeded"
                    ? nil
                    : (browserResult.failureReason ?? "browser_verifier_failed")
            )
        }

        private nonisolated static func bridgeCompleteJourneyFailedAttempt(
            attemptId: String,
            startedAtEpochMilliseconds: Double,
            failureReason: String
        ) -> BridgeCompleteJourneyAttempt {
            BridgeCompleteJourneyAttempt(
                attemptId: attemptId,
                durationMilliseconds: min(
                    15_000,
                    max(0, bridgeCompleteJourneyEpochMilliseconds() - startedAtEpochMilliseconds)
                ),
                outcome: .failed,
                phaseCompletionElapsedMilliseconds: BridgeCompleteJourneyPhaseCompletion(),
                failureReason: failureReason
            )
        }

        private nonisolated static func bridgeCompleteJourneyPhaseCompletion(
            startedAtEpochMilliseconds: Double,
            browserResult: BridgeCompleteJourneyBrowserResult
        ) -> BridgeCompleteJourneyPhaseCompletion {
            var previousElapsed = 0.0
            func monotonicElapsed(_ epochMilliseconds: Double?) -> Double? {
                guard let epochMilliseconds else { return nil }
                let elapsed = max(previousElapsed, max(0, epochMilliseconds - startedAtEpochMilliseconds))
                previousElapsed = elapsed
                return elapsed
            }
            return BridgeCompleteJourneyPhaseCompletion(
                pageApplication: monotonicElapsed(browserResult.pageApplicationEpochMilliseconds),
                handshakeWorker: monotonicElapsed(browserResult.handshakeWorkerEpochMilliseconds),
                sourceMetadata: monotonicElapsed(browserResult.sourceMetadataEpochMilliseconds),
                selectionContent: monotonicElapsed(browserResult.selectionContentEpochMilliseconds),
                commitPaint: monotonicElapsed(browserResult.commitPaintEpochMilliseconds)
            )
        }

        private nonisolated static func bridgeCompleteJourneyEpochMilliseconds() -> Double {
            Date().timeIntervalSince1970 * 1000
        }
    }
#endif
