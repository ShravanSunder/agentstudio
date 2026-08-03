import Foundation
import Testing

@testable import AgentStudioBridge

struct BridgePaneSurfaceSelectionContractTests {
    @Test("pane surface-selection metadata carries a strict shared Review target command")
    func paneSurfaceSelectionMetadataCarriesStrictReviewTargetCommand() throws {
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let roundTrippedData = try encoder.encode(decoded)
        #expect(roundTrippedData == data)
    }

    @Test("pane surface-selection metadata accepts context and exact File command variants")
    func paneSurfaceSelectionMetadataAcceptsContextAndExactFileVariants() throws {
        var contextObject = surfaceSelectionFrameObject()
        contextObject["navigationCommand"] =
            [
                "bindingRevision": 2,
                "commandId": "native-selection-context-1",
                "commandKind": "activateContext",
                "surface": "file",
            ] as [String: Any]
        var fileObject = surfaceSelectionFrameObject()
        fileObject["navigationCommand"] =
            [
                "bindingRevision": 3,
                "commandId": "native-selection-file-1",
                "commandKind": "activateTarget",
                "source": [
                    "sourceId": "file-source-1",
                    "sourceKind": "file",
                    "subscriptionGeneration": 4,
                ],
                "surface": "file",
                "target": [
                    "path": "README.md",
                    "targetKind": "file",
                    "version": "current",
                ],
            ] as [String: Any]

        for object in [contextObject, fileObject] {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let decoded = try BridgeProductStrictJSON.decode(BridgeProductMetadataFrame.self, from: data)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let roundTripData = try encoder.encode(decoded)
            #expect(roundTripData == data)
        }
    }

    @Test("pane surface-selection metadata enforces the closed navigation command matrix")
    func paneSurfaceSelectionMetadataEnforcesClosedNavigationCommandMatrix() throws {
        let mutations: [(inout [String: Any]) -> Void] = [
            { (object: inout [String: Any]) in
                var command = object["navigationCommand"] as! [String: Any]
                command["bindingRevision"] = 0
                object["navigationCommand"] = command
            },
            { (object: inout [String: Any]) in
                var command = object["navigationCommand"] as! [String: Any]
                command["commandId"] = ""
                object["navigationCommand"] = command
            },
            { (object: inout [String: Any]) in
                var command = object["navigationCommand"] as! [String: Any]
                command["surface"] = "file"
                object["navigationCommand"] = command
            },
            { (object: inout [String: Any]) in
                var command = object["navigationCommand"] as! [String: Any]
                command["source"] =
                    [
                        "sourceId": "file-source-1",
                        "sourceKind": "file",
                        "subscriptionGeneration": 3,
                    ] as [String: Any]
                object["navigationCommand"] = command
            },
            { (object: inout [String: Any]) in
                var command = object["navigationCommand"] as! [String: Any]
                var target = command["target"] as! [String: Any]
                target["path"] = "Sources/App.swift"
                target.removeValue(forKey: "version")
                command["target"] = target
                object["navigationCommand"] = command
            },
            { (object: inout [String: Any]) in
                var command = object["navigationCommand"] as! [String: Any]
                command["publicationId"] = "publication-1"
                object["navigationCommand"] = command
            },
            { (object: inout [String: Any]) in object.removeValue(forKey: "paneSessionId") },
            { (object: inout [String: Any]) in object.removeValue(forKey: "workerInstanceId") },
            { (object: inout [String: Any]) in object.removeValue(forKey: "metadataStreamId") },
            { (object: inout [String: Any]) in object["unexpected"] = true },
        ]
        for mutation in mutations {
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

    @Test("navigation source generations match the JavaScript safe-integer boundary")
    func navigationSourceGenerationsMatchJavaScriptSafeIntegerBoundary() throws {
        // Arrange
        let maximumSafeInteger = BridgeProductWireContract.maximumSafeInteger
        let invalidGeneration = maximumSafeInteger + 1
        let maximumFileSource = BridgeProductNavigationFileSource(
            sourceId: "file-source-1",
            subscriptionGeneration: maximumSafeInteger
        )
        let maximumReviewSource = BridgeProductNavigationReviewSource(
            generation: maximumSafeInteger,
            metadataSourceId: "review-source-1",
            packageId: "review-package-1"
        )
        let invalidFileSourceData = try JSONSerialization.data(
            withJSONObject: [
                "sourceId": "file-source-1",
                "sourceKind": "file",
                "subscriptionGeneration": invalidGeneration,
            ]
        )
        let invalidReviewSourceData = try JSONSerialization.data(
            withJSONObject: [
                "generation": invalidGeneration,
                "metadataSourceId": "review-source-1",
                "packageId": "review-package-1",
                "sourceKind": "review",
            ]
        )

        // Act / Assert
        _ = try JSONEncoder().encode(maximumFileSource)
        _ = try JSONEncoder().encode(maximumReviewSource)
        #expect(throws: (any Error).self) {
            try JSONEncoder().encode(
                BridgeProductNavigationFileSource(
                    sourceId: "file-source-1",
                    subscriptionGeneration: invalidGeneration
                )
            )
        }
        #expect(throws: (any Error).self) {
            try JSONEncoder().encode(
                BridgeProductNavigationReviewSource(
                    generation: invalidGeneration,
                    metadataSourceId: "review-source-1",
                    packageId: "review-package-1"
                )
            )
        }
        #expect(throws: (any Error).self) {
            try BridgeProductStrictJSON.decode(
                BridgeProductNavigationFileSource.self,
                from: invalidFileSourceData
            )
        }
        #expect(throws: (any Error).self) {
            try BridgeProductStrictJSON.decode(
                BridgeProductNavigationReviewSource.self,
                from: invalidReviewSourceData
            )
        }
    }

    @Test("navigation source identifiers are revalidated when encoding")
    func navigationSourceIdentifiersAreRevalidatedWhenEncoding() {
        #expect(throws: (any Error).self) {
            try JSONEncoder().encode(
                BridgeProductNavigationFileSource(
                    sourceId: "invalid source",
                    subscriptionGeneration: 1
                )
            )
        }
        #expect(throws: (any Error).self) {
            try JSONEncoder().encode(
                BridgeProductNavigationReviewSource(
                    generation: 1,
                    metadataSourceId: "invalid source",
                    packageId: "review-package-1"
                )
            )
        }
        #expect(throws: (any Error).self) {
            try JSONEncoder().encode(
                BridgeProductNavigationReviewSource(
                    generation: 1,
                    metadataSourceId: "review-source-1",
                    packageId: "invalid package"
                )
            )
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
        #expect(staleRequest.bindingRevision > 0)
        #expect(currentRequest.bindingRevision == staleRequest.bindingRevision + 1)
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
        #expect(workerBRequest.requestId == workerARequest.requestId)
        #expect(workerBRequest.bindingRevision == workerARequest.bindingRevision + 1)
        #expect(workerBRequest.surface == .review)
        #expect(workerBRequest.workerInstanceId == "worker-instance-b")
        #expect(
            authority.admitReceipt(
                nativeSelectionRequestId: workerARequest.requestId,
                mode: .review,
                paneSessionId: "pane-session-1",
                workerInstanceId: "worker-instance-a"
            ) == .rejected(.wrongWorkerInstance)
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

    @Test("acknowledged native surface intent rebinds to a replacement worker")
    func acknowledgedNativeSurfaceIntentRebindsToReplacementWorker() throws {
        // Arrange
        var authority = BridgePaneSurfaceSelectionAuthority()
        authority.retainIntent(surface: .review)
        let workerARequest = try #require(
            try authority.bindRetainedIntent(
                paneSessionId: "pane-session-1",
                workerInstanceId: "worker-instance-a"
            )
        )
        #expect(
            authority.admitReceipt(
                nativeSelectionRequestId: workerARequest.requestId,
                mode: .review,
                paneSessionId: "pane-session-1",
                workerInstanceId: "worker-instance-a"
            ) == .accepted
        )

        // Act
        let workerBRequest = try authority.bindRetainedIntent(
            paneSessionId: "pane-session-1",
            workerInstanceId: "worker-instance-b"
        )

        // Assert
        let reboundRequest = try #require(workerBRequest)
        #expect(reboundRequest.surface == .review)
        #expect(reboundRequest.workerInstanceId == "worker-instance-b")
        #expect(reboundRequest.bindingRevision == workerARequest.bindingRevision + 1)
    }

    @Test("exact Review intent binds the committed source and target without publication identity")
    func exactReviewIntentBindsCommittedSourceAndTarget() throws {
        var authority = BridgePaneSurfaceSelectionAuthority()
        let source = BridgeProductNavigationReviewSource(
            generation: 9,
            metadataSourceId: "review-query-1",
            packageId: "review-package-1"
        )
        let target = BridgeProductNavigationReviewTarget(reviewItemId: "review-item-1")

        let retention = authority.retainReviewTarget(source: source, target: target)
        let request = try #require(
            try authority.bindRetainedIntent(
                paneSessionId: "pane-session-1",
                workerInstanceId: "worker-instance-1"
            )
        )

        #expect(request.requestId == retention.commandId)
        guard
            case .activateReviewTarget(let commandId, let revision, let boundSource, let boundTarget) =
                request.navigationCommand
        else {
            Issue.record("Expected exact Review navigation command")
            return
        }
        #expect(commandId == retention.commandId)
        #expect(revision == 1)
        #expect(boundSource == source)
        #expect(boundTarget == target)
    }

    @Test("binding invalidation rejects the stale receipt and truthfully rebinds retained intent")
    func bindingInvalidationRejectsStaleReceiptAndRebindsRetainedIntent() throws {
        var authority = BridgePaneSurfaceSelectionAuthority()
        authority.retainIntent(surface: .review)
        let staleRequest = try #require(
            try authority.bindRetainedIntent(
                paneSessionId: "pane-session-1",
                workerInstanceId: "worker-instance-a"
            )
        )

        #expect(authority.invalidateCurrentBinding() == staleRequest.requestId)
        #expect(
            authority.admitReceipt(
                nativeSelectionRequestId: staleRequest.requestId,
                mode: .review,
                paneSessionId: "pane-session-1",
                workerInstanceId: "worker-instance-a"
            ) == .rejected(.staleRequest)
        )
        let reboundRequest = try #require(
            try authority.bindRetainedIntent(
                paneSessionId: "pane-session-1",
                workerInstanceId: "worker-instance-b"
            )
        )
        #expect(reboundRequest.requestId == staleRequest.requestId)
        #expect(reboundRequest.bindingRevision == staleRequest.bindingRevision + 1)
    }

    private func surfaceSelectionFrameObject() -> [String: Any] {
        [
            "kind": "pane.surfaceSelectionRequested",
            "metadataStreamId": "metadata-stream-1",
            "navigationCommand": [
                "bindingRevision": 1,
                "commandId": "native-selection-request-1",
                "commandKind": "activateTarget",
                "source": [
                    "generation": 7,
                    "metadataSourceId": "review-query-1",
                    "packageId": "review-package-1",
                    "sourceKind": "review",
                ],
                "surface": "review",
                "target": [
                    "path": "Sources/App.swift",
                    "reviewItemId": "review-item-1",
                    "targetKind": "review",
                    "version": "head",
                ],
            ],
            "paneSessionId": "pane-session-1",
            "streamSequence": 2,
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
