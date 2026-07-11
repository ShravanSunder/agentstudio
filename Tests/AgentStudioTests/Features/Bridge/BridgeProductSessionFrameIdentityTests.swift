import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product session frame identity")
struct BridgeProductSessionFrameIdentityTests {
    @Test("metadata producer rejects a typed frame from the wrong producer kind")
    func metadataProducerRejectsWrongTypedFrameKind() async throws {
        // Arrange
        let harness = try await FrameIdentitySessionHarness.opened()
        let operation = FrameIdentityProducerOperationGate()
        let request = try metadataStreamRequest(metadataStreamId: "metadata-arbitrary")
        let foreignContentRequest = try fileContentRequest(identitySuffix: "wrong-frame-kind")
        let registration = await harness.session.registerMetadataProducer(
            request: request
        ) { lease in
            await operation.run(lease)
        }
        let lease = try #require(registration.acceptedLease)
        _ = await operation.waitUntilStarted()
        let beforeEnqueue = await harness.session.producerSnapshot()

        // Act
        let result = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { _ in
                .content(
                    .init(
                        header: .accepted(for: foreignContentRequest.admission),
                        payload: Data()
                    )
                )
            }
        )
        let afterEnqueue = await harness.session.producerSnapshot()

        // Assert
        #expect(result.isRejected)
        #expect(afterEnqueue.queuedFrameCount == beforeEnqueue.queuedFrameCount)
        #expect(
            afterEnqueue.nextMetadataStreamSequence
                == beforeEnqueue.nextMetadataStreamSequence
        )
        try await closeProducer(lease, in: harness.session)
    }

    @Test("metadata producer binds encoded identity and sequence to its registered stream")
    func metadataProducerRejectsCrossWiredIdentityAndSequence() async throws {
        // Arrange
        let harness = try await FrameIdentitySessionHarness.opened()
        let operation = FrameIdentityProducerOperationGate()
        let registeredRequest = try metadataStreamRequest(
            metadataStreamId: "metadata-registered"
        )
        let foreignRequest = try metadataStreamRequest(
            metadataStreamId: "metadata-foreign"
        )
        let registration = await harness.session.registerMetadataProducer(
            request: registeredRequest
        ) { lease in
            await operation.run(lease)
        }
        let lease = try #require(registration.acceptedLease)
        _ = await operation.waitUntilStarted()

        // Act
        let result = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { expectedSequence in
                let crossWiredFrame = BridgeProductMetadataFrame.metadataStreamAccepted(
                    try BridgeProductMetadataStreamAcceptedFrame(
                        stream: foreignRequest.correlation,
                        streamSequence: expectedSequence + 1,
                        resumeDisposition: .resumed
                    )
                )
                return .metadata(crossWiredFrame)
            }
        )
        let afterEnqueue = await harness.session.producerSnapshot()

        // Assert
        #expect(result.isRejected)
        #expect(afterEnqueue.queuedFrameCount == 0)
        #expect(afterEnqueue.nextMetadataStreamSequence == 0)
        try await closeProducer(lease, in: harness.session)
    }

    @Test("content producer binds accepted identity to its registered admission")
    func contentProducerRejectsCrossWiredAcceptedIdentity() async throws {
        // Arrange
        let harness = try await FrameIdentitySessionHarness.opened()
        let operation = FrameIdentityProducerOperationGate()
        let registeredRequest = try fileContentRequest(identitySuffix: "registered")
        let foreignRequest = try fileContentRequest(identitySuffix: "foreign")
        let registration = await harness.session.registerContentProducer(
            request: registeredRequest
        ) { lease in
            await operation.run(lease)
        }
        let lease = try #require(registration.acceptedLease)
        _ = await operation.waitUntilStarted()

        // Act
        let result = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { _ in
                .content(
                    .init(
                        header: .accepted(for: foreignRequest.admission),
                        payload: Data()
                    )
                )
            }
        )
        let afterEnqueue = await harness.session.producerSnapshot()

        // Assert
        #expect(result.isRejected)
        #expect(afterEnqueue.queuedFrameCount == 0)
        try await closeProducer(lease, in: harness.session)
    }

    @Test("content producer rejects an encoded sequence different from its lease sequence")
    func contentProducerRejectsMismatchedProgressSequence() async throws {
        // Arrange
        let harness = try await FrameIdentitySessionHarness.opened()
        let operation = FrameIdentityProducerOperationGate()
        let request = try fileContentRequest(identitySuffix: "sequence")
        let registration = await harness.session.registerContentProducer(
            request: request
        ) { lease in
            await operation.run(lease)
        }
        let lease = try #require(registration.acceptedLease)
        _ = await operation.waitUntilStarted()
        let openingResult = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { _ in
                .content(
                    .init(
                        header: .accepted(for: request.admission),
                        payload: Data()
                    )
                )
            }
        )
        #expect(openingResult.isEnqueued)
        _ = try #require(
            await consumeNextBridgeProductProducerFrame(
                for: lease,
                from: harness.session
            )
        )

        // Act
        let progressResult = try await harness.session.enqueueProducerFrame(
            for: lease,
            build: { expectedSequence in
                .content(
                    .init(
                        header: try .data(
                            contentSequence: expectedSequence + 1,
                            offsetBytes: 0
                        ),
                        payload: Data([0x41])
                    )
                )
            },
            overflowReset: { expectedSequence in
                .content(
                    .init(
                        header: try .reset(
                            contentSequence: expectedSequence,
                            reason: .producerOverflow
                        ),
                        payload: Data()
                    )
                )
            }
        )
        let afterProgress = await harness.session.producerSnapshot()

        // Assert
        #expect(progressResult.isRejected)
        #expect(afterProgress.queuedFrameCount == 0)
        try await closeProducer(lease, in: harness.session)
    }

    @Test("maximum safe control sequence is rejected before execution")
    func maximumSafeControlSequenceIsRejectedBeforeExecution() {
        // Arrange
        let maximumSafeInteger = BridgeProductWireContract.maximumSafeInteger
        var replayCache = BridgeProductControlReplayCache(
            nextExpectedRequestSequence: maximumSafeInteger
        )
        let initialSnapshot = replayCache.snapshot

        // Act
        let admission = replayCache.begin(
            requestSequence: maximumSafeInteger,
            exactRequestBytes: Data("maximum-sequence-request".utf8)
        )

        // Assert
        #expect(admission.isRejected)
        #expect(replayCache.snapshot == initialSnapshot)
    }

    @Test("metadata resume rejects a cursor without accepted and terminal successors")
    func metadataResumeRejectsSequenceExhaustion() throws {
        // Arrange
        let firstNonresumableSequence =
            BridgeProductWireContract.maximumResumableStreamSequence + 1

        // Act
        let rejected = try? metadataStreamRequest(
            metadataStreamId: "metadata-exhaustion",
            resumeFromStreamSequence: firstNonresumableSequence
        )

        // Assert
        #expect(rejected == nil)
    }
}

private struct FrameIdentitySessionHarness {
    static let paneSessionId = "pane-session-frame-identity"
    static let workerInstanceId = "worker-instance-frame-identity"

    let session: BridgeProductSession

    static func opened() async throws -> Self {
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        let session = try BridgeProductSession(
            paneSessionId: paneSessionId,
            workerInstanceId: workerInstanceId,
            capabilityBytes: capabilityBytes
        )
        let requestBytes = try JSONSerialization.data(
            withJSONObject: [
                "kind": "workerSession.open",
                "paneSessionId": paneSessionId,
                "request": NSNull(),
                "requestId": "request-frame-identity-open",
                "requestSequence": 1,
                "wireVersion": BridgeProductWireContract.version,
                "workerInstanceId": workerInstanceId,
            ],
            options: [.sortedKeys]
        )
        let request = try BridgeProductStrictJSON.decode(
            BridgeProductControlRequest.self,
            from: requestBytes
        )
        let admission = await session.beginControl(
            exactRequestBytes: requestBytes,
            presentedCapability: capabilityHeader
        )
        let token = try #require(admission.executionToken)
        let response = try BridgeProductControlResponse.workerSessionAccepted(
            correlating: request
        )
        _ = try await session.completeControl(
            token: token,
            exactResponseBytes: try JSONEncoder().encode(response)
        )
        return Self(session: session)
    }
}

private actor FrameIdentityProducerOperationGate {
    private var cancellationContinuation: CheckedContinuation<Void, Never>?
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
                if Task.isCancelled {
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
        cancellationContinuation?.resume()
        cancellationContinuation = nil
    }
}

extension BridgeProductSessionControlAdmission {
    fileprivate var executionToken: BridgeProductControlAdmissionToken? {
        guard case .execute(let token, _) = self else { return nil }
        return token
    }
}

extension BridgeProductControlReplayAdmission {
    fileprivate var isRejected: Bool {
        guard case .rejected = self else { return false }
        return true
    }
}

extension BridgeProductProducerRegistration {
    fileprivate var acceptedLease: BridgeProductProducerLease? {
        guard case .accepted(let lease) = self else { return nil }
        return lease
    }
}

extension BridgeProductProducerEnqueueResult {
    fileprivate var isEnqueued: Bool {
        guard case .enqueued = self else { return false }
        return true
    }

    fileprivate var isRejected: Bool {
        guard case .rejected = self else { return false }
        return true
    }
}

private func closeProducer(
    _ lease: BridgeProductProducerLease,
    in session: BridgeProductSession
) async throws {
    #expect(await session.stopProducer(lease))
    let acknowledgement = try #require(await session.unregisterProducer(lease))
    #expect(await session.acknowledgeProducerLifecycle(acknowledgement))
}

private func metadataStreamRequest(
    metadataStreamId: String,
    resumeFromStreamSequence: Int? = nil
) throws -> BridgeProductMetadataStreamRequest {
    let data = try JSONSerialization.data(
        withJSONObject: [
            "kind": "metadataStream.open",
            "metadataStreamId": metadataStreamId,
            "paneSessionId": FrameIdentitySessionHarness.paneSessionId,
            "resumeFromStreamSequence": resumeFromStreamSequence.map { $0 as Any } ?? NSNull(),
            "wireVersion": BridgeProductWireContract.version,
            "workerInstanceId": FrameIdentitySessionHarness.workerInstanceId,
        ],
        options: [.sortedKeys]
    )
    return try BridgeProductStrictJSON.decode(
        BridgeProductMetadataStreamRequest.self,
        from: data
    )
}

private func fileContentRequest(
    identitySuffix: String
) throws -> BridgeProductContentRequest {
    let requestJSON = """
        {
          "kind": "content.open",
          "wireVersion": 2,
          "paneSessionId": "\(FrameIdentitySessionHarness.paneSessionId)",
          "workerDerivationEpoch": 1,
          "workerInstanceId": "\(FrameIdentitySessionHarness.workerInstanceId)",
          "contentRequestId": "content-request-\(identitySuffix)",
          "leaseId": "lease-\(identitySuffix)",
          "contentKind": "file.content",
          "descriptor": {
            "contentKind": "file.content",
            "declaredByteLength": 1,
            "descriptorId": "file-descriptor-\(identitySuffix)",
            "encoding": "utf-8",
            "expectedSha256": null,
            "fileId": "file-\(identitySuffix)",
            "maximumBytes": 2097152,
            "source": {
              "repoId": "00000000-0000-4000-8000-000000000001",
              "rootRevisionToken": null,
              "sourceCursor": "source-cursor-\(identitySuffix)",
              "sourceId": "source-\(identitySuffix)",
              "subscriptionGeneration": 1,
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
