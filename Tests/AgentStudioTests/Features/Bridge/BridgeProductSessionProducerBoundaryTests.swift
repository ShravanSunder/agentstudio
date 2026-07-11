import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product session producer public boundaries")
struct BridgeProductSessionProducerBoundaryTests {
    @Test("fresh sessions reject unproven metadata resume cursors atomically")
    func freshSessionRejectsUnprovenMetadataResumeCursors() async throws {
        // Arrange
        let harness = try await BridgeProductSessionProducerHarness.opened()
        let initialSnapshot = await harness.session.producerSnapshot()
        let unprovenRequest = try bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-unproven-fresh",
            resumeFromStreamSequence: 6
        )
        let nearExhaustionRequest = try bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-unproven-near-exhaustion",
            resumeFromStreamSequence: BridgeProductWireContract.maximumResumableStreamSequence
        )

        // Act / Assert
        try await expectMetadataRegistrationRejectedWithoutMutation(
            request: unprovenRequest,
            session: harness.session
        )
        try await expectMetadataRegistrationRejectedWithoutMutation(
            request: nearExhaustionRequest,
            session: harness.session
        )
        #expect(await harness.session.producerSnapshot() == initialSnapshot)
        #expect(initialSnapshot.nextMetadataStreamSequence == 0)
    }

    @Test("metadata reopen rejects future and near-exhaustion cursors after progress")
    func metadataReopenRejectsInvalidCursorsAfterProgress() async throws {
        // Arrange
        let harness = try await openedSessionAfterMetadataProgress()
        let progressedSnapshot = await harness.session.producerSnapshot()
        let futureRequest = try bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-reopen-future",
            resumeFromStreamSequence: progressedSnapshot.nextMetadataStreamSequence
        )
        let nearExhaustionRequest = try bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-reopen-near-exhaustion",
            resumeFromStreamSequence: BridgeProductWireContract.maximumResumableStreamSequence
        )

        // Act / Assert
        #expect(progressedSnapshot.nextMetadataStreamSequence == 3)
        #expect(progressedSnapshot.hasZeroResidue)
        try await expectMetadataRegistrationRejectedWithoutMutation(
            request: futureRequest,
            session: harness.session
        )
        try await expectMetadataRegistrationRejectedWithoutMutation(
            request: nearExhaustionRequest,
            session: harness.session
        )
        #expect(await harness.session.producerSnapshot() == progressedSnapshot)
    }

    @Test("nil reopen requires snapshot restart and preserves durable high-water")
    func nilReopenSnapshotsFromZeroWithoutRegressingHighWater() async throws {
        // Arrange
        let harness = try await openedSessionAfterMetadataProgress()
        let request = try bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-nil-reopen",
            resumeFromStreamSequence: nil
        )
        let operation = BridgeProductSessionProducerOperationGate()
        let registration = await harness.session.registerMetadataProducer(request: request) { lease in
            await operation.run(lease)
        }
        let lease = try bridgeProductAcceptedLease(registration)
        _ = await operation.waitUntilStarted()
        let beforeMismatch = await harness.session.producerSnapshot()

        // Act
        let mismatchedOpening = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { sequence in
                try bridgeProductMetadataAcceptedFrame(
                    request: request,
                    streamSequence: sequence,
                    resumeDisposition: .resumed
                )
            }
        )
        let afterMismatch = await harness.session.producerSnapshot()
        let correctOpening = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { sequence in
                try bridgeProductMetadataAcceptedFrame(
                    request: request,
                    streamSequence: sequence,
                    resumeDisposition: .snapshotRequired
                )
            }
        )
        let afterOpening = await harness.session.producerSnapshot()
        let deliveredOpening = await harness.session.dequeueProducerFrame(for: lease)
        let progress = try await harness.session.enqueueProducerFrame(
            for: lease,
            build: { sequence in
                try bridgeProductMetadataProgressFrame(
                    request: request,
                    streamSequence: sequence,
                    identitySuffix: "nil-reopen"
                )
            },
            overflowReset: { sequence in
                try bridgeProductMetadataTerminalFrame(
                    request: request,
                    streamSequence: sequence
                )
            }
        )
        let afterProgress = await harness.session.producerSnapshot()

        // Assert
        #expect(bridgeProductEnqueuedFrame(mismatchedOpening) == nil)
        #expect(afterMismatch == beforeMismatch)
        #expect(bridgeProductEnqueuedFrame(correctOpening)?.sequence == 0)
        #expect(deliveredOpening?.sequence == 0)
        #expect(afterOpening.nextMetadataStreamSequence == 3)
        #expect(bridgeProductEnqueuedFrame(progress)?.sequence == 1)
        #expect(afterProgress.nextMetadataStreamSequence == 3)
        #expect(await harness.session.dequeueProducerFrame(for: lease)?.sequence == 1)
        try await closeBridgeProductSessionProducer(lease, in: harness.session)
    }

    @Test("exact current metadata cursor resumes contiguously")
    func exactCurrentMetadataCursorResumesContiguously() async throws {
        // Arrange
        let harness = try await openedSessionAfterMetadataProgress()
        let request = try bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-exact-resume",
            resumeFromStreamSequence: 2
        )
        let operation = BridgeProductSessionProducerOperationGate()
        let registration = await harness.session.registerMetadataProducer(request: request) { lease in
            await operation.run(lease)
        }
        let lease = try bridgeProductAcceptedLease(registration)
        _ = await operation.waitUntilStarted()

        // Act
        let opening = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { sequence in
                try bridgeProductMetadataAcceptedFrame(
                    request: request,
                    streamSequence: sequence,
                    resumeDisposition: .resumed
                )
            }
        )
        let deliveredOpening = await harness.session.dequeueProducerFrame(for: lease)
        let progress = try await harness.session.enqueueProducerFrame(
            for: lease,
            build: { sequence in
                try bridgeProductMetadataProgressFrame(
                    request: request,
                    streamSequence: sequence,
                    identitySuffix: "exact-resume"
                )
            },
            overflowReset: { sequence in
                try bridgeProductMetadataTerminalFrame(
                    request: request,
                    streamSequence: sequence
                )
            }
        )

        // Assert
        #expect(bridgeProductEnqueuedFrame(opening)?.sequence == 3)
        #expect(deliveredOpening?.sequence == 3)
        #expect(bridgeProductEnqueuedFrame(progress)?.sequence == 4)
        #expect(await harness.session.dequeueProducerFrame(for: lease)?.sequence == 4)
        #expect((await harness.session.producerSnapshot()).nextMetadataStreamSequence == 5)
        try await closeBridgeProductSessionProducer(lease, in: harness.session)
        #expect((await harness.session.producerSnapshot()).hasZeroResidue)
    }

    @Test("exact cursor rejects snapshot-required disposition without mutation")
    func exactCursorRequiresResumedDisposition() async throws {
        // Arrange
        let harness = try await openedSessionAfterMetadataProgress()
        let request = try bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-exact-disposition",
            resumeFromStreamSequence: 2
        )
        let operation = BridgeProductSessionProducerOperationGate()
        let registration = await harness.session.registerMetadataProducer(request: request) { lease in
            await operation.run(lease)
        }
        let lease = try bridgeProductAcceptedLease(registration)
        _ = await operation.waitUntilStarted()
        let beforeMismatch = await harness.session.producerSnapshot()

        // Act
        let mismatchedOpening = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { sequence in
                try bridgeProductMetadataAcceptedFrame(
                    request: request,
                    streamSequence: sequence,
                    resumeDisposition: .snapshotRequired
                )
            }
        )
        let afterMismatch = await harness.session.producerSnapshot()
        let correctOpening = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { sequence in
                try bridgeProductMetadataAcceptedFrame(
                    request: request,
                    streamSequence: sequence,
                    resumeDisposition: .resumed
                )
            }
        )

        // Assert
        #expect(bridgeProductEnqueuedFrame(mismatchedOpening) == nil)
        #expect(afterMismatch == beforeMismatch)
        #expect(bridgeProductEnqueuedFrame(correctOpening)?.sequence == 3)
        #expect(await harness.session.dequeueProducerFrame(for: lease)?.sequence == 3)
        try await closeBridgeProductSessionProducer(lease, in: harness.session)
    }

    @Test("lagging authorized cursor snapshots contiguously without regressing high-water")
    func laggingCursorSnapshotsWithoutRegressingHighWater() async throws {
        // Arrange
        let harness = try await openedSessionAfterMetadataProgress()
        let request = try bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-lagging-snapshot",
            resumeFromStreamSequence: 0
        )
        let operation = BridgeProductSessionProducerOperationGate()
        let registration = await harness.session.registerMetadataProducer(request: request) { lease in
            await operation.run(lease)
        }
        let lease = try bridgeProductAcceptedLease(registration)
        _ = await operation.waitUntilStarted()

        // Act
        let opening = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { sequence in
                try bridgeProductMetadataAcceptedFrame(
                    request: request,
                    streamSequence: sequence,
                    resumeDisposition: .snapshotRequired
                )
            }
        )
        let afterOpening = await harness.session.producerSnapshot()
        let deliveredOpening = await harness.session.dequeueProducerFrame(for: lease)
        let replayedProgress = try await harness.session.enqueueProducerFrame(
            for: lease,
            build: { sequence in
                try bridgeProductMetadataProgressFrame(
                    request: request,
                    streamSequence: sequence,
                    identitySuffix: "lagging-replay"
                )
            },
            overflowReset: { sequence in
                try bridgeProductMetadataTerminalFrame(
                    request: request,
                    streamSequence: sequence
                )
            }
        )
        let afterReplay = await harness.session.producerSnapshot()

        // Assert
        #expect(bridgeProductEnqueuedFrame(opening)?.sequence == 1)
        #expect(deliveredOpening?.sequence == 1)
        #expect(afterOpening.nextMetadataStreamSequence == 3)
        #expect(bridgeProductEnqueuedFrame(replayedProgress)?.sequence == 2)
        #expect(afterReplay.nextMetadataStreamSequence == 3)
        #expect(await harness.session.dequeueProducerFrame(for: lease)?.sequence == 2)
        try await closeBridgeProductSessionProducer(lease, in: harness.session)
    }

    @Test("lagging overflow reset cannot regress pane metadata high-water")
    func laggingOverflowResetPreservesPaneMetadataHighWater() async throws {
        // Arrange
        let durableNextSequence = 5
        let harness = try await openedSessionAfterMetadataProgress(
            progressFrameCount: durableNextSequence - 1
        )
        let request = try bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-lagging-overflow",
            resumeFromStreamSequence: 0
        )
        let operation = BridgeProductSessionProducerOperationGate()
        let registration = await harness.session.registerMetadataProducer(request: request) { lease in
            await operation.run(lease)
        }
        let lease = try bridgeProductAcceptedLease(registration)
        _ = await operation.waitUntilStarted()
        let opening = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { sequence in
                try bridgeProductMetadataAcceptedFrame(
                    request: request,
                    streamSequence: sequence,
                    resumeDisposition: .snapshotRequired
                )
            }
        )
        #expect(bridgeProductEnqueuedFrame(opening)?.sequence == 1)
        #expect(await harness.session.dequeueProducerFrame(for: lease)?.sequence == 1)
        let nonterminalCapacity =
            BridgeProductWireContract.maximumQueuedStreamFrames
            - BridgeProductWireContract.terminalFrameReserve
        for expectedSequence in 2..<(2 + nonterminalCapacity) {
            let progress = try await harness.session.enqueueProducerFrame(
                for: lease,
                build: { sequence in
                    try bridgeProductMetadataProgressFrame(
                        request: request,
                        streamSequence: sequence,
                        identitySuffix: "lagging-overflow-\(sequence)"
                    )
                },
                overflowReset: { sequence in
                    try bridgeProductMetadataTerminalFrame(
                        request: request,
                        streamSequence: sequence
                    )
                }
            )
            #expect(bridgeProductEnqueuedFrame(progress)?.sequence == expectedSequence)
        }

        // Act
        let reset = try await harness.session.enqueueProducerFrame(
            for: lease,
            build: { sequence in
                try bridgeProductMetadataProgressFrame(
                    request: request,
                    streamSequence: sequence,
                    identitySuffix: "lagging-overflow-reset"
                )
            },
            overflowReset: { sequence in
                try bridgeProductMetadataTerminalFrame(
                    request: request,
                    streamSequence: sequence
                )
            }
        )
        let afterReset = await harness.session.producerSnapshot()

        // Assert
        #expect(bridgeProductEnqueuedFrame(reset)?.sequence == 2)
        #expect(afterReset.nextMetadataStreamSequence == durableNextSequence)
        try await closeBridgeProductSessionProducer(lease, in: harness.session)
    }

    @Test("lagging cursor rejects resumed disposition without mutation")
    func laggingCursorRequiresSnapshotDisposition() async throws {
        // Arrange
        let harness = try await openedSessionAfterMetadataProgress()
        let request = try bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-lagging-disposition",
            resumeFromStreamSequence: 0
        )
        let operation = BridgeProductSessionProducerOperationGate()
        let registration = await harness.session.registerMetadataProducer(request: request) { lease in
            await operation.run(lease)
        }
        let lease = try bridgeProductAcceptedLease(registration)
        _ = await operation.waitUntilStarted()
        let beforeMismatch = await harness.session.producerSnapshot()

        // Act
        let mismatchedOpening = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { sequence in
                try bridgeProductMetadataAcceptedFrame(
                    request: request,
                    streamSequence: sequence,
                    resumeDisposition: .resumed
                )
            }
        )
        let afterMismatch = await harness.session.producerSnapshot()
        let correctOpening = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { sequence in
                try bridgeProductMetadataAcceptedFrame(
                    request: request,
                    streamSequence: sequence,
                    resumeDisposition: .snapshotRequired
                )
            }
        )

        // Assert
        #expect(bridgeProductEnqueuedFrame(mismatchedOpening) == nil)
        #expect(afterMismatch == beforeMismatch)
        #expect(bridgeProductEnqueuedFrame(correctOpening)?.sequence == 1)
        #expect(await harness.session.dequeueProducerFrame(for: lease)?.sequence == 1)
        try await closeBridgeProductSessionProducer(lease, in: harness.session)
    }

}

private func openedSessionAfterMetadataProgress(
    progressFrameCount: Int = 2
) async throws
    -> BridgeProductSessionProducerHarness
{
    let harness = try await BridgeProductSessionProducerHarness.opened()
    let request = try bridgeProductMetadataStreamRequest(
        metadataStreamId: "metadata-history-\(UUID().uuidString)",
        resumeFromStreamSequence: nil
    )
    let operation = BridgeProductSessionProducerOperationGate()
    let registration = await harness.session.registerMetadataProducer(request: request) { lease in
        await operation.run(lease)
    }
    let lease = try bridgeProductAcceptedLease(registration)
    _ = await operation.waitUntilStarted()
    let opening = try await harness.session.enqueueRequiredProducerOpeningFrame(
        for: lease,
        build: { sequence in
            try bridgeProductMetadataAcceptedFrame(
                request: request,
                streamSequence: sequence,
                resumeDisposition: .snapshotRequired
            )
        }
    )
    #expect(bridgeProductEnqueuedFrame(opening)?.sequence == 0)
    #expect(await harness.session.dequeueProducerFrame(for: lease)?.sequence == 0)
    for expectedSequence in 1...progressFrameCount {
        let progress = try await harness.session.enqueueProducerFrame(
            for: lease,
            build: { sequence in
                try bridgeProductMetadataProgressFrame(
                    request: request,
                    streamSequence: sequence,
                    identitySuffix: "history-\(sequence)"
                )
            },
            overflowReset: { sequence in
                try bridgeProductMetadataTerminalFrame(
                    request: request,
                    streamSequence: sequence
                )
            }
        )
        #expect(bridgeProductEnqueuedFrame(progress)?.sequence == expectedSequence)
        #expect(await harness.session.dequeueProducerFrame(for: lease)?.sequence == expectedSequence)
    }
    try await closeBridgeProductSessionProducer(lease, in: harness.session)
    #expect(
        (await harness.session.producerSnapshot()).nextMetadataStreamSequence
            == progressFrameCount + 1
    )
    #expect((await harness.session.producerSnapshot()).hasZeroResidue)
    return harness
}

private func expectMetadataRegistrationRejectedWithoutMutation(
    request: BridgeProductMetadataStreamRequest,
    session: BridgeProductSession
) async throws {
    let operation = BridgeProductSessionProducerOperationGate()
    let beforeRegistration = await session.producerSnapshot()
    let registration = await session.registerMetadataProducer(request: request) { lease in
        await operation.run(lease)
    }
    let afterRegistration = await session.producerSnapshot()

    guard case .accepted(let unexpectedLease) = registration else {
        #expect(afterRegistration == beforeRegistration)
        return
    }

    Issue.record("Expected metadata resume registration rejection")
    #expect(afterRegistration == beforeRegistration)
    try await closeBridgeProductSessionProducer(unexpectedLease, in: session)
}
