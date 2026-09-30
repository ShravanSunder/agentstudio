import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge metadata reset retirement ownership")
struct BridgeMetadataRetirementOwnershipTests {
    @Test("a retained resync survives a predecessor producer's late reset")
    func retainedResyncSurvivesPredecessorFailure() async throws {
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let firstLease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: firstLease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let probe = MetadataRetirementOwnershipProbe(holdBeforeReset: true)
        var observations = probe.observations.makeAsyncIterator()
        let registry = try BridgePaneProductMetadataNativeApplicationRegistry(applications: [
            .init(
                registration: AnyBridgeProductMetadataApplicationProtocol(
                    BridgeProductFileMetadataApplication.self
                ),
                adapter: .init(
                    open: { _, _, _, _, _, _, _ in try await probe.open() },
                    cancel: { _, _ in await probe.cancel() }
                )
            )
        ])
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: refreshWorkAdmission.source,
            lifecycleTraceRecorder: probe,
            nativeApplicationRegistry: registry
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: firstLease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        let openRequest = try bridgeProductLifecycleControlRequest(
            bridgeProductLifecycleFileSubscriptionOpenObject(requestSequence: 2, epoch: 1)
        )
        let openToken = try #require(controlExecutionToken(try await harness.begin(openRequest)))
        #expect(await harness.session.admitControlProviderExecution(token: openToken))
        let openResponse = try BridgeProductControlResponse.subscriptionOpenAccepted(
            correlating: openRequest,
            worktreeId: nil
        )
        let openEffect = try await harness.session.completeAdmittedControl(
            token: openToken,
            exactResponseBytes: try JSONEncoder().encode(openResponse)
        )
        guard case .subscriptionOpened(let subscription) = openEffect else {
            Issue.record("Expected File subscription to open")
            return
        }
        _ = try await pullMetadataFrame(from: pump)
        await coordinator.apply(openEffect, productAdmission: harness.productAdmission.context)
        await harness.session.settleControlProviderDispatch(token: openToken)
        #expect(await observations.next() == .producerFailedBeforeReset)

        #expect(try await reconcileRetainedFileSubscription(harness, subscription) == ["retained"])

        #expect(await pump.cancel())
        let successorLease = try await harness.admitMetadataFrames(through: 0)
        await probe.releaseProducerFailure()
        #expect(await probe.waitForFailedProducerReason() == .producerRejection(.unknownLease))

        let resnapshotRequest = try reconnectFileResnapshotRequest()
        let resnapshotAdmission = try await harness.begin(resnapshotRequest)
        if let resnapshotToken = controlExecutionToken(resnapshotAdmission) {
            #expect(await harness.session.admitControlProviderExecution(token: resnapshotToken))
            let resnapshotResponse = try BridgeProductControlResponse.viewAccepted(
                correlating: resnapshotRequest
            )
            _ = try await harness.session.completeAdmittedControl(
                token: resnapshotToken,
                exactResponseBytes: try JSONEncoder().encode(resnapshotResponse)
            )
            await harness.session.settleControlProviderDispatch(token: resnapshotToken)
        } else {
            Issue.record("The retained subscription was refused at resnapshot")
        }
        #expect(
            await harness.session.subscriptionSnapshot(subscriptionId: subscription.subscriptionId) != nil
        )
        await coordinator.uninstall(lease: firstLease)
        try await harness.closeProducer(successorLease)
        await probe.finish()
    }

    @Test("failed predecessor completion cannot retire a replacement producer", .timeLimit(.minutes(1)))
    func failedPredecessorCannotRetireReplacement() async throws {
        // Arrange
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let probe = MetadataRetirementOwnershipProbe()
        var observations = probe.observations.makeAsyncIterator()
        let registry = try BridgePaneProductMetadataNativeApplicationRegistry(applications: [
            .init(
                registration: AnyBridgeProductMetadataApplicationProtocol(
                    BridgeProductFileMetadataApplication.self
                ),
                adapter: .init(
                    open: { _, _, _, _, _, _, _ in try await probe.open() },
                    cancel: { _, _ in await probe.cancel() }
                )
            )
        ])
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: refreshWorkAdmission.source,
            lifecycleTraceRecorder: probe,
            nativeApplicationRegistry: registry
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        let openRequest = try bridgeProductLifecycleControlRequest(
            bridgeProductLifecycleFileSubscriptionOpenObject(requestSequence: 2, epoch: 1)
        )
        let token = try #require(controlExecutionToken(try await harness.begin(openRequest)))
        #expect(await harness.session.admitControlProviderExecution(token: token))
        let response = try BridgeProductControlResponse.subscriptionOpenAccepted(
            correlating: openRequest,
            worktreeId: nil
        )
        let effect = try await harness.session.completeAdmittedControl(
            token: token,
            exactResponseBytes: try JSONEncoder().encode(response)
        )
        guard case .subscriptionOpened(let subscription) = effect else {
            Issue.record("Opening File subscription did not produce a lifecycle effect")
            return
        }
        _ = try await pullMetadataFrame(from: pump)
        await coordinator.apply(effect, productAdmission: harness.productAdmission.context)
        let producerEffect = BridgeProductSessionCompletionEffect.subscriptionOpened(subscription)
        #expect(await observations.next() == .resetEnqueued)
        #expect(await harness.session.subscriptionSnapshot(subscriptionId: subscription.subscriptionId) == nil)
        await harness.session.settleControlProviderDispatch(token: token)

        // Act: hold the old failure after its reset is enqueued, install its
        // successor, then let the stale completion reach the retirement owner.
        await coordinator.apply(
            producerEffect,
            productAdmission: harness.productAdmission.context
        )
        #expect(await observations.next() == .replacementOpened)
        await probe.releaseFailureCompletion()
        #expect(await observations.next() == .failedProducerFinished)

        // Assert
        #expect(await probe.cancellationCount == 0)
        #expect(await coordinator.subscriptionKindById[subscription.subscriptionId] == .fileMetadata)
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
        await probe.finish()
    }
}

private func reconcileRetainedFileSubscription(
    _ harness: BridgeProductSessionLifecycleHarness,
    _ subscription: BridgeProductSubscriptionSnapshot
) async throws -> [String] {
    let scopeRequest = try reconnectFileScopeRequest()
    let scopeToken = try #require(controlExecutionToken(try await harness.begin(scopeRequest)))
    #expect(await harness.session.admitControlProviderExecution(token: scopeToken))
    let scopeResponse = try BridgeProductControlResponse.viewAccepted(correlating: scopeRequest)
    _ = try await harness.session.completeAdmittedControl(
        token: scopeToken,
        exactResponseBytes: try JSONEncoder().encode(scopeResponse)
    )
    await harness.session.settleControlProviderDispatch(token: scopeToken)

    let resyncRequest = try reconnectResyncRequest(
        subscription: subscription,
        lastAcceptedStreamSequence: 1
    )
    let resyncToken = try #require(controlExecutionToken(try await harness.begin(resyncRequest)))
    #expect(await harness.session.admitControlProviderExecution(token: resyncToken))
    let resyncResponse = try await harness.authoritativeResyncResponse(
        request: resyncRequest,
        token: resyncToken
    )
    _ = try await harness.session.completeAdmittedControl(
        token: resyncToken,
        exactResponseBytes: try JSONEncoder().encode(resyncResponse)
    )
    await harness.session.settleControlProviderDispatch(token: resyncToken)
    guard case .resyncAccepted(let accepted) = resyncResponse else {
        Issue.record("Expected typed resync acceptance")
        return []
    }
    return accepted.reconciliation.map(\.dispositionName)
}

private actor MetadataRetirementOwnershipProbe: BridgeProductMetadataLifecycleTraceRecording {
    enum Observation: Equatable, Sendable {
        case producerFailedBeforeReset
        case resetEnqueued
        case replacementOpened
        case failedProducerFinished
    }

    nonisolated let observations: AsyncStream<Observation>
    private let continuation: AsyncStream<Observation>.Continuation
    private var failureCompletionRelease: CheckedContinuation<Void, Never>?
    private var producerFailureRelease: CheckedContinuation<Void, Never>?
    private var failedProducerFinishedWaiters:
        [CheckedContinuation<BridgeProductMetadataProducerFailureReason?, Never>] = []
    private var failedProducerFinished = false
    private var failedProducerReason: BridgeProductMetadataProducerFailureReason?
    private let holdBeforeReset: Bool
    private var replacementRelease: CheckedContinuation<Void, Never>?
    private var operationCount = 0
    private(set) var cancellationCount = 0

    init(holdBeforeReset: Bool = false) {
        self.holdBeforeReset = holdBeforeReset
        let stream = AsyncStream.makeStream(of: Observation.self, bufferingPolicy: .bufferingNewest(8))
        observations = stream.stream
        continuation = stream.continuation
    }

    func open() async throws {
        try await runProducer()
    }

    private func runProducer() async throws {
        operationCount += 1
        if operationCount == 1 {
            throw BridgePaneProductFileMetadataSourceError.unavailableAuthority
        }
        await withCheckedContinuation { pending in
            replacementRelease = pending
            continuation.yield(.replacementOpened)
        }
    }

    func cancel() {
        cancellationCount += 1
        replacementRelease?.resume()
        replacementRelease = nil
    }

    func record(_ event: BridgeProductMetadataLifecycleTraceEvent) async {
        if holdBeforeReset, event.stage == .producerFailed {
            await withCheckedContinuation { pending in
                producerFailureRelease = pending
                continuation.yield(.producerFailedBeforeReset)
            }
        } else if event.stage == .subscriptionResetEnqueued, !holdBeforeReset {
            await withCheckedContinuation { pending in
                failureCompletionRelease = pending
                continuation.yield(.resetEnqueued)
            }
        } else if event.stage == .bootstrapFinished, event.result == .failure {
            failedProducerReason = event.failureReason
            failedProducerFinished = true
            let waiters = failedProducerFinishedWaiters
            failedProducerFinishedWaiters.removeAll()
            for waiter in waiters { waiter.resume(returning: event.failureReason) }
            continuation.yield(.failedProducerFinished)
        }
    }

    func record(_: BridgeProductReviewMetadataPublicationTraceEvent) {}

    func releaseFailureCompletion() {
        failureCompletionRelease?.resume()
        failureCompletionRelease = nil
    }

    func releaseProducerFailure() {
        producerFailureRelease?.resume()
        producerFailureRelease = nil
    }

    func waitForFailedProducerReason() async -> BridgeProductMetadataProducerFailureReason? {
        if failedProducerFinished { return failedProducerReason }
        return await withCheckedContinuation { pending in
            failedProducerFinishedWaiters.append(pending)
        }
    }

    func finish() {
        continuation.finish()
    }
}
