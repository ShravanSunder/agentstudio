import Foundation
import Testing

@testable import AgentStudio

struct BridgeProductSessionLifecycleHarness {
    let capabilityHeader: String
    let session: BridgeProductSession

    static func opened() async throws -> Self {
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        let session = try BridgeProductSession(
            paneSessionId: "pane-session-1",
            workerInstanceId: "worker-instance-1",
            capabilityBytes: capabilityBytes
        )
        let harness = Self(capabilityHeader: capabilityHeader, session: session)
        let request = try bridgeProductLifecycleControlRequest(workerSessionOpenObject())
        let token = try #require(lifecycleExecutionToken(try await harness.begin(request)))
        let response = try BridgeProductControlResponse.workerSessionAccepted(correlating: request)
        _ = try await session.completeControl(
            token: token,
            exactResponseBytes: try JSONEncoder().encode(response)
        )
        return harness
    }

    func begin(
        _ request: BridgeProductControlRequest
    ) async throws -> BridgeProductSessionControlAdmission {
        await session.beginControl(
            exactRequestBytes: try JSONEncoder().encode(request),
            presentedCapability: capabilityHeader
        )
    }

    func openSubscription(_ object: [String: Any]) async throws {
        let request = try bridgeProductLifecycleControlRequest(object)
        let token = try #require(lifecycleExecutionToken(try await begin(request)))
        let interestSha256: String
        switch request.surface {
        case .review:
            interestSha256 =
                try BridgeProductSubscriptionInterestState
                .reviewMetadata(interests: [])
                .sha256Hex()
        case .file:
            interestSha256 =
                try BridgeProductSubscriptionInterestState
                .fileMetadata(interests: [], pathScope: [])
                .sha256Hex()
        case nil:
            Issue.record("Expected a surface-scoped subscription request")
            return
        }
        let response = try BridgeProductControlResponse.subscriptionOpenAccepted(
            correlating: request,
            interestSha256: interestSha256
        )
        _ = try await session.completeControl(
            token: token,
            exactResponseBytes: try JSONEncoder().encode(response)
        )
    }

    func admitMetadataFrames(through lastSequence: Int) async throws -> BridgeProductProducerLease {
        let operation = SessionMetadataProducerGate()
        let request = try metadataStreamRequest()
        let progressSubscription = try metadataProgressSubscriptionCorrelation()
        let registration = await session.registerMetadataProducer(
            request: request
        ) { lease in
            await operation.run(lease)
        }
        let lease = try #require(lifecycleProducerLease(registration))
        _ = await operation.waitUntilStarted()

        let opening = try await session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { sequence in
                try metadataAcceptedProducerFrame(
                    request: request,
                    streamSequence: sequence
                )
            }
        )
        #expect(lifecycleAdmittedFrame(opening)?.sequence == 0)
        #expect(await session.dequeueProducerFrame(for: lease)?.sequence == 0)

        if lastSequence > 0 {
            for expectedSequence in 1...lastSequence {
                let result = try await session.enqueueProducerFrame(
                    for: lease,
                    build: { sequence in
                        try metadataProgressProducerFrame(
                            request: request,
                            streamSequence: sequence,
                            subscription: progressSubscription
                        )
                    },
                    overflowReset: { sequence in
                        try metadataOverflowProducerFrame(
                            request: request,
                            streamSequence: sequence
                        )
                    }
                )
                #expect(lifecycleAdmittedFrame(result)?.sequence == expectedSequence)
                #expect(await session.dequeueProducerFrame(for: lease)?.sequence == expectedSequence)
            }
        }
        return lease
    }

    func closeProducer(_ lease: BridgeProductProducerLease) async throws {
        #expect(await session.stopProducer(lease))
        let acknowledgement = try #require(await session.unregisterProducer(lease))
        #expect(await session.acknowledgeProducerLifecycle(acknowledgement))
    }

    func expectStreamSequenceRejectionPreservesState(
        _ expectation: ResyncStreamSequenceRejectionExpectation
    ) async throws {
        let beforeSession = await session.snapshot
        let beforeProducer = await session.producerSnapshot()
        let beforeReviewSubscription = await session.subscriptionSnapshot(
            subscriptionId: "review-subscription-1"
        )
        let beforeFileSubscription = await session.subscriptionSnapshot(
            subscriptionId: "file-subscription-1"
        )
        let request = try bridgeProductLifecycleControlRequest(
            try bridgeProductLifecycleResyncObject(
                requestSequence: expectation.requestSequence,
                lastAcceptedRequestSequence: expectation.lastAcceptedRequestSequence,
                lastAcceptedStreamSequence: expectation.lastAcceptedStreamSequence,
                reviewEpoch: expectation.reviewEpoch,
                fileEpoch: expectation.fileEpoch
            )
        )

        #expect(
            try await begin(request)
                == .rejected(
                    .streamSequenceConflict(
                        nextMetadataStreamSequence: expectation.nextMetadataStreamSequence
                    )
                )
        )
        #expect((await session.snapshot) == beforeSession)
        #expect((await session.producerSnapshot()) == beforeProducer)
        #expect(
            await session.subscriptionSnapshot(
                subscriptionId: "review-subscription-1"
            ) == beforeReviewSubscription
        )
        #expect(
            await session.subscriptionSnapshot(
                subscriptionId: "file-subscription-1"
            ) == beforeFileSubscription
        )
    }
}

struct ResyncStreamSequenceRejectionExpectation {
    let requestSequence: Int
    let lastAcceptedRequestSequence: Int
    let lastAcceptedStreamSequence: Int
    let nextMetadataStreamSequence: Int
    let reviewEpoch: Int
    let fileEpoch: Int
}

func bridgeProductLifecycleControlRequest(
    _ object: [String: Any]
) throws -> BridgeProductControlRequest {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try BridgeProductStrictJSON.decode(BridgeProductControlRequest.self, from: data)
}

func bridgeProductLifecycleReviewSubscriptionOpenObject(
    requestSequence: Int,
    epoch: Int
) -> [String: Any] {
    surfaceControlIdentity(
        kind: "subscription.open",
        requestId: "request-review-open-\(requestSequence)",
        requestSequence: requestSequence,
        epoch: epoch
    ).merging([
        "subscription": ["subscriptionKind": "review.metadata"],
        "subscriptionId": "review-subscription-1",
    ]) { _, new in new }
}

func bridgeProductLifecycleFileSubscriptionOpenObject(
    requestSequence: Int,
    epoch: Int
) -> [String: Any] {
    surfaceControlIdentity(
        kind: "subscription.open",
        requestId: "request-file-open-\(requestSequence)",
        requestSequence: requestSequence,
        epoch: epoch
    ).merging([
        "subscription": [
            "source": [
                "cwdScope": NSNull(),
                "freshness": "live",
                "includeStatuses": true,
                "repoId": "00000000-0000-4000-8000-000000000001",
                "rootPathToken": "root-token-1",
                "worktreeId": "00000000-0000-4000-8000-000000000002",
            ],
            "subscriptionKind": "file.metadata",
        ],
        "subscriptionId": "file-subscription-1",
    ]) { _, new in new }
}

func bridgeProductLifecycleSubscriptionCancelObject(
    requestSequence: Int,
    epoch: Int
) -> [String: Any] {
    surfaceControlIdentity(
        kind: "subscription.cancel",
        requestId: "request-review-cancel-\(requestSequence)",
        requestSequence: requestSequence,
        epoch: epoch
    ).merging([
        "subscriptionId": "review-subscription-1",
        "subscriptionKind": "review.metadata",
    ]) { _, new in new }
}

func bridgeProductLifecycleReviewCallObject(
    requestSequence: Int,
    epoch: Int
) -> [String: Any] {
    surfaceControlIdentity(
        kind: "product.call",
        requestId: "request-review-call-\(requestSequence)",
        requestSequence: requestSequence,
        epoch: epoch
    ).merging([
        "call": [
            "method": "review.markFileViewed",
            "request": ["itemId": "review-item-1"],
        ]
    ]) { _, new in new }
}

func bridgeProductLifecycleResyncObject(
    requestSequence: Int,
    lastAcceptedRequestSequence: Int,
    lastAcceptedStreamSequence: Int,
    reviewEpoch: Int,
    fileEpoch: Int
) throws -> [String: Any] {
    let reviewEmptySHA256 =
        try BridgeProductSubscriptionInterestState
        .reviewMetadata(interests: [])
        .sha256Hex()
    let fileEmptySHA256 =
        try BridgeProductSubscriptionInterestState
        .fileMetadata(interests: [], pathScope: [])
        .sha256Hex()
    return controlIdentity(
        kind: "workerSession.resync",
        requestId: "request-resync-\(requestSequence)",
        requestSequence: requestSequence
    ).merging([
        "activeSubscriptions": [
            [
                "interestRevision": 0,
                "interestSha256": reviewEmptySHA256,
                "subscriptionId": "review-subscription-1",
                "subscriptionKind": "review.metadata",
                "workerDerivationEpoch": reviewEpoch,
            ],
            [
                "interestRevision": 0,
                "interestSha256": fileEmptySHA256,
                "subscriptionId": "file-subscription-1",
                "subscriptionKind": "file.metadata",
                "workerDerivationEpoch": fileEpoch,
            ],
        ],
        "lastAcceptedRequestSequence": lastAcceptedRequestSequence,
        "lastAcceptedStreamSequence": lastAcceptedStreamSequence,
    ]) { _, new in new }
}

private func lifecycleExecutionToken(
    _ admission: BridgeProductSessionControlAdmission
) -> BridgeProductControlAdmissionToken? {
    guard case .execute(let token) = admission else { return nil }
    return token
}

private func lifecycleProducerLease(
    _ registration: BridgeProductProducerRegistration
) -> BridgeProductProducerLease? {
    guard case .accepted(let lease) = registration else { return nil }
    return lease
}

private func lifecycleAdmittedFrame(
    _ result: BridgeProductProducerEnqueueResult
) -> BridgeProductQueuedProducerFrame? {
    switch result {
    case .enqueued(let frame), .queueReset(let frame, _, _):
        frame
    case .rejected:
        nil
    }
}

private func metadataStreamRequest() throws -> BridgeProductMetadataStreamRequest {
    let data = try JSONSerialization.data(
        withJSONObject: [
            "kind": "metadataStream.open",
            "metadataStreamId": "metadata-stream-1",
            "paneSessionId": "pane-session-1",
            "resumeFromStreamSequence": NSNull(),
            "wireVersion": BridgeProductWireContract.version,
            "workerInstanceId": "worker-instance-1",
        ],
        options: [.sortedKeys]
    )
    return try BridgeProductStrictJSON.decode(BridgeProductMetadataStreamRequest.self, from: data)
}

private func metadataProgressSubscriptionCorrelation()
    throws -> BridgeProductSubscriptionFrameCorrelation
{
    try .init(
        cursor: nil,
        interestRevision: 0,
        interestSha256:
            BridgeProductSubscriptionInterestState
            .reviewMetadata(interests: [])
            .sha256Hex(),
        sourceGeneration: 0,
        subscriptionId: "metadata-progress-subscription",
        subscriptionKind: .reviewMetadata,
        workerDerivationEpoch: 0
    )
}

private func metadataAcceptedProducerFrame(
    request: BridgeProductMetadataStreamRequest,
    streamSequence: Int
) throws -> BridgeProductProducerFrame {
    .metadata(
        .metadataStreamAccepted(
            try BridgeProductMetadataStreamAcceptedFrame(
                stream: request.correlation,
                streamSequence: streamSequence,
                resumeDisposition: .snapshotRequired
            )
        )
    )
}

private func metadataProgressProducerFrame(
    request: BridgeProductMetadataStreamRequest,
    streamSequence: Int,
    subscription: BridgeProductSubscriptionFrameCorrelation
) throws -> BridgeProductProducerFrame {
    .metadata(
        try .subscriptionAccepted(
            stream: request.correlation,
            streamSequence: streamSequence,
            subscription: subscription
        )
    )
}

private func metadataOverflowProducerFrame(
    request: BridgeProductMetadataStreamRequest,
    streamSequence: Int
) throws -> BridgeProductProducerFrame {
    .metadata(
        try .metadataStreamError(
            stream: request.correlation,
            streamSequence: streamSequence,
            code: .resyncRequired,
            retryable: true,
            safeMessage: nil
        )
    )
}

private func workerSessionOpenObject() -> [String: Any] {
    controlIdentity(
        kind: "workerSession.open",
        requestId: "request-open-1",
        requestSequence: 1
    ).merging(["request": NSNull()]) { _, new in new }
}

private func surfaceControlIdentity(
    kind: String,
    requestId: String,
    requestSequence: Int,
    epoch: Int
) -> [String: Any] {
    controlIdentity(
        kind: kind,
        requestId: requestId,
        requestSequence: requestSequence
    ).merging(["workerDerivationEpoch": epoch]) { _, new in new }
}

private func controlIdentity(
    kind: String,
    requestId: String,
    requestSequence: Int
) -> [String: Any] {
    [
        "kind": kind,
        "paneSessionId": "pane-session-1",
        "requestId": requestId,
        "requestSequence": requestSequence,
        "wireVersion": BridgeProductWireContract.version,
        "workerInstanceId": "worker-instance-1",
    ]
}

private actor SessionMetadataProducerGate {
    private var cancellationContinuation: CheckedContinuation<Void, Never>?
    private var cancellationWasRequested = false
    private var startedLease: BridgeProductProducerLease?
    private var startWaiters: [CheckedContinuation<BridgeProductProducerLease, Never>] = []

    func run(_ lease: BridgeProductProducerLease) async {
        startedLease = lease
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: lease)
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if cancellationWasRequested || Task.isCancelled {
                    continuation.resume()
                } else {
                    cancellationContinuation = continuation
                }
            }
        } onCancel: {
            Task { await self.releaseForCancellation() }
        }
    }

    func waitUntilStarted() async -> BridgeProductProducerLease {
        if let startedLease { return startedLease }
        return await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    private func releaseForCancellation() {
        cancellationWasRequested = true
        cancellationContinuation?.resume()
        cancellationContinuation = nil
    }
}
