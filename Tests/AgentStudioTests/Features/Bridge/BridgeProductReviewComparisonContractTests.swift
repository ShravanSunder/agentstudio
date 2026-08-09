import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge product Review comparison contract")
struct BridgeProductReviewComparisonContractTests {
    @Test("comparison update acknowledges only after the committed target effect")
    func comparisonUpdateAcknowledgesAfterCommittedTargetEffect() async throws {
        // Arrange
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        let session = try BridgeProductSession(
            paneSessionId: bridgeProductTestPaneSessionId,
            workerInstanceId: bridgeProductTestWorkerInstanceId,
            capabilityBytes: capabilityBytes
        )
        let recorder = await MainActor.run { BridgeProductComparisonTargetRecorder() }
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let provider = BridgePaneProductSchemeProvider(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
            markReviewItemViewed: { _, _ in },
            applyReviewComparisonUpdate: { request, _ in
                recorder.record(request.target)
            },
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        let productAdmission = try BridgeProductAdmissionTestContext.make().context
        let dispatcher = makeBridgeProductSchemeControlDispatcher(
            session: session,
            provider: provider,
            productAdmission: productAdmission
        )
        _ = try await dispatcher.dispatch(
            exactRequestBytes: bridgeProductSchemeWorkerOpenBody(),
            presentedCapability: capabilityHeader
        )

        // Act
        let result = try await dispatcher.dispatch(
            exactRequestBytes: reviewComparisonUpdateBody(),
            presentedCapability: capabilityHeader
        )

        // Assert
        guard case .response(let responseBytes) = result,
            case .callCompleted(let response) = try BridgeProductStrictJSON.decode(
                BridgeProductControlResponse.self,
                from: responseBytes
            )
        else {
            Issue.record("Expected a committed comparison-update completion")
            return
        }
        #expect(response.call == .reviewComparisonUpdate)
        #expect(await recorder.targets == [.branch(name: "stack/base")])
    }

    @Test("failed comparison target effect suppresses successful acknowledgement")
    func failedComparisonTargetEffectSuppressesAcknowledgement() async throws {
        // Arrange
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        let session = try BridgeProductSession(
            paneSessionId: bridgeProductTestPaneSessionId,
            workerInstanceId: bridgeProductTestWorkerInstanceId,
            capabilityBytes: capabilityBytes
        )
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let productAdmissionGate = BridgeProductAdmissionGate()
        let provider = BridgePaneProductSchemeProvider(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
            markReviewItemViewed: { _, _ in },
            applyReviewComparisonUpdate: { _, _ in
                productAdmissionGate.close()
            },
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        let productAdmission = try #require(productAdmissionGate.acquire())
        let dispatcher = makeBridgeProductSchemeControlDispatcher(
            session: session,
            provider: provider,
            productAdmission: productAdmission
        )
        _ = try await dispatcher.dispatch(
            exactRequestBytes: bridgeProductSchemeWorkerOpenBody(),
            presentedCapability: capabilityHeader
        )

        // Act
        let result = try await dispatcher.dispatch(
            exactRequestBytes: reviewComparisonUpdateBody(),
            presentedCapability: capabilityHeader
        )

        // Assert
        #expect(result == .admissionClosed)
    }

    @Test("target-only comparison update request and null result round trip")
    func targetOnlyComparisonUpdateRoundTrips() throws {
        // Arrange
        let requestJSON = Data(
            #"{"method":"review.comparison.update","request":{"target":{"kind":"branch","name":"stack/base"}}}"#.utf8
        )
        let resultJSON = Data(
            #"{"method":"review.comparison.update","result":null}"#.utf8
        )

        // Act
        let request = try BridgeProductStrictJSON.decode(
            BridgeProductCallRequest.self,
            from: requestJSON
        )
        let result = try BridgeProductStrictJSON.decode(
            BridgeProductCallResult.self,
            from: resultJSON
        )
        let encodedRequest = try sortedJSONObject(request)
        let canonicalRequest = try sortedJSONObject(from: requestJSON)
        let encodedResult = try sortedJSONObject(result)
        let canonicalResult = try sortedJSONObject(from: resultJSON)

        // Assert
        #expect(
            request
                == .reviewComparisonUpdate(
                    BridgeProductReviewComparisonUpdateRequest(
                        target: .branch(name: "stack/base")
                    )
                )
        )
        #expect(result == .reviewComparisonUpdate)
        #expect(encodedRequest == canonicalRequest)
        #expect(encodedResult == canonicalResult)
    }

    @Test("pane presentation carries canonical target attempt and snapshot identity")
    func panePresentationCarriesComparisonState() throws {
        // Arrange
        let presentationJSON = Data(
            #"{"kind":"pane.presentation","wireVersion":2,"paneSessionId":"pane-session-1","workerInstanceId":"worker-instance-1","metadataStreamId":"metadata-stream-1","streamSequence":3,"presentationRevision":9,"nativeActivity":"foreground","refreshingLanes":["review"],"reviewComparison":{"activeTarget":{"kind":"branch","name":"stack/base"},"attempt":{"status":"pending","reviewGeneration":8},"displayedSnapshot":{"status":"stale","packageId":"package-7","reviewGeneration":7,"revision":11}}}"#
                .utf8
        )

        // Act
        let frame = try BridgeProductStrictJSON.decode(
            BridgeProductMetadataFrame.self,
            from: presentationJSON
        )
        let encodedFrame = try sortedJSONObject(frame)
        let canonicalFrame = try sortedJSONObject(from: presentationJSON)

        // Assert
        guard case .panePresentation(let presentation) = frame else {
            Issue.record("Expected pane presentation frame")
            return
        }
        #expect(presentation.presentationRevision == 9)
        #expect(
            presentation.reviewComparison
                == BridgePaneReviewComparisonPresentation(
                    activeTarget: .branch(name: "stack/base"),
                    attempt: .pending(reviewGeneration: 8),
                    displayedSnapshot: .stale(
                        BridgePaneReviewDisplayedSnapshotIdentity(
                            packageId: "package-7",
                            reviewGeneration: 7,
                            revision: 11
                        )
                    )
                )
        )
        #expect(encodedFrame == canonicalFrame)
    }

    private func sortedJSONObject<TValue: Encodable>(_ value: TValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try #require(String(data: encoder.encode(value), encoding: .utf8))
    }

    private func sortedJSONObject(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        let sorted = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try #require(String(data: sorted, encoding: .utf8))
    }

    private func reviewComparisonUpdateBody() -> Data {
        Data(
            """
            {
              "call": {
                "method": "review.comparison.update",
                "request": { "target": { "kind": "branch", "name": "stack/base" } }
              },
              "kind": "product.call",
              "paneSessionId": "\(bridgeProductTestPaneSessionId)",
              "requestId": "review-comparison-update-1",
              "requestSequence": 2,
              "wireVersion": 2,
              "workerDerivationEpoch": 0,
              "workerInstanceId": "\(bridgeProductTestWorkerInstanceId)"
            }
            """.utf8
        )
    }
}

@MainActor
private final class BridgeProductComparisonTargetRecorder {
    private(set) var targets: [WorkspaceReviewContributionTarget] = []

    func record(_ target: WorkspaceReviewContributionTarget) {
        targets.append(target)
    }
}
