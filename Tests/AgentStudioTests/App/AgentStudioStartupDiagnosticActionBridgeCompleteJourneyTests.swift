import Foundation
import Testing

@testable import AgentStudio

// Suite identity matches the startup diagnostic action it proves.
// swiftlint:disable:next type_name
struct AgentStudioStartupDiagnosticActionBridgeCompleteJourneyTests {
    @Test("complete journey configuration requires the explicit native mode")
    func configurationRequiresExplicitNativeMode() throws {
        let enabled = try BridgeCompleteJourneyConfiguration.decode(
            Data(#"{"enabled":true,"mode":"native","attemptCount":100,"launchId":"native-01"}"#.utf8)
        )

        #expect(enabled.attemptCount == 100)
        #expect(enabled.launchId == "native-01")

        for invalidConfiguration in [
            #"{"enabled":false,"mode":"native","attemptCount":100,"launchId":"native-01"}"#,
            #"{"enabled":true,"mode":"development","attemptCount":100,"launchId":"native-01"}"#,
            #"{"enabled":true,"mode":"native","attemptCount":0,"launchId":"native-01"}"#,
            #"{"enabled":true,"mode":"native","attemptCount":100,"launchId":"../../escape"}"#,
        ] {
            #expect(throws: (any Error).self) {
                _ = try BridgeCompleteJourneyConfiguration.decode(Data(invalidConfiguration.utf8))
            }
        }
    }

    @Test("complete journey uses fixed private config and receipt paths")
    func configurationUsesFixedPrivatePaths() {
        let dataDirectory = URL(fileURLWithPath: "/private/tmp/agentstudio-data", isDirectory: true)

        #expect(
            BridgeCompleteJourneyConfiguration.configURL(dataDirectory: dataDirectory).path
                == "/private/tmp/agentstudio-data/bridge-complete-journey/config.json"
        )
        #expect(
            BridgeCompleteJourneyConfiguration.receiptURL(dataDirectory: dataDirectory).path
                == "/private/tmp/agentstudio-data/bridge-complete-journey/native-launch.json"
        )
    }

    @Test("complete journey receipt encodes exactly four journey collections")
    func receiptEncodesExactlyFourJourneys() throws {
        let phaseCompletion = BridgeCompleteJourneyPhaseCompletion(
            pageApplication: 1,
            handshakeWorker: 2,
            sourceMetadata: 3,
            selectionContent: 4,
            commitPaint: 5
        )
        let attempt = BridgeCompleteJourneyAttempt(
            attemptId: "native-01-firstFile-0",
            durationMilliseconds: 5,
            outcome: .succeeded,
            phaseCompletionElapsedMilliseconds: phaseCompletion,
            failureReason: nil
        )
        let receipt = BridgeCompleteJourneyNativeLaunchReceipt(
            launchId: "native-01",
            attemptsByJourney: .init(
                firstFile: [attempt],
                firstReview: [attempt],
                fileToReview: [attempt],
                reviewToFile: [attempt]
            ),
            telemetryProof: BridgeCompleteJourneyTelemetryProof(expectedAttemptCount: 4)
        )

        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? [String: Any]
        )
        #expect(Set(object.keys) == ["launchId", "attemptsByJourney", "telemetryProof"])
        let attemptsByJourney = try #require(object["attemptsByJourney"] as? [String: Any])
        #expect(Set(attemptsByJourney.keys) == ["firstFile", "firstReview", "fileToReview", "reviewToFile"])
        let telemetryProof = try #require(object["telemetryProof"] as? [String: Any])
        #expect(
            Set(telemetryProof.keys) == [
                "drainFailureCount",
                "expectedAttemptCount",
                "lossyPaneReportCount",
                "missingPaneReportCount",
                "nativeBatchSequenceGapCount",
                "observedPaneReportCount",
                "optionalLossCount",
                "proofEligiblePaneReportCount",
                "requiredLossCount",
                "workerSequenceGapCount",
            ]
        )
    }

    @Test("complete journey telemetry proof aggregates real report outcomes")
    func telemetryProofAggregatesReportOutcomes() {
        var proof = BridgeCompleteJourneyTelemetryProof(expectedAttemptCount: 3)

        proof.merge(
            BridgeCompleteJourneyTelemetryProofObservation(
                drainFailed: false,
                lossy: false,
                missingReport: false,
                nativeBatchSequenceGapCount: 0,
                optionalLossCount: 0,
                proofEligible: true,
                requiredLossCount: 0,
                workerSequenceGapCount: 0
            )
        )
        proof.merge(.missing(drainFailed: true))
        proof.merge(
            BridgeCompleteJourneyTelemetryProofObservation(
                drainFailed: true,
                lossy: true,
                missingReport: false,
                nativeBatchSequenceGapCount: 3,
                optionalLossCount: 2,
                proofEligible: false,
                requiredLossCount: 1,
                workerSequenceGapCount: 4
            )
        )

        #expect(proof.expectedAttemptCount == 3)
        #expect(proof.observedPaneReportCount == 2)
        #expect(proof.missingPaneReportCount == 1)
        #expect(proof.proofEligiblePaneReportCount == 1)
        #expect(proof.lossyPaneReportCount == 1)
        #expect(proof.requiredLossCount == 1)
        #expect(proof.optionalLossCount == 2)
        #expect(proof.workerSequenceGapCount == 4)
        #expect(proof.nativeBatchSequenceGapCount == 3)
        #expect(proof.drainFailureCount == 2)
    }

    @Test("complete journey source uses canonical commands and exact cleanup")
    func sourceUsesCanonicalCommandsAndExactCleanup() throws {
        let source = try String(
            contentsOfFile: "Sources/AgentStudio/App/Boot/AppDelegate+BridgeCompleteJourneyCohortDiagnostics.swift",
            encoding: .utf8
        )

        for command in [
            ".openBridgeFilesInNewTab",
            ".openBridgeReviewInNewTab",
            ".showBridgeReview",
            ".showBridgeFiles",
        ] {
            #expect(source.contains(command))
        }
        #expect(source.contains("paneTabViewController.execute(surface.openCommand"))
        #expect(source.contains("paneTabViewController.execute(sourceSurface.openCommand"))
        #expect(source.contains("paneTabViewController.execute(targetSurface.switchCommand"))
        #expect(source.contains("paneTabViewController.execute(.closePane"))
        #expect(source.contains("workspaceSurfaceCoordinator.drainBridgePaneRetirements()"))
        #expect(source.contains("store.paneAtom.paneSnapshot()"))
        #expect(source.contains("viewRegistry.allBridgeViews"))
        #expect(source.contains("paneIdsAfterSwitch == paneIdsBeforeSwitch"))
        #expect(!source.contains("requestViewerSurface"))
        #expect(!source.contains("workspaceSurfaceCoordinator.openBridge"))
    }

    @Test("complete journey verifier requires current visible content and two later frames")
    func verifierRequiresCurrentVisibleContentAndTwoLaterFrames() throws {
        let javaScript = AppDelegate.bridgeCompleteJourneyUsablePaintJavaScript(surface: .review)

        for marker in [
            "bridge-app-root",
            "pageApplicationEpochMilliseconds = Date.now()",
            "document.visibilityState === 'visible'",
            "data-bridge-viewer-mode-active",
            "!host.inert",
            "data-review-metadata-item-count",
            "data-selected-content-state",
            "bridge-review-trees-panel",
            "bridge-code-view-panel",
            "bridge-viewer-context-file",
            "bridge-viewer-context-review",
            "bridge-review-view-settings-trigger",
            "bridge-file-view-settings-trigger",
            "control instanceof HTMLButtonElement && !control.disabled",
            "requestAnimationFrame",
            "pageReadyFirstObservedAtEpochMilliseconds",
            "commWorkerSessionReadyFirstObservedAtEpochMilliseconds",
            "nativeBootstrapInstallAcceptedFirstObservedAtEpochMilliseconds",
        ] {
            #expect(javaScript.contains(marker))
        }
        let pageReadyHandshake = try #require(
            javaScript.range(of: "diagnostic.pageReadyFirstObservedAtEpochMilliseconds,")
        )
        let workerReadyHandshake = try #require(
            javaScript.range(
                of: "diagnostic.commWorkerSessionReadyFirstObservedAtEpochMilliseconds,",
                range: pageReadyHandshake.upperBound..<javaScript.endIndex
            )
        )
        let bootstrapHandshake = try #require(
            javaScript.range(
                of: "diagnostic.nativeBootstrapInstallAcceptedFirstObservedAtEpochMilliseconds,",
                range: workerReadyHandshake.upperBound..<javaScript.endIndex
            )
        )
        #expect(workerReadyHandshake.lowerBound < bootstrapHandshake.lowerBound)
        #expect(javaScript.components(separatedBy: "requestAnimationFrame").count >= 3)
        #expect(javaScript.contains("__bridgeCompleteJourneyUsablePaintProbes"))
        #expect(javaScript.contains("outcome: 'pending'"))
        #expect(!javaScript.contains("return await new Promise"))
    }

    @Test("complete journey retries evaluator admission within one readiness deadline")
    func browserEvaluatorAdmissionUsesOneBoundedRetryWindow() throws {
        let source = try String(
            contentsOfFile: "Sources/AgentStudio/App/Boot/AppDelegate+BridgeCompleteJourneyCohortDiagnostics.swift",
            encoding: .utf8
        )
        let helperStart = try #require(
            source.range(of: "private func bridgeCompleteJourneyBrowserResult(")
        )
        let helperEnd = try #require(
            source.range(
                of: "private func closeBridgeCompleteJourneyPane(",
                range: helperStart.upperBound..<source.endIndex
            )
        )
        let helper = source[helperStart.lowerBound..<helperEnd.lowerBound]

        #expect(
            helper.contains(
                "ContinuousClock.now\n"
                    + "                + AppPolicies.StartupDiagnostic.bridgeFileViewSmokeReadinessTimeout"
            )
        )
        #expect(helper.contains("while ContinuousClock.now < deadline"))
        #expect(helper.contains("controller.page.callJavaScript"))
        #expect(helper.contains("decoded.outcome == \"pending\""))
        #expect(helper.contains("Task.sleep("))
        #expect(helper.components(separatedBy: "bridgeFileViewSmokeReadinessTimeout").count == 2)
        #expect(!helper.contains("guard let latestProbeResult else { return nil }"))
        #expect(helper.contains("latestProbeResult?.pageApplicationEpochMilliseconds"))
    }

    @Test("complete journey timeout distinguishes a pane that never became foreground")
    func timeoutDistinguishesNeverForegroundPaneActivity() {
        #expect(
            bridgeCompleteJourneyUsablePaintTimeoutFailureReason(
                observedForegroundActivity: false,
                latestActivity: .loadedHidden
            ) == "native_activity_never_foreground_loadedHidden"
        )
        #expect(
            bridgeCompleteJourneyUsablePaintTimeoutFailureReason(
                observedForegroundActivity: true,
                latestActivity: .loadedHidden
            ) == "usable_paint_timeout"
        )
        #expect(
            bridgeCompleteJourneyUsablePaintTimeoutFailureReason(
                observedForegroundActivity: false,
                latestActivity: nil
            ) == "native_activity_missing"
        )
    }

    @Test("complete journey flushes telemetry after T1 and before close")
    func telemetryFlushFollowsBrowserResultAndPrecedesClose() throws {
        let source = try String(
            contentsOfFile: "Sources/AgentStudio/App/Boot/AppDelegate+BridgeCompleteJourneyCohortDiagnostics.swift",
            encoding: .utf8
        )
        for (functionName, nextFunctionName) in [
            (
                "private func collectBridgeCompleteJourneyFirstPaneAttempt(",
                "private func collectBridgeCompleteJourneySwitchAttempt("
            ),
            (
                "private func collectBridgeCompleteJourneySwitchAttempt(",
                "private func waitForBridgeCompleteJourneyPane("
            ),
        ] {
            let functionStart = try #require(source.range(of: functionName))
            let functionEnd = try #require(
                source.range(
                    of: nextFunctionName,
                    range: functionStart.upperBound..<source.endIndex
                )
            )
            let function = source[functionStart.lowerBound..<functionEnd.lowerBound]
            let browserResult = try #require(function.range(of: "bridgeCompleteJourneyBrowserResult("))
            let telemetryFlush = try #require(
                function.range(
                    of: "bridgeCompleteJourneyTelemetryProofObservation(",
                    range: browserResult.upperBound..<function.endIndex
                )
            )
            let close = try #require(
                function.range(
                    of: "closeBridgeCompleteJourneyPane(",
                    range: telemetryFlush.upperBound..<function.endIndex
                )
            )
            #expect(telemetryFlush.lowerBound < close.lowerBound)
        }
        #expect(source.contains("controller.flushTelemetryForIPC()"))
    }

    @Test("paint diagnostic admits worktree before cohort and its one-shot Review open")
    func paintDiagnosticAdmitsWorktreeBeforeCohortAndOneShotReviewOpen() throws {
        let source = try String(
            contentsOfFile:
                "Sources/AgentStudio/App/Boot/AppDelegate+BridgeProductPaintCorrelationStartupDiagnostics.swift",
            encoding: .utf8
        )
        let worktreeCreation = try #require(
            source.range(of: "store.mutationCoordinator.ensureMainWorktree(")
        )
        let worktreeAdmission = try #require(
            source.range(
                of: "workspaceSurfaceCoordinator.syncFilesystemRootsAndActivityUntilIdle()",
                range: worktreeCreation.upperBound..<source.endIndex
            )
        )
        let cohortBranch = try #require(
            source.range(
                of: "runBridgeCompleteJourneyCohortIfConfigured(",
                range: worktreeAdmission.upperBound..<source.endIndex
            )
        )
        let oneShotOpen = try #require(
            source.range(of: "workspaceSurfaceCoordinator.openBridgeReviewInNewTab(")
        )

        #expect(worktreeCreation.lowerBound < worktreeAdmission.lowerBound)
        #expect(worktreeAdmission.lowerBound < cohortBranch.lowerBound)
        #expect(cohortBranch.lowerBound < oneShotOpen.lowerBound)
    }
}
