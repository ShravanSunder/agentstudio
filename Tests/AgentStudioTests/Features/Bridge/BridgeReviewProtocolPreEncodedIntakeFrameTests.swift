import Foundation
import Testing
import WebKit

@testable import AgentStudio

@MainActor
@Suite("BridgeReviewProtocol pre-encoded intake frame contract", .serialized)
struct BridgeReviewProtocolPreEncodedIntakeFrameTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @MainActor
    @Test("delivery API accepts only pre-encoded intake frames")
    func deliveryAPIAcceptsOnlyPreEncodedIntakeFrames() async throws {
        let capture = PreEncodedIntakeFrameCapture()
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(panelKind: .diffViewer, source: nil),
            preEncodedIntakeFrameSink: { _, frame in
                await capture.append(frame.envelopeJSON)
            }
        )
        defer { controller.teardown() }
        controller.handleBridgeReady()

        let frame = try await PreEncodedIntakeFrame.make(
            metadata: BridgeIntakeFrameMetadata(
                kind: .snapshot,
                streamId: "review:type-seam",
                generation: 1,
                sequence: 0
            ),
            payload: ReviewProtocolPreEncodedProbePayload(value: true),
            traceContext: nil,
            pushNonce: controller.pushNonce
        )
        let deliverOnlyPreEncodedFrame: @MainActor (PreEncodedIntakeFrame) async -> Bool =
            controller.deliverIntakeFrame

        let delivered = await deliverOnlyPreEncodedFrame(frame)

        #expect(delivered)
        #expect(await capture.frames() == [frame.envelopeJSON])
    }

    @MainActor
    @Test("pre-encoded factory moves payload envelope and JavaScript literal encoding off main")
    func preEncodedFactoryMovesEncodingOffMain() async throws {
        let frame = try await PreEncodedIntakeFrame.make(
            metadata: BridgeIntakeFrameMetadata(
                kind: .snapshot,
                streamId: "review:off-main",
                generation: 1,
                sequence: 0
            ),
            payload: ReviewProtocolPreEncodedProbePayload(value: true),
            traceContext: nil,
            pushNonce: "nonce-with-\"quote\""
        )

        #expect(!frame.encodingRanOnMainThread)
        #expect(frame.envelopeJSON.contains(#""streamId":"review:off-main""#))
        #expect(frame.envelopeJSON.contains(#""payload":{"value":true}"#))
        #expect(frame.frameJavaScriptLiteral.contains(#"\"review:off-main\""#))
        #expect(frame.pushNonceJavaScriptLiteral == #""nonce-with-\"quote\"""#)
    }

    @MainActor
    @Test("review pre-encoded delivery retries with the same sequence after transport failure")
    func reviewPreEncodedDeliveryRetriesWithSameSequenceAfterTransportFailure() async throws {
        let capture = PreEncodedIntakeFrameFailFirstCapture()
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(panelKind: .diffViewer, source: nil),
            preEncodedIntakeFrameSink: { _, frame in
                if await capture.recordAndShouldFail(frame.envelopeJSON) {
                    throw PreEncodedIntakeFrameTestError.transportFailure
                }
            }
        )
        defer { controller.teardown() }
        controller.handleBridgeReady()
        controller.nextReviewGeneration = 1
        await controller.worktreeFileMetadataScheduler.acceptGeneration(1, protocolId: "review")
        await controller.worktreeFileMetadataScheduler.openGate(protocolId: "review")

        await controller.enqueueReviewProtocolFrameJob(
            lane: .foreground,
            generation: 1,
            traceContext: nil
        ) { sequence in
            .invalidation(
                BridgeReviewProtocolFrameBuilder.invalidation(
                    request: BridgeReviewProtocolInvalidationBuildRequest(
                        streamId: controller.reviewProtocolStreamId(),
                        generation: 1,
                        sequence: sequence,
                        scope: "package",
                        itemIds: nil,
                        pathHints: nil,
                        reason: "watchEvent"
                    )
                )
            )
        }
        await controller.worktreeFileMetadataScheduler.waitUntilDrained()

        #expect(controller.nextReviewProtocolSequence == 0)
        await controller.worktreeFileMetadataScheduler.openGate(protocolId: "review")
        await controller.worktreeFileMetadataScheduler.waitUntilDrained()

        let attempts = await capture.frames()
        #expect(attempts.count == 2)
        #expect(attempts.compactMap(Self.sequence(of:)) == [0, 0])
        #expect(controller.nextReviewProtocolSequence == 1)
    }

    private static func sequence(of frameJSON: String) -> Int? {
        guard let data = frameJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object["sequence"] as? Int
    }
}

private struct ReviewProtocolPreEncodedProbePayload: Encodable, Sendable {
    let value: Bool
}

private actor PreEncodedIntakeFrameCapture {
    private var capturedFrames: [String] = []

    func append(_ frameJSON: String) {
        capturedFrames.append(frameJSON)
    }

    func frames() -> [String] {
        capturedFrames
    }
}

private actor PreEncodedIntakeFrameFailFirstCapture {
    private var capturedFrames: [String] = []
    private var shouldFailNextDelivery = true

    func recordAndShouldFail(_ frameJSON: String) -> Bool {
        capturedFrames.append(frameJSON)
        guard shouldFailNextDelivery else {
            return false
        }
        shouldFailNextDelivery = false
        return true
    }

    func frames() -> [String] {
        capturedFrames
    }
}

private enum PreEncodedIntakeFrameTestError: Error {
    case transportFailure
}
