import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product scheme control completion effects")
struct BridgeProductSchemeControlCompletionEffectsTests {
    @Test("product call mutates only after committed completion and only once")
    func productCallMutationRequiresCommittedCompletion() async throws {
        // Arrange
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        let session = try BridgeProductSession(
            paneSessionId: bridgeProductTestPaneSessionId,
            workerInstanceId: bridgeProductTestWorkerInstanceId,
            capabilityBytes: capabilityBytes
        )
        let recorder = await MainActor.run { BridgeProductCallMutationRecorder() }
        let provider = BridgePaneProductSchemeProvider(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            reviewContentSource: BridgeUnavailablePaneProductReviewContentSource()
        ) { itemId in
            recorder.record(itemId)
        }
        let dispatcher = BridgeProductSchemeControlDispatcher(session: session, provider: provider)
        let callBody = bridgeProductCompletionEffectsMarkViewedBody()
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
        let countAfterCommitAndReplay = await recorder.count
        let revocation = await session.revoke(acknowledgeLifecycle: { _ in true })
        #expect(await revocation.wait())
        _ = try await dispatcher.dispatch(
            exactRequestBytes: callBody,
            presentedCapability: capabilityHeader
        )

        // Assert
        #expect(countAfterProviderResponse == 0)
        #expect(countAfterCommitAndReplay == 1)
        #expect(await recorder.count == 1)
        #expect(await recorder.itemIds == ["item-1"])
    }

    @Test("committed effects reach the provider after mutation and only once across replay")
    func committedEffectsAreDeliveredAfterSessionMutation() async throws {
        // Arrange
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        let session = try BridgeProductSession(
            paneSessionId: bridgeProductTestPaneSessionId,
            workerInstanceId: bridgeProductTestWorkerInstanceId,
            capabilityBytes: capabilityBytes
        )
        let provider = BridgeProductCompletionEffectsRecordingProvider(session: session)
        let dispatcher = BridgeProductSchemeControlDispatcher(session: session, provider: provider)
        let subscriptionOpenBody = bridgeProductCompletionEffectsSubscriptionOpenBody()
        let subscriptionCancelBody = bridgeProductCompletionEffectsSubscriptionCancelBody()

        _ = try await dispatcher.dispatch(
            exactRequestBytes: bridgeProductSchemeWorkerOpenBody(),
            presentedCapability: capabilityHeader
        )
        _ = try await installCompletionEffectsMetadataStream(in: session)
        _ = try await dispatcher.dispatch(
            exactRequestBytes: subscriptionOpenBody,
            presentedCapability: capabilityHeader
        )

        // Act
        _ = try await dispatcher.dispatch(
            exactRequestBytes: subscriptionCancelBody,
            presentedCapability: capabilityHeader
        )
        _ = try await dispatcher.dispatch(
            exactRequestBytes: subscriptionCancelBody,
            presentedCapability: capabilityHeader
        )
        let observations = await provider.completionEffectObservations

        // Assert
        let observation = try #require(observations.first)
        #expect(observations.count == 1)
        #expect(observation.cancelledSubscriptionId == bridgeProductCompletionEffectsSubscriptionId)
        #expect(!observation.cancelledSubscriptionWasStillRegistered)
        #expect(observation.nextExpectedRequestSequence == 4)
    }

    @Test("a rejected candidate mutation never publishes completion effects")
    func rejectedCandidateMutationDoesNotPublishEffects() async throws {
        // Arrange
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        let session = try BridgeProductSession(
            paneSessionId: bridgeProductTestPaneSessionId,
            workerInstanceId: bridgeProductTestWorkerInstanceId,
            capabilityBytes: capabilityBytes
        )
        let provider = BridgeProductCompletionEffectsRecordingProvider(
            session: session,
            subscriptionOpenInterestSha256: String(repeating: "0", count: 64)
        )
        let dispatcher = BridgeProductSchemeControlDispatcher(session: session, provider: provider)

        _ = try await dispatcher.dispatch(
            exactRequestBytes: bridgeProductSchemeWorkerOpenBody(),
            presentedCapability: capabilityHeader
        )

        // Act
        let dispatchResult = try await dispatcher.dispatch(
            exactRequestBytes: bridgeProductCompletionEffectsSubscriptionOpenBody(),
            presentedCapability: capabilityHeader
        )

        // Assert
        guard case .response(let responseBytes) = dispatchResult,
            case .requestError(let response) = try BridgeProductStrictJSON.decode(
                BridgeProductControlResponse.self,
                from: responseBytes
            )
        else {
            Issue.record("Expected a typed internal response for the rejected mutation")
            return
        }
        #expect(response.code == .internal)
        #expect(response.nextExpectedRequestSequence == 3)
        #expect(await provider.completionEffectObservations.isEmpty)
        #expect(
            await session.subscriptionSnapshot(
                subscriptionId: bridgeProductCompletionEffectsSubscriptionId
            ) == nil
        )
        let finalSnapshot = await session.snapshot
        #expect(!finalSnapshot.pendingControlProviderDispatched)
        #expect(finalSnapshot.controlReplay.inFlightRequestSequence == nil)
        #expect(finalSnapshot.controlReplay.replayableRequestSequence == 2)
    }

    @Test("pane provider rejects subscription open until metadata stream is installed")
    func paneProviderRequiresMetadataStreamBeforeSubscriptionOpen() async throws {
        // Arrange
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        let session = try BridgeProductSession(
            paneSessionId: bridgeProductTestPaneSessionId,
            workerInstanceId: bridgeProductTestWorkerInstanceId,
            capabilityBytes: capabilityBytes
        )
        let provider = BridgePaneProductSchemeProvider(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            reviewContentSource: BridgeUnavailablePaneProductReviewContentSource()
        ) { _ in }
        let dispatcher = BridgeProductSchemeControlDispatcher(session: session, provider: provider)
        _ = try await dispatcher.dispatch(
            exactRequestBytes: bridgeProductSchemeWorkerOpenBody(),
            presentedCapability: capabilityHeader
        )

        // Act
        let dispatchResult = try await dispatcher.dispatch(
            exactRequestBytes: bridgeProductCompletionEffectsSubscriptionOpenBody(),
            presentedCapability: capabilityHeader
        )

        // Assert
        guard case .response(let responseBytes) = dispatchResult else {
            Issue.record("Expected a correlated subscription-open response")
            return
        }
        let response = try BridgeProductStrictJSON.decode(
            BridgeProductControlResponse.self,
            from: responseBytes
        )
        guard case .requestError(let requestError) = response else {
            Issue.record("Expected a typed resync-required response")
            return
        }
        #expect(requestError.code == .resyncRequired)
        #expect(requestError.retryable)
        #expect(
            await session.subscriptionSnapshot(
                subscriptionId: bridgeProductCompletionEffectsSubscriptionId
            ) == nil
        )
        #expect((await session.snapshot).controlReplay.nextExpectedRequestSequence == 3)
    }

    @Test("forced lifecycle admission failure caches only a typed error and no mutation")
    func lifecycleAdmissionFailureCannotCacheAcceptedResponse() async throws {
        // Arrange
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        let session = try BridgeProductSession(
            paneSessionId: bridgeProductTestPaneSessionId,
            workerInstanceId: bridgeProductTestWorkerInstanceId,
            capabilityBytes: capabilityBytes
        )
        let provider = BridgeProductCompletionEffectsRecordingProvider(session: session)
        let dispatcher = BridgeProductSchemeControlDispatcher(session: session, provider: provider)
        let openBody = bridgeProductCompletionEffectsSubscriptionOpenBody()
        _ = try await dispatcher.dispatch(
            exactRequestBytes: bridgeProductSchemeWorkerOpenBody(),
            presentedCapability: capabilityHeader
        )

        // Act
        let firstResult = try await dispatcher.dispatch(
            exactRequestBytes: openBody,
            presentedCapability: capabilityHeader
        )
        let replayResult = try await dispatcher.dispatch(
            exactRequestBytes: openBody,
            presentedCapability: capabilityHeader
        )

        // Assert
        guard case .response(let firstBytes) = firstResult,
            case .response(let replayBytes) = replayResult,
            case .requestError(let errorResponse) = try BridgeProductStrictJSON.decode(
                BridgeProductControlResponse.self,
                from: firstBytes
            )
        else {
            Issue.record("Expected a replayable typed error response")
            return
        }
        #expect(errorResponse.code == .internal)
        #expect(firstBytes == replayBytes)
        #expect(
            await session.subscriptionSnapshot(
                subscriptionId: bridgeProductCompletionEffectsSubscriptionId
            ) == nil
        )
        #expect((await session.snapshot).controlReplay.replayableRequestSequence == 2)
        #expect(await provider.completionEffectObservations.isEmpty)
    }

    @Test("revocation waits until committed control effects finish")
    func revocationWaitsForCommittedControlEffects() async throws {
        // Arrange
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        let session = try BridgeProductSession(
            paneSessionId: bridgeProductTestPaneSessionId,
            workerInstanceId: bridgeProductTestWorkerInstanceId,
            capabilityBytes: capabilityBytes
        )
        let committedEffectsGate = BridgeProductCommittedEffectsGate()
        let provider = BridgeProductCompletionEffectsRecordingProvider(
            session: session,
            committedEffectsGate: committedEffectsGate
        )
        let dispatcher = BridgeProductSchemeControlDispatcher(session: session, provider: provider)
        _ = try await dispatcher.dispatch(
            exactRequestBytes: bridgeProductSchemeWorkerOpenBody(),
            presentedCapability: capabilityHeader
        )
        _ = try await installCompletionEffectsMetadataStream(in: session)
        _ = try await dispatcher.dispatch(
            exactRequestBytes: bridgeProductCompletionEffectsSubscriptionOpenBody(),
            presentedCapability: capabilityHeader
        )
        let cancelDispatch = Task {
            try await dispatcher.dispatch(
                exactRequestBytes: bridgeProductCompletionEffectsSubscriptionCancelBody(),
                presentedCapability: capabilityHeader
            )
        }
        await committedEffectsGate.waitUntilStarted()

        // Act
        let revocationBarrier = await session.revoke(acknowledgeLifecycle: { _ in true })
        let whileEffectsAreBlocked = await session.snapshot
        let revocationProbe = BridgeProductRevocationBarrierProbe()
        let revocationWait = Task { await revocationProbe.wait(on: revocationBarrier) }
        await revocationProbe.waitUntilStarted()
        let revocationResultBeforeEffectsFinished = await revocationProbe.result

        cancelDispatch.cancel()
        await committedEffectsGate.release()
        let cancelledCallerResult = try await cancelDispatch.value
        let revocationResult = await revocationWait.value
        let afterEffectsFinished = await session.snapshot

        // Assert
        #expect(whileEffectsAreBlocked.pendingControlProviderDispatched)
        #expect(revocationResultBeforeEffectsFinished == nil)
        guard case .response = cancelledCallerResult else {
            Issue.record("Expected claimed dispatch to finish after caller cancellation")
            return
        }
        #expect(revocationResult)
        #expect(!afterEffectsFinished.pendingControlProviderDispatched)
        #expect(afterEffectsFinished.controlReplay.inFlightRequestSequence == nil)
    }

    @Test("claimed open cleanup cannot resurrect a revoked session")
    func claimedOpenCleanupPreservesRevocation() async throws {
        // Arrange
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        let session = try BridgeProductSession(
            paneSessionId: bridgeProductTestPaneSessionId,
            workerInstanceId: bridgeProductTestWorkerInstanceId,
            capabilityBytes: capabilityBytes
        )
        let admission = await session.beginControl(
            exactRequestBytes: bridgeProductSchemeWorkerOpenBody(),
            presentedCapability: capabilityHeader
        )
        guard case .execute(let token, _) = admission else {
            Issue.record("Expected worker open execution admission")
            return
        }
        #expect(await session.claimControlProviderDispatch(token: token))

        // Act
        let revocationBarrier = await session.revoke(acknowledgeLifecycle: { _ in true })
        await session.settleControlProviderDispatch(token: token)
        let didRevoke = await revocationBarrier.wait()

        // Assert
        #expect(didRevoke)
        #expect((await session.snapshot).lifecycle == .revoked)
        #expect(!(await session.authorizes(presentedCapability: capabilityHeader)))
    }
}

private func installCompletionEffectsMetadataStream(
    in session: BridgeProductSession
) async throws -> BridgeProductProducerLease {
    let operation = BridgeProductSessionProducerOperationGate()
    let request = try bridgeProductMetadataStreamRequest(
        metadataStreamId: "metadata-completion-effects-\(UUID().uuidString)",
        resumeFromStreamSequence: nil
    )
    let registration = await session.registerMetadataProducer(request: request) { lease in
        await operation.run(lease)
    }
    guard case .accepted(let lease) = registration else {
        throw BridgeProductSessionError.lifecycleFrameAdmissionFailed
    }
    _ = await operation.waitUntilStarted()
    _ = try await session.enqueueRequiredProducerOpeningFrame(
        for: lease,
        build: { sequence in
            try producerRegistryMetadataOpeningFrame(for: request, sequence: sequence)
        }
    )
    return lease
}

@MainActor
private final class BridgeProductCallMutationRecorder {
    private(set) var itemIds: [String] = []
    var count: Int { itemIds.count }

    func record(_ itemId: String) {
        itemIds.append(itemId)
    }
}

private func bridgeProductCompletionEffectsMarkViewedBody() -> Data {
    Data(
        """
        {
          "call": {
            "method": "review.markFileViewed",
            "request": { "itemId": "item-1" }
          },
          "kind": "product.call",
          "paneSessionId": "\(bridgeProductTestPaneSessionId)",
          "requestId": "mark-viewed-1",
          "requestSequence": 2,
          "wireVersion": 2,
          "workerDerivationEpoch": 0,
          "workerInstanceId": "\(bridgeProductTestWorkerInstanceId)"
        }
        """.utf8
    )
}

private let bridgeProductCompletionEffectsSubscriptionId = "review-subscription-effects-1"
private let bridgeProductCompletionEffectsEmptyInterestSha256 =
    "1a71797cab8ed23c72233b7706b166a33049e4e87dfbc55b9e252f9c1843eca6"

private struct BridgeProductCompletionEffectsObservation: Equatable, Sendable {
    let cancelledSubscriptionId: String?
    let cancelledSubscriptionWasStillRegistered: Bool
    let nextExpectedRequestSequence: Int
}

private actor BridgeProductCompletionEffectsRecordingProvider: BridgeProductSchemeProvider {
    private let committedEffectsGate: BridgeProductCommittedEffectsGate?
    private let session: BridgeProductSession
    private let subscriptionOpenInterestSha256: String
    private(set) var completionEffectObservations: [BridgeProductCompletionEffectsObservation] = []

    init(
        session: BridgeProductSession,
        subscriptionOpenInterestSha256: String = bridgeProductCompletionEffectsEmptyInterestSha256,
        committedEffectsGate: BridgeProductCommittedEffectsGate? = nil
    ) {
        self.committedEffectsGate = committedEffectsGate
        self.session = session
        self.subscriptionOpenInterestSha256 = subscriptionOpenInterestSha256
    }

    func response(
        for request: BridgeProductControlRequest
    ) async -> BridgeProductControlResponse {
        do {
            switch request {
            case .workerSessionOpen:
                return try .workerSessionAccepted(correlating: request)
            case .subscriptionOpen:
                return try .subscriptionOpenAccepted(
                    correlating: request,
                    interestSha256: subscriptionOpenInterestSha256
                )
            case .subscriptionCancel:
                return try .subscriptionCancelAccepted(correlating: request)
            case .productCall, .subscriptionUpdateBatch, .workerSessionResync:
                preconditionFailure("Unexpected completion-effects control request")
            }
        } catch {
            preconditionFailure("Could not build completion-effects control response")
        }
    }

    func applyCommittedControlEffect(
        _ effect: BridgeProductSessionCompletionEffect,
        for request: BridgeProductControlRequest
    ) async {
        _ = request
        guard case .subscriptionCancelled(let cancelledSubscription) = effect else { return }
        await committedEffectsGate?.waitForReleaseAfterStarting()
        let cancelledSubscriptionId = cancelledSubscription.subscriptionId
        let cancelledSubscriptionWasStillRegistered =
            await session.subscriptionSnapshot(subscriptionId: cancelledSubscriptionId) != nil
        completionEffectObservations.append(
            .init(
                cancelledSubscriptionId: cancelledSubscriptionId,
                cancelledSubscriptionWasStillRegistered: cancelledSubscriptionWasStillRegistered,
                nextExpectedRequestSequence: await session.snapshot.controlReplay.nextExpectedRequestSequence
            )
        )
    }

    func runMetadataProducer(
        request: BridgeProductMetadataStreamRequest,
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async {
        _ = (request, lease, session)
    }

    func runContentProducer(
        request: BridgeProductContentRequest,
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async {
        _ = (request, lease, session)
    }

    func acknowledgeLifecycle(
        _ acknowledgement: BridgeProductProducerLifecycleAcknowledgement
    ) async -> Bool {
        _ = acknowledgement
        return true
    }
}

private actor BridgeProductCommittedEffectsGate {
    private var didRelease = false
    private var didStart = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?

    func waitForReleaseAfterStarting() async {
        didStart = true
        startContinuation?.resume()
        startContinuation = nil
        if didRelease { return }
        await withCheckedContinuation { continuation in
            precondition(releaseContinuation == nil)
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { continuation in
            precondition(startContinuation == nil)
            startContinuation = continuation
        }
    }

    func release() {
        guard !didRelease else { return }
        didRelease = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor BridgeProductRevocationBarrierProbe {
    private(set) var result: Bool?
    private var didStart = false
    private var startContinuation: CheckedContinuation<Void, Never>?

    func wait(on barrier: BridgeProductSessionRevocationBarrier) async -> Bool {
        didStart = true
        startContinuation?.resume()
        startContinuation = nil
        let result = await barrier.wait()
        self.result = result
        return result
    }

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { continuation in
            precondition(startContinuation == nil)
            startContinuation = continuation
        }
    }
}

private func bridgeProductCompletionEffectsSubscriptionOpenBody() -> Data {
    Data(
        """
        {
          "kind":"subscription.open",
          "wireVersion":2,
          "paneSessionId":"\(bridgeProductTestPaneSessionId)",
          "workerDerivationEpoch":1,
          "workerInstanceId":"\(bridgeProductTestWorkerInstanceId)",
          "requestId":"request-review-subscription-effects-open-1",
          "requestSequence":2,
          "subscriptionId":"\(bridgeProductCompletionEffectsSubscriptionId)",
          "subscription":{"subscriptionKind":"review.metadata"}
        }
        """.utf8
    )
}

private func bridgeProductCompletionEffectsSubscriptionCancelBody() -> Data {
    Data(
        """
        {
          "kind":"subscription.cancel",
          "wireVersion":2,
          "paneSessionId":"\(bridgeProductTestPaneSessionId)",
          "workerDerivationEpoch":1,
          "workerInstanceId":"\(bridgeProductTestWorkerInstanceId)",
          "requestId":"request-review-subscription-effects-cancel-1",
          "requestSequence":3,
          "subscriptionId":"\(bridgeProductCompletionEffectsSubscriptionId)",
          "subscriptionKind":"review.metadata"
        }
        """.utf8
    )
}
