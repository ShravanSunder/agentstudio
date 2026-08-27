import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge product session protocol lifecycle admission")
struct BridgePaneProductMetadataCoordinatorTests {
    @Test("committed File interest waits for source bootstrap without cancelling it")
    func committedFileInterestWaitsForSourceBootstrap() async throws {
        // Arrange
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let source = CoordinatorGatedFileMetadataSource()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: source,
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        let lifecycle = try coordinatorFileSubscriptionLifecycle()
        await coordinator.apply(
            .subscriptionOpened(lifecycle.opened),
            productAdmission: harness.productAdmission.context
        )
        await source.waitUntilOpenStarted()

        // Act
        await coordinator.apply(
            .subscriptionInterestsCommitted(
                barrier: lifecycle.commitBarrier,
                subscription: lifecycle.updated
            ),
            productAdmission: harness.productAdmission.context
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
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
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
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: refreshWorkAdmission.source
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
        await coordinator.apply(
            effect,
            productAdmission: harness.productAdmission.context
        )
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
            data: .fileMetadata(try coordinatorSourceAcceptedEvent()),
            productAdmission: harness.productAdmission.context,
            foregroundWorkAdmission: refreshWorkAdmission.admission
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
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let source = CoordinatorFileMetadataSource()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: source,
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        let metadataRequest = try coordinatorMetadataStreamRequest()
        await coordinator.install(
            request: metadataRequest,
            lease: lease,
            productAdmission: harness.productAdmission.context,
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
        await coordinator.apply(
            effect,
            productAdmission: harness.productAdmission.context
        )
        let dataFrame = try await pullMetadataFrame(from: pump)
        await harness.session.settleControlProviderDispatch(token: token)

        // Assert
        guard case .subscriptionAccepted(let accepted) = acceptedFrame,
            case .subscriptionData(let data) = dataFrame,
            let fileEvent = data.data.fileMetadataEvent,
            case .sourceAccepted(let sourceAccepted) = fileEvent
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

    @Test("committed Review publication waits for its exact final frame observation")
    func committedReviewPublicationWaitsForExactFinalFrameObservation() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let reviewPackage = try coordinatorReviewPackageFixture()
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let reviewSource = CoordinatorTrackingReviewMetadataSource()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: reviewSource,
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
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
        await coordinator.apply(
            effect,
            productAdmission: harness.productAdmission.context
        )
        await reviewSource.waitUntilOpenRegistered()
        let publication = coordinatorCommittedReviewPublication(reviewPackage)
        let reservation = try await coordinator.reserveReviewPublication(
            package: reviewPackage,
            publicationId: publication.publicationId,
            productAdmission: harness.productAdmission.context,
            foregroundWorkAdmission: refreshWorkAdmission.admission
        )
        let deliveryProbe = CoordinatorReviewDeliveryDispositionProbe()
        let delivery = Task {
            let disposition = await coordinator.deliverReviewPublication(
                publication,
                reservation: reservation,
                productAdmission: harness.productAdmission.context,
                foregroundWorkAdmission: refreshWorkAdmission.admission
            )
            await deliveryProbe.record(disposition)
            return disposition
        }
        let publicationReceipt = await reviewSource.waitUntilPublicationReceipt()
        let sourceAcceptedFrame = try await pullMetadataFrame(from: pump)
        #expect(await deliveryProbe.disposition == nil)
        let snapshotFrame = try await pullMetadataFrame(from: pump)
        let deliveryDisposition = await delivery.value
        await harness.session.settleControlProviderDispatch(token: token)

        // Assert
        guard case .subscriptionAccepted(let accepted) = acceptedFrame,
            case .subscriptionData(let sourceAcceptedData) = sourceAcceptedFrame,
            let sourceAcceptedEvent = sourceAcceptedData.data.reviewMetadataEvent,
            case .sourceAccepted(let sourceAccepted) = sourceAcceptedEvent,
            case .subscriptionData(let snapshotData) = snapshotFrame,
            let snapshotEvent = snapshotData.data.reviewMetadataEvent,
            case .snapshot(let snapshot) = snapshotEvent
        else {
            Issue.record("Expected Review accepted followed by source-accepted and snapshot data")
            return
        }
        #expect(accepted.frameIdentity.streamSequence == 1)
        #expect(sourceAcceptedData.frameIdentity.streamSequence == 2)
        #expect(sourceAcceptedData.subscriptionIdentity.subscriptionSequence == 1)
        #expect(snapshotData.frameIdentity.streamSequence == 3)
        #expect(snapshotData.subscriptionIdentity.subscriptionSequence == 2)
        #expect(sourceAccepted.identity.generation == 42)
        #expect(sourceAccepted.identity.packageId == "package-42")
        #expect(sourceAccepted.identity.revision == 1)
        #expect(sourceAccepted.identity.sourceIdentity == "query-42")
        #expect(snapshot.identity == sourceAccepted.identity)
        #expect(deliveryDisposition == .transportAcknowledged)
        #expect(
            publicationReceipt.finalFrames == [
                BridgeReviewMetadataFinalFrame(
                    sequence: 3,
                    subscriptionId: "review-subscription-1"
                )
            ]
        )
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }

    @Test("committed Review interest update republishes current source after its lifecycle barrier")
    func committedReviewInterestUpdateRepublishesCurrentSource() async throws {
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
        let reviewSource = CoordinatorReviewMetadataSource(event: try coordinatorReviewSourceAcceptedEvent())
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: reviewSource,
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
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
        await coordinator.apply(
            openEffect,
            productAdmission: harness.productAdmission.context
        )
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
        await coordinator.apply(
            updateEffect,
            productAdmission: harness.productAdmission.context
        )
        let dataFrame = try await pullMetadataFrame(from: pump)
        await harness.session.settleControlProviderDispatch(token: updateToken)

        // Assert
        guard case .subscriptionInterestsCommitted(let committed) = committedFrame,
            case .subscriptionData(let data) = dataFrame,
            let event = data.data.reviewMetadataEvent
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
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let fileSource = CoordinatorFileMetadataSource()
        let reviewSource = CoordinatorReviewMetadataSource(event: try coordinatorReviewSourceAcceptedEvent())
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: fileSource,
            reviewMetadataSource: reviewSource,
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
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
        await coordinator.apply(
            openEffect,
            productAdmission: harness.productAdmission.context
        )
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
        await coordinator.apply(
            cancelEffect,
            productAdmission: harness.productAdmission.context
        )
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
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: CoordinatorFileMetadataSource(),
            reviewMetadataSource: CoordinatorReviewMetadataSource(
                event: try coordinatorReviewSourceAcceptedEvent()
            ),
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
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
            await coordinator.apply(
                effect,
                productAdmission: harness.productAdmission.context
            )
            observedFrames.append(try await pullMetadataFrame(from: pump))
            await harness.session.settleControlProviderDispatch(token: token)
        }

        // Assert
        #expect(observedFrames.map(\.streamSequenceForTest) == [1, 2, 3, 4])
        guard case .subscriptionData(let fileData) = observedFrames[1],
            fileData.data.subscriptionKind == .fileMetadata,
            case .subscriptionData(let reviewData) = observedFrames[3],
            reviewData.data.subscriptionKind == .reviewMetadata
        else {
            Issue.record("Expected File and Review subscription data on the shared stream")
            return
        }
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }

    @Test("current Review failure resets Review subscription and leaves File active")
    func currentReviewFailureResetsOnlyReviewSubscription() async throws {
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
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: CoordinatorFileMetadataSource(),
            reviewMetadataSource: CoordinatorReviewMetadataSource(
                event: try coordinatorReviewSourceAcceptedEvent()
            ),
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
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
            _ = try await pullMetadataFrame(from: pump)
            await coordinator.apply(effect, productAdmission: harness.productAdmission.context)
            _ = try await pullMetadataFrame(from: pump)
            await harness.session.settleControlProviderDispatch(token: token)
        }

        // Act
        await coordinator.resetCurrentReviewSubscriptionsForUnavailableSource(
            productAdmission: harness.productAdmission.context,
            foregroundWorkAdmission: refreshWorkAdmission.admission
        )
        let resetFrame = try await pullMetadataFrame(from: pump)
        let fileDataResult = try await harness.session.enqueueSubscriptionData(
            subscriptionId: "file-subscription-1",
            data: .fileMetadata(try coordinatorSourceAcceptedEvent()),
            productAdmission: harness.productAdmission.context,
            foregroundWorkAdmission: refreshWorkAdmission.admission
        )

        // Assert
        guard case .subscriptionReset(let reset) = resetFrame else {
            Issue.record("Expected a Review subscription reset")
            return
        }
        #expect(reset.identity.subscriptionIdentity.subscriptionId == "review-subscription-1")
        #expect(reset.reason == .staleSource)
        guard case .enqueued = fileDataResult else {
            Issue.record("Expected File subscription to remain active")
            return
        }
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }

    @Test("foreground resume skips a missing deferred subscription and replays the next one")
    @MainActor
    func foregroundResumeContinuesAfterMissingSubscriptionSnapshot() async throws {
        // Arrange
        let activityCoordinator = BridgePaneRefreshAdmissionCoordinator(
            initialActivity: .loadedHidden
        )
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: CoordinatorFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: activityCoordinator.workAdmissionSource
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
        _ = try await pullMetadataFrame(from: pump)
        guard case .subscriptionOpened(let activeSubscription) = effect else {
            Issue.record("Expected an opened File subscription effect")
            return
        }
        let missingSubscription = BridgeProductSubscriptionSnapshot(
            subscription: activeSubscription.subscription,
            subscriptionId: "aaa-missing-subscription",
            subscriptionKind: activeSubscription.subscriptionKind,
            workerDerivationEpoch: activeSubscription.workerDerivationEpoch,
            interestRevision: activeSubscription.interestRevision,
            interestSha256: activeSubscription.interestSha256,
            interestState: activeSubscription.interestState,
            hasStagedUpdate: activeSubscription.hasStagedUpdate
        )
        await coordinator.apply(
            .subscriptionOpened(missingSubscription),
            productAdmission: harness.productAdmission.context
        )
        await coordinator.apply(
            effect,
            productAdmission: harness.productAdmission.context
        )

        // Act
        activityCoordinator.applyActivity(.foreground)
        await coordinator.resumeForegroundWork()
        for _ in 0..<1000
        where (await harness.session.producerSnapshot()).queuedFrameCount == 0 {
            await Task.yield()
        }

        // Assert
        #expect((await harness.session.producerSnapshot()).queuedFrameCount == 1)
        guard (await harness.session.producerSnapshot()).queuedFrameCount == 1 else {
            await coordinator.uninstall(lease: lease)
            #expect(await pump.cancel())
            return
        }
        let dataFrame = try await pullMetadataFrame(from: pump)
        guard case .subscriptionData(let data) = dataFrame,
            data.data.subscriptionKind == .fileMetadata
        else {
            Issue.record("Expected the surviving File subscription to resume")
            return
        }
        #expect(data.subscriptionIdentity.subscriptionId == activeSubscription.subscriptionId)
        await harness.session.settleControlProviderDispatch(token: token)
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
            productAdmission: harness.productAdmission.context,
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

@Suite("Bridge pane presentation telemetry")
struct BridgePanePresentationCoordinatorTests {
    @Test("pane presentation records when no metadata stream can receive it")
    func panePresentationRecordsMissingMetadataStream() async throws {
        // Arrange
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let traceRecorder = CoordinatorPanePresentationTraceRecorder()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: refreshWorkAdmission.source,
            lifecycleTraceRecorder: traceRecorder
        )
        let presentation = coordinatorPanePresentation(
            presentationRevision: 17,
            attempt: .pending(reviewGeneration: 4)
        )

        // Act
        await coordinator.publishPanePresentation(presentation)

        // Assert
        let events = await traceRecorder.presentationEvents
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.stage == .notEnqueued)
        #expect(event.result == .skipped)
        #expect(event.resultReason == .noActiveStream)
        #expect(event.presentationRevision == 17)
        #expect(event.comparisonAttempt == .pending)
        #expect(event.reviewGeneration == 4)
        #expect(event.refreshingReview == true)
        #expect(event.hasActiveStream == false)
    }

    @Test("pane presentation records successful metadata-stream enqueue")
    func panePresentationRecordsSuccessfulMetadataStreamEnqueue() async throws {
        // Arrange
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let traceRecorder = CoordinatorPanePresentationTraceRecorder()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: refreshWorkAdmission.source,
            lifecycleTraceRecorder: traceRecorder
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        let presentation = coordinatorPanePresentation(
            presentationRevision: 18,
            attempt: .settled(reviewGeneration: 5)
        )

        // Act
        await coordinator.publishPanePresentation(presentation)

        // Assert
        let events = await traceRecorder.presentationEvents
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.stage == .enqueued)
        #expect(event.result == .success)
        #expect(event.resultReason == .noReason)
        #expect(event.presentationRevision == 18)
        #expect(event.comparisonAttempt == .settled)
        #expect(event.reviewGeneration == 5)
        #expect(event.refreshingReview == true)
        #expect(event.hasActiveStream == true)
        await coordinator.uninstall(lease: lease)
    }

    @Test("pane presentation overflow emits a retryable resync terminal")
    func panePresentationOverflowEmitsRetryableResyncTerminal() async throws {
        let queueLimits = try BridgeProductProducerQueueLimits(
            maximumQueuedFrameCount: 3,
            maximumQueuedByteCount: BridgeProductWireContract.maximumQueuedStreamBytes,
            maximumEncodedFrameByteCount:
                BridgeProductProducerQueueLimits.maximumProductEncodedFrameByteCount,
            terminalFrameReserve: BridgeProductWireContract.terminalFrameReserve
        )
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened(
            producerQueueLimits: queueLimits
        )
        let lease = try await harness.admitMetadataFrames(through: 0)
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )

        await coordinator.publishPanePresentation(
            coordinatorPanePresentation(
                presentationRevision: 20,
                attempt: .settled(reviewGeneration: 5)
            )
        )
        await coordinator.publishPanePresentation(
            coordinatorPanePresentation(
                presentationRevision: 21,
                attempt: .settled(reviewGeneration: 6)
            )
        )
        await coordinator.publishPanePresentation(
            coordinatorPanePresentation(
                presentationRevision: 22,
                attempt: .settled(reviewGeneration: 7)
            )
        )

        let terminal = try #require(
            await consumeNextBridgeProductProducerFrame(
                for: lease,
                from: harness.session,
                productAdmission: harness.productAdmission.context
            )
        )
        let decoder = try BridgeProductMetadataFrameDecoder()
        let decodedFrames = try decoder.append(terminal.data)
        guard case .metadataStreamError(let error) = try #require(decodedFrames.first)
        else {
            Issue.record("Expected pane presentation overflow to emit metadata.streamError")
            return
        }
        #expect(error.code == .resyncRequired)
        #expect(error.retryable)
        await coordinator.uninstall(lease: lease)
    }
}

private actor CoordinatorPanePresentationTraceRecorder:
    BridgeProductMetadataLifecycleTraceRecording
{
    private(set) var presentationEvents: [BridgePanePresentationTraceEvent] = []

    func record(_: BridgeProductMetadataLifecycleTraceEvent) {}

    func record(_: BridgeProductReviewMetadataPublicationTraceEvent) {}

    func record(_ event: BridgePanePresentationTraceEvent) {
        presentationEvents.append(event)
    }
}

private func coordinatorPanePresentation(
    presentationRevision: Int,
    attempt: BridgePaneReviewComparisonAttempt
) -> BridgePaneProductPresentationSnapshot {
    BridgePaneProductPresentationSnapshot(
        nativeActivity: .foreground,
        presentationRevision: presentationRevision,
        refreshingLanes: [.review],
        reviewComparison: BridgePaneReviewComparisonPresentation(
            activeTarget: .branch(name: "comparison-target"),
            attempt: attempt,
            displayedSnapshot: .absent,
            repositoryDefaultTarget: nil
        )
    )
}
