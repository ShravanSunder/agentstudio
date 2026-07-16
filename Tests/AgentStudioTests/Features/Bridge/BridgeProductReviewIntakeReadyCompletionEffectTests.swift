import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product review intake-ready completion effect")
struct BridgeReviewIntakeCompletionEffectTests {
    @Test("Review intake readiness mutates only after committed completion and only once")
    func reviewIntakeReadyRequiresCommittedCompletion() async throws {
        // Arrange
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        let session = try BridgeProductSession(
            paneSessionId: bridgeProductTestPaneSessionId,
            workerInstanceId: bridgeProductTestWorkerInstanceId,
            capabilityBytes: capabilityBytes
        )
        let recorder = await MainActor.run { BridgeProductReviewIntakeReadyMutationRecorder() }
        let provider = BridgePaneProductSchemeProvider(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
            markReviewItemViewed: { _, _ in },
            handleReviewIntakeReady: { request, productAdmission in
                recorder.record(request, productAdmission: productAdmission)
            }
        )
        let productAdmission = try BridgeProductAdmissionTestContext.make().context
        let dispatcher = makeBridgeProductSchemeControlDispatcher(
            session: session,
            provider: provider,
            productAdmission: productAdmission
        )
        let callBody = bridgeProductReviewIntakeReadyBody()
        let decodedCall = try BridgeProductStrictJSON.decode(
            BridgeProductControlRequest.self,
            from: callBody
        )

        // Act
        _ = await provider.response(for: decodedCall)
        let countAfterProviderResponse = await recorder.count
        _ = try await dispatcher.dispatch(
            exactRequestBytes: bridgeProductSchemeWorkerOpenBody(),
            presentedCapability: capabilityHeader
        )
        _ = try await dispatcher.dispatch(
            exactRequestBytes: callBody,
            presentedCapability: capabilityHeader
        )
        _ = try await dispatcher.dispatch(
            exactRequestBytes: callBody,
            presentedCapability: capabilityHeader
        )
        let requestsAfterCommitAndReplay = await recorder.requests
        let revocation = await session.revoke(acknowledgeLifecycle: { _ in true })
        #expect(await revocation.wait())
        _ = try await dispatcher.dispatch(
            exactRequestBytes: callBody,
            presentedCapability: capabilityHeader
        )

        // Assert
        #expect(countAfterProviderResponse == 0)
        #expect(
            requestsAfterCommitAndReplay == [
                BridgeProductReviewIntakeReadyRequest(
                    reason: "sequence_gap",
                    streamId: "review:stream-1"
                )
            ]
        )
        #expect(await recorder.count == 1)
    }
}

@MainActor
private final class BridgeProductReviewIntakeReadyMutationRecorder {
    private(set) var requests: [BridgeProductReviewIntakeReadyRequest] = []
    var count: Int { requests.count }

    func record(
        _ request: BridgeProductReviewIntakeReadyRequest,
        productAdmission: BridgeProductAdmissionContext
    ) {
        _ = productAdmission.withValidAdmission {
            requests.append(request)
        }
    }
}

private func bridgeProductReviewIntakeReadyBody() -> Data {
    Data(
        """
        {
          "call": {
            "method": "review.intake.ready",
            "request": { "reason": "sequence_gap", "streamId": "review:stream-1" }
          },
          "kind": "product.call",
          "paneSessionId": "\(bridgeProductTestPaneSessionId)",
          "requestId": "review-intake-ready-1",
          "requestSequence": 2,
          "wireVersion": 2,
          "workerDerivationEpoch": 0,
          "workerInstanceId": "\(bridgeProductTestWorkerInstanceId)"
        }
        """.utf8
    )
}
