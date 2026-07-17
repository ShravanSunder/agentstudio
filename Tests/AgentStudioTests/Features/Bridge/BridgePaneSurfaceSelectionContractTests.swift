import Foundation
import Testing

@testable import AgentStudio

struct BridgePaneSurfaceSelectionContractTests {
    @Test("pane surface-selection metadata carries exact native and stream identity")
    func paneSurfaceSelectionMetadataCarriesExactIdentity() throws {
        // Arrange
        let object = surfaceSelectionFrameObject()
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        // Act
        let decoded = try BridgeProductStrictJSON.decode(BridgeProductMetadataFrame.self, from: data)

        // Assert
        guard case .paneSurfaceSelectionRequested(let frame) = decoded else {
            Issue.record("Expected pane.surfaceSelectionRequested metadata frame")
            return
        }
        #expect(frame.frameIdentity.metadataStreamId == "metadata-stream-1")
        #expect(frame.frameIdentity.paneSessionId == "pane-session-1")
        #expect(frame.frameIdentity.streamSequence == 2)
        #expect(frame.frameIdentity.wireVersion == BridgeProductWireContract.version)
        #expect(frame.frameIdentity.workerInstanceId == "worker-instance-1")
        #expect(frame.requestId == "native-selection-request-1")
        #expect(frame.selectionRevision == 1)
        #expect(frame.surface == .review)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let roundTrippedData = try encoder.encode(decoded)
        let roundTrippedObject = try #require(
            JSONSerialization.jsonObject(with: roundTrippedData) as? [String: AnyHashable]
        )
        #expect(roundTrippedObject == object)
    }

    @Test("pane surface-selection metadata remains a closed positive contract")
    func paneSurfaceSelectionMetadataRemainsClosedAndPositive() throws {
        for mutation in [
            { (object: inout [String: AnyHashable]) in object["selectionRevision"] = 0 },
            { (object: inout [String: AnyHashable]) in object["requestId"] = "" },
            { (object: inout [String: AnyHashable]) in object["surface"] = "terminal" },
            { (object: inout [String: AnyHashable]) in object.removeValue(forKey: "paneSessionId") },
            { (object: inout [String: AnyHashable]) in object.removeValue(forKey: "workerInstanceId") },
            { (object: inout [String: AnyHashable]) in object.removeValue(forKey: "metadataStreamId") },
            { (object: inout [String: AnyHashable]) in object["unexpected"] = true },
        ] {
            // Arrange
            var object = surfaceSelectionFrameObject()
            mutation(&object)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

            // Act / Assert
            #expect(throws: (any Error).self) {
                try BridgeProductStrictJSON.decode(BridgeProductMetadataFrame.self, from: data)
            }
        }
    }

    @Test("active-viewer receipt requires an explicit nullable native request id")
    func activeViewerReceiptRequiresExplicitNullableNativeRequestId() throws {
        // Arrange
        let baseObject: [String: Any] = [
            "activeSource": NSNull(),
            "nativeSelectionRequestId": NSNull(),
            "sequence": 1,
            "sessionId": "viewer-session-1",
        ]

        // Act / Assert
        let nullReceipt = try decodeActiveViewerUpdate(baseObject)
        #expect(nullReceipt.nativeSelectionRequestId == nil)

        var correlatedObject = baseObject
        correlatedObject["nativeSelectionRequestId"] = "native-selection-request-1"
        let correlatedReceipt = try decodeActiveViewerUpdate(correlatedObject)
        #expect(correlatedReceipt.nativeSelectionRequestId == "native-selection-request-1")

        var missingObject = baseObject
        missingObject.removeValue(forKey: "nativeSelectionRequestId")
        #expect(throws: (any Error).self) { try decodeActiveViewerUpdate(missingObject) }

        var emptyObject = baseObject
        emptyObject["nativeSelectionRequestId"] = ""
        #expect(throws: (any Error).self) { try decodeActiveViewerUpdate(emptyObject) }

        var unknownKeyObject = baseObject
        unknownKeyObject["unexpected"] = true
        #expect(throws: (any Error).self) { try decodeActiveViewerUpdate(unknownKeyObject) }
    }

    @Test("native receipt authority accepts only the current exact request and replay")
    func nativeReceiptAuthorityAcceptsOnlyCurrentExactRequestAndReplay() throws {
        // Arrange
        var authority = BridgePaneSurfaceSelectionAuthority()
        authority.retainIntent(surface: .file)
        let staleRequestCandidate = try authority.bindRetainedIntent(
            paneSessionId: "pane-session-1",
            workerInstanceId: "worker-instance-1"
        )
        let staleRequest = try #require(staleRequestCandidate)
        authority.retainIntent(surface: .review)
        let currentRequestCandidate = try authority.bindRetainedIntent(
            paneSessionId: "pane-session-1",
            workerInstanceId: "worker-instance-1"
        )
        let currentRequest = try #require(currentRequestCandidate)
        #expect(staleRequest.selectionRevision > 0)
        #expect(currentRequest.selectionRevision == staleRequest.selectionRevision + 1)
        #expect(!currentRequest.requestId.isEmpty)

        // Act / Assert: stale and mismatched receipts cannot consume the current request.
        #expect(
            authority.admitReceipt(
                nativeSelectionRequestId: staleRequest.requestId,
                mode: .review,
                paneSessionId: "pane-session-1",
                workerInstanceId: "worker-instance-1"
            ) == .rejected(.staleRequest)
        )
        #expect(
            authority.admitReceipt(
                nativeSelectionRequestId: currentRequest.requestId,
                mode: .file,
                paneSessionId: "pane-session-1",
                workerInstanceId: "worker-instance-1"
            ) == .rejected(.wrongMode)
        )
        #expect(
            authority.admitReceipt(
                nativeSelectionRequestId: currentRequest.requestId,
                mode: .review,
                paneSessionId: "other-pane-session",
                workerInstanceId: "worker-instance-1"
            ) == .rejected(.wrongPaneSession)
        )
        #expect(
            authority.admitReceipt(
                nativeSelectionRequestId: currentRequest.requestId,
                mode: .review,
                paneSessionId: "pane-session-1",
                workerInstanceId: "other-worker-instance"
            ) == .rejected(.wrongWorkerInstance)
        )

        #expect(
            authority.admitReceipt(
                nativeSelectionRequestId: currentRequest.requestId,
                mode: .review,
                paneSessionId: "pane-session-1",
                workerInstanceId: "worker-instance-1"
            ) == .accepted
        )
        #expect(
            authority.admitReceipt(
                nativeSelectionRequestId: currentRequest.requestId,
                mode: .review,
                paneSessionId: "pane-session-1",
                workerInstanceId: "worker-instance-1"
            ) == .idempotentReplay
        )
    }

    @Test("unsettled native surface intent rebinds to a replacement worker")
    func unsettledNativeSurfaceIntentRebindsToReplacementWorker() throws {
        // Arrange
        var authority = BridgePaneSurfaceSelectionAuthority()
        authority.retainIntent(surface: .review)
        let workerARequestCandidate = try authority.bindRetainedIntent(
            paneSessionId: "pane-session-1",
            workerInstanceId: "worker-instance-a"
        )
        let workerARequest = try #require(workerARequestCandidate)
        #expect(
            try authority.bindRetainedIntent(
                paneSessionId: "pane-session-1",
                workerInstanceId: "worker-instance-a"
            ) == nil
        )

        // Act
        let workerBRequestCandidate = try authority.bindRetainedIntent(
            paneSessionId: "pane-session-1",
            workerInstanceId: "worker-instance-b"
        )
        let workerBRequest = try #require(workerBRequestCandidate)

        // Assert
        #expect(workerBRequest.requestId != workerARequest.requestId)
        #expect(workerBRequest.selectionRevision == workerARequest.selectionRevision + 1)
        #expect(workerBRequest.surface == .review)
        #expect(workerBRequest.workerInstanceId == "worker-instance-b")
        #expect(
            authority.admitReceipt(
                nativeSelectionRequestId: workerARequest.requestId,
                mode: .review,
                paneSessionId: "pane-session-1",
                workerInstanceId: "worker-instance-a"
            ) == .rejected(.staleRequest)
        )
        #expect(
            authority.admitReceipt(
                nativeSelectionRequestId: workerBRequest.requestId,
                mode: .review,
                paneSessionId: "pane-session-1",
                workerInstanceId: "worker-instance-b"
            ) == .accepted
        )
    }

    private func surfaceSelectionFrameObject() -> [String: AnyHashable] {
        [
            "kind": "pane.surfaceSelectionRequested",
            "metadataStreamId": "metadata-stream-1",
            "paneSessionId": "pane-session-1",
            "requestId": "native-selection-request-1",
            "selectionRevision": 1,
            "streamSequence": 2,
            "surface": "review",
            "wireVersion": BridgeProductWireContract.version,
            "workerInstanceId": "worker-instance-1",
        ]
    }

    private func decodeActiveViewerUpdate(
        _ object: [String: Any]
    ) throws -> BridgeProductActiveViewerModeUpdateRequest {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try BridgeProductStrictJSON.decode(
            BridgeProductActiveViewerModeUpdateRequest.self,
            from: data
        )
    }
}
