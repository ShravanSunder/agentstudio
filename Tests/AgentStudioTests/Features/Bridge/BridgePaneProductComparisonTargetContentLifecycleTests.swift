import CryptoKit
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge comparison-target content lifecycle")
struct BridgeComparisonTargetContentLifecycleTests {
    @Test("exact descriptor identity streams the pending body")
    func exactDescriptorIdentityStreamsPendingBody() async throws {
        let body = Data("comparison-target-body".utf8)
        let capture = try await makeCapture(body: body, suffix: "exact")
        let provider = await makeProvider(capture: capture)
        _ = await provider.response(for: try queryRequest())

        let result = try await openContent(
            provider: provider,
            request: contentRequest(descriptor: capture.descriptor, suffix: "exact")
        )

        #expect(result.body == body)
        #expect(result.errorMessage == nil)
    }

    @Test("same descriptor id and digest with changed metadata is rejected without detaching the active descriptor")
    func changedMetadataIsRejectedWithoutDetachingActiveDescriptor() async throws {
        let body = Data("comparison-target-body".utf8)
        let capture = try await makeCapture(body: body, suffix: "metadata")
        let provider = await makeProvider(capture: capture)
        _ = await provider.response(for: try queryRequest())
        let alteredDescriptor = try BridgeProductReviewComparisonTargetsContentDescriptor(
            capturedAtUnixMilliseconds: capture.descriptor.capturedAtUnixMilliseconds + 1,
            cutoffUnixMilliseconds: capture.descriptor.cutoffUnixMilliseconds,
            declaredByteLength: capture.descriptor.declaredByteLength,
            descriptorId: capture.descriptor.descriptorId,
            expectedSha256: capture.descriptor.expectedSha256,
            maximumBytes: capture.descriptor.maximumBytes
        )

        let mismatch = try await openContent(
            provider: provider,
            request: contentRequest(descriptor: alteredDescriptor, suffix: "metadata-mismatch")
        )
        let secondOpen = try await openContent(
            provider: provider,
            request: contentRequest(descriptor: capture.descriptor, suffix: "metadata-replay")
        )

        #expect(mismatch.body.isEmpty)
        #expect(mismatch.errorMessage == "Content descriptor is not active")
        #expect(secondOpen.body == body)
        #expect(secondOpen.errorMessage == nil)
    }

    @Test("different descriptor identity is rejected without detaching the active descriptor")
    func differentDescriptorIdentityIsRejectedWithoutDetachingActiveDescriptor() async throws {
        let body = Data("comparison-target-body".utf8)
        let capture = try await makeCapture(body: body, suffix: "different")
        let provider = await makeProvider(capture: capture)
        _ = await provider.response(for: try queryRequest())
        let differentDescriptor = try await makeCapture(body: body, suffix: "other").descriptor

        let mismatch = try await openContent(
            provider: provider,
            request: contentRequest(descriptor: differentDescriptor, suffix: "different-mismatch")
        )
        let replay = try await openContent(
            provider: provider,
            request: contentRequest(descriptor: capture.descriptor, suffix: "different-replay")
        )

        #expect(mismatch.errorMessage == "Content descriptor is not active")
        #expect(replay.body == body)
        #expect(replay.errorMessage == nil)
    }

    @Test("late stale open does not detach the newest query")
    func lateStaleOpenDoesNotDetachNewestQuery() async throws {
        let firstCapture = try await makeCapture(
            body: Data("first-comparison-target-body".utf8),
            suffix: "exact"
        )
        let newestBody = Data("newest-comparison-target-body".utf8)
        let newestCapture = try await makeCapture(body: newestBody, suffix: "other")
        let captureQueue = ComparisonTargetCaptureQueue(captures: [firstCapture, newestCapture])
        let provider = await makeProvider(captureQueue: captureQueue)
        _ = await provider.response(for: try queryRequest(suffix: "first", sequence: 1))
        _ = await provider.response(for: try queryRequest(suffix: "newest", sequence: 2))

        let staleOpen = try await openContent(
            provider: provider,
            request: contentRequest(descriptor: firstCapture.descriptor, suffix: "stale-open")
        )
        let newestOpen = try await openContent(
            provider: provider,
            request: contentRequest(descriptor: newestCapture.descriptor, suffix: "newest-open")
        )

        #expect(staleOpen.errorMessage == "Content descriptor is not active")
        #expect(newestOpen.body == newestBody)
        #expect(newestOpen.errorMessage == nil)
    }

    @Test("second exact open is rejected after the first consumes the pending body")
    func secondExactOpenIsRejected() async throws {
        let body = Data("comparison-target-body".utf8)
        let capture = try await makeCapture(body: body, suffix: "second")
        let provider = await makeProvider(capture: capture)
        _ = await provider.response(for: try queryRequest())

        let first = try await openContent(
            provider: provider,
            request: contentRequest(descriptor: capture.descriptor, suffix: "first")
        )
        let second = try await openContent(
            provider: provider,
            request: contentRequest(descriptor: capture.descriptor, suffix: "second")
        )

        #expect(first.body == body)
        #expect(second.errorMessage == "Content descriptor is not active")
    }

    @Test("close and drain releases a pending comparison capture")
    func closeAndDrainReleasesPendingCapture() async throws {
        let capture = try await makeCapture(body: Data("comparison-target-body".utf8), suffix: "cleanup")
        let provider = await makeProvider(capture: capture)
        _ = await provider.response(for: try queryRequest())
        await provider.closeAndDrain()
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let request = try contentRequest(descriptor: capture.descriptor, suffix: "cleanup-open")
        let registration = await harness.session.registerContentProducer(
            request: request,
            productAdmission: harness.productAdmission.context
        ) { lease in
            await provider.runContentProducer(
                request: request,
                lease: lease,
                productAdmission: harness.productAdmission.context,
                session: harness.session
            )
        }
        let lease = try bridgeProductAcceptedLease(registration)

        try await harness.closeProducer(lease)

        #expect((await harness.session.producerSnapshot()).hasZeroResidue)
    }

    private struct ContentResult {
        let body: Data
        let errorMessage: String?
    }

    private func makeProvider(
        capture: BridgeProductReviewComparisonTargetsQueryCapture
    ) async -> BridgePaneProductSchemeProvider {
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        return BridgePaneProductSchemeProvider(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
            markReviewItemViewed: { _, _ in },
            queryReviewComparisonTargets: { capture },
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
    }

    private func makeProvider(
        captureQueue: ComparisonTargetCaptureQueue
    ) async -> BridgePaneProductSchemeProvider {
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        return BridgePaneProductSchemeProvider(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
            markReviewItemViewed: { _, _ in },
            queryReviewComparisonTargets: { await captureQueue.nextCapture() },
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
    }

    private func makeCapture(
        body: Data,
        suffix: String
    ) async throws -> BridgeProductReviewComparisonTargetsQueryCapture {
        let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let descriptor = try BridgeProductReviewComparisonTargetsContentDescriptor(
            capturedAtUnixMilliseconds: 2000,
            cutoffUnixMilliseconds: 1000,
            declaredByteLength: body.count,
            descriptorId: suffix == "other"
                ? "019FEEC5-A29D-7858-A3BD-AB969E228485"
                : "019FEEC5-A29D-7858-A3BD-AB969E228484",
            expectedSha256: digest,
            maximumBytes: body.count
        )
        return BridgeProductReviewComparisonTargetsQueryCapture(
            descriptor: descriptor,
            body: body,
            foregroundWorkAdmission: (await BridgePaneRefreshWorkAdmissionTestContext.foreground()).admission
        )
    }

    private func queryRequest(
        suffix: String = "1",
        sequence: Int = 1
    ) throws -> BridgeProductControlRequest {
        try BridgeProductStrictJSON.decode(
            BridgeProductControlRequest.self,
            from: Data(
                """
                {"call":{"method":"review.comparisonTargets.query","request":{}},"kind":"product.call","paneSessionId":"pane-session-1","requestId":"query-\(suffix)","requestSequence":\(sequence),"wireVersion":2,"workerDerivationEpoch":0,"workerInstanceId":"worker-instance-1"}
                """.utf8
            )
        )
    }

    private func contentRequest(
        descriptor: BridgeProductReviewComparisonTargetsContentDescriptor,
        suffix: String
    ) throws -> BridgeProductContentRequest {
        try BridgeProductStrictJSON.decode(
            BridgeProductContentRequest.self,
            from: JSONEncoder().encode(
                BridgeReviewComparisonTargetsContentRequestTest(
                    descriptor: descriptor,
                    suffix: suffix
                )
            )
        )
    }

    private func openContent(
        provider: BridgePaneProductSchemeProvider,
        request: BridgeProductContentRequest
    ) async throws -> ContentResult {
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let registration = await harness.session.registerContentProducer(
            request: request,
            productAdmission: harness.productAdmission.context
        ) { lease in
            await provider.runContentProducer(
                request: request,
                lease: lease,
                productAdmission: harness.productAdmission.context,
                session: harness.session
            )
        }
        let lease = try bridgeProductAcceptedLease(registration)
        let decoder = try BridgeProductContentFrameDecoder()
        let openingDelivery = try await nextFrame(for: lease, in: harness)
        let opening = try #require(
            decoder.append(openingDelivery.frame.data).first
        )
        #expect(opening.header.kind == "content.accepted")
        #expect(
            await harness.session.acknowledgeContentFrameObservation(
                try contentFrameAcknowledgement(
                    for: request.admission,
                    contentSequence: openingDelivery.frame.sequence
                ),
                productAdmission: harness.productAdmission.context
            )
        )
        var body = Data()
        var errorMessage: String?
        while true {
            let delivery = try await nextFrame(for: lease, in: harness)
            let frame = try #require(
                decoder.append(delivery.frame.data).first
            )
            let observed = await harness.session.acknowledgeContentFrameObservation(
                try contentFrameAcknowledgement(
                    for: request.admission,
                    contentSequence: delivery.frame.sequence
                ),
                productAdmission: harness.productAdmission.context
            )
            switch frame.header {
            case .data:
                #expect(observed)
                body.append(frame.payload)
            case .end:
                #expect(observed)
                try await harness.closeProducer(lease)
                return ContentResult(body: body, errorMessage: errorMessage)
            case .error(let header):
                errorMessage = header.safeMessage
                #expect(observed)
                try await harness.closeProducer(lease)
                return ContentResult(body: body, errorMessage: errorMessage)
            case .accepted, .reset:
                #expect(observed)
                Issue.record("Unexpected non-terminal comparison content frame")
            }
        }
    }

    private func nextFrame(
        for lease: BridgeProductProducerLease,
        in harness: BridgeProductSessionLifecycleHarness
    ) async throws -> BridgeProductProducerFrameDelivery {
        let result = await harness.session.pullProducerFrame(
            for: lease,
            productAdmission: harness.productAdmission.context
        )
        guard case .frame(let delivery) = result else {
            throw TestError.expectedFrame
        }
        return delivery
    }

    private func contentFrameAcknowledgement(
        for admission: BridgeProductContentAdmission,
        contentSequence: Int
    ) throws -> BridgeProductContentFrameAcknowledgement {
        let data = try JSONSerialization.data(withJSONObject: [
            "contentRequestId": admission.contentRequestId,
            "contentSequence": contentSequence,
            "kind": "stream.frameObserved",
            "leaseId": admission.leaseId,
            "paneSessionId": admission.paneSessionId,
            "streamKind": "content",
            "wireVersion": admission.wireVersion,
            "workerInstanceId": admission.workerInstanceId,
        ])
        return try BridgeProductStrictJSON.decode(
            BridgeProductContentFrameAcknowledgement.self,
            from: data
        )
    }

    private enum TestError: Error {
        case expectedFrame
    }
}

private actor ComparisonTargetCaptureQueue {
    private var captures: [BridgeProductReviewComparisonTargetsQueryCapture]

    init(captures: [BridgeProductReviewComparisonTargetsQueryCapture]) {
        self.captures = captures
    }

    func nextCapture() -> BridgeProductReviewComparisonTargetsQueryCapture? {
        guard !captures.isEmpty else { return nil }
        return captures.removeFirst()
    }
}

private struct BridgeReviewComparisonTargetsContentRequestTest: Encodable {
    let descriptor: BridgeProductReviewComparisonTargetsContentDescriptor
    let suffix: String

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("review.comparisonTargets", forKey: .contentKind)
        try container.encode("content-request-\(suffix)", forKey: .contentRequestId)
        try container.encode(descriptor, forKey: .descriptor)
        try container.encode("content.open", forKey: .kind)
        try container.encode("lease-\(suffix)", forKey: .leaseId)
        try container.encode("pane-session-1", forKey: .paneSessionId)
        try container.encode(2, forKey: .wireVersion)
        try container.encode(0, forKey: .workerDerivationEpoch)
        try container.encode("worker-instance-1", forKey: .workerInstanceId)
    }

    private enum CodingKeys: String, CodingKey {
        case contentKind
        case contentRequestId
        case descriptor
        case kind
        case leaseId
        case paneSessionId
        case wireVersion
        case workerDerivationEpoch
        case workerInstanceId
    }
}
