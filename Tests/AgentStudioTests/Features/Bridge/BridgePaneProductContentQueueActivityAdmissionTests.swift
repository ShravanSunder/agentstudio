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
        let queueMutationGate = ActivityQueueMutationGate()
        let (precheckEvents, precheckContinuation) = AsyncStream<Void>.makeStream()
        let enqueueTask = Task {
            try await enqueueActivityContentFrameAfterLoosePrecheck(
                target: mutationTarget,
                productAdmission: harness.productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                session: harness.session,
                precheckContinuation: precheckContinuation,
                queueMutationGate: queueMutationGate
            )
        }
        var precheckIterator = precheckEvents.makeAsyncIterator()
        _ = await precheckIterator.next()

        // Act
        boundaryCase.invalidation.apply(to: activityCoordinator)
        await queueMutationGate.release()
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

private func enqueueActivityContentFrameAfterLoosePrecheck(
    target: ActivityContentQueueMutationTarget,
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

actor ActivityQueueMutationGate {
    private var isReleased = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilReleased() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }
}
