import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product metadata coordinator producer task ownership")
struct BridgeMetadataCoordinatorProducerTaskTests {
    @Test("internally thrown cancellation error resets the accepted subscription")
    func internallyThrownCancellationErrorResetsAcceptedSubscription() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            acknowledgeLifecycle: { _ in true }
        )
        let source = CoordinatorCancellationErrorFileSource()
        let traceRecorder = CoordinatorProducerTaskTraceRecorder()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: source,
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            lifecycleTraceRecorder: traceRecorder
        )
        await coordinator.install(
            request: try producerTaskMetadataStreamRequest(),
            lease: lease,
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
        await coordinator.apply(effect)
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
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            acknowledgeLifecycle: { _ in true }
        )
        let source = CoordinatorReplacementBootstrapFileMetadataSource()
        let traceRecorder = CoordinatorProducerTaskTraceRecorder()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: source,
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            lifecycleTraceRecorder: traceRecorder
        )
        await coordinator.install(
            request: try producerTaskMetadataStreamRequest(),
            lease: lease,
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
        await coordinator.apply(effect)
        await source.waitUntilOpenStarted(openOrdinal: 1)

        // Act
        await coordinator.apply(.subscriptionCancelled(try producerTaskFileSubscriptionSnapshot()))
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
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let source = CoordinatorReplacementBootstrapFileMetadataSource()
        let traceRecorder = CoordinatorProducerTaskTraceRecorder()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: source,
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            lifecycleTraceRecorder: traceRecorder
        )
        await coordinator.install(
            request: try producerTaskMetadataStreamRequest(),
            lease: lease,
            session: harness.session
        )
        let subscription = try producerTaskFileSubscriptionSnapshot()
        await coordinator.apply(.subscriptionOpened(subscription))
        await source.waitUntilOpenStarted(openOrdinal: 1)
        await coordinator.apply(.subscriptionOpened(subscription))
        await source.waitUntilOpenStarted(openOrdinal: 2)

        // Act
        await source.releaseOpen(openOrdinal: 1)
        await source.waitUntilOpenFinished(openOrdinal: 1)
        await traceRecorder.waitUntilBootstrapFinished()
        await coordinator.apply(.subscriptionCancelled(subscription))
        await source.waitUntilOpenFinished(openOrdinal: 2)

        // Assert
        #expect(await source.openObservedCancellation(openOrdinal: 2))
        await coordinator.uninstall(lease: lease)
    }

    @Test("Review bootstrap failures retain their typed source and producer causes")
    func reviewBootstrapFailuresRetainTypedCauses() async throws {
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
                lifecycleTraceRecorder: traceRecorder
            )
            await coordinator.install(
                request: try producerTaskMetadataStreamRequest(),
                lease: lease,
                session: harness.session
            )

            await coordinator.apply(.subscriptionOpened(try producerTaskReviewSubscriptionSnapshot()))
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
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {}

    func publish(
        availability _: BridgePaneProductReviewMetadataAvailability
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        .loading(retained: 0)
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
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {}

    func cancel(subscriptionId _: String) {
        let releases = openReleaseByOrdinal.values
        openReleaseByOrdinal.removeAll(keepingCapacity: false)
        for release in releases { release.resume() }
    }

    func publish(status _: GitWorkingTreeStatus) -> [BridgePaneProductFileMetadataEmission] { [] }

    func publish(changeset _: FileChangeset) async throws -> [BridgePaneProductFileMetadataEmission] { [] }

    func contentBody(for _: BridgeProductFileContentRequest) -> BridgePaneProductFileContentBody? { nil }

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
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        didAttemptOpen = true
        throw CancellationError()
    }

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {}

    func cancel(subscriptionId _: String) {}

    func publish(status _: GitWorkingTreeStatus) -> [BridgePaneProductFileMetadataEmission] { [] }

    func publish(changeset _: FileChangeset) async throws -> [BridgePaneProductFileMetadataEmission] { [] }

    func contentBody(for _: BridgeProductFileContentRequest) -> BridgePaneProductFileContentBody? { nil }
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
