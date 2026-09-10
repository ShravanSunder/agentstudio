import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge pane product metadata reconnect subscription")
struct BridgeMetadataReconnectTests {
    @Test(
        "reconnection does not retain a subscription with an undeliverable sequence gap",
        arguments: [false, true]
    )
    func reconnectDoesNotRetainUndeliverableSubscriptionSequenceGap(
        publicationAfterReconciliation: Bool
    ) async throws {
        // Arrange: the worker observed through stream sequence 3. A later
        // publication is queued by Swift but lost with the physical response.
        let context = try await makeReconnectSubscriptionContext()
        let resyncRequest = try reconnectResyncRequest(
            subscription: context.retainedSubscription,
            lastAcceptedStreamSequence: 3
        )
        let precedingResponse: BridgeProductControlResponse? =
            publicationAfterReconciliation
            ? try await dispatchReconnectControl(
                resyncRequest,
                dispatcher: context.dispatcher,
                capabilityHeader: context.harness.capabilityHeader
            ) : nil
        let disposition = await context.provider.publishFileChangeset(
            try reconnectFileChangeset(),
            productAdmission: context.harness.productAdmission.context,
            foregroundWorkAdmission: context.refreshWorkAdmission,
            operationCorrelationID: String(repeating: "d", count: 64),
            operationStageAttempt: 1
        )
        if publicationAfterReconciliation {
            #expect(disposition == .applied || disposition == .notRequired)
        } else {
            #expect(disposition == .applied)
        }
        if disposition == .applied {
            #expect(await context.harness.session.producerSnapshot().queuedFrameCount > 0)
        }
        #expect(await context.firstStream.pump.cancel())

        // Act: reconcile from the worker's actual last observation, not the
        // native queue head, then consume the first replacement subscription frame.
        let response: BridgeProductControlResponse
        if let precedingResponse {
            response = precedingResponse
        } else {
            response = try await dispatchReconnectControl(
                resyncRequest,
                dispatcher: context.dispatcher,
                capabilityHeader: context.harness.capabilityHeader
            )
        }
        guard case .resyncAccepted(let accepted) = response else {
            await context.provider.closeAndDrain()
            Issue.record("Expected reconciliation of interrupted metadata")
            return
        }
        if case .reopenRequired(let reopened) = accepted.reconciliation.first {
            // A fresh subscription identity can establish its own sequence zero.
            #expect(reopened.reason == .snapshotRequired)
            #expect(
                await context.harness.session.subscriptionSnapshot(
                    subscriptionId: context.retainedSubscription.subscriptionId
                ) == nil
            )
            await context.provider.closeAndDrain()
            #expect(await context.harness.session.producerSnapshot().hasZeroResidue)
            return
        }
        let replacement = try await installReconnectMetadataStream(
            request: bridgeProductMetadataStreamRequest(
                metadataStreamId: "metadata-after-lost-frame",
                resumeFromStreamSequence: accepted.metadataStreamSequenceBarrier
            ),
            provider: context.provider,
            harness: context.harness
        )
        let sourceActive = await waitForReconnectSourceActivity(context.fileSource)
        let deadline = ContinuousClock.now + .seconds(2)
        while await context.harness.session.producerSnapshot().queuedFrameCount == 0,
            ContinuousClock.now < deadline
        {
            await Task.yield()
        }
        let frame =
            await context.harness.session.producerSnapshot().queuedFrameCount > 0
            ? try await pullMetadataFrame(from: replacement.pump) : nil
        #expect(await replacement.pump.cancel())
        await context.provider.closeAndDrain()

        // Assert: retaining an identity must preserve the worker's strict next
        // subscription sequence. A physical-stream barrier cannot waive this.
        #expect(await context.harness.session.producerSnapshot().hasZeroResidue)
        #expect(sourceActive)
        guard case .subscriptionData(let data) = frame else {
            Issue.record("Expected contiguous source data or explicit fresh-subscription reconciliation")
            return
        }
        #expect(
            data.subscriptionIdentity.subscriptionSequence
                == context.committedInterest.identity.subscriptionIdentity.subscriptionSequence + 1
        )
    }

    @Test("metadata reattachment restores subscriptions reconciled while disconnected")
    func restoresReconciledSubscriptionsWhenMetadataReattaches() async throws {
        // Arrange
        let context = try await makeReconnectSubscriptionContext()
        #expect(await context.firstStream.pump.cancel())
        let response = try await dispatchReconnectControl(
            reconnectResyncRequest(subscription: context.retainedSubscription, lastAcceptedStreamSequence: 3),
            dispatcher: context.dispatcher,
            capabilityHeader: context.harness.capabilityHeader
        )
        guard case .resyncAccepted(let accepted) = response else {
            await context.provider.closeAndDrain()
            Issue.record("Expected reconciliation before stream reattachment")
            return
        }

        // Act
        let replacement = try await installReconnectMetadataStream(
            request: bridgeProductMetadataStreamRequest(
                metadataStreamId: "metadata-reattached",
                resumeFromStreamSequence: accepted.metadataStreamSequenceBarrier
            ),
            provider: context.provider,
            harness: context.harness
        )
        let sourceActive = await waitForReconnectSourceActivity(context.fileSource)
        let disposition = await context.provider.publishFileChangeset(
            try reconnectFileChangeset(),
            productAdmission: context.harness.productAdmission.context,
            foregroundWorkAdmission: context.refreshWorkAdmission,
            operationCorrelationID: String(repeating: "c", count: 64),
            operationStageAttempt: 1
        )
        let frame =
            disposition == .applied
            ? try await pullPostReconnectPublication(from: replacement.pump, session: context.harness.session)
            : nil
        #expect(await replacement.pump.cancel())
        await context.provider.closeAndDrain()

        // Assert
        #expect(await context.harness.session.producerSnapshot().hasZeroResidue)
        #expect(sourceActive)
        #expect(disposition == .applied)
        guard case .subscriptionData(let data) = frame else {
            Issue.record("Expected post-reattachment source publication")
            return
        }
        #expect(data.frameIdentity.metadataStreamId == "metadata-reattached")
        #expect(data.subscriptionIdentity.interestRevision == 1)
    }

    @Test("session reconciliation remains available after its metadata response closes")
    func reconcilesSessionAfterMetadataResponseCloses() async throws {
        // Arrange
        let context = try await makeReconnectSubscriptionContext()
        #expect(await context.firstStream.pump.cancel())
        let request = try reconnectResyncRequest(
            subscription: context.retainedSubscription,
            lastAcceptedStreamSequence: 3
        )

        // Act
        let response = try await dispatchReconnectControl(
            request,
            dispatcher: context.dispatcher,
            capabilityHeader: context.harness.capabilityHeader
        )
        await context.provider.closeAndDrain()

        // Assert
        #expect(await context.harness.session.producerSnapshot().hasZeroResidue)
        guard case .resyncAccepted(let accepted) = response else {
            Issue.record("A closed metadata response must not disable its session reconciliation command")
            return
        }
        #expect(accepted.metadataStreamSequenceBarrier == 3)
        #expect(accepted.reconciliation.map(\.dispositionName) == ["retained"])
    }

    @Test("reset reconciliation applies canonical empty interests to the source")
    func resetReconciliationAppliesCanonicalSourceInterests() async throws {
        // Arrange
        let context = try await makeReconnectSubscriptionContext()
        let emptyInterestHash = try coordinatorFileSubscriptionLifecycle().opened.interestSha256
        let request = try reconnectResyncRequest(
            subscription: context.retainedSubscription,
            lastAcceptedStreamSequence: 3,
            claimedInterestSha256: String(repeating: "f", count: 64)
        )

        // Act
        let response = try await dispatchReconnectControl(
            request,
            dispatcher: context.dispatcher,
            capabilityHeader: context.harness.capabilityHeader
        )
        guard case .resyncAccepted(let accepted) = response else {
            await context.provider.closeAndDrain()
            Issue.record("Expected canonical reset reconciliation")
            return
        }
        #expect(await context.harness.session.producerSnapshot().hasZeroResidue)
        let replacement = try await installReconnectMetadataStream(
            request: bridgeProductMetadataStreamRequest(
                metadataStreamId: "metadata-reset-interests",
                resumeFromStreamSequence: accepted.metadataStreamSequenceBarrier
            ),
            provider: context.provider,
            harness: context.harness
        )
        #expect(await waitForReconnectSourceActivity(context.fileSource))
        let sourceDiagnostics = await context.fileSource.diagnostics
        let canonicalSubscription = await context.harness.session.subscriptionSnapshot(
            subscriptionId: context.retainedSubscription.subscriptionId
        )
        #expect(await context.firstStream.pump.cancel())
        #expect(await replacement.pump.cancel())
        await context.provider.closeAndDrain()

        // Assert
        #expect(await context.harness.session.producerSnapshot().hasZeroResidue)
        #expect(canonicalSubscription?.interestRevision == 2)
        #expect(canonicalSubscription?.interestSha256 == emptyInterestHash)
        #expect(sourceDiagnostics.interestSha256 == emptyInterestHash)
        #expect(accepted.reconciliation.map(\.dispositionName) == ["reset"])
    }

    @Test("retained reconciliation reattaches unchanged interests once after physical response retirement")
    func retainedReconciliationPreservesHealthySource() async throws {
        // Arrange
        let context = try await makeReconnectSubscriptionContext()
        let before = await context.fileSource.diagnostics
        let request = try reconnectResyncRequest(
            subscription: context.retainedSubscription,
            lastAcceptedStreamSequence: 3
        )

        // Act
        let response = try await dispatchReconnectControl(
            request,
            dispatcher: context.dispatcher,
            capabilityHeader: context.harness.capabilityHeader
        )
        guard case .resyncAccepted(let accepted) = response else {
            await context.provider.closeAndDrain()
            Issue.record("Expected retained subscription reconciliation")
            return
        }
        let afterReconciliation = await context.fileSource.diagnostics
        let retained = await context.harness.session.subscriptionSnapshot(
            subscriptionId: context.retainedSubscription.subscriptionId
        )
        #expect(await context.harness.session.producerSnapshot().hasZeroResidue)
        let replacement = try await installReconnectMetadataStream(
            request: bridgeProductMetadataStreamRequest(
                metadataStreamId: "metadata-retained-interests",
                resumeFromStreamSequence: accepted.metadataStreamSequenceBarrier
            ),
            provider: context.provider,
            harness: context.harness
        )
        #expect(await waitForReconnectSourceActivity(context.fileSource))
        let disposition = await context.provider.publishFileChangeset(
            try reconnectFileChangeset(),
            productAdmission: context.harness.productAdmission.context,
            foregroundWorkAdmission: context.refreshWorkAdmission,
            operationCorrelationID: String(repeating: "b", count: 64),
            operationStageAttempt: 1
        )
        let publication =
            disposition == .applied
            ? try await pullPostReconnectPublication(
                from: replacement.pump,
                session: context.harness.session
            ) : nil
        let after = await context.fileSource.diagnostics
        #expect(await context.firstStream.pump.cancel())
        #expect(await replacement.pump.cancel())
        await context.provider.closeAndDrain()

        // Assert
        #expect(await context.harness.session.producerSnapshot().hasZeroResidue)
        #expect(retained == context.retainedSubscription)
        #expect(afterReconciliation.openCallCount == before.openCallCount)
        #expect(afterReconciliation.updateCallCount == before.updateCallCount)
        #expect(after.openCallCount == before.openCallCount + 1)
        #expect(after.updateCallCount == before.updateCallCount)
        #expect(after.cancellationCount == before.cancellationCount + 1)
        #expect(disposition == .applied)
        guard case .subscriptionData(let data) = publication else {
            Issue.record("Expected retained healthy source publication")
            return
        }
        #expect(accepted.reconciliation.map(\.dispositionName) == ["retained"])
        #expect(data.frameIdentity.metadataStreamId == "metadata-retained-interests")
    }

    @Test(
        "reconciled File subscription delivers source data after metadata stream replacement",
        arguments: [false, true]
    )
    func reconciledFileSubscriptionDeliversAfterMetadataStreamReplacement(
        mismatchedInterests: Bool
    ) async throws {
        // Arrange
        let context = try await makeReconnectSubscriptionContext()
        #expect(await context.firstStream.pump.cancel())
        let retiredSnapshot = await context.harness.session.producerSnapshot()
        let resyncRequest = try reconnectResyncRequest(
            subscription: context.retainedSubscription,
            lastAcceptedStreamSequence: 3,
            claimedInterestSha256: mismatchedInterests ? String(repeating: "f", count: 64) : nil
        )

        // Act
        let resyncResponse = try await dispatchReconnectControl(
            resyncRequest,
            dispatcher: context.dispatcher,
            capabilityHeader: context.harness.capabilityHeader
        )
        guard case .resyncAccepted(let acceptedResync) = resyncResponse else {
            await context.provider.closeAndDrain()
            Issue.record("Expected the production provider resync response")
            return
        }
        let secondStream = try await installReconnectMetadataStream(
            request: bridgeProductMetadataStreamRequest(
                metadataStreamId: "metadata-after-reconnect",
                resumeFromStreamSequence: acceptedResync.metadataStreamSequenceBarrier
            ),
            provider: context.provider,
            harness: context.harness
        )
        let sourceActiveAfterResync = await waitForReconnectSourceActivity(context.fileSource)
        let publicationDisposition = await context.provider.publishFileChangeset(
            try reconnectFileChangeset(),
            productAdmission: context.harness.productAdmission.context,
            foregroundWorkAdmission: context.refreshWorkAdmission,
            operationCorrelationID: String(repeating: "a", count: 64),
            operationStageAttempt: 1
        )
        let replacementFrame =
            publicationDisposition == .applied
            ? try await pullPostReconnectPublication(
                from: secondStream.pump,
                session: context.harness.session
            )
            : nil
        let sourceDiagnostics = await context.fileSource.diagnostics
        #expect(await secondStream.pump.cancel())
        await context.provider.closeAndDrain()
        let finalProducerSnapshot = await context.harness.session.producerSnapshot()

        // Assert
        #expect(finalProducerSnapshot.hasZeroResidue)
        #expect(acceptedResync.reconciliation.map(\.dispositionName) == [mismatchedInterests ? "reset" : "retained"])
        #expect(context.initialData.data.subscriptionKind == .fileMetadata)
        #expect(context.committedInterest.identity.subscriptionIdentity.interestRevision == 1)
        #expect(context.retainedSubscription.interestRevision == 1)
        #expect(retiredSnapshot.hasZeroResidue)
        #expect(sourceActiveAfterResync, "Accepted reconciliation must restore source work")
        #expect(publicationDisposition == .applied)
        #expect(sourceDiagnostics.openCallCount >= 1)
        #expect(sourceDiagnostics.publicationCallCount == 1)
        #expect(sourceDiagnostics.updateCallCount >= 1)
        let expectedInterestHash =
            mismatchedInterests
            ? try coordinatorFileSubscriptionLifecycle().opened.interestSha256
            : context.retainedSubscription.interestSha256
        #expect(sourceDiagnostics.interestSha256 == expectedInterestHash)
        guard case .subscriptionData(let replacementData) = replacementFrame else {
            Issue.record("Expected File data on the replacement metadata stream")
            return
        }
        #expect(replacementData.frameIdentity.metadataStreamId == "metadata-after-reconnect")
        #expect(replacementData.data.subscriptionKind == .fileMetadata)
        #expect(replacementData.subscriptionIdentity.interestRevision == (mismatchedInterests ? 2 : 1))
    }
}
