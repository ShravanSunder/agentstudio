import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests.BridgePaneControllerIPCProjectionTests {
    @Test("IPC render state maps bridge diagnostics probes and bounds discard records")
    func ipcRenderState_mapsBridgeDiagnosticsProbesAndBoundsDiscardRecords() async throws {
        let controller = makeIPCRenderStateForegroundController()
        defer { controller.teardown() }

        try await WebPageTestHarness.withManagedPage(controller.page) { page in
            _ = try await page.callJavaScript(
                """
                window.__bridgeVisibleHydrationStateProbe = {
                  reportedVisibleItemCount: 24,
                  trackedVisibleItemCount: 12,
                  truncatedVisibleItemCount: 12,
                  untrackedItemCount: 3,
                  loadingItemCount: 4,
                  readyItemCount: 5,
                  failedItemCount: 6,
                  deferredItemCount: 7,
                  abortedItemCount: 8,
                  pausedNow: true
                };
                window.__bridgeVisibleHydrationDiscardProbe = {
                  readyResultDiscardCount: 25,
                  records: Array.from({ length: 25 }, (_, index) => ({
                    hadState: index >= 5,
                    pausedNow: index % 2 === 0
                  }))
                };
                window.__bridgeFrameJankProbe = {
                  long_task: { count: 2, total_ms: 44.5, max_ms: 30.25 },
                  dropped_frame: { count: 3, worst_gap_ms: 19.75 },
                  last_long_task_at_ms: 1234.5
                };
                window.__bridgeProductMetadataStreamDiagnostic = {
                  kind: 'productMetadataStream',
                  acknowledgedFrameCount: 1,
                  activeSubscriptionCount: 2,
                  committedFrameCount: 1,
                  decoderState: 'poisoned',
                  expectedNextStreamSequence: 1,
                  failureCode: 'stream_identity_mismatch',
                  failureStage: 'acknowledgement',
                  identityMismatchField: 'metadataStreamId',
                  lastChunkByteCount: 256,
                  lastAcknowledgedStreamSequence: 0,
                  lastCommittedFrameKind: 'metadataStream.accepted',
                  lastRoutedFrameKind: 'subscription.accepted',
                  lifecycleState: 'failed',
                  peakRetainedByteCount: 512,
                  pushCount: 2,
                  readFulfilledCount: 3,
                  readPending: false,
                  readRequestCount: 4,
                  receivedByteCount: 768,
                  retainedByteCount: 0,
                  routeFailureCode: 'unknown_subscription',
                  routedFrameCount: 2,
                  streamOpenCount: 1
                };
                """
            )

            let result = try await controller.renderStateForIPC()
            let hydrationState = try #require(result.summary.visibleHydrationStateProbe)
            let discardProbe = try #require(result.summary.visibleHydrationDiscardProbe)
            let frameJankProbe = try #require(result.summary.frameJankProbe)
            let metadataStream = try #require(result.diagnostics.productMetadataStream)
            let productSession = result.diagnostics.productSession

            #expect(hydrationState.reportedVisibleItemCount == 24)
            #expect(hydrationState.trackedVisibleItemCount == 12)
            #expect(hydrationState.truncatedVisibleItemCount == 12)
            #expect(hydrationState.untrackedItemCount == 3)
            #expect(hydrationState.loadingItemCount == 4)
            #expect(hydrationState.readyItemCount == 5)
            #expect(hydrationState.failedItemCount == 6)
            #expect(hydrationState.deferredItemCount == 7)
            #expect(hydrationState.abortedItemCount == 8)
            #expect(hydrationState.pausedNow == true)
            #expect(discardProbe.readyResultDiscardCount == 25)
            #expect(discardProbe.records.count == 20)
            #expect(discardProbe.records.allSatisfy { $0.hadState == true })
            #expect(discardProbe.records.first?.pausedNow == false)
            #expect(frameJankProbe.longTask.count == 2)
            #expect(frameJankProbe.longTask.totalMs == 44.5)
            #expect(frameJankProbe.longTask.maxMs == 30.25)
            #expect(frameJankProbe.droppedFrame.count == 3)
            #expect(frameJankProbe.droppedFrame.worstGapMs == 19.75)
            #expect(frameJankProbe.lastLongTaskAtMs == 1234.5)
            #expect(result.visibleHydrationStateProbe == hydrationState)
            #expect(result.visibleHydrationDiscardProbe == discardProbe)
            #expect(result.frameJankProbe == frameJankProbe)
            expectProductMetadataStreamDiagnostic(metadataStream)
            #expect(productSession.activeProducerCount == 0)
            #expect(productSession.activeProducerTaskCount == 0)
            #expect(productSession.activeContentLeaseCount == 0)
            #expect(productSession.queuedFrameCount == 0)
            #expect(productSession.queuedByteCount == 0)
            #expect(productSession.pendingFrameWaiterCount == 0)
            #expect(productSession.inFlightFrameReceiptCount == 0)
            #expect(productSession.pendingLifecycleAcknowledgementCount == 0)
            #expect(productSession.nextMetadataStreamSequence == 0)
        }
    }

    @Test("IPC render state projects every bounded native pane activity value")
    func ipcRenderState_projectsEveryBoundedNativePaneActivityValue() async throws {
        let expectedActivities: [BridgePaneActivity] = [
            .foreground,
            .loadedHidden,
            .dormant,
            .closed,
        ]

        for expectedActivity in expectedActivities {
            let controller = makeIPCRenderStateForegroundController()
            controller.refreshAdmissionCoordinator.applyActivity(expectedActivity)
            defer { controller.teardown() }

            try await WebPageTestHarness.withManagedPage(controller.page) { _ in
                let result = try await controller.renderStateForIPC()
                let diagnostics = try encodedIPCBridgeDiagnostics(result.diagnostics)

                #expect(diagnostics["nativeActivity"] as? String == expectedActivity.rawValue)
            }
        }
    }

    @Test("IPC render state projects native dirty and catch-up diagnostics")
    func ipcRenderState_projectsNativeDirtyAndCatchUpDiagnostics() async throws {
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(panelKind: .diffViewer, source: nil),
            initialPaneActivity: .loadedHidden
        )
        defer { controller.teardown() }
        controller.refreshAdmissionCoordinator.recordInvalidation(
            fileChangeset: nil,
            requiresReviewRefresh: true
        )
        controller.refreshAdmissionCoordinator.applyActivity(.foreground)
        _ = try #require(controller.refreshAdmissionCoordinator.reserveForegroundRefreshPass())
        controller.refreshAdmissionCoordinator.recordInvalidation(
            fileChangeset: nil,
            requiresReviewRefresh: true
        )
        let nativeSnapshot = controller.refreshAdmissionCoordinator.diagnosticSnapshot

        try await WebPageTestHarness.withManagedPage(controller.page) { _ in
            let result = try await controller.renderStateForIPC()
            let diagnostics = try encodedIPCBridgeDiagnostics(result.diagnostics)

            #expect(diagnostics["nativeActivity"] as? String == nativeSnapshot.activity.rawValue)
            #expect(
                (diagnostics["foregroundWorkEpoch"] as? NSNumber)?.uint64Value
                    == nativeSnapshot.foregroundWorkEpoch
            )
            #expect(diagnostics["dirtyFactPresent"] as? Bool == (nativeSnapshot.dirtyFact != nil))
            #expect(
                diagnostics["activeRefreshPassPresent"] as? Bool
                    == (nativeSnapshot.activeRefreshPass != nil)
            )
            #expect(
                (diagnostics["refreshPassCount"] as? NSNumber)?.intValue
                    == nativeSnapshot.refreshPassCount
            )
        }
    }

    @Test("IPC render state rejects negative worker acknowledgement diagnostics")
    func ipcRenderState_rejectsNegativeWorkerAcknowledgementDiagnostics() async throws {
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(panelKind: .diffViewer, source: nil),
            initialPaneActivity: .foreground
        )
        defer { controller.teardown() }

        try await WebPageTestHarness.withManagedPage(controller.page) { page in
            _ = try await page.callJavaScript(
                """
                window.__bridgeProductMetadataStreamDiagnostic = {
                  kind: 'productMetadataStream',
                  acknowledgedFrameCount: -1,
                  lastAcknowledgedStreamSequence: -2,
                  failureStage: 'acknowledgement'
                };
                """
            )

            let result = try await controller.renderStateForIPC()
            let diagnostic = try #require(result.diagnostics.productMetadataStream)

            #expect(diagnostic.acknowledgedFrameCount == nil)
            #expect(diagnostic.lastAcknowledgedStreamSequence == nil)
            #expect(diagnostic.failureStage == "acknowledgement")
        }
    }

    @Test("IPC render state projects bounded Review DOM facts")
    func ipcRenderState_projectsBoundedReviewDOMFacts() async throws {
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(panelKind: .diffViewer, source: nil),
            initialPaneActivity: .foreground
        )
        defer { controller.teardown() }

        try await WebPageTestHarness.withManagedPage(controller.page) { page in
            _ = try await page.callJavaScript(
                """
                document.body.innerHTML = `
                  <div
                    data-bridge-viewer-mode-active="true"
                    data-bridge-viewer-mode-host="review"
                  >
                    <div
                      data-selected-item-id="review-item-42"
                      data-testid="bridge-code-view-panel"
                    ></div>
                  </div>
                  <div
                    data-bridge-viewer-mode-active="false"
                    data-bridge-viewer-mode-host="file"
                  ></div>
                `;
                const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
                const diffContainer = document.createElement('diffs-container');
                const shadowRoot = diffContainer.attachShadow({ mode: 'open' });
                shadowRoot.textContent = 'rendered Review content';
                codePanel.append(diffContainer);
                Object.defineProperty(document, 'visibilityState', {
                  configurable: true,
                  value: 'visible'
                });
                window.__bridgeFrameLivenessProbe = { rafAlive: 'true' };
                """
            )

            let result = try await controller.renderStateForIPC()

            #expect(result.summary.activeViewerMode == "review")
            #expect(result.summary.documentVisibilityState == "visible")
            #expect(result.summary.frameLivenessRafAlive == "true")
            #expect(result.summary.reviewSelectedItemId == "review-item-42")
            #expect(result.summary.reviewCodeTextLength == 23)
        }
    }

    @Test("IPC render state rejects invalid and absent Review DOM facts")
    func ipcRenderState_rejectsInvalidAndAbsentReviewDOMFacts() async throws {
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(panelKind: .diffViewer, source: nil),
            initialPaneActivity: .foreground
        )
        defer { controller.teardown() }

        try await WebPageTestHarness.withManagedPage(controller.page) { page in
            _ = try await page.callJavaScript(
                """
                document.body.innerHTML = `
                  <div
                    data-bridge-viewer-mode-active="true"
                    data-bridge-viewer-mode-host="terminal"
                  ></div>
                `;
                Object.defineProperty(document, 'visibilityState', {
                  configurable: true,
                  value: 'compromised'
                });
                window.__bridgeFrameLivenessProbe = { rafAlive: 'sometimes' };
                """
            )

            let result = try await controller.renderStateForIPC()

            #expect(result.summary.activeViewerMode == nil)
            #expect(result.summary.documentVisibilityState == nil)
            #expect(result.summary.frameLivenessRafAlive == nil)
            #expect(result.summary.reviewSelectedItemId == nil)
            #expect(result.summary.reviewCodeTextLength == nil)
        }
    }

    @Test("IPC render state leaves absent bridge diagnostics probes nil")
    func ipcRenderState_leavesAbsentBridgeDiagnosticsProbesNil() async throws {
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(panelKind: .diffViewer, source: nil),
            initialPaneActivity: .foreground
        )
        defer { controller.teardown() }

        try await WebPageTestHarness.withManagedPage(controller.page) { _ in
            let result = try await controller.renderStateForIPC()

            #expect(result.summary.visibleHydrationStateProbe == nil)
            #expect(result.summary.visibleHydrationDiscardProbe == nil)
            #expect(result.summary.frameJankProbe == nil)
            #expect(result.visibleHydrationStateProbe == nil)
            #expect(result.visibleHydrationDiscardProbe == nil)
            #expect(result.frameJankProbe == nil)
            #expect(result.diagnostics.productMetadataStream == nil)
            #expect(result.diagnostics.productSession.activeProducerCount == 0)
        }
    }

    @Test("IPC render state preserves native product session diagnostics when page projection fails")
    func ipcRenderState_preservesNativeProductSessionDiagnosticsWhenPageProjectionFails() async throws {
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(panelKind: .diffViewer, source: nil),
            initialPaneActivity: .foreground
        )
        defer { controller.teardown() }

        try await WebPageTestHarness.withManagedPage(controller.page) { page in
            _ = try await page.callJavaScript("JSON.stringify = () => null;")

            let result = try await controller.renderStateForIPC()

            #expect(!result.diagnostics.evaluateSucceeded)
            #expect(result.diagnostics.pageErrorKinds == ["render_state_result_not_string"])
            #expect(result.diagnostics.productMetadataStream == nil)
            #expect(result.diagnostics.productSession.activeProducerCount == 0)
            #expect(result.diagnostics.productSession.nextMetadataStreamSequence == 0)
        }
    }
}

@MainActor
private func makeIPCRenderStateForegroundController() -> BridgePaneController {
    BridgePaneController(
        paneId: UUIDv7.generate(),
        state: BridgePaneState(panelKind: .diffViewer, source: nil),
        initialPaneActivity: .foreground
    )
}

private func encodedIPCBridgeDiagnostics(
    _ diagnostics: IPCBridgeRenderDiagnostics
) throws -> [String: Any] {
    let encodedDiagnostics = try JSONEncoder().encode(diagnostics)
    return try #require(
        JSONSerialization.jsonObject(with: encodedDiagnostics) as? [String: Any]
    )
}

private func expectProductMetadataStreamDiagnostic(
    _ diagnostic: IPCBridgeProductMetadataStreamDiagnostic
) {
    #expect(diagnostic.kind == .productMetadataStream)
    #expect(diagnostic.acknowledgedFrameCount == 1)
    #expect(diagnostic.activeSubscriptionCount == 2)
    #expect(diagnostic.committedFrameCount == 1)
    #expect(diagnostic.decoderState == "poisoned")
    #expect(diagnostic.expectedNextStreamSequence == 1)
    #expect(diagnostic.failureCode == "stream_identity_mismatch")
    #expect(diagnostic.failureStage == "acknowledgement")
    #expect(diagnostic.identityMismatchField == "metadataStreamId")
    #expect(diagnostic.lastChunkByteCount == 256)
    #expect(diagnostic.lastAcknowledgedStreamSequence == 0)
    #expect(diagnostic.lastCommittedFrameKind == "metadataStream.accepted")
    #expect(diagnostic.lastRoutedFrameKind == "subscription.accepted")
    #expect(diagnostic.lifecycleState == "failed")
    #expect(diagnostic.peakRetainedByteCount == 512)
    #expect(diagnostic.pushCount == 2)
    #expect(diagnostic.readFulfilledCount == 3)
    #expect(diagnostic.readPending == false)
    #expect(diagnostic.readRequestCount == 4)
    #expect(diagnostic.receivedByteCount == 768)
    #expect(diagnostic.retainedByteCount == 0)
    #expect(diagnostic.routeFailureCode == "unknown_subscription")
    #expect(diagnostic.routedFrameCount == 2)
    #expect(diagnostic.streamOpenCount == 1)
}
