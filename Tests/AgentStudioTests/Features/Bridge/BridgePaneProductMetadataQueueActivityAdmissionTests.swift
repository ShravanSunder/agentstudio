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
        let (barrierEntryEvents, barrierEntryContinuation) = AsyncStream<Void>.makeStream()
        let barrierRelease = DispatchSemaphore(value: 0)
        let barrierTask = Task {
            try await context.harness.session.enqueueProducerFrame(
                for: context.lease,
                productAdmission: context.harness.productAdmission.context,
                build: { _ in
                    barrierEntryContinuation.yield()
                    barrierEntryContinuation.finish()
                    barrierRelease.wait()
                    throw MetadataQueueActivityAdmissionTestError.barrierReleased
                },
                overflowReset: { _ in
                    throw MetadataQueueActivityAdmissionTestError.unexpectedOverflow
                }
            )
        }
        var barrierEntryIterator = barrierEntryEvents.makeAsyncIterator()
        _ = await barrierEntryIterator.next()
        await context.fileSource.releaseEmission()
        for _ in 0..<2000 where await context.fileSource.emissionAttemptCount == 0 {
            await Task.yield()
        }
        #expect(await context.fileSource.emissionAttemptCount == 1)

        // Act
        context.activityCoordinator.applyActivity(.loadedHidden)
        barrierRelease.signal()
        _ = await barrierTask.result
        await context.fileSource.waitUntilEmissionFinished()
        let staleResetResult = try await context.harness.session.enqueueSubscriptionReset(
            subscriptionId: fileOpen.subscriptionId,
            reason: .staleSource,
            productAdmission: context.harness.productAdmission.context,
            foregroundWorkAdmission: originalForegroundWorkAdmission
        )
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

private enum MetadataQueueActivityAdmissionTestError: Error {
    case barrierReleased
    case unexpectedOverflow
}
