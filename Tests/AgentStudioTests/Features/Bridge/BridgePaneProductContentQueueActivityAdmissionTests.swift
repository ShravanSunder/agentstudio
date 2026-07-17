import Foundation
import Testing

@testable import AgentStudio

extension BridgePaneProductContentActivityAdmissionTests {
    @Test(
        "content queue mutation rejects foreground activity invalidated after its precheck",
        arguments: ActivityContentQueueBoundaryCase.allCases
    )
    @MainActor
    func contentQueueMutationRejectsInvalidatedActivity(
        _ boundaryCase: ActivityContentQueueBoundaryCase
    ) async throws {
        // Arrange
        let harness = try await BridgeProductSessionProducerHarness.opened()
        let request = try bridgeProductFileContentRequest(
            identitySuffix: "activity-queue-\(boundaryCase.testDescription)"
        )
        let operation = BridgeProductSessionProducerOperationGate()
        let registration = await harness.session.registerContentProducer(
            request: request,
            productAdmission: harness.productAdmission
        ) { lease in
            await operation.run(lease)
        }
        let lease = try bridgeProductAcceptedLease(registration)
        #expect(await operation.waitUntilStarted() == lease)
        if boundaryCase.phase != .opening {
            _ = try await harness.session.enqueueRequiredProducerOpeningFrame(
                for: lease,
                productAdmission: harness.productAdmission,
                build: { _ in producerRegistryContentOpeningFrame(for: request) }
            )
            #expect(
                await consumeNextBridgeProductProducerFrame(
                    for: lease,
                    from: harness.session,
                    productAdmission: harness.productAdmission
                )?.sequence == 0
            )
        }
        let activityCoordinator = BridgePaneRefreshAdmissionCoordinator(
            initialActivity: .foreground
        )
        let foregroundWorkAdmission = try #require(
            activityCoordinator.acquireForegroundWork()
        )
        let mutationTarget = ActivityContentQueueMutationTarget(
            phase: boundaryCase.phase,
            lease: lease,
            request: request
        )
        let (barrierEntryEvents, barrierEntryContinuation) = AsyncStream<Void>.makeStream()
        let barrierRelease = DispatchSemaphore(value: 0)
        let barrierTask = Task {
            try await holdActivityContentSessionQueue(
                phase: boundaryCase.phase,
                lease: lease,
                productAdmission: harness.productAdmission,
                session: harness.session,
                barrierEntryContinuation: barrierEntryContinuation,
                barrierRelease: barrierRelease
            )
        }
        var barrierEntryIterator = barrierEntryEvents.makeAsyncIterator()
        _ = await barrierEntryIterator.next()
        let (precheckEvents, precheckContinuation) = AsyncStream<Void>.makeStream()
        let enqueueTask = Task {
            try await enqueueActivityContentFrameAfterLoosePrecheck(
                target: mutationTarget,
                productAdmission: harness.productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                session: harness.session,
                precheckContinuation: precheckContinuation
            )
        }
        var precheckIterator = precheckEvents.makeAsyncIterator()
        _ = await precheckIterator.next()

        // Act
        boundaryCase.invalidation.apply(to: activityCoordinator)
        barrierRelease.signal()
        do {
            try await barrierTask.value
            Issue.record("Expected the queue barrier to exit through its injected error")
        } catch ActivityContentQueueBoundaryTestError.barrierReleased {
            // The actor is now free to linearize the content enqueue.
        }
        let enqueueResult = try await enqueueTask.value

        // Assert
        #expect(enqueueResult == .rejected(.lifecycleClosed))
        let invalidatedSnapshot = await harness.session.producerSnapshot()
        #expect(invalidatedSnapshot.queuedFrameCount == 0)
        #expect(invalidatedSnapshot.inFlightFrameReceiptCount == 0)
        try await closeBridgeProductSessionProducer(lease, in: harness.session)
        await operation.waitUntilCancelled()
        #expect((await harness.session.producerSnapshot()).hasZeroResidue)
    }
}

struct ActivityContentQueueBoundaryCase: CustomTestStringConvertible, Sendable {
    static let allCases: [Self] = ActivityContentQueueMutationPhase.allCases.flatMap { phase in
        ActivityReviewInvalidation.allCases.map { invalidation in
            Self(phase: phase, invalidation: invalidation)
        }
    }

    let phase: ActivityContentQueueMutationPhase
    let invalidation: ActivityReviewInvalidation

    var testDescription: String {
        "\(phase.rawValue)-\(invalidation.rawValue)"
    }
}

enum ActivityContentQueueMutationPhase: String, CaseIterable, Sendable {
    case data
    case opening
    case terminal
}

private enum ActivityContentQueueBoundaryTestError: Error {
    case barrierReleased
    case unexpectedOverflow
}

private struct ActivityContentQueueMutationTarget: Sendable {
    let phase: ActivityContentQueueMutationPhase
    let lease: BridgeProductProducerLease
    let request: BridgeProductContentRequest
}

@MainActor
extension ActivityReviewInvalidation {
    fileprivate func apply(to activityCoordinator: BridgePaneRefreshAdmissionCoordinator) {
        switch self {
        case .closed:
            activityCoordinator.close()
        case .loadedHidden:
            activityCoordinator.applyActivity(.loadedHidden)
        }
    }
}

private func holdActivityContentSessionQueue(
    phase: ActivityContentQueueMutationPhase,
    lease: BridgeProductProducerLease,
    productAdmission: BridgeProductAdmissionContext,
    session: BridgeProductSession,
    barrierEntryContinuation: AsyncStream<Void>.Continuation,
    barrierRelease: DispatchSemaphore
) async throws {
    let barrierBuilder: @Sendable (Int) throws -> BridgeProductProducerFrame = { _ in
        barrierEntryContinuation.yield()
        barrierEntryContinuation.finish()
        barrierRelease.wait()
        throw ActivityContentQueueBoundaryTestError.barrierReleased
    }
    switch phase {
    case .opening:
        _ = try await session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            productAdmission: productAdmission,
            build: barrierBuilder
        )
    case .data, .terminal:
        _ = try await session.enqueueProducerFrame(
            for: lease,
            productAdmission: productAdmission,
            build: barrierBuilder,
            overflowReset: { _ in
                throw ActivityContentQueueBoundaryTestError.unexpectedOverflow
            }
        )
    }
}

private func enqueueActivityContentFrameAfterLoosePrecheck(
    target: ActivityContentQueueMutationTarget,
    productAdmission: BridgeProductAdmissionContext,
    foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
    session: BridgeProductSession,
    precheckContinuation: AsyncStream<Void>.Continuation
) async throws -> BridgeProductProducerEnqueueResult {
    guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
        return .rejected(.lifecycleClosed)
    }
    precheckContinuation.yield()
    precheckContinuation.finish()
    switch target.phase {
    case .opening:
        return try await session.enqueueRequiredContentOpeningFrame(
            for: target.lease,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            build: { _ in producerRegistryContentOpeningFrame(for: target.request) }
        )
    case .data:
        return try await session.enqueueContentFrame(
            for: target.lease,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            build: { sequence in
                .content(
                    .init(
                        header: try .data(contentSequence: sequence, offsetBytes: 0),
                        payload: Data("a".utf8)
                    )
                )
            },
            overflowReset: { sequence in
                try producerRegistryContentTerminalFrame(sequence: sequence)
            }
        )
    case .terminal:
        return try await session.enqueueTerminalContentFrame(
            for: target.lease,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            build: { sequence in
                try producerRegistryContentTerminalFrame(sequence: sequence)
            }
        )
    }
}
