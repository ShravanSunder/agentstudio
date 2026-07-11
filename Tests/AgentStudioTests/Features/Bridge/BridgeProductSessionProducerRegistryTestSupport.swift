import Foundation
import Testing

@testable import AgentStudio

func producerRegistryMetadataStreamRequest(
    metadataStreamId: String = "metadata-stream-1",
    resumeFromStreamSequence: Int? = nil
) throws -> BridgeProductMetadataStreamRequest {
    let data = try JSONSerialization.data(
        withJSONObject: [
            "kind": "metadataStream.open",
            "metadataStreamId": metadataStreamId,
            "paneSessionId": "pane-session-1",
            "resumeFromStreamSequence": resumeFromStreamSequence.map { $0 as Any } ?? NSNull(),
            "wireVersion": BridgeProductWireContract.version,
            "workerInstanceId": "worker-instance-1",
        ],
        options: [.sortedKeys]
    )
    return try BridgeProductStrictJSON.decode(BridgeProductMetadataStreamRequest.self, from: data)
}

func producerRegistryContentRequest(workerDerivationEpoch: Int) throws -> BridgeProductContentRequest {
    let requestJSON = """
        {
          "kind": "content.open",
          "wireVersion": 2,
          "paneSessionId": "pane-session-1",
          "workerDerivationEpoch": \(workerDerivationEpoch),
          "workerInstanceId": "worker-instance-1",
          "contentRequestId": "content-request-1",
          "leaseId": "lease-1",
          "contentKind": "file.content",
          "descriptor": {
            "contentKind": "file.content",
            "declaredByteLength": 3,
            "descriptorId": "file-descriptor-1",
            "encoding": "utf-8",
            "expectedSha256": null,
            "fileId": "file-1",
            "maximumBytes": 2097152,
            "source": {
              "repoId": "00000000-0000-4000-8000-000000000001",
              "rootRevisionToken": null,
              "sourceCursor": "source-cursor-1",
              "sourceId": "source-1",
              "subscriptionGeneration": 11,
              "worktreeId": "00000000-0000-4000-8000-000000000002"
            },
            "window": {
              "kind": "prefix",
              "maximumBytes": 2097152,
              "maximumLines": 10000,
              "startByte": 0
            }
          }
        }
        """
    return try BridgeProductStrictJSON.decode(
        BridgeProductContentRequest.self,
        from: Data(requestJSON.utf8)
    )
}

func closeAllProducerRegistryProducers(
    in registry: BridgeProductProducerRegistryTestHarness
) async throws {
    let stoppedLeases = await registry.cancelAll()
    for lease in stoppedLeases {
        let acknowledgement = try #require(await registry.unregister(lease))
        #expect(await registry.acknowledgeLifecycle(acknowledgement))
    }
}
func producerRegistryMetadataOpeningFrame(
    for request: BridgeProductMetadataStreamRequest,
    sequence: Int
) throws -> BridgeProductProducerFrame {
    .metadata(
        .metadataStreamAccepted(
            try .init(
                stream: request.correlation,
                streamSequence: sequence,
                resumeDisposition: request.resumeFromStreamSequence == nil ? .snapshotRequired : .resumed
            )
        )
    )
}

func producerRegistryMetadataProgressFrame(
    for request: BridgeProductMetadataStreamRequest,
    sequence: Int,
    identitySuffix: String
) throws -> BridgeProductProducerFrame {
    let subscription = try BridgeProductSubscriptionFrameCorrelation(
        cursor: nil,
        interestRevision: 0,
        interestSha256: String(repeating: "a", count: 64),
        sourceGeneration: 1,
        subscriptionId: "subscription-\(identitySuffix)",
        subscriptionKind: .fileMetadata,
        workerDerivationEpoch: 1
    )
    return .metadata(
        try .subscriptionAccepted(
            stream: request.correlation,
            streamSequence: sequence,
            subscription: subscription
        )
    )
}

func producerRegistryMetadataTerminalFrame(
    for request: BridgeProductMetadataStreamRequest,
    sequence: Int,
    safeMessage: String? = nil
) throws -> BridgeProductProducerFrame {
    .metadata(
        try .metadataStreamError(
            stream: request.correlation,
            streamSequence: sequence,
            code: .internal,
            retryable: false,
            safeMessage: safeMessage
        )
    )
}

func producerRegistryContentOpeningFrame(
    for request: BridgeProductContentRequest
) -> BridgeProductProducerFrame {
    .content(
        BridgeProductContentFrame(
            header: .accepted(for: request.admission),
            payload: Data()
        )
    )
}

func producerRegistryContentTerminalFrame(sequence: Int) throws -> BridgeProductProducerFrame {
    .content(
        BridgeProductContentFrame(
            header: try .reset(contentSequence: sequence, reason: .producerOverflow),
            payload: Data()
        )
    )
}

actor BridgeProductProducerOperationGate {
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

actor BridgeProductProducerInvocationCounter {
    private(set) var wasInvoked = false

    func recordInvocation() {
        wasInvoked = true
    }
}
