import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product Review metadata availability lifecycle")
struct BridgeProductReviewAvailabilityTests {
    @Test("Review open before package publication stays accepted and emits initial metadata later")
    func reviewOpenBeforePackagePublicationStaysAccepted() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let reviewSource = BridgePaneProductReviewMetadataSource(initialAvailability: .loading)
        let traceRecorder = AvailabilityReviewPublicationTraceRecorder()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: reviewSource,
            lifecycleTraceRecorder: traceRecorder
        )
        await coordinator.install(
            request: try availabilityMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )

        // Act
        let acceptedFrame = try await openAvailabilityReviewSubscription(
            coordinator: coordinator,
            harness: harness,
            pump: pump
        )
        for _ in 0..<100 where (await harness.session.producerSnapshot()).queuedFrameCount == 0 {
            await Task.yield()
        }
        let queuedFrameCountBeforePublication =
            (await harness.session.producerSnapshot()).queuedFrameCount
        let reviewPackage = try availabilityReviewPackageFixture()
        let traceContext = try BridgeTraceContext(
            traceId: "55555555555555555555555555555555",
            spanId: "6666666666666666",
            parentSpanId: nil,
            sampled: true
        )
        await coordinator.publish(
            availability: .ready(reviewPackage),
            productAdmission: harness.productAdmission.context,
            traceContext: traceContext
        )
        let sourceAcceptedFrame = try await pullAvailabilityMetadataFrame(from: pump)
        let snapshotFrame = try await pullAvailabilityMetadataFrame(from: pump)

        // Assert
        guard case .subscriptionAccepted(let accepted) = acceptedFrame,
            case .subscriptionData(let sourceAcceptedData) = sourceAcceptedFrame,
            case .reviewMetadata(.sourceAccepted(let sourceAccepted)) = sourceAcceptedData.data,
            case .subscriptionData(let snapshotData) = snapshotFrame,
            case .reviewMetadata(.snapshot(let snapshot)) = snapshotData.data
        else {
            Issue.record("Expected Review accepted followed by sourceAccepted and snapshot after publication")
            return
        }
        #expect(accepted.frameIdentity.streamSequence == 1)
        #expect(queuedFrameCountBeforePublication == 0)
        #expect(sourceAcceptedData.frameIdentity.streamSequence == 2)
        #expect(snapshotData.frameIdentity.streamSequence == 3)
        #expect(sourceAccepted.identity.packageId == reviewPackage.packageId)
        #expect(snapshot.identity.packageId == reviewPackage.packageId)
        #expect(
            await traceRecorder.publicationEvents == [
                .started(retainedSubscriptions: 1, traceContext: traceContext),
                .completed(
                    receipt: BridgeReviewMetadataPublicationReceipt(
                        retained: 1,
                        publishedSubscriptions: 1,
                        emittedEvents: 2,
                        superseded: 0
                    ),
                    traceContext: traceContext
                ),
            ]
        )
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }

    @Test("producer rejection preserves its failure before successful subscription reset recovery")
    func producerRejectionPreservesFailureBeforeResetRecovery() async throws {
        let traceContext = try BridgeTraceContext(
            traceId: "77777777777777777777777777777777",
            spanId: "8888888888888888",
            parentSpanId: nil,
            sampled: true
        )

        let result = try await exerciseAvailabilityPublicationFailure(
            .producerRejection,
            traceContext: traceContext
        )

        guard case .subscriptionReset(let reset) = result.recoveryFrame else {
            Issue.record("Expected producer rejection recovery to enqueue a subscription reset")
            return
        }
        #expect(reset.reason == .staleSource)
        #expect(
            result.traceEvents == [
                .started(retainedSubscriptions: 1, traceContext: traceContext),
                .failed(
                    failure: .producerRejection,
                    retainedSubscriptions: 1,
                    traceContext: traceContext
                ),
            ]
        )
    }

    @Test("Review event construction failure remains distinct through reset recovery")
    func eventConstructionFailureRemainsDistinctThroughResetRecovery() async throws {
        let traceContext = try BridgeTraceContext(
            traceId: "99999999999999999999999999999999",
            spanId: "aaaaaaaaaaaaaaaa",
            parentSpanId: nil,
            sampled: true
        )

        let result = try await exerciseAvailabilityPublicationFailure(
            .eventConstruction,
            traceContext: traceContext
        )

        guard case .subscriptionReset(let reset) = result.recoveryFrame else {
            Issue.record("Expected event construction recovery to enqueue a subscription reset")
            return
        }
        #expect(reset.reason == .staleSource)
        #expect(
            result.traceEvents == [
                .started(retainedSubscriptions: 1, traceContext: traceContext),
                .failed(
                    failure: .eventConstruction,
                    retainedSubscriptions: 1,
                    traceContext: traceContext
                ),
            ]
        )
    }

    @Test("terminal failed Review availability resets an accepted subscription")
    func terminalFailedReviewAvailabilityResetsAcceptedSubscription() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgePaneProductReviewMetadataSource(initialAvailability: .loading)
        )
        await coordinator.install(
            request: try availabilityMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        let acceptedFrame = try await openAvailabilityReviewSubscription(
            coordinator: coordinator,
            harness: harness,
            pump: pump
        )

        // Act
        await coordinator.publish(
            availability: .failed,
            productAdmission: harness.productAdmission.context
        )
        let terminalFrame = try await pullAvailabilityMetadataFrame(from: pump)

        // Assert
        guard case .subscriptionAccepted = acceptedFrame,
            case .subscriptionReset(let reset) = terminalFrame
        else {
            Issue.record("Expected failed Review availability to terminate the accepted subscription")
            return
        }
        #expect(reset.reason == .staleSource)
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }

    @Test("failing Review publication cannot reset a replacement metadata stream")
    func failingReviewPublicationCannotResetReplacementMetadataStream() async throws {
        // Arrange
        let firstHarness = try await BridgeProductSessionLifecycleHarness.opened()
        let firstLease = try await firstHarness.admitMetadataFrames(through: 0)
        let firstPump = BridgeProductSchemeFramePump(
            session: firstHarness.session,
            producerLease: firstLease,
            productAdmission: firstHarness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let source = AvailabilitySuspendedFailingReviewMetadataSource()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: source
        )
        await coordinator.install(
            request: try availabilityMetadataStreamRequest(),
            lease: firstLease,
            productAdmission: firstHarness.productAdmission.context,
            session: firstHarness.session
        )
        _ = try await openAvailabilityReviewSubscription(
            coordinator: coordinator,
            harness: firstHarness,
            pump: firstPump
        )
        let reviewPackage = try availabilityReviewPackageFixture()
        let failingPublication = Task {
            await coordinator.publish(
                availability: .ready(reviewPackage),
                productAdmission: firstHarness.productAdmission.context
            )
        }
        await source.waitUntilPublishStarted()

        let replacementHarness = try await BridgeProductSessionLifecycleHarness.opened()
        let replacementLease = try await replacementHarness.admitMetadataFrames(through: 0)
        let replacementPump = BridgeProductSchemeFramePump(
            session: replacementHarness.session,
            producerLease: replacementLease,
            productAdmission: replacementHarness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        await coordinator.install(
            request: try availabilityMetadataStreamRequest(),
            lease: replacementLease,
            productAdmission: replacementHarness.productAdmission.context,
            session: replacementHarness.session
        )
        let replacementAcceptedFrame = try await openAvailabilityReviewSubscription(
            coordinator: coordinator,
            harness: replacementHarness,
            pump: replacementPump
        )

        // Act
        await source.releasePublishFailure()
        await failingPublication.value

        // Assert
        guard case .subscriptionAccepted = replacementAcceptedFrame else {
            Issue.record("Expected the replacement Review subscription to be accepted")
            return
        }
        #expect((await replacementHarness.session.producerSnapshot()).queuedFrameCount == 0)
        await coordinator.uninstall(lease: replacementLease)
        #expect(await firstPump.cancel())
        #expect(await replacementPump.cancel())
    }
}

private enum AvailabilityCoordinatorTestError: Error {
    case expectedFrame
    case publicationFailed
}

private enum AvailabilityReviewPublicationFailureMode: Sendable {
    case eventConstruction
    case producerRejection
}

private struct AvailabilityReviewPublicationFailureResult {
    let recoveryFrame: BridgeProductMetadataFrame
    let traceEvents: [BridgeProductReviewMetadataPublicationTraceEvent]
}

private actor AvailabilityReviewPublicationTraceRecorder:
    BridgeProductMetadataLifecycleTraceRecording
{
    private(set) var publicationEvents: [BridgeProductReviewMetadataPublicationTraceEvent] = []

    func record(_: BridgeProductMetadataLifecycleTraceEvent) {}

    func record(_ event: BridgeProductReviewMetadataPublicationTraceEvent) {
        publicationEvents.append(event)
    }
}

private actor AvailabilityThrowingReviewMetadataSource:
    BridgePaneProductReviewMetadataProducing
{
    private let failureMode: AvailabilityReviewPublicationFailureMode

    init(failureMode: AvailabilityReviewPublicationFailureMode) {
        self.failureMode = failureMode
    }

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {}

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {}

    func publish(
        availability _: BridgePaneProductReviewMetadataAvailability,
        productAdmission _: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        switch failureMode {
        case .eventConstruction:
            throw BridgePaneProductReviewMetadataSourceError.metadataEventExceedsByteLimit
        case .producerRejection:
            throw BridgePaneProductMetadataCoordinatorError.producerRejected(.unknownLease)
        }
    }

    func cancel(subscriptionId _: String) {}
}

private actor AvailabilitySuspendedFailingReviewMetadataSource:
    BridgePaneProductReviewMetadataProducing
{
    private var publishStarted = false
    private var publishStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var publishRelease: CheckedContinuation<Void, Never>?

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {}

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {}

    func publish(
        availability _: BridgePaneProductReviewMetadataAvailability,
        productAdmission _: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        publishStarted = true
        let waiters = publishStartedWaiters
        publishStartedWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            publishRelease = continuation
        }
        throw AvailabilityCoordinatorTestError.publicationFailed
    }

    func cancel(subscriptionId _: String) {}

    func waitUntilPublishStarted() async {
        if publishStarted { return }
        await withCheckedContinuation { continuation in
            publishStartedWaiters.append(continuation)
        }
    }

    func releasePublishFailure() {
        publishRelease?.resume()
        publishRelease = nil
    }
}

private func openAvailabilityReviewSubscription(
    coordinator: BridgePaneProductMetadataCoordinator,
    harness: BridgeProductSessionLifecycleHarness,
    pump: BridgeProductSchemeFramePump
) async throws -> BridgeProductMetadataFrame {
    let openRequest = try bridgeProductLifecycleControlRequest(
        bridgeProductLifecycleReviewSubscriptionOpenObject(requestSequence: 2, epoch: 1)
    )
    let token = try #require(availabilityControlExecutionToken(try await harness.begin(openRequest)))
    #expect(await harness.session.claimControlProviderDispatch(token: token))
    let response = try BridgeProductControlResponse.subscriptionOpenAccepted(
        correlating: openRequest,
        interestSha256: BridgeProductSubscriptionInterestState.reviewMetadata(interests: []).sha256Hex()
    )
    let effect = try await harness.session.completeControl(
        token: token,
        exactResponseBytes: try JSONEncoder().encode(response)
    )
    let acceptedFrame = try await pullAvailabilityMetadataFrame(from: pump)
    await coordinator.apply(
        effect,
        productAdmission: harness.productAdmission.context
    )
    await harness.session.settleControlProviderDispatch(token: token)
    return acceptedFrame
}

private func pullAvailabilityMetadataFrame(
    from pump: BridgeProductSchemeFramePump
) async throws -> BridgeProductMetadataFrame {
    guard case .frame(let delivery) = await pump.nextFrame() else {
        throw AvailabilityCoordinatorTestError.expectedFrame
    }
    #expect(await pump.acknowledgeFrameConsumed(delivery.receipt))
    let decoder = try BridgeProductMetadataFrameDecoder()
    let frames = try decoder.append(delivery.frame.data)
    return try #require(frames.first)
}

private func exerciseAvailabilityPublicationFailure(
    _ failureMode: AvailabilityReviewPublicationFailureMode,
    traceContext: BridgeTraceContext
) async throws -> AvailabilityReviewPublicationFailureResult {
    let harness = try await BridgeProductSessionLifecycleHarness.opened()
    let lease = try await harness.admitMetadataFrames(through: 0)
    let pump = BridgeProductSchemeFramePump(
        session: harness.session,
        producerLease: lease,
        productAdmission: harness.productAdmission.context,
        acknowledgeLifecycle: { _ in true }
    )
    let traceRecorder = AvailabilityReviewPublicationTraceRecorder()
    let coordinator = BridgePaneProductMetadataCoordinator(
        fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
        reviewMetadataSource: AvailabilityThrowingReviewMetadataSource(failureMode: failureMode),
        lifecycleTraceRecorder: traceRecorder
    )
    await coordinator.install(
        request: try availabilityMetadataStreamRequest(),
        lease: lease,
        productAdmission: harness.productAdmission.context,
        session: harness.session
    )
    _ = try await openAvailabilityReviewSubscription(
        coordinator: coordinator,
        harness: harness,
        pump: pump
    )

    await coordinator.publish(
        availability: .ready(try availabilityReviewPackageFixture()),
        productAdmission: harness.productAdmission.context,
        traceContext: traceContext
    )
    let recoveryFrame = try await pullAvailabilityMetadataFrame(from: pump)
    let traceEvents = await traceRecorder.publicationEvents
    await coordinator.uninstall(lease: lease)
    #expect(await pump.cancel())
    return AvailabilityReviewPublicationFailureResult(
        recoveryFrame: recoveryFrame,
        traceEvents: traceEvents
    )
}

private func availabilityControlExecutionToken(
    _ admission: BridgeProductSessionControlAdmission
) -> BridgeProductControlAdmissionToken? {
    guard case .execute(let token, _) = admission else { return nil }
    return token
}

private func availabilityReviewPackageFixture() throws -> BridgeReviewPackage {
    let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
    let fixtureURL = projectRoot.appending(
        path: "Tests/BridgeContractFixtures/valid/bridge-review-package.json"
    )
    return try JSONDecoder().decode(
        BridgeReviewPackage.self,
        from: Data(contentsOf: fixtureURL)
    )
}

private func availabilityMetadataStreamRequest() throws -> BridgeProductMetadataStreamRequest {
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
