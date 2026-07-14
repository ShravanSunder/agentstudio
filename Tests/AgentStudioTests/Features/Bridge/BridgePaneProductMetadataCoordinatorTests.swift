import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product session protocol lifecycle admission")
struct BridgePaneProductMetadataCoordinatorTests {
    @Test("committed File interest waits for source bootstrap without cancelling it")
    func committedFileInterestWaitsForSourceBootstrap() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let source = CoordinatorGatedFileMetadataSource()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: source,
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource()
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            session: harness.session
        )
        let lifecycle = try coordinatorFileSubscriptionLifecycle()
        await coordinator.apply(.subscriptionOpened(lifecycle.opened))
        await source.waitUntilOpenStarted()

        // Act
        await coordinator.apply(
            .subscriptionInterestsCommitted(
                barrier: lifecycle.commitBarrier,
                subscription: lifecycle.updated
            )
        )
        await source.releaseOpen()
        await source.waitUntilOpenFinished()
        await source.waitUntilUpdateStarted()

        // Assert
        #expect(!(await source.openObservedCancellation))
        #expect(await source.updateObservedOpenFinished)
        await coordinator.uninstall(lease: lease)
    }

    @Test("unavailable File source resets the accepted subscription and retires delivery")
    func unavailableFileSourceResetsAcceptedSubscription() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            acknowledgeLifecycle: { _ in true }
        )
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource()
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            session: harness.session
        )
        let openRequest = try bridgeProductLifecycleControlRequest(
            bridgeProductLifecycleFileSubscriptionOpenObject(requestSequence: 2, epoch: 1)
        )

        // Act
        let token = try #require(controlExecutionToken(try await harness.begin(openRequest)))
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
        let acceptedFrame = try await pullMetadataFrame(from: pump)
        await coordinator.apply(effect)
        for _ in 0..<1000
        where (await harness.session.producerSnapshot()).queuedFrameCount == 0 {
            await Task.yield()
        }
        guard (await harness.session.producerSnapshot()).queuedFrameCount > 0 else {
            Issue.record("Expected unavailable source to enqueue a subscription reset")
            return
        }
        let resetFrame = try await pullMetadataFrame(from: pump)
        let dataResult = try await harness.session.enqueueSubscriptionData(
            subscriptionId: "file-subscription-1",
            data: .fileMetadata(try coordinatorSourceAcceptedEvent())
        )

        // Assert
        guard case .subscriptionAccepted(let accepted) = acceptedFrame,
            case .subscriptionReset(let reset) = resetFrame
        else {
            Issue.record("Expected accepted followed by subscription reset")
            return
        }
        #expect(accepted.frameIdentity.streamSequence == 1)
        #expect(reset.identity.frameIdentity.streamSequence == 2)
        #expect(reset.identity.subscriptionIdentity.subscriptionSequence == 1)
        #expect(reset.reason == .staleSource)
        #expect(dataResult == .rejected(.unknownLease))
        await harness.session.settleControlProviderDispatch(token: token)
        #expect(await pump.cancel())
    }

    @Test("committed File open publishes data after the accepted lifecycle frame")
    func committedFileOpenPublishesDataAfterAcceptedLifecycle() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            acknowledgeLifecycle: { _ in true }
        )
        let source = CoordinatorFileMetadataSource()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: source,
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource()
        )
        let metadataRequest = try coordinatorMetadataStreamRequest()
        await coordinator.install(
            request: metadataRequest,
            lease: lease,
            session: harness.session
        )
        let openRequest = try bridgeProductLifecycleControlRequest(
            bridgeProductLifecycleFileSubscriptionOpenObject(requestSequence: 2, epoch: 1)
        )

        // Act
        let token = try #require(controlExecutionToken(try await harness.begin(openRequest)))
        #expect(await harness.session.claimControlProviderDispatch(token: token))
        let response = try BridgeProductControlResponse.subscriptionOpenAccepted(
            correlating: openRequest,
            interestSha256:
                BridgeProductSubscriptionInterestState
                .fileMetadata(interests: [], pathScope: [])
                .sha256Hex()
        )
        let effect = try await harness.session.completeControl(
            token: token,
            exactResponseBytes: try JSONEncoder().encode(response)
        )
        let acceptedFrame = try await pullMetadataFrame(from: pump)
        await coordinator.apply(effect)
        let dataFrame = try await pullMetadataFrame(from: pump)
        await harness.session.settleControlProviderDispatch(token: token)

        // Assert
        guard case .subscriptionAccepted(let accepted) = acceptedFrame,
            case .subscriptionData(let data) = dataFrame,
            case .fileMetadata(.sourceAccepted(let sourceAccepted)) = data.data
        else {
            Issue.record("Expected File accepted followed by source-accepted data")
            return
        }
        #expect(accepted.frameIdentity.streamSequence == 1)
        #expect(accepted.subscriptionIdentity.subscriptionSequence == 0)
        #expect(data.frameIdentity.streamSequence == 2)
        #expect(data.subscriptionIdentity.subscriptionSequence == 1)
        #expect(data.subscriptionIdentity.interestRevision == 0)
        #expect(sourceAccepted.source.sourceId == "file-source-1")
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }

    @Test("committed Review open publishes source data after the accepted lifecycle frame")
    func committedReviewOpenPublishesDataAfterAcceptedLifecycle() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            acknowledgeLifecycle: { _ in true }
        )
        let reviewPackage = try coordinatorReviewPackageFixture()
        let reviewSource = BridgePaneProductReviewMetadataSource(initialAvailability: .ready(reviewPackage))
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: reviewSource
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            session: harness.session
        )
        let openRequest = try bridgeProductLifecycleControlRequest(
            bridgeProductLifecycleReviewSubscriptionOpenObject(requestSequence: 2, epoch: 1)
        )

        // Act
        let token = try #require(controlExecutionToken(try await harness.begin(openRequest)))
        #expect(await harness.session.claimControlProviderDispatch(token: token))
        let response = try BridgeProductControlResponse.subscriptionOpenAccepted(
            correlating: openRequest,
            interestSha256: BridgeProductSubscriptionInterestState.reviewMetadata(interests: []).sha256Hex()
        )
        let effect = try await harness.session.completeControl(
            token: token,
            exactResponseBytes: try JSONEncoder().encode(response)
        )
        let acceptedFrame = try await pullMetadataFrame(from: pump)
        await coordinator.apply(effect)
        let dataFrame = try await pullMetadataFrame(from: pump)
        await harness.session.settleControlProviderDispatch(token: token)

        // Assert
        guard case .subscriptionAccepted(let accepted) = acceptedFrame,
            case .subscriptionData(let data) = dataFrame,
            case .reviewMetadata(let event) = data.data
        else {
            Issue.record("Expected Review accepted followed by source-accepted data")
            return
        }
        #expect(accepted.frameIdentity.streamSequence == 1)
        #expect(data.frameIdentity.streamSequence == 2)
        #expect(data.subscriptionIdentity.subscriptionSequence == 1)
        #expect(event.generation == 42)
        #expect(event.packageId == "package-42")
        #expect(event.revision == 1)
        #expect(event.sourceIdentity == "query-42")
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }

    @Test("committed Review interest update republishes current source after its lifecycle barrier")
    func committedReviewInterestUpdateRepublishesCurrentSource() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            acknowledgeLifecycle: { _ in true }
        )
        let reviewSource = CoordinatorReviewMetadataSource(event: try coordinatorReviewSourceAcceptedEvent())
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: reviewSource
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            session: harness.session
        )
        let openRequest = try bridgeProductLifecycleControlRequest(
            bridgeProductLifecycleReviewSubscriptionOpenObject(requestSequence: 2, epoch: 1)
        )
        let openToken = try #require(controlExecutionToken(try await harness.begin(openRequest)))
        #expect(await harness.session.claimControlProviderDispatch(token: openToken))
        let emptyInterestSha256 =
            try BridgeProductSubscriptionInterestState
            .reviewMetadata(interests: []).sha256Hex()
        let openResponse = try BridgeProductControlResponse.subscriptionOpenAccepted(
            correlating: openRequest,
            interestSha256: emptyInterestSha256
        )
        let openEffect = try await harness.session.completeControl(
            token: openToken,
            exactResponseBytes: try JSONEncoder().encode(openResponse)
        )
        _ = try await pullMetadataFrame(from: pump)
        await coordinator.apply(openEffect)
        _ = try await pullMetadataFrame(from: pump)
        await harness.session.settleControlProviderDispatch(token: openToken)
        let updateRequest = try coordinatorReviewUpdateRequest(
            emptyInterestSha256: emptyInterestSha256,
            updateId: "review-update-provider-1"
        )

        // Act
        let updateToken = try #require(controlExecutionToken(try await harness.begin(updateRequest)))
        #expect(await harness.session.claimControlProviderDispatch(token: updateToken))
        let updateResponse = try BridgeProductControlResponse.subscriptionUpdateBatchAccepted(
            correlating: updateRequest,
            disposition: .committed
        )
        let updateEffect = try await harness.session.completeControl(
            token: updateToken,
            exactResponseBytes: try JSONEncoder().encode(updateResponse)
        )
        let committedFrame = try await pullMetadataFrame(from: pump)
        await coordinator.apply(updateEffect)
        let dataFrame = try await pullMetadataFrame(from: pump)
        await harness.session.settleControlProviderDispatch(token: updateToken)

        // Assert
        guard case .subscriptionInterestsCommitted(let committed) = committedFrame,
            case .subscriptionData(let data) = dataFrame,
            case .reviewMetadata(let event) = data.data
        else {
            Issue.record("Expected Review interest barrier followed by refreshed source data")
            return
        }
        #expect(committed.identity.frameIdentity.streamSequence == 3)
        #expect(data.frameIdentity.streamSequence == 4)
        #expect(data.subscriptionIdentity.interestRevision == 1)
        #expect(event.packageId == "review-package-1")
        #expect(await reviewSource.updatedItemIds == ["review-item-1", "review-item-2"])
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }

    @Test("Review cancel retires its producer without disturbing the metadata stream")
    func reviewCancelRetiresProducerWithoutDisturbingStream() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            acknowledgeLifecycle: { _ in true }
        )
        let fileSource = CoordinatorFileMetadataSource()
        let reviewSource = CoordinatorReviewMetadataSource(event: try coordinatorReviewSourceAcceptedEvent())
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: fileSource,
            reviewMetadataSource: reviewSource
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            session: harness.session
        )
        let openRequest = try bridgeProductLifecycleControlRequest(
            bridgeProductLifecycleReviewSubscriptionOpenObject(requestSequence: 2, epoch: 1)
        )
        let openToken = try #require(controlExecutionToken(try await harness.begin(openRequest)))
        #expect(await harness.session.claimControlProviderDispatch(token: openToken))
        let openResponse = try BridgeProductControlResponse.subscriptionOpenAccepted(
            correlating: openRequest,
            interestSha256: BridgeProductSubscriptionInterestState.reviewMetadata(interests: []).sha256Hex()
        )
        let openEffect = try await harness.session.completeControl(
            token: openToken,
            exactResponseBytes: try JSONEncoder().encode(openResponse)
        )
        _ = try await pullMetadataFrame(from: pump)
        await coordinator.apply(openEffect)
        _ = try await pullMetadataFrame(from: pump)
        await harness.session.settleControlProviderDispatch(token: openToken)
        let cancelRequest = try bridgeProductLifecycleControlRequest(
            bridgeProductLifecycleSubscriptionCancelObject(requestSequence: 3, epoch: 1)
        )

        // Act
        let cancelToken = try #require(controlExecutionToken(try await harness.begin(cancelRequest)))
        #expect(await harness.session.claimControlProviderDispatch(token: cancelToken))
        let cancelResponse = try BridgeProductControlResponse.subscriptionCancelAccepted(
            correlating: cancelRequest
        )
        let cancelEffect = try await harness.session.completeControl(
            token: cancelToken,
            exactResponseBytes: try JSONEncoder().encode(cancelResponse)
        )
        let cancelledFrame = try await pullMetadataFrame(from: pump)
        await coordinator.apply(cancelEffect)
        await harness.session.settleControlProviderDispatch(token: cancelToken)

        // Assert
        guard case .subscriptionCancelled(let cancelled) = cancelledFrame else {
            Issue.record("Expected Review subscription-cancelled lifecycle")
            return
        }
        #expect(cancelled.identity.frameIdentity.streamSequence == 3)
        #expect(await reviewSource.cancelledSubscriptionIds == ["review-subscription-1"])
        #expect(await fileSource.cancelledSubscriptionIds.isEmpty)
        #expect((await harness.session.producerSnapshot()).queuedFrameCount == 0)
        await coordinator.uninstall(lease: lease)
        #expect(await reviewSource.cancelledSubscriptionIds == ["review-subscription-1"])
        #expect(await fileSource.cancelledSubscriptionIds.isEmpty)
        #expect(await pump.cancel())
    }

    @Test("File and Review subscriptions multiplex data on one contiguous metadata stream")
    func fileAndReviewSubscriptionsMultiplexOneContiguousStream() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            acknowledgeLifecycle: { _ in true }
        )
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: CoordinatorFileMetadataSource(),
            reviewMetadataSource: CoordinatorReviewMetadataSource(
                event: try coordinatorReviewSourceAcceptedEvent()
            )
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            session: harness.session
        )

        // Act
        var observedFrames: [BridgeProductMetadataFrame] = []
        for (request, expectedInterestState) in [
            (
                try bridgeProductLifecycleControlRequest(
                    bridgeProductLifecycleFileSubscriptionOpenObject(requestSequence: 2, epoch: 1)
                ),
                BridgeProductSubscriptionInterestState.fileMetadata(interests: [], pathScope: [])
            ),
            (
                try bridgeProductLifecycleControlRequest(
                    bridgeProductLifecycleReviewSubscriptionOpenObject(requestSequence: 3, epoch: 1)
                ),
                BridgeProductSubscriptionInterestState.reviewMetadata(interests: [])
            ),
        ] {
            let token = try #require(controlExecutionToken(try await harness.begin(request)))
            #expect(await harness.session.claimControlProviderDispatch(token: token))
            let response = try BridgeProductControlResponse.subscriptionOpenAccepted(
                correlating: request,
                interestSha256: expectedInterestState.sha256Hex()
            )
            let effect = try await harness.session.completeControl(
                token: token,
                exactResponseBytes: try JSONEncoder().encode(response)
            )
            observedFrames.append(try await pullMetadataFrame(from: pump))
            await coordinator.apply(effect)
            observedFrames.append(try await pullMetadataFrame(from: pump))
            await harness.session.settleControlProviderDispatch(token: token)
        }

        // Assert
        #expect(observedFrames.map(\.streamSequenceForTest) == [1, 2, 3, 4])
        guard case .subscriptionData(let fileData) = observedFrames[1],
            case .fileMetadata = fileData.data,
            case .subscriptionData(let reviewData) = observedFrames[3],
            case .reviewMetadata = reviewData.data
        else {
            Issue.record("Expected File and Review subscription data on the shared stream")
            return
        }
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }

    @Test("control commit admits one ordered subscription lifecycle before replay")
    func committedSubscriptionLifecycleEmitsOrderedFrames() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            acknowledgeLifecycle: { _ in true }
        )
        let emptyInterestSha256 =
            try BridgeProductSubscriptionInterestState
            .reviewMetadata(interests: []).sha256Hex()
        let openRequest = try bridgeProductLifecycleControlRequest(
            bridgeProductLifecycleReviewSubscriptionOpenObject(requestSequence: 2, epoch: 1)
        )

        // Act
        let openToken = try #require(controlExecutionToken(try await harness.begin(openRequest)))
        #expect(await harness.session.claimControlProviderDispatch(token: openToken))
        let openResponse = try BridgeProductControlResponse.subscriptionOpenAccepted(
            correlating: openRequest,
            interestSha256: emptyInterestSha256
        )
        _ = try await harness.session.completeControl(
            token: openToken,
            exactResponseBytes: try JSONEncoder().encode(openResponse)
        )
        let acceptedFrame = try await pullMetadataFrame(from: pump)
        await harness.session.settleControlProviderDispatch(token: openToken)

        let updateId = "review-update-coordinator-1"
        let updateRequest = try coordinatorReviewUpdateRequest(
            emptyInterestSha256: emptyInterestSha256,
            updateId: updateId
        )
        let updateToken = try #require(
            controlExecutionToken(try await harness.begin(updateRequest))
        )
        #expect(await harness.session.claimControlProviderDispatch(token: updateToken))
        let updateResponse = try BridgeProductControlResponse.subscriptionUpdateBatchAccepted(
            correlating: updateRequest,
            disposition: .committed
        )
        _ = try await harness.session.completeControl(
            token: updateToken,
            exactResponseBytes: try JSONEncoder().encode(updateResponse)
        )
        let committedFrame = try await pullMetadataFrame(from: pump)
        await harness.session.settleControlProviderDispatch(token: updateToken)

        let cancelRequest = try bridgeProductLifecycleControlRequest(
            bridgeProductLifecycleSubscriptionCancelObject(requestSequence: 4, epoch: 1)
        )
        let cancelToken = try #require(
            controlExecutionToken(try await harness.begin(cancelRequest))
        )
        #expect(await harness.session.claimControlProviderDispatch(token: cancelToken))
        let cancelResponse = try BridgeProductControlResponse.subscriptionCancelAccepted(
            correlating: cancelRequest
        )
        _ = try await harness.session.completeControl(
            token: cancelToken,
            exactResponseBytes: try JSONEncoder().encode(cancelResponse)
        )
        let cancelledFrame = try await pullMetadataFrame(from: pump)
        await harness.session.settleControlProviderDispatch(token: cancelToken)

        // Assert
        guard case .subscriptionAccepted(let accepted) = acceptedFrame,
            case .subscriptionInterestsCommitted(let committed) = committedFrame,
            case .subscriptionCancelled(let cancelled) = cancelledFrame
        else {
            Issue.record("Expected accepted, interests-committed, and cancelled frames")
            return
        }
        #expect(accepted.frameIdentity.streamSequence == 1)
        #expect(accepted.subscriptionIdentity.subscriptionSequence == 0)
        #expect(committed.identity.frameIdentity.streamSequence == 2)
        #expect(committed.identity.subscriptionIdentity.subscriptionSequence == 1)
        #expect(committed.updateId == updateId)
        #expect(cancelled.identity.frameIdentity.streamSequence == 3)
        #expect(cancelled.identity.subscriptionIdentity.subscriptionSequence == 2)
        #expect((await harness.session.snapshot).controlReplay.replayableRequestSequence == 4)
        #expect(await pump.cancel())
    }
}

private func coordinatorReviewUpdateRequest(
    emptyInterestSha256: String,
    updateId: String
) throws -> BridgeProductControlRequest {
    try bridgeProductLifecycleControlRequest(
        [
            "baseInterestRevision": 0,
            "baseInterestSha256": emptyInterestSha256,
            "batchCount": 1,
            "batchIndex": 0,
            "delta": [
                "add": [
                    ["itemId": "review-item-1", "lane": "foreground"],
                    ["itemId": "review-item-2", "lane": "visible"],
                ],
                "removeItemIds": [],
                "subscriptionKind": "review.metadata",
            ],
            "kind": "subscription.updateBatch",
            "paneSessionId": "pane-session-1",
            "requestId": "request-review-update-3",
            "requestSequence": 3,
            "subscriptionId": "review-subscription-1",
            "subscriptionKind": "review.metadata",
            "targetInterestRevision": 1,
            "targetInterestSha256":
                "2535176c2a822c1f5007dd72a7987b7c0a1b6e9af1bc28324ec4618b43f71ebd",
            "totalDeltaItemCount": 2,
            "updateId": updateId,
            "wireVersion": BridgeProductWireContract.version,
            "workerDerivationEpoch": 1,
            "workerInstanceId": "worker-instance-1",
        ]
    )
}

private func pullMetadataFrame(
    from pump: BridgeProductSchemeFramePump
) async throws -> BridgeProductMetadataFrame {
    guard case .frame(let delivery) = await pump.nextFrame() else {
        throw BridgePaneProductMetadataCoordinatorTestError.expectedFrame
    }
    #expect(await pump.acknowledgeFrameConsumed(delivery.receipt))
    let decoder = try BridgeProductMetadataFrameDecoder()
    let frames = try decoder.append(delivery.frame.data)
    return try #require(frames.first)
}

private func controlExecutionToken(
    _ admission: BridgeProductSessionControlAdmission
) -> BridgeProductControlAdmissionToken? {
    guard case .execute(let token, _) = admission else { return nil }
    return token
}

private enum BridgePaneProductMetadataCoordinatorTestError: Error {
    case expectedFrame
    case invalidFileSubscriptionLifecycle
}

private func coordinatorFileSubscriptionLifecycle() throws -> (
    opened: BridgeProductSubscriptionSnapshot,
    updated: BridgeProductSubscriptionSnapshot,
    commitBarrier: BridgeProductSubscriptionCommitBarrierIntent
) {
    let controlRequest = try bridgeProductLifecycleControlRequest(
        bridgeProductLifecycleFileSubscriptionOpenObject(requestSequence: 2, epoch: 1)
    )
    guard case .subscriptionOpen(let openRequest) = controlRequest else {
        throw BridgePaneProductMetadataCoordinatorTestError.invalidFileSubscriptionLifecycle
    }
    var state = BridgeProductSubscriptionState()
    _ = try state.open(openRequest)
    guard let opened = state.snapshot(subscriptionId: openRequest.subscriptionId) else {
        throw BridgePaneProductMetadataCoordinatorTestError.invalidFileSubscriptionLifecycle
    }
    let interestState = BridgeProductSubscriptionInterestState.fileMetadata(
        interests: [try .init(lane: .foreground, paths: ["Sources/App.swift"])],
        pathScope: []
    )
    let interestSha256 = try interestState.sha256Hex()
    let updated = BridgeProductSubscriptionSnapshot(
        subscription: opened.subscription,
        subscriptionId: opened.subscriptionId,
        subscriptionKind: opened.subscriptionKind,
        workerDerivationEpoch: opened.workerDerivationEpoch,
        interestRevision: 1,
        interestSha256: interestSha256,
        interestState: interestState,
        hasStagedUpdate: false
    )
    return (
        opened: opened,
        updated: updated,
        commitBarrier: .init(
            subscriptionId: opened.subscriptionId,
            subscriptionKind: opened.subscriptionKind,
            workerDerivationEpoch: opened.workerDerivationEpoch,
            interestRevision: 1,
            interestSha256: interestSha256,
            updateId: "file-update-1"
        )
    )
}

private enum CoordinatorReviewMetadataSourceError: Error {
    case unavailable
    case unknownSubscription
}

private actor CoordinatorReviewMetadataSource: BridgePaneProductReviewMetadataProducing {
    private let event: BridgeProductReviewMetadataEvent?
    private var activeSubscriptionIds: Set<String> = []
    private(set) var cancelledSubscriptionIds: [String] = []
    private(set) var updatedItemIds: [String] = []

    init(event: BridgeProductReviewMetadataEvent?) {
        self.event = event
    }

    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        guard let event else { throw CoordinatorReviewMetadataSourceError.unavailable }
        activeSubscriptionIds.insert(subscription.subscriptionId)
        try await emit(event)
    }

    func update(
        subscription: BridgeProductSubscriptionSnapshot,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        guard activeSubscriptionIds.contains(subscription.subscriptionId) else {
            throw CoordinatorReviewMetadataSourceError.unknownSubscription
        }
        guard case .reviewMetadata(let interests) = subscription.interestState,
            let event
        else {
            throw CoordinatorReviewMetadataSourceError.unavailable
        }
        updatedItemIds = interests.flatMap(\.itemIds)
        try await emit(event)
    }

    func publish(
        availability _: BridgePaneProductReviewMetadataAvailability
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        .loading(retained: activeSubscriptionIds.count)
    }

    func cancel(subscriptionId: String) {
        activeSubscriptionIds.remove(subscriptionId)
        cancelledSubscriptionIds.append(subscriptionId)
    }
}

private func coordinatorSourceAcceptedEvent() throws -> BridgeProductFileMetadataEvent {
    .sourceAccepted(
        .init(
            source: try .init(
                repoId: "00000000-0000-4000-8000-000000000001",
                rootRevisionToken: "root-token-1",
                sourceCursor: "source-cursor-1",
                sourceId: "file-source-1",
                subscriptionGeneration: 1,
                worktreeId: "00000000-0000-4000-8000-000000000002"
            )
        )
    )
}

private func coordinatorReviewSourceAcceptedEvent() throws -> BridgeProductReviewMetadataEvent {
    try .init(
        generation: 7,
        packageId: "review-package-1",
        revision: 11,
        sourceIdentity: "review-query-1"
    )
}

private func coordinatorReviewPackageFixture() throws -> BridgeReviewPackage {
    let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
    let fixtureURL = projectRoot.appending(
        path: "Tests/BridgeContractFixtures/valid/bridge-review-package.json"
    )
    return try JSONDecoder().decode(
        BridgeReviewPackage.self,
        from: Data(contentsOf: fixtureURL)
    )
}

extension BridgeProductMetadataFrame {
    fileprivate var streamSequenceForTest: Int {
        switch self {
        case .metadataStreamAccepted(let frame): frame.frameIdentity.streamSequence
        case .subscriptionAccepted(let frame): frame.frameIdentity.streamSequence
        case .subscriptionInterestsCommitted(let frame): frame.identity.frameIdentity.streamSequence
        case .subscriptionData(let frame): frame.frameIdentity.streamSequence
        case .subscriptionReset(let frame): frame.identity.frameIdentity.streamSequence
        case .subscriptionCancelled(let frame): frame.identity.frameIdentity.streamSequence
        default: fatalError("Unexpected frame in contiguous stream assertion")
        }
    }
}

private actor CoordinatorGatedFileMetadataSource: BridgePaneProductFileMetadataProducing {
    private var didFinishOpen = false
    private var didStartOpen = false
    private var didStartUpdate = false
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private var isOpenReleased = false
    private var openWaiters: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var updateWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var openObservedCancellation = false
    private(set) var updateObservedOpenFinished = false

    func currentSource() -> BridgeProductFileSourceCurrentResult {
        .unavailable(.noFileSourceAuthority)
    }

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        didStartOpen = true
        for waiter in startWaiters { waiter.resume() }
        startWaiters.removeAll(keepingCapacity: false)
        if !isOpenReleased {
            await withCheckedContinuation { continuation in
                openWaiters.append(continuation)
            }
        }
        openObservedCancellation = Task.isCancelled
        didFinishOpen = true
        for waiter in finishWaiters { waiter.resume() }
        finishWaiters.removeAll(keepingCapacity: false)
    }

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        updateObservedOpenFinished = didFinishOpen
        didStartUpdate = true
        for waiter in updateWaiters { waiter.resume() }
        updateWaiters.removeAll(keepingCapacity: false)
    }

    func cancel(subscriptionId _: String) {}

    func publish(status _: GitWorkingTreeStatus) -> [BridgePaneProductFileMetadataEmission] { [] }

    func publish(changeset _: FileChangeset) async throws -> [BridgePaneProductFileMetadataEmission] { [] }

    func contentBody(for _: BridgeProductFileContentRequest) -> BridgePaneProductFileContentBody? { nil }

    func waitUntilOpenStarted() async {
        guard !didStartOpen else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilUpdateStarted() async {
        guard !didStartUpdate else { return }
        await withCheckedContinuation { continuation in
            updateWaiters.append(continuation)
        }
    }

    func releaseOpen() {
        isOpenReleased = true
        for waiter in openWaiters { waiter.resume() }
        openWaiters.removeAll(keepingCapacity: false)
    }

    func waitUntilOpenFinished() async {
        guard !didFinishOpen else { return }
        await withCheckedContinuation { continuation in
            finishWaiters.append(continuation)
        }
    }
}

private actor CoordinatorFileMetadataSource: BridgePaneProductFileMetadataProducing {
    private(set) var cancelledSubscriptionIds: [String] = []

    func currentSource() -> BridgeProductFileSourceCurrentResult {
        .unavailable(.noFileSourceAuthority)
    }

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        emit: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        try await emit(
            .sourceAccepted(
                .init(
                    source: try .init(
                        repoId: "00000000-0000-4000-8000-000000000001",
                        rootRevisionToken: "root-token-1",
                        sourceCursor: "source-cursor-1",
                        sourceId: "file-source-1",
                        subscriptionGeneration: 1,
                        worktreeId: "00000000-0000-4000-8000-000000000002"
                    )
                )
            )
        )
    }

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {}

    func cancel(subscriptionId: String) {
        cancelledSubscriptionIds.append(subscriptionId)
    }

    func publish(status _: GitWorkingTreeStatus) -> [BridgePaneProductFileMetadataEmission] { [] }

    func publish(changeset _: FileChangeset) async throws -> [BridgePaneProductFileMetadataEmission] { [] }

    func contentBody(for _: BridgeProductFileContentRequest) -> BridgePaneProductFileContentBody? { nil }
}

private func coordinatorMetadataStreamRequest() throws -> BridgeProductMetadataStreamRequest {
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
