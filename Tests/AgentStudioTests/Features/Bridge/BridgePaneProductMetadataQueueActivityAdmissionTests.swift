import Foundation
import Testing

@testable import AgentStudio

extension BridgePaneProductMetadataActivityAdmissionTests {
    @Test("metadata queue mutation rejects an invalidated foreground activity token")
    @MainActor
    func metadataQueueMutationRejectsInvalidatedActivity() async throws {
        // Arrange
        let context = try await makeActivityMetadataContext(
            initialActivity: .foreground,
            suspendFileSourceBeforeEmission: true
        )
        let fileOpen = try await openActivityMetadataSubscription(
            context: context,
            object: bridgeProductLifecycleFileSubscriptionOpenObject(
                requestSequence: 2,
                epoch: 1
            ),
            subscriptionId: "file-subscription-1"
        )
        await context.fileSource.waitUntilEmissionReady()
        let originalForegroundWorkAdmission = try #require(
            context.activityCoordinator.acquireForegroundWork()
        )
        let queueMutationGate = ActivityQueueMutationGate()
        let (precheckEvents, precheckContinuation) = AsyncStream<Void>.makeStream()
        let enqueueTask = Task {
            try await enqueueActivityMetadataResetAfterLoosePrecheck(
                subscriptionId: fileOpen.subscriptionId,
                productAdmission: context.harness.productAdmission.context,
                foregroundWorkAdmission: originalForegroundWorkAdmission,
                session: context.harness.session,
                precheckContinuation: precheckContinuation,
                queueMutationGate: queueMutationGate
            )
        }
        var precheckIterator = precheckEvents.makeAsyncIterator()
        _ = await precheckIterator.next()

        // Act
        context.activityCoordinator.applyActivity(.loadedHidden)
        await queueMutationGate.release()
        let staleResetResult = try await enqueueTask.value
        await context.fileSource.releaseEmission()
        await context.fileSource.waitUntilEmissionFinished()
        let hiddenSnapshot = await waitForActivityMetadataState(context) { snapshot in
            snapshot.queuedFrameCount == 0
        }
        let observedFrames = try await drainQueuedActivityMetadataFrames(context)

        // Assert
        #expect(staleResetResult == .rejected(.lifecycleClosed))
        #expect(hiddenSnapshot.queuedFrameCount == 0)
        #expect(observedFrames.isEmpty)
        await context.provider.applyCommittedControlEffect(
            .subscriptionCancelled(fileOpen),
            for: context.fileOpenRequest,
            productAdmission: context.harness.productAdmission.context
        )
        await finishActivityMetadataContext(context)
    }
}

private func drainQueuedActivityMetadataFrames(
    _ context: ActivityMetadataContext
) async throws -> [BridgeProductMetadataFrame] {
    var frames: [BridgeProductMetadataFrame] = []
    while (await context.harness.session.producerSnapshot()).queuedFrameCount > 0 {
        frames.append(try await requiredActivityMetadataFrame(from: context.pump))
    }
    return frames
}

private func enqueueActivityMetadataResetAfterLoosePrecheck(
    subscriptionId: String,
    productAdmission: BridgeProductAdmissionContext,
    foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
    session: BridgeProductSession,
    precheckContinuation: AsyncStream<Void>.Continuation,
    queueMutationGate: ActivityQueueMutationGate
) async throws -> BridgeProductProducerEnqueueResult {
    guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
        return .rejected(.lifecycleClosed)
    }
    precheckContinuation.yield()
    precheckContinuation.finish()
    await queueMutationGate.waitUntilReleased()
    return try await session.enqueueSubscriptionReset(
        subscriptionId: subscriptionId,
        reason: .staleSource,
        productAdmission: productAdmission,
        foregroundWorkAdmission: foregroundWorkAdmission
    )
}
