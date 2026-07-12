import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product session producer ownership")
struct BridgeProductSessionProducerOwnershipTests {
    @Test("metadata admission validates ownership and derives its fresh opening sequence")
    func metadataAdmissionValidatesIdentityAndFreshSequence() async throws {
        // Arrange
        let freshHarness = try await ProducerSessionHarness.opened()
        let rejectedOperation = ProducerInvocationProbe()
        let wrongPaneRequest = try metadataStreamRequest(
            metadataStreamId: "metadata-wrong-pane",
            paneSessionId: "pane-session-other",
            resumeFromStreamSequence: nil
        )
        let wrongWorkerRequest = try metadataStreamRequest(
            metadataStreamId: "metadata-wrong-worker",
            resumeFromStreamSequence: nil,
            workerInstanceId: "worker-instance-other"
        )
        let freshRequest = try metadataStreamRequest(
            metadataStreamId: "metadata-fresh",
            resumeFromStreamSequence: nil
        )

        // Act
        let wrongPaneRegistration = await freshHarness.session.registerMetadataProducer(
            request: wrongPaneRequest
        ) { _ in
            await rejectedOperation.recordInvocation()
        }
        let wrongWorkerRegistration = await freshHarness.session.registerMetadataProducer(
            request: wrongWorkerRequest
        ) { _ in
            await rejectedOperation.recordInvocation()
        }
        let freshOperation = ProducerOperationGate()
        let freshRegistration = await freshHarness.session.registerMetadataProducer(
            request: freshRequest
        ) { lease in
            await freshOperation.run(lease)
        }
        let freshLease = try #require(freshRegistration.lease)
        _ = await freshOperation.waitUntilStarted()
        let freshOpening = try await freshHarness.session.enqueueRequiredProducerOpeningFrame(
            for: freshLease,
            build: { sequence in
                try metadataAcceptedProducerFrame(
                    request: freshRequest,
                    streamSequence: sequence,
                    resumeDisposition: .snapshotRequired
                )
            }
        )

        // Assert
        #expect(wrongPaneRegistration == .rejected(.staleWorker))
        #expect(wrongWorkerRegistration == .rejected(.staleWorker))
        #expect(!(await rejectedOperation.wasInvoked))
        #expect(freshOpening.enqueuedFrame?.sequence == 0)
        #expect(freshOpening.enqueuedFrame?.requiredOpening == true)
        #expect(
            await consumeNextBridgeProductProducerFrame(
                for: freshLease,
                from: freshHarness.session
            )?.sequence == 0
        )
        try await closeProducer(freshLease, in: freshHarness.session)
    }

    @Test("higher surface epoch stops only stale content and preserves cleanup")
    func higherSurfaceEpochStopsOnlyMatchingStaleContent() async throws {
        // Arrange
        let harness = try await ProducerSessionHarness.opened()
        let metadataOperation = ProducerOperationGate()
        let metadataRegistration = await harness.session.registerMetadataProducer(
            request: try metadataStreamRequest(
                metadataStreamId: "metadata-surface-scope",
                resumeFromStreamSequence: nil
            )
        ) { lease in
            await metadataOperation.run(lease)
        }
        let metadataLease = try #require(metadataRegistration.lease)
        _ = await metadataOperation.waitUntilStarted()

        let oldContentOperation = ProducerOperationGate()
        let oldContentRequest = try fileContentRequest(
            identitySuffix: "old",
            workerDerivationEpoch: 2
        )
        let oldContentRegistration = await harness.session.registerContentProducer(
            request: oldContentRequest
        ) { lease in
            await oldContentOperation.run(lease)
        }
        let oldContentLease = try #require(oldContentRegistration.lease)
        _ = await oldContentOperation.waitUntilStarted()
        _ = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: oldContentLease,
            build: { _ in contentAcceptedProducerFrame(request: oldContentRequest) }
        )
        #expect(
            await consumeNextBridgeProductProducerFrame(
                for: oldContentLease,
                from: harness.session
            )?.sequence == 0
        )

        // Act
        let currentContentOperation = ProducerOperationGate()
        let currentContentRequest = try fileContentRequest(
            identitySuffix: "current",
            workerDerivationEpoch: 3
        )
        let currentContentRegistration = await harness.session.registerContentProducer(
            request: currentContentRequest
        ) { lease in
            await currentContentOperation.run(lease)
        }
        let currentContentLease = try #require(currentContentRegistration.lease)
        _ = await currentContentOperation.waitUntilStarted()
        await oldContentOperation.waitUntilCancelled()

        let staleOperation = ProducerInvocationProbe()
        let staleContentRequest = try fileContentRequest(
            identitySuffix: "stale-new",
            workerDerivationEpoch: 2
        )
        let staleRegistration = await harness.session.registerContentProducer(
            request: staleContentRequest
        ) { _ in
            await staleOperation.recordInvocation()
        }
        let cleanupTerminal = try await harness.session.enqueueTerminalProducerFrame(
            for: oldContentLease,
            build: { sequence in try contentResetProducerFrame(contentSequence: sequence) }
        )

        // Assert
        #expect(!(await metadataOperation.wasCancelled))
        #expect(!(await currentContentOperation.wasCancelled))
        #expect(
            staleRegistration == .rejected(.staleSurfaceEpoch(currentFloor: 3))
        )
        #expect(!(await staleOperation.wasInvoked))
        #expect(cleanupTerminal.enqueuedFrame?.sequence == 1)
        #expect(cleanupTerminal.enqueuedFrame?.terminal == true)
        #expect(
            await consumeNextBridgeProductProducerFrame(
                for: oldContentLease,
                from: harness.session
            )?.sequence == 1
        )

        let scopedSnapshot = await harness.session.producerSnapshot()
        #expect(scopedSnapshot.activeProducerCount == 3)
        #expect(scopedSnapshot.activeProducerTaskCount == 2)
        #expect(scopedSnapshot.activeContentLeaseCount == 2)
        try await closeStoppedProducer(oldContentLease, in: harness.session)
        let revocation = await harness.session.revoke(acknowledgeLifecycle: { _ in true })
        #expect(await revocation.wait())
        #expect((await harness.session.producerSnapshot()).hasZeroResidue)
        _ = metadataLease
        _ = currentContentLease
    }

    @Test("revoke awaits every lifecycle acknowledgement and leaves zero residue")
    func revokeAwaitsAcknowledgementsAndClearsOwnedResidue() async throws {
        // Arrange
        let harness = try await ProducerSessionHarness.opened()
        try await harness.openFileSubscription(workerDerivationEpoch: 2)

        let metadataOperation = ProducerOperationGate()
        let metadataRequest = try metadataStreamRequest(
            metadataStreamId: "metadata-revoke",
            resumeFromStreamSequence: nil
        )
        let metadataRegistration = await harness.session.registerMetadataProducer(
            request: metadataRequest
        ) { lease in
            await metadataOperation.run(lease)
        }
        let metadataLease = try #require(metadataRegistration.lease)
        _ = await metadataOperation.waitUntilStarted()

        let contentOperation = ProducerOperationGate()
        let contentRequest = try fileContentRequest(
            identitySuffix: "revoke",
            workerDerivationEpoch: 2
        )
        let contentRegistration = await harness.session.registerContentProducer(
            request: contentRequest
        ) { lease in
            await contentOperation.run(lease)
        }
        let contentLease = try #require(contentRegistration.lease)
        _ = await contentOperation.waitUntilStarted()
        _ = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: metadataLease,
            build: { sequence in
                try metadataAcceptedProducerFrame(
                    request: metadataRequest,
                    streamSequence: sequence,
                    resumeDisposition: .snapshotRequired
                )
            }
        )
        _ = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: contentLease,
            build: { _ in contentAcceptedProducerFrame(request: contentRequest) }
        )
        let beforeRevoke = await harness.session.producerSnapshot()
        #expect(beforeRevoke.activeProducerTaskCount == 2)
        #expect(beforeRevoke.queuedFrameCount == 2)
        #expect(
            await harness.session.subscriptionSnapshot(
                subscriptionId: ProducerSessionHarness.fileSubscriptionId
            ) != nil
        )

        let acknowledgementGate = ProducerLifecycleAcknowledgementGate()
        let completionProbe = ProducerInvocationProbe()

        // Act
        let revocation = await harness.session.revoke { acknowledgement in
            await acknowledgementGate.acknowledge(acknowledgement)
        }
        let revokeTask = Task {
            let didRevoke = await revocation.wait()
            await completionProbe.recordInvocation()
            return didRevoke
        }
        await acknowledgementGate.waitForInvocationCount(1)

        // Assert
        await metadataOperation.waitUntilCancelled()
        await contentOperation.waitUntilCancelled()
        #expect(!(await completionProbe.wasInvoked))
        #expect(!(await harness.session.producerSnapshot()).hasZeroResidue)

        await acknowledgementGate.releaseNext()
        await acknowledgementGate.waitForInvocationCount(2)
        #expect(!(await completionProbe.wasInvoked))
        #expect(!(await harness.session.producerSnapshot()).hasZeroResidue)

        await acknowledgementGate.releaseNext()
        #expect(await revokeTask.value)
        #expect(await completionProbe.wasInvoked)
        #expect(
            Set(await acknowledgementGate.acknowledgedLeases)
                == Set([metadataLease, contentLease])
        )

        let finalProducerSnapshot = await harness.session.producerSnapshot()
        #expect(finalProducerSnapshot.hasZeroResidue)
        #expect(finalProducerSnapshot.activeProducerCount == 0)
        #expect(finalProducerSnapshot.activeProducerTaskCount == 0)
        #expect(finalProducerSnapshot.activeContentLeaseCount == 0)
        #expect(finalProducerSnapshot.queuedFrameCount == 0)
        #expect(finalProducerSnapshot.queuedByteCount == 0)
        #expect(finalProducerSnapshot.pendingLifecycleAcknowledgementCount == 0)
        #expect(finalProducerSnapshot.isRevoked)
        #expect((await harness.session.snapshot).lifecycle == .revoked)
        #expect(
            await harness.session.subscriptionSnapshot(
                subscriptionId: ProducerSessionHarness.fileSubscriptionId
            ) == nil
        )
    }
}

private struct ProducerSessionHarness {
    static let fileSubscriptionId = "file-subscription-producer-ownership"

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
        let request = try controlRequest([
            "kind": "workerSession.open",
            "paneSessionId": "pane-session-1",
            "request": NSNull(),
            "requestId": "request-open-1",
            "requestSequence": 1,
            "wireVersion": BridgeProductWireContract.version,
            "workerInstanceId": "worker-instance-1",
        ])
        let token = try #require(
            await harness.session.beginControl(
                exactRequestBytes: try JSONEncoder().encode(request),
                presentedCapability: capabilityHeader
            ).executionToken
        )
        let response = try BridgeProductControlResponse.workerSessionAccepted(correlating: request)
        _ = try await session.completeControl(
            token: token,
            exactResponseBytes: try JSONEncoder().encode(response)
        )
        return harness
    }

    func openFileSubscription(workerDerivationEpoch: Int) async throws {
        let request = try controlRequest([
            "kind": "subscription.open",
            "paneSessionId": "pane-session-1",
            "requestId": "request-file-open-2",
            "requestSequence": 2,
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
            "subscriptionId": Self.fileSubscriptionId,
            "wireVersion": BridgeProductWireContract.version,
            "workerDerivationEpoch": workerDerivationEpoch,
            "workerInstanceId": "worker-instance-1",
        ])
        let token = try #require(
            await session.beginControl(
                exactRequestBytes: try JSONEncoder().encode(request),
                presentedCapability: capabilityHeader
            ).executionToken
        )
        let interestSha256 =
            try BridgeProductSubscriptionInterestState
            .fileMetadata(interests: [], pathScope: [])
            .sha256Hex()
        let response = try BridgeProductControlResponse.subscriptionOpenAccepted(
            correlating: request,
            interestSha256: interestSha256
        )
        _ = try await session.completeControl(
            token: token,
            exactResponseBytes: try JSONEncoder().encode(response)
        )
    }
}

private actor ProducerOperationGate {
    private var cancellationContinuation: CheckedContinuation<Void, Never>?
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var wasCancelled = false
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
                if wasCancelled || Task.isCancelled {
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

    func waitUntilCancelled() async {
        if wasCancelled { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
        }
    }

    private func releaseForCancellation() {
        wasCancelled = true
        cancellationContinuation?.resume()
        cancellationContinuation = nil
        let waiters = cancellationWaiters
        cancellationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor ProducerInvocationProbe {
    private(set) var wasInvoked = false

    func recordInvocation() {
        wasInvoked = true
    }
}

extension BridgeProductSessionControlAdmission {
    fileprivate var executionToken: BridgeProductControlAdmissionToken? {
        guard case .execute(let token, _) = self else { return nil }
        return token
    }
}

extension BridgeProductProducerRegistration {
    fileprivate var lease: BridgeProductProducerLease? {
        guard case .accepted(let lease) = self else { return nil }
        return lease
    }
}

extension BridgeProductProducerEnqueueResult {
    fileprivate var enqueuedFrame: BridgeProductQueuedProducerFrame? {
        switch self {
        case .enqueued(let frame), .queueReset(let frame, _, _):
            frame
        case .rejected:
            nil
        }
    }
}

private func closeProducer(
    _ lease: BridgeProductProducerLease,
    in session: BridgeProductSession
) async throws {
    #expect(await session.stopProducer(lease))
    try await closeStoppedProducer(lease, in: session)
}

private func closeStoppedProducer(
    _ lease: BridgeProductProducerLease,
    in session: BridgeProductSession
) async throws {
    let acknowledgement = try #require(await session.unregisterProducer(lease))
    #expect(await session.acknowledgeProducerLifecycle(acknowledgement))
}

private func controlRequest(_ object: [String: Any]) throws -> BridgeProductControlRequest {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try BridgeProductStrictJSON.decode(BridgeProductControlRequest.self, from: data)
}

private func metadataStreamRequest(
    metadataStreamId: String,
    paneSessionId: String = "pane-session-1",
    resumeFromStreamSequence: Int?,
    workerInstanceId: String = "worker-instance-1"
) throws -> BridgeProductMetadataStreamRequest {
    let data = try JSONSerialization.data(
        withJSONObject: [
            "kind": "metadataStream.open",
            "metadataStreamId": metadataStreamId,
            "paneSessionId": paneSessionId,
            "resumeFromStreamSequence": resumeFromStreamSequence.map { $0 as Any } ?? NSNull(),
            "wireVersion": BridgeProductWireContract.version,
            "workerInstanceId": workerInstanceId,
        ],
        options: [.sortedKeys]
    )
    return try BridgeProductStrictJSON.decode(BridgeProductMetadataStreamRequest.self, from: data)
}

private func metadataAcceptedProducerFrame(
    request: BridgeProductMetadataStreamRequest,
    streamSequence: Int,
    resumeDisposition: BridgeProductMetadataStreamResumeDisposition
) throws -> BridgeProductProducerFrame {
    .metadata(
        .metadataStreamAccepted(
            try BridgeProductMetadataStreamAcceptedFrame(
                stream: request.correlation,
                streamSequence: streamSequence,
                resumeDisposition: resumeDisposition
            )
        )
    )
}

private func contentAcceptedProducerFrame(
    request: BridgeProductContentRequest
) -> BridgeProductProducerFrame {
    .content(
        .init(
            header: .accepted(for: request.admission),
            payload: Data()
        )
    )
}

private func contentResetProducerFrame(
    contentSequence: Int
) throws -> BridgeProductProducerFrame {
    .content(
        .init(
            header: try .reset(
                contentSequence: contentSequence,
                reason: .staleSource
            ),
            payload: Data()
        )
    )
}

private func fileContentRequest(
    identitySuffix: String,
    workerDerivationEpoch: Int
) throws -> BridgeProductContentRequest {
    let requestJSON = """
        {
          "kind": "content.open",
          "wireVersion": 2,
          "paneSessionId": "pane-session-1",
          "workerDerivationEpoch": \(workerDerivationEpoch),
          "workerInstanceId": "worker-instance-1",
          "contentRequestId": "content-request-\(identitySuffix)",
          "leaseId": "lease-\(identitySuffix)",
          "contentKind": "file.content",
          "descriptor": {
            "contentKind": "file.content",
            "declaredByteLength": 3,
            "descriptorId": "file-descriptor-\(identitySuffix)",
            "encoding": "utf-8",
            "expectedSha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "fileId": "file-\(identitySuffix)",
            "maximumBytes": 2097152,
            "source": {
              "repoId": "00000000-0000-4000-8000-000000000001",
              "rootRevisionToken": null,
              "sourceCursor": "source-cursor-\(identitySuffix)",
              "sourceId": "source-\(identitySuffix)",
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
