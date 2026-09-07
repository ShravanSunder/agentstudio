import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge metadata reset retirement ownership")
struct BridgeMetadataRetirementOwnershipTests {
    @Test(
        "failed predecessor completion cannot retire a replacement producer",
        .timeLimit(.minutes(1)),
        arguments: [false, true]
    )
    func failedPredecessorCannotRetireReplacement(failsDuringInterest: Bool) async throws {
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
        let probe = MetadataRetirementOwnershipProbe(failsDuringInterest: failsDuringInterest)
        var observations = probe.observations.makeAsyncIterator()
        let registry = try BridgePaneProductMetadataNativeApplicationRegistry(applications: [
            .init(
                registration: AnyBridgeProductMetadataApplicationProtocol(
                    BridgeProductFileMetadataApplication.self
                ),
                adapter: .init(
                    open: { _, _, _, _, _, _, _ in try await probe.open() },
                    update: { _, _, _, _, _, _, _ in try await probe.update() },
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
        #expect(await harness.session.claimControlProviderDispatch(token: token))
        let lifecycle = try coordinatorFileSubscriptionLifecycle()
        let subscription = lifecycle.opened
        let response = try BridgeProductControlResponse.subscriptionOpenAccepted(
            correlating: openRequest,
            interestSha256: subscription.interestSha256
        )
        let effect = try await harness.session.completeControl(
            token: token,
            exactResponseBytes: try JSONEncoder().encode(response)
        )
        _ = try await pullMetadataFrame(from: pump)
        await coordinator.apply(effect, productAdmission: harness.productAdmission.context)
        let producerEffect: BridgeProductSessionCompletionEffect =
            failsDuringInterest
            ? .subscriptionInterestsCommitted(barrier: lifecycle.commitBarrier, subscription: lifecycle.updated)
            : .subscriptionOpened(subscription)
        if failsDuringInterest {
            #expect(await observations.next() == .initialBootstrapFinished)
            await coordinator.apply(producerEffect, productAdmission: harness.productAdmission.context)
        }
        #expect(await observations.next() == .resetEnqueued)
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

private actor MetadataRetirementOwnershipProbe: BridgeProductMetadataLifecycleTraceRecording {
    enum Observation: Equatable, Sendable {
        case initialBootstrapFinished
        case resetEnqueued
        case replacementOpened
        case failedProducerFinished
    }

    nonisolated let observations: AsyncStream<Observation>
    private let continuation: AsyncStream<Observation>.Continuation
    private let failsDuringInterest: Bool
    private var failureCompletionRelease: CheckedContinuation<Void, Never>?
    private var replacementRelease: CheckedContinuation<Void, Never>?
    private var operationCount = 0
    private(set) var cancellationCount = 0

    init(failsDuringInterest: Bool) {
        self.failsDuringInterest = failsDuringInterest
        let stream = AsyncStream.makeStream(of: Observation.self, bufferingPolicy: .bufferingNewest(8))
        observations = stream.stream
        continuation = stream.continuation
    }

    func open() async throws {
        if !failsDuringInterest { try await runProducer() }
    }

    func update() async throws {
        if failsDuringInterest { try await runProducer() }
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
        if event.stage == .subscriptionResetEnqueued {
            await withCheckedContinuation { pending in
                failureCompletionRelease = pending
                continuation.yield(.resetEnqueued)
            }
        } else if event.stage == .bootstrapFinished, event.result == .failure {
            continuation.yield(.failedProducerFinished)
        } else if event.stage == .bootstrapFinished, operationCount == 0 {
            continuation.yield(.initialBootstrapFinished)
        }
    }

    func record(_: BridgeProductReviewMetadataPublicationTraceEvent) {}

    func releaseFailureCompletion() {
        failureCompletionRelease?.resume()
        failureCompletionRelease = nil
    }

    func finish() {
        continuation.finish()
    }
}
