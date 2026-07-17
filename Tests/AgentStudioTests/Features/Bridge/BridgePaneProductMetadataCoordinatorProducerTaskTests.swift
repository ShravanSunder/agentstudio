import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product metadata coordinator producer task ownership")
struct BridgeMetadataCoordinatorProducerTaskTests {
    @Test("internally thrown cancellation error resets the accepted subscription")
    func internallyThrownCancellationErrorResetsAcceptedSubscription() async throws {
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
        let source = CoordinatorCancellationErrorFileSource()
        let traceRecorder = CoordinatorProducerTaskTraceRecorder()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: source,
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: refreshWorkAdmission.source,
            lifecycleTraceRecorder: traceRecorder
        )
        await coordinator.install(
            request: try producerTaskMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        let openRequest = try bridgeProductLifecycleControlRequest(
            bridgeProductLifecycleFileSubscriptionOpenObject(requestSequence: 2, epoch: 1)
        )

        // Act
        let token = try #require(producerTaskControlExecutionToken(try await harness.begin(openRequest)))
        #expect(await harness.session.claimControlProviderDispatch(token: token))
        let response = try BridgeProductControlResponse.subscriptionOpenAccepted(
            correlating: openRequest,
            interestSha256:
                BridgeProductSubscriptionInterestState
                .fileMetadata(interests: [], pathScope: []).sha256Hex()
        )
        let effect = try await harness.session.completeControl(
            token: token,
            exactResponseBytes: try JSONEncoder().encode(response)
        )
        _ = try await pullProducerTaskMetadataFrame(from: pump)
        await coordinator.apply(
            effect,
            productAdmission: harness.productAdmission.context
        )
        await traceRecorder.waitUntilBootstrapFinished()

        // Assert
        #expect(await source.didAttemptOpen)
        guard (await harness.session.producerSnapshot()).queuedFrameCount > 0 else {
            Issue.record("Expected internally thrown CancellationError to enqueue a subscription reset")
            await harness.session.settleControlProviderDispatch(token: token)
            #expect(await pump.cancel())
            return
        }
        let resetFrame = try await pullProducerTaskMetadataFrame(from: pump)
        guard case .subscriptionReset(let reset) = resetFrame else {
            Issue.record("Expected internally thrown CancellationError to reset the subscription")
            await harness.session.settleControlProviderDispatch(token: token)
            #expect(await pump.cancel())
            return
        }
        #expect(reset.reason == .staleSource)
        #expect(
            await traceRecorder.lifecycleEvents.contains {
                $0.stage == .producerFailed && $0.failureReason == .cancellation
            }
        )
        await harness.session.settleControlProviderDispatch(token: token)
        #expect(await pump.cancel())
    }

    @Test("actual bootstrap task cancellation does not synthesize a reset")
    func actualBootstrapTaskCancellationDoesNotSynthesizeReset() async throws {
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
        let source = CoordinatorReplacementBootstrapFileMetadataSource()
        let traceRecorder = CoordinatorProducerTaskTraceRecorder()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: source,
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: refreshWorkAdmission.source,
            lifecycleTraceRecorder: traceRecorder
        )
        await coordinator.install(
            request: try producerTaskMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        let openRequest = try bridgeProductLifecycleControlRequest(
            bridgeProductLifecycleFileSubscriptionOpenObject(requestSequence: 2, epoch: 1)
        )
        let token = try #require(producerTaskControlExecutionToken(try await harness.begin(openRequest)))
        #expect(await harness.session.claimControlProviderDispatch(token: token))
        let response = try BridgeProductControlResponse.subscriptionOpenAccepted(
            correlating: openRequest,
            interestSha256:
                BridgeProductSubscriptionInterestState
                .fileMetadata(interests: [], pathScope: []).sha256Hex()
        )
        let effect = try await harness.session.completeControl(
            token: token,
            exactResponseBytes: try JSONEncoder().encode(response)
        )
        _ = try await pullProducerTaskMetadataFrame(from: pump)
        await coordinator.apply(
            effect,
            productAdmission: harness.productAdmission.context
        )
        await source.waitUntilOpenStarted(openOrdinal: 1)

        // Act
        await coordinator.apply(
            .subscriptionCancelled(try producerTaskFileSubscriptionSnapshot()),
            productAdmission: harness.productAdmission.context
        )
        await source.waitUntilOpenFinished(openOrdinal: 1)
        await traceRecorder.waitUntilBootstrapFinished()

        // Assert
        #expect(await source.openObservedCancellation(openOrdinal: 1))
        #expect(
            await traceRecorder.lifecycleEvents.contains {
                $0.stage == .producerCancelled && $0.failureReason == .taskCancellation
            }
        )
        #expect((await harness.session.producerSnapshot()).queuedFrameCount == 0)
        await harness.session.settleControlProviderDispatch(token: token)
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }

    @Test("stale bootstrap completion preserves the replacement task handle")
    func staleBootstrapCompletionPreservesReplacementTaskHandle() async throws {
        // Arrange
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let source = CoordinatorReplacementBootstrapFileMetadataSource()
        let traceRecorder = CoordinatorProducerTaskTraceRecorder()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: source,
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: refreshWorkAdmission.source,
            lifecycleTraceRecorder: traceRecorder
        )
        await coordinator.install(
            request: try producerTaskMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        let subscription = try producerTaskFileSubscriptionSnapshot()
        await coordinator.apply(
            .subscriptionOpened(subscription),
            productAdmission: harness.productAdmission.context
        )
        await source.waitUntilOpenStarted(openOrdinal: 1)
        await coordinator.apply(
            .subscriptionOpened(subscription),
            productAdmission: harness.productAdmission.context
        )
        await source.waitUntilOpenStarted(openOrdinal: 2)

        // Act
        await source.releaseOpen(openOrdinal: 1)
        await source.waitUntilOpenFinished(openOrdinal: 1)
        await traceRecorder.waitUntilBootstrapFinished()
        await coordinator.apply(
            .subscriptionCancelled(subscription),
            productAdmission: harness.productAdmission.context
        )
        await source.waitUntilOpenFinished(openOrdinal: 2)

        // Assert
        #expect(await source.openObservedCancellation(openOrdinal: 2))
        await coordinator.uninstall(lease: lease)
    }

    @Test("replacement install does not return until cancelled predecessor open drains")
    func replacementInstallWaitsForCancelledPredecessorOpenToDrain() async throws {
        // Arrange
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let firstHarness = try await BridgeProductSessionLifecycleHarness.opened()
        let firstLease = try await firstHarness.admitMetadataFrames(through: 0)
        let source = CoordinatorDrainControlledReviewMetadataSource()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: source,
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        await coordinator.install(
            request: try producerTaskMetadataStreamRequest(),
            lease: firstLease,
            productAdmission: firstHarness.productAdmission.context,
            session: firstHarness.session
        )
        await coordinator.apply(
            .subscriptionOpened(try producerTaskReviewSubscriptionSnapshot()),
            productAdmission: firstHarness.productAdmission.context
        )
        await source.waitUntilOpenStarted()

        let replacementHarness = try await BridgeProductSessionLifecycleHarness.opened()
        let replacementLease = try await replacementHarness.admitMetadataFrames(through: 0)
        let replacementRequest = try producerTaskMetadataStreamRequest()
        let completionProbe = CoordinatorReplacementInstallCompletionProbe()
        let replacementInstall = Task {
            await coordinator.install(
                request: replacementRequest,
                lease: replacementLease,
                productAdmission: replacementHarness.productAdmission.context,
                session: replacementHarness.session
            )
            await completionProbe.recordCompletion()
        }

        // Act
        await source.waitUntilCancelledOpenReachedDrainBarrier()
        for _ in 0..<1000 where !(await completionProbe.didComplete) {
            await Task.yield()
        }
        let completedBeforeDrain = await completionProbe.didComplete
        await source.releaseOpenDrain()
        await replacementInstall.value

        // Assert
        #expect(!completedBeforeDrain)
        #expect(await source.openFinished)
        await coordinator.uninstall(lease: replacementLease)
        try await firstHarness.closeProducer(firstLease)
        try await replacementHarness.closeProducer(replacementLease)
    }

    @Test("subscription cancel does not return until its cancelled producer task drains")
    func subscriptionCancelWaitsForCancelledProducerTaskToDrain() async throws {
        // Arrange
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let source = CoordinatorDrainControlledReviewMetadataSource()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: source,
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        await coordinator.install(
            request: try producerTaskMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        let subscription = try producerTaskReviewSubscriptionSnapshot()
        await coordinator.apply(
            .subscriptionOpened(subscription),
            productAdmission: harness.productAdmission.context
        )
        await source.waitUntilOpenStarted()
        let completionProbe = CoordinatorReplacementInstallCompletionProbe()
        let cancellation = Task {
            await coordinator.apply(
                .subscriptionCancelled(subscription),
                productAdmission: harness.productAdmission.context
            )
            await completionProbe.recordCompletion()
        }

        // Act
        await source.waitUntilCancelledOpenReachedDrainBarrier()
        let completedBeforeDrain = await completionProbe.didComplete
        await source.releaseOpenDrain()
        await cancellation.value

        // Assert
        #expect(!completedBeforeDrain)
        #expect(await source.openFinished)
        await coordinator.uninstall(lease: lease)
        try await harness.closeProducer(lease)
    }

    @Test("coordinator close does not return until cancelled producer tasks drain")
    func closeWaitsForCancelledProducerTasksToDrain() async throws {
        // Arrange
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let source = CoordinatorDrainControlledReviewMetadataSource()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: source,
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        await coordinator.install(
            request: try producerTaskMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        await coordinator.apply(
            .subscriptionOpened(try producerTaskReviewSubscriptionSnapshot()),
            productAdmission: harness.productAdmission.context
        )
        await source.waitUntilOpenStarted()
        let completionProbe = CoordinatorReplacementInstallCompletionProbe()
        let close = Task {
            await coordinator.closeAndDrain()
            await completionProbe.recordCompletion()
        }

        // Act
        await source.waitUntilCancelledOpenReachedDrainBarrier()
        let completedBeforeDrain = await completionProbe.didComplete
        await source.releaseOpenDrain()
        await close.value

        // Assert
        #expect(!completedBeforeDrain)
        #expect(await source.openFinished)
        #expect(!(await coordinator.hasActiveStream))
        try await harness.closeProducer(lease)
    }

    @Test("Review bootstrap failures retain their typed source and producer causes")
    func reviewBootstrapFailuresRetainTypedCauses() async throws {
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let expectations: [(CoordinatorReviewBootstrapFailureMode, BridgeProductMetadataProducerFailureReason)] = [
            (.eventConstruction, .reviewEventConstruction),
            (.producerQueueReset, .producerQueueReset),
            (.producerRejection, .producerRejection(.unknownLease)),
            (.sessionEnqueueFailure, .sessionEnqueueFailure),
            (.unexpected, .unexpected),
        ]

        for (failureMode, expectedReason) in expectations {
            let harness = try await BridgeProductSessionLifecycleHarness.opened()
            let lease = try await harness.admitMetadataFrames(through: 0)
            let traceRecorder = CoordinatorProducerTaskTraceRecorder()
            let coordinator = BridgePaneProductMetadataCoordinator(
                fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
                reviewMetadataSource: CoordinatorThrowingReviewMetadataSource(failureMode: failureMode),
                refreshWorkAdmissionSource: refreshWorkAdmission.source,
                lifecycleTraceRecorder: traceRecorder
            )
            await coordinator.install(
                request: try producerTaskMetadataStreamRequest(),
                lease: lease,
                productAdmission: harness.productAdmission.context,
                session: harness.session
            )

            await coordinator.apply(
                .subscriptionOpened(try producerTaskReviewSubscriptionSnapshot()),
                productAdmission: harness.productAdmission.context
            )
            await traceRecorder.waitUntilBootstrapFinished()

            #expect(
                await traceRecorder.lifecycleEvents.contains {
                    $0.stage == .producerFailed && $0.failureReason == expectedReason
                },
                "Expected typed Review bootstrap failure for \(String(describing: failureMode))"
            )
            await coordinator.uninstall(lease: lease)
            try await harness.closeProducer(lease)
        }
    }
}

private actor CoordinatorReplacementInstallCompletionProbe {
    private(set) var didComplete = false

    func recordCompletion() {
        didComplete = true
    }
}

private actor CoordinatorDrainControlledReviewMetadataSource:
    BridgePaneProductReviewMetadataProducing
{
    private var cancelledOpenReachedDrainBarrier = false
    private var cancelledOpenReachedDrainBarrierWaiters: [CheckedContinuation<Void, Never>] = []
    private var openDrainRelease: CheckedContinuation<Void, Never>?
    private(set) var openFinished = false
    private var openStarted = false
    private var openStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var openSuspensionRelease: CheckedContinuation<Void, Never>?

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        openStarted = true
        let waiters = openStartedWaiters
        openStartedWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            openSuspensionRelease = continuation
        }
        cancelledOpenReachedDrainBarrier = true
        let drainWaiters = cancelledOpenReachedDrainBarrierWaiters
        cancelledOpenReachedDrainBarrierWaiters.removeAll(keepingCapacity: false)
        for waiter in drainWaiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            openDrainRelease = continuation
        }
        openFinished = true
        try Task.checkCancellation()
    }

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {}

    func reserve(
        package: BridgeReviewPackage,
        publicationId: UUID,
        productAdmission _: BridgeProductAdmissionContext
    ) -> BridgeReviewMetadataPublicationReservation {
        coordinatorReviewReservation(for: package, publicationId: publicationId)
    }

    func deliver(
        package _: BridgeReviewPackage,
        reservation _: BridgeReviewMetadataPublicationReservation,
        productAdmission _: BridgeProductAdmissionContext
    ) -> BridgePaneProductReviewMetadataPublicationOutcome {
        .deferred(retained: 0)
    }

    func cancel(subscriptionId _: String) {
        openSuspensionRelease?.resume()
        openSuspensionRelease = nil
    }

    func releaseOpenDrain() {
        openDrainRelease?.resume()
        openDrainRelease = nil
    }

    func waitUntilCancelledOpenReachedDrainBarrier() async {
        guard !cancelledOpenReachedDrainBarrier else { return }
        await withCheckedContinuation { continuation in
            cancelledOpenReachedDrainBarrierWaiters.append(continuation)
        }
    }

    func waitUntilOpenStarted() async {
        guard !openStarted else { return }
        await withCheckedContinuation { continuation in
            openStartedWaiters.append(continuation)
        }
    }
}

private enum CoordinatorReviewBootstrapFailureMode: Sendable {
    case eventConstruction
    case producerQueueReset
    case producerRejection
    case sessionEnqueueFailure
    case unexpected
}

private actor CoordinatorThrowingReviewMetadataSource: BridgePaneProductReviewMetadataProducing {
    private let failureMode: CoordinatorReviewBootstrapFailureMode

    init(failureMode: CoordinatorReviewBootstrapFailureMode) {
        self.failureMode = failureMode
    }

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        switch failureMode {
        case .eventConstruction:
            throw BridgePaneProductReviewMetadataSourceError.metadataEventExceedsByteLimit
        case .producerQueueReset:
            throw BridgePaneProductMetadataCoordinatorError.producerQueueReset
        case .producerRejection:
            throw BridgePaneProductMetadataCoordinatorError.producerRejected(.unknownLease)
        case .sessionEnqueueFailure:
            throw BridgeProductSessionError.lifecycleFrameAdmissionFailed
        case .unexpected:
            throw CoordinatorProducerTaskTestError.unexpectedReviewBootstrapFailure
        }
    }

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {}

    func reserve(
        package: BridgeReviewPackage,
        publicationId: UUID,
        productAdmission _: BridgeProductAdmissionContext
    ) async throws -> BridgeReviewMetadataPublicationReservation {
        BridgeReviewMetadataPublicationReservation(
            reservationId: UUID(),
            packageId: package.packageId,
            publicationId: publicationId,
            reviewGeneration: package.reviewGeneration,
            revision: package.revision
        )
    }

    func deliver(
        package _: BridgeReviewPackage,
        reservation _: BridgeReviewMetadataPublicationReservation,
        productAdmission _: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        .deferred(retained: 0)
    }

    func cancel(subscriptionId _: String) {}
}

private actor CoordinatorReplacementBootstrapFileMetadataSource:
    BridgePaneProductFileMetadataProducing
{
    private var finishedOpenOrdinals: Set<Int> = []
    private var finishedOpenWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var nextOpenOrdinal = 1
    private var observedCancellationByOpenOrdinal: [Int: Bool] = [:]
    private var openReleaseByOrdinal: [Int: CheckedContinuation<Void, Never>] = [:]
    private var startedOpenOrdinals: Set<Int> = []
    private var startedOpenWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func currentSource() -> BridgeProductFileSourceCurrentResult {
        .unavailable(.noFileSourceAuthority)
    }

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        let openOrdinal = nextOpenOrdinal
        nextOpenOrdinal += 1
        startedOpenOrdinals.insert(openOrdinal)
        for waiter in startedOpenWaiters.removeValue(forKey: openOrdinal) ?? [] {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            openReleaseByOrdinal[openOrdinal] = continuation
        }
        observedCancellationByOpenOrdinal[openOrdinal] = Task.isCancelled
        finishedOpenOrdinals.insert(openOrdinal)
        for waiter in finishedOpenWaiters.removeValue(forKey: openOrdinal) ?? [] {
            waiter.resume()
        }
        try Task.checkCancellation()
    }

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {}

    func cancel(subscriptionId _: String) {
        let releases = openReleaseByOrdinal.values
        openReleaseByOrdinal.removeAll(keepingCapacity: false)
        for release in releases { release.resume() }
    }

    func publish(
        status _: GitWorkingTreeStatus,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission
    ) -> [BridgePaneProductFileMetadataEmission] { [] }

    func publish(
        changeset _: FileChangeset,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission
    ) async throws -> [BridgePaneProductFileMetadataEmission] { [] }

    func contentReadPlan(
        for _: BridgeProductFileContentRequest,
        productAdmission _: BridgeProductAdmissionContext
    ) -> BridgePaneProductFileContentReadPlan? { nil }

    func openObservedCancellation(openOrdinal: Int) -> Bool {
        observedCancellationByOpenOrdinal[openOrdinal] ?? false
    }

    func releaseOpen(openOrdinal: Int) {
        openReleaseByOrdinal.removeValue(forKey: openOrdinal)?.resume()
    }

    func waitUntilOpenFinished(openOrdinal: Int) async {
        guard !finishedOpenOrdinals.contains(openOrdinal) else { return }
        await withCheckedContinuation { continuation in
            finishedOpenWaiters[openOrdinal, default: []].append(continuation)
        }
    }

    func waitUntilOpenStarted(openOrdinal: Int) async {
        guard !startedOpenOrdinals.contains(openOrdinal) else { return }
        await withCheckedContinuation { continuation in
            startedOpenWaiters[openOrdinal, default: []].append(continuation)
        }
    }
}

private actor CoordinatorCancellationErrorFileSource:
    BridgePaneProductFileMetadataProducing
{
    private(set) var didAttemptOpen = false

    func currentSource() -> BridgeProductFileSourceCurrentResult {
        .unavailable(.noFileSourceAuthority)
    }

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        didAttemptOpen = true
        throw CancellationError()
    }

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {}

    func cancel(subscriptionId _: String) {}

    func publish(
        status _: GitWorkingTreeStatus,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission
    ) -> [BridgePaneProductFileMetadataEmission] { [] }

    func publish(
        changeset _: FileChangeset,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission
    ) async throws -> [BridgePaneProductFileMetadataEmission] { [] }

    func contentReadPlan(
        for _: BridgeProductFileContentRequest,
        productAdmission _: BridgeProductAdmissionContext
    ) -> BridgePaneProductFileContentReadPlan? { nil }
}

private actor CoordinatorProducerTaskTraceRecorder: BridgeProductMetadataLifecycleTraceRecording {
    private var bootstrapFinished = false
    private var bootstrapFinishedWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var lifecycleEvents: [BridgeProductMetadataLifecycleTraceEvent] = []

    func record(_ event: BridgeProductMetadataLifecycleTraceEvent) {
        lifecycleEvents.append(event)
        guard event.stage == .bootstrapFinished else { return }
        bootstrapFinished = true
        let waiters = bootstrapFinishedWaiters
        bootstrapFinishedWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }

    func record(_: BridgeProductReviewMetadataPublicationTraceEvent) {}

    func waitUntilBootstrapFinished() async {
        guard !bootstrapFinished else { return }
        await withCheckedContinuation { continuation in
            bootstrapFinishedWaiters.append(continuation)
        }
    }
}

private enum CoordinatorProducerTaskTestError: Error {
    case expectedMetadataFrame
    case invalidFileSubscription
    case invalidReviewSubscription
    case unexpectedReviewBootstrapFailure
}

private func pullProducerTaskMetadataFrame(
    from pump: BridgeProductSchemeFramePump
) async throws -> BridgeProductMetadataFrame {
    guard case .frame(let delivery) = await pump.nextFrame() else {
        throw CoordinatorProducerTaskTestError.expectedMetadataFrame
    }
    #expect(await pump.acknowledgeFrameConsumed(delivery.receipt))
    let decoder = try BridgeProductMetadataFrameDecoder()
    return try #require(try decoder.append(delivery.frame.data).first)
}

private func producerTaskControlExecutionToken(
    _ admission: BridgeProductSessionControlAdmission
) -> BridgeProductControlAdmissionToken? {
    guard case .execute(let token, _) = admission else { return nil }
    return token
}

private func producerTaskFileSubscriptionSnapshot() throws -> BridgeProductSubscriptionSnapshot {
    let request = try bridgeProductLifecycleControlRequest(
        bridgeProductLifecycleFileSubscriptionOpenObject(requestSequence: 2, epoch: 1)
    )
    guard case .subscriptionOpen(let openRequest) = request else {
        throw CoordinatorProducerTaskTestError.invalidFileSubscription
    }
    var state = BridgeProductSubscriptionState()
    _ = try state.open(openRequest)
    guard let snapshot = state.snapshot(subscriptionId: openRequest.subscriptionId) else {
        throw CoordinatorProducerTaskTestError.invalidFileSubscription
    }
    return snapshot
}

private func producerTaskReviewSubscriptionSnapshot() throws -> BridgeProductSubscriptionSnapshot {
    let request = try bridgeProductLifecycleControlRequest(
        bridgeProductLifecycleReviewSubscriptionOpenObject(requestSequence: 2, epoch: 1)
    )
    guard case .subscriptionOpen(let openRequest) = request else {
        throw CoordinatorProducerTaskTestError.invalidReviewSubscription
    }
    var state = BridgeProductSubscriptionState()
    _ = try state.open(openRequest)
    guard let snapshot = state.snapshot(subscriptionId: openRequest.subscriptionId) else {
        throw CoordinatorProducerTaskTestError.invalidReviewSubscription
    }
    return snapshot
}

private func producerTaskMetadataStreamRequest() throws -> BridgeProductMetadataStreamRequest {
    let data = try JSONSerialization.data(
        withJSONObject: [
            "kind": "metadataStream.open",
            "metadataStreamId": "metadata-stream-producer-task",
            "paneSessionId": "pane-session-1",
            "resumeFromStreamSequence": NSNull(),
            "wireVersion": BridgeProductWireContract.version,
            "workerInstanceId": "worker-instance-1",
        ],
        options: [.sortedKeys]
    )
    return try BridgeProductStrictJSON.decode(BridgeProductMetadataStreamRequest.self, from: data)
}
