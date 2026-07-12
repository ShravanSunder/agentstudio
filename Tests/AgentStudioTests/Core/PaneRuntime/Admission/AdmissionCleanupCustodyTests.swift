import Foundation
import Testing
import os

@testable import AgentStudio

@Suite("Admission cleanup physical custody")
struct AdmissionCleanupCustodyTests {
    @Test("latest invalidation preserves bounded physical custody", arguments: [1, 100, 300])
    func latestInvalidationPreservesBoundedPhysicalCustody(retainedDepth: Int) throws {
        // Arrange
        let generation = AdmissionGeneration(owner: .terminalViewport, value: 71)
        let clock = TestPushClock()
        let recorder = CleanupReleaseRecorder()
        let mailboxBox = LatestCleanupMailboxBox()
        let cleanupQuantum = AdmissionCleanupQuantum(maximumEntries: 17, maximumBytes: nil)
        let mailbox = LatestValueMailbox<Int, CleanupPayload>(
            generation: generation,
            declaredKeys: Set(0..<retainedDepth),
            limits: makeLatestValueTestLimits(cleanupQuantum: cleanupQuantum),
            clock: clock
        )
        mailboxBox.mailbox = mailbox
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding
        for key in 0..<retainedDepth {
            _ = mailbox.producerPort.offer(
                generation: generation,
                key: key,
                value: makeLatestPayload(
                    identifier: "latest-secret-\(key)",
                    mailboxBox: mailboxBox,
                    recorder: recorder
                )
            )
        }
        _ = try requireLatestDrainToken(
            consumer.takeDrain(binding: binding, generation: generation)
        )
        let semanticBeforeInvalidation = latestSnapshot(lifecycle.diagnostics)
        clock.advance(by: .seconds(2))

        // Act
        let invalidation = lifecycle.invalidate(generation: generation)
        clock.advance(by: .seconds(3))
        let cleanupBeforeTurns = latestSnapshot(lifecycle.diagnostics)

        // Assert
        #expect(invalidation == .applied)
        #expect(recorder.identifiers.isEmpty)
        #expect(
            semanticBeforeInvalidation
                == CleanupCustodySnapshot(
                    semanticEntryCount: retainedDepth,
                    pendingEntryCount: 0,
                    leasedEntryCount: retainedDepth,
                    cleanupEntryCount: 0,
                    physicalEntryCount: retainedDepth,
                    semanticByteCount: nil,
                    cleanupByteCount: nil,
                    physicalByteCount: nil,
                    semanticEntryHighWater: retainedDepth,
                    cleanupEntryHighWater: 0,
                    physicalEntryHighWater: retainedDepth,
                    semanticByteHighWater: nil,
                    cleanupByteHighWater: nil,
                    physicalByteHighWater: nil,
                    oldestCleanupAge: nil,
                    isQuiescent: false
                )
        )
        expectCleanupOnlySnapshot(
            cleanupBeforeTurns,
            entries: retainedDepth,
            bytes: nil,
            oldestAge: .seconds(5)
        )
        expectDiagnosticsExcludePayloads(lifecycle.diagnostics, marker: "latest-secret-")
        performAllCleanup(
            expectedEntries: retainedDepth,
            expectedBytes: nil,
            quantum: cleanupQuantum,
            recorder: recorder,
            performCleanup: { lifecycle.performCleanup(generation: generation) },
            diagnostics: { latestSnapshot(lifecycle.diagnostics) }
        )
    }

    @Test("gather retirement and invalidation preserve bounded physical custody", arguments: [1, 100, 300])
    func gatherRetirementAndInvalidationPreserveBoundedPhysicalCustody(retainedDepth: Int) {
        // Arrange
        let generation = AdmissionGeneration(owner: .filesystemObservation, value: 72)
        let clock = TestPushClock()
        let recorder = CleanupReleaseRecorder()
        let mailboxBox = GatherCleanupMailboxBox()
        let cleanupQuantum = AdmissionCleanupQuantum(maximumEntries: 17, maximumBytes: 17)
        let limits = GatherMailboxLimits(
            maximumDeclaredKeys: 1,
            maximumRetainedContributions: retainedDepth,
            maximumRetainedItems: retainedDepth,
            maximumRetainedBytes: retainedDepth,
            maximumRetainedContributionsPerKey: retainedDepth,
            maximumRetainedItemsPerKey: retainedDepth,
            maximumRetainedBytesPerKey: retainedDepth,
            maximumContributionsPerLease: retainedDepth,
            maximumItemsPerLease: retainedDepth,
            maximumBytesPerLease: min(retainedDepth, cleanupQuantum.maximumBytes!),
            cleanupQuantum: cleanupQuantum
        )
        let mailbox = BoundedGatherMailbox<Int, CleanupPayload>(
            generation: generation,
            declaredKeys: [0],
            limits: limits,
            clock: clock
        )
        mailboxBox.mailbox = mailbox
        let lifecycle = mailbox.lifecyclePort
        for contributionIndex in 0..<retainedDepth {
            _ = mailbox.producerPort.offer(
                generation: generation,
                contribution: GatherContribution(
                    key: 0,
                    payload: makeGatherPayload(
                        identifier: "gather-secret-\(contributionIndex)",
                        mailboxBox: mailboxBox,
                        recorder: recorder
                    ),
                    footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                    recoverySignal: .ordinary
                )
            )
        }
        clock.advance(by: .seconds(2))

        // Act
        _ = mailbox.producerPort.offer(
            generation: generation,
            contribution: GatherContribution(
                key: 0,
                payload: CleanupPayload(identifier: "incoming-pressure") {},
                footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                recoverySignal: .ordinary
            )
        )
        let releasesAfterProducerReturn = recorder.identifiers
        let invalidation = lifecycle.invalidate(generation: generation)
        clock.advance(by: .seconds(3))
        let cleanupBeforeTurns = gatherSnapshot(lifecycle.diagnostics)

        // Assert
        #expect(releasesAfterProducerReturn.isEmpty)
        #expect(invalidation == .applied)
        #expect(recorder.identifiers.isEmpty)
        expectCleanupOnlySnapshot(
            cleanupBeforeTurns,
            entries: retainedDepth,
            bytes: retainedDepth,
            oldestAge: .seconds(5)
        )
        #expect(lifecycle.diagnostics.cleanupItemCount == retainedDepth)
        #expect(lifecycle.diagnostics.cleanupMetadataEntryCount == 1)
        #expect(lifecycle.diagnostics.physicalRetainedItemCount == retainedDepth)
        #expect(lifecycle.diagnostics.cleanupItemHighWater == retainedDepth)
        #expect(lifecycle.diagnostics.physicalRetainedItemHighWater == retainedDepth)
        expectDiagnosticsExcludePayloads(lifecycle.diagnostics, marker: "gather-secret-")
        performAllCleanup(
            expectedEntries: retainedDepth,
            expectedNonPayloadEntries: 1,
            expectedBytes: retainedDepth,
            quantum: cleanupQuantum,
            recorder: recorder,
            performCleanup: { lifecycle.performCleanup(generation: generation) },
            diagnostics: { gatherSnapshot(lifecycle.diagnostics) }
        )
    }

    @Test("journal eviction and invalidation preserve bounded physical custody", arguments: [1, 100, 300])
    func journalEvictionAndInvalidationPreserveBoundedPhysicalCustody(retainedDepth: Int) throws {
        // Arrange
        let generation = AdmissionGeneration(owner: .runtimeFacts, value: 73)
        let clock = TestPushClock()
        let recorder = CleanupReleaseRecorder()
        let journalBox = JournalCleanupMailboxBox()
        let cleanupQuantum = AdmissionCleanupQuantum(
            maximumEntries: 17,
            maximumBytes: retainedDepth
        )
        let journal = try OrderedFactJournal<CleanupPayload, CleanupSnapshot>(
            generation: generation,
            maximumRetainedFacts: retainedDepth,
            maximumRetainedBytes: retainedDepth,
            snapshotLimits: OrderedFactSnapshotLimits(
                maximumSnapshotBytes: retainedDepth,
                maximumPhysicalSnapshotCount: Int.max,
                maximumPhysicalSnapshotBytes: Int.max
            ),
            maximumDrainFacts: retainedDepth,
            cleanupQuantum: cleanupQuantum,
            initialSnapshot: nil,
            initialSnapshotBytes: 0,
            admissionClock: .make(clock: clock)
        )
        journalBox.journal = journal
        let consumer = journal.consumerPort
        let lifecycle = journal.lifecyclePort
        let binding = consumer.bindConsumer().binding
        for factIndex in 0..<retainedDepth {
            _ = journal.producerPort.offer(
                generation: generation,
                fact: makeJournalPayload(
                    identifier: "journal-secret-\(factIndex)",
                    journalBox: journalBox,
                    recorder: recorder
                ),
                estimatedFactBytes: 1,
                snapshotReplacement: nil
            )
        }
        let drainToken = try requireJournalDrainToken(
            consumer.takeDrain(binding: binding, generation: generation)
        )
        _ = consumer.acknowledge(drainToken, disposition: .transferred)
        clock.advance(by: .seconds(2))

        // Act
        _ = journal.producerPort.offer(
            generation: generation,
            fact: CleanupPayload(identifier: "incoming-pressure") {},
            estimatedFactBytes: retainedDepth,
            snapshotReplacement: nil
        )
        let releasesAfterProducerReturn = recorder.identifiers
        let invalidation = lifecycle.invalidate(generation: generation)
        clock.advance(by: .seconds(3))
        let cleanupBeforeTurns = journalSnapshot(lifecycle.diagnostics)

        // Assert
        #expect(releasesAfterProducerReturn.isEmpty)
        #expect(invalidation == .applied)
        #expect(recorder.identifiers.isEmpty)
        expectCleanupOnlySnapshot(
            cleanupBeforeTurns,
            entries: retainedDepth,
            bytes: retainedDepth,
            oldestAge: .seconds(5)
        )
        expectDiagnosticsExcludePayloads(lifecycle.diagnostics, marker: "journal-secret-")
        performAllCleanup(
            expectedEntries: retainedDepth,
            expectedBytes: retainedDepth,
            quantum: cleanupQuantum,
            recorder: recorder,
            performCleanup: { lifecycle.performCleanup(generation: generation) },
            diagnostics: { journalSnapshot(lifecycle.diagnostics) }
        )
    }
}

private struct CleanupCustodySnapshot: Equatable {
    let semanticEntryCount: Int
    let pendingEntryCount: Int
    let leasedEntryCount: Int
    let cleanupEntryCount: Int
    let physicalEntryCount: Int
    let semanticByteCount: Int?
    let cleanupByteCount: Int?
    let physicalByteCount: Int?
    let semanticEntryHighWater: Int
    let cleanupEntryHighWater: Int
    let physicalEntryHighWater: Int
    let semanticByteHighWater: Int?
    let cleanupByteHighWater: Int?
    let physicalByteHighWater: Int?
    let oldestCleanupAge: AdmissionAgeMeasurement?
    let isQuiescent: Bool
}

private final class CleanupPayload: @unchecked Sendable {
    let identifier: String
    private let onDeinitialize: @Sendable () -> Void

    init(identifier: String, onDeinitialize: @escaping @Sendable () -> Void) {
        self.identifier = identifier
        self.onDeinitialize = onDeinitialize
    }

    deinit {
        onDeinitialize()
    }
}

private struct CleanupSnapshot: Sendable {
    let payload: CleanupPayload
}

private final class CleanupReleaseRecorder: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [String]())

    func record(_ identifier: String) {
        lock.withLock { $0.append(identifier) }
    }

    var identifiers: [String] {
        lock.withLock { $0 }
    }
}

private final class LatestCleanupMailboxBox: @unchecked Sendable {
    weak var mailbox: LatestValueMailbox<Int, CleanupPayload>?
}

private final class GatherCleanupMailboxBox: @unchecked Sendable {
    weak var mailbox: BoundedGatherMailbox<Int, CleanupPayload>?
}

private final class JournalCleanupMailboxBox: @unchecked Sendable {
    weak var journal: OrderedFactJournal<CleanupPayload, CleanupSnapshot>?
}

private func makeLatestPayload(
    identifier: String,
    mailboxBox: LatestCleanupMailboxBox,
    recorder: CleanupReleaseRecorder
) -> CleanupPayload {
    CleanupPayload(identifier: identifier) {
        _ = mailboxBox.mailbox?.lifecyclePort.diagnostics
        recorder.record(identifier)
    }
}

private func makeGatherPayload(
    identifier: String,
    mailboxBox: GatherCleanupMailboxBox,
    recorder: CleanupReleaseRecorder
) -> CleanupPayload {
    CleanupPayload(identifier: identifier) {
        _ = mailboxBox.mailbox?.lifecyclePort.diagnostics
        recorder.record(identifier)
    }
}

private func makeJournalPayload(
    identifier: String,
    journalBox: JournalCleanupMailboxBox,
    recorder: CleanupReleaseRecorder
) -> CleanupPayload {
    CleanupPayload(identifier: identifier) {
        _ = journalBox.journal?.lifecyclePort.diagnostics
        recorder.record(identifier)
    }
}

private func requireLatestDrainToken(
    _ result: LatestValueDrainResult<Int, CleanupPayload>
) throws -> AdmissionDrainToken {
    guard case .drain(let drain) = result else {
        throw CleanupCustodyTestError.expectedLatestDrain
    }
    return drain.token
}

private func requireJournalDrainToken(
    _ result: OrderedFactTakeDrainResult<CleanupPayload>
) throws -> AdmissionDrainToken {
    guard case .drain(let drain) = result else {
        throw CleanupCustodyTestError.expectedJournalDrain
    }
    return drain.token
}

private enum CleanupCustodyTestError: Error {
    case expectedLatestDrain
    case expectedJournalDrain
}

private func latestSnapshot(_ diagnostics: LatestValueAdmissionDiagnostics) -> CleanupCustodySnapshot {
    CleanupCustodySnapshot(
        semanticEntryCount: diagnostics.semanticRetainedValueCount,
        pendingEntryCount: diagnostics.pendingValueCount,
        leasedEntryCount: diagnostics.leasedValueCount,
        cleanupEntryCount: diagnostics.cleanupValueCount,
        physicalEntryCount: diagnostics.physicalRetainedValueCount,
        semanticByteCount: nil,
        cleanupByteCount: nil,
        physicalByteCount: nil,
        semanticEntryHighWater: diagnostics.semanticRetainedValueHighWater,
        cleanupEntryHighWater: diagnostics.cleanupValueHighWater,
        physicalEntryHighWater: diagnostics.physicalRetainedValueHighWater,
        semanticByteHighWater: nil,
        cleanupByteHighWater: nil,
        physicalByteHighWater: nil,
        oldestCleanupAge: diagnostics.oldestCleanupAge,
        isQuiescent: diagnostics.isQuiescent
    )
}

private func gatherSnapshot(_ diagnostics: GatherAdmissionDiagnostics) -> CleanupCustodySnapshot {
    CleanupCustodySnapshot(
        semanticEntryCount: diagnostics.retainedContributionCount,
        pendingEntryCount: diagnostics.pendingContributionCount,
        leasedEntryCount: diagnostics.leasedContributionCount,
        cleanupEntryCount: diagnostics.cleanupContributionCount,
        physicalEntryCount: diagnostics.physicalRetainedContributionCount,
        semanticByteCount: diagnostics.retainedByteCount,
        cleanupByteCount: diagnostics.cleanupByteCount,
        physicalByteCount: diagnostics.physicalRetainedByteCount,
        semanticEntryHighWater: diagnostics.retainedContributionHighWater,
        cleanupEntryHighWater: diagnostics.cleanupContributionHighWater,
        physicalEntryHighWater: diagnostics.physicalRetainedContributionHighWater,
        semanticByteHighWater: diagnostics.retainedByteHighWater,
        cleanupByteHighWater: diagnostics.cleanupByteHighWater,
        physicalByteHighWater: diagnostics.physicalRetainedByteHighWater,
        oldestCleanupAge: diagnostics.oldestCleanupAge,
        isQuiescent: diagnostics.isQuiescent
    )
}

private func journalSnapshot(_ diagnostics: OrderedFactJournalDiagnostics) -> CleanupCustodySnapshot {
    CleanupCustodySnapshot(
        semanticEntryCount: diagnostics.retainedFactCount,
        pendingEntryCount: diagnostics.pendingFactCount,
        leasedEntryCount: diagnostics.leasedFactCount,
        cleanupEntryCount: diagnostics.cleanupFactCount,
        physicalEntryCount: diagnostics.physicalRetainedFactCount,
        semanticByteCount: diagnostics.retainedByteCount,
        cleanupByteCount: diagnostics.cleanupByteCount,
        physicalByteCount: diagnostics.physicalRetainedByteCount,
        semanticEntryHighWater: diagnostics.retainedFactHighWater,
        cleanupEntryHighWater: diagnostics.cleanupFactHighWater,
        physicalEntryHighWater: diagnostics.physicalRetainedFactHighWater,
        semanticByteHighWater: diagnostics.retainedByteHighWater,
        cleanupByteHighWater: diagnostics.cleanupByteHighWater,
        physicalByteHighWater: diagnostics.physicalRetainedByteHighWater,
        oldestCleanupAge: diagnostics.oldestCleanupAge,
        isQuiescent: diagnostics.isQuiescent
    )
}

private func expectCleanupOnlySnapshot(
    _ snapshot: CleanupCustodySnapshot,
    entries: Int,
    bytes: Int?,
    oldestAge: Duration
) {
    #expect(snapshot.semanticEntryCount == 0)
    #expect(snapshot.pendingEntryCount == 0)
    #expect(snapshot.leasedEntryCount == 0)
    #expect(snapshot.cleanupEntryCount == entries)
    #expect(snapshot.physicalEntryCount == entries)
    #expect(snapshot.semanticEntryCount == snapshot.pendingEntryCount + snapshot.leasedEntryCount)
    #expect(snapshot.physicalEntryCount == snapshot.semanticEntryCount + snapshot.cleanupEntryCount)
    #expect(snapshot.semanticByteCount == 0 || snapshot.semanticByteCount == nil)
    #expect(snapshot.cleanupByteCount == bytes)
    #expect(snapshot.physicalByteCount == bytes)
    #expect(snapshot.semanticEntryHighWater == entries)
    #expect(snapshot.cleanupEntryHighWater == entries)
    #expect(snapshot.physicalEntryHighWater == entries)
    #expect(snapshot.semanticByteHighWater == bytes)
    #expect(snapshot.cleanupByteHighWater == bytes)
    #expect(snapshot.physicalByteHighWater == bytes)
    #expect(snapshot.oldestCleanupAge == .exact(oldestAge))
    #expect(snapshot.isQuiescent == false)
}

private func performAllCleanup(
    expectedEntries: Int,
    expectedNonPayloadEntries: Int = 0,
    expectedBytes: Int?,
    quantum: AdmissionCleanupQuantum,
    recorder: CleanupReleaseRecorder,
    performCleanup: () -> AdmissionCleanupTurnResult,
    diagnostics: () -> CleanupCustodySnapshot
) {
    let expectedTotalEntries = expectedEntries + expectedNonPayloadEntries
    var releasedEntries = 0
    var releasedNonPayloadEntries = 0
    var releasedBytes = 0
    var observedFollowUpWake = false
    cleanupLoop: for _ in 0...expectedTotalEntries {
        let releasedBeforeTurn = recorder.identifiers.count
        switch performCleanup() {
        case .performed(let turn):
            #expect(turn.releasedEntryCount > 0)
            #expect(turn.releasedEntryCount <= quantum.maximumEntries)
            let releasedPayloadEntries = recorder.identifiers.count - releasedBeforeTurn
            #expect(releasedPayloadEntries <= turn.releasedEntryCount)
            releasedNonPayloadEntries += turn.releasedEntryCount - releasedPayloadEntries
            releasedEntries += turn.releasedEntryCount
            if let maximumBytes = quantum.maximumBytes {
                #expect(turn.releasedByteCount != nil)
                #expect(turn.releasedByteCount! <= maximumBytes)
                releasedBytes += turn.releasedByteCount!
            } else {
                #expect(turn.releasedByteCount == nil)
            }
            if releasedEntries < expectedTotalEntries {
                #expect(turn.wake == .scheduleDrain)
                observedFollowUpWake = true
            } else {
                #expect(turn.wake == .noWake)
            }
        case .empty:
            break cleanupLoop
        case .staleGeneration:
            Issue.record("Cleanup unexpectedly rejected the current generation")
            break cleanupLoop
        case .alreadyCleaning:
            Issue.record("Cleanup unexpectedly found another active cleanup turn")
            break cleanupLoop
        case .blockedByReplayReader:
            Issue.record("Cleanup unexpectedly found an active replay reader")
            break cleanupLoop
        }
    }

    #expect(releasedEntries == expectedTotalEntries)
    #expect(releasedNonPayloadEntries == expectedNonPayloadEntries)
    #expect(expectedBytes == nil || releasedBytes == expectedBytes)
    let expectsFollowUpWake =
        expectedTotalEntries > quantum.maximumEntries
        || expectedNonPayloadEntries > 0
    #expect(observedFollowUpWake == expectsFollowUpWake)
    #expect(performCleanup() == .empty)
    let finalSnapshot = diagnostics()
    #expect(finalSnapshot.semanticEntryCount == 0)
    #expect(finalSnapshot.cleanupEntryCount == 0)
    #expect(finalSnapshot.physicalEntryCount == 0)
    #expect(finalSnapshot.isQuiescent)
}

private func expectDiagnosticsExcludePayloads<Diagnostics>(
    _ diagnostics: Diagnostics,
    marker: String
) {
    #expect(String(reflecting: diagnostics).contains(marker) == false)
}
