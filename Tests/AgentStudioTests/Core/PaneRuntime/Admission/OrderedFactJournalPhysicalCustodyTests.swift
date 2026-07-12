import Foundation
import Testing

@testable import AgentStudio

@Suite("Admission OrderedFactJournal Physical Custody")
struct AdmissionOrderedFactJournalPhysicalCustodyTests {
    private enum SnapshotConfigurationOutcome: Equatable {
        case accepted
        case rejected(OrderedFactJournalConfigurationError)
    }

    private struct AdmissionCounterSnapshot: Equatable {
        let offered: UInt64
        let admitted: UInt64
        let contracted: UInt64
        let rejectedStale: UInt64
        let rejectedUndeclared: UInt64
        let rejectedInvalid: UInt64
        let rejectedCapacity: UInt64
        let rejectedClosed: UInt64
        let repairEscalations: UInt64

        init(_ diagnostics: AdmissionDiagnostics) {
            offered = diagnostics.offered
            admitted = diagnostics.admitted
            contracted = diagnostics.contracted
            rejectedStale = diagnostics.rejectedStale
            rejectedUndeclared = diagnostics.rejectedUndeclared
            rejectedInvalid = diagnostics.rejectedInvalid
            rejectedCapacity = diagnostics.rejectedCapacity
            rejectedClosed = diagnostics.rejectedClosed
            repairEscalations = diagnostics.repairEscalations
        }
    }

    @Test("zero-byte snapshots consume bounded physical count and recover after cleanup")
    func zeroByteSnapshotsConsumePhysicalCountAndRecoverAfterCleanup() {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedBytes: 0,
            maximumSnapshotBytes: 0,
            snapshotLimits: OrderedFactSnapshotLimits(
                maximumSnapshotBytes: 0,
                maximumPhysicalSnapshotCount: 2,
                maximumPhysicalSnapshotBytes: 0
            ),
            cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 1, maximumBytes: 1),
            initialSnapshotBytes: 0
        )

        // Act
        let first = offerSnapshot("first", bytes: 0, to: journal, generation: generation)
        let second = offerSnapshot("second", bytes: 0, to: journal, generation: generation)
        let beforeRejection = journal.lifecycle.diagnostics
        let rejected = offerSnapshot("rejected", bytes: 0, to: journal, generation: generation)
        let afterRejection = journal.lifecycle.diagnostics
        let cleanup = journal.lifecycle.performCleanup(generation: generation)
        let recovered = offerSnapshot("recovered", bytes: 0, to: journal, generation: generation)

        // Assert
        #expect(admittedSequence(first) == 1)
        #expect(admittedSequence(second) == 2)
        guard case .snapshotPhysicalCapacityExceeded = rejected else {
            Issue.record("Expected zero-byte physical-count rejection")
            return
        }
        #expect(beforeRejection.latestSequence == afterRejection.latestSequence)
        #expect(afterRejection.admission.offered == beforeRejection.admission.offered + 1)
        #expect(
            afterRejection.admission.rejectedCapacity
                == beforeRejection.admission.rejectedCapacity + 1
        )
        #expect(beforeRejection.admission.admitted == afterRejection.admission.admitted)
        #expect(beforeRejection.cleanupByteCount == afterRejection.cleanupByteCount)
        #expect(cleanup == .performed(.init(releasedEntryCount: 1, releasedByteCount: 0, wake: .noWake)))
        #expect(admittedSequence(recovered) == 3)
    }

    @Test("offer snapshot count and byte pressure reject atomically before sequence")
    func offerSnapshotPhysicalPressureIsAtomic() {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedBytes: 0,
            maximumSnapshotBytes: 8,
            snapshotLimits: OrderedFactSnapshotLimits(
                maximumSnapshotBytes: 8,
                maximumPhysicalSnapshotCount: 3,
                maximumPhysicalSnapshotBytes: 16
            ),
            cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 4, maximumBytes: 8)
        )
        _ = offerSnapshot("maximum", bytes: 8, to: journal, generation: generation)
        _ = offerSnapshot("second-maximum", bytes: 8, to: journal, generation: generation)
        let before = journal.lifecycle.diagnostics

        // Act
        let rejected = offerSnapshot("bound-plus-one", bytes: 1, to: journal, generation: generation)
        let after = journal.lifecycle.diagnostics
        let next = journal.producer.offer(
            generation: generation,
            fact: .finished(0),
            estimatedFactBytes: 0,
            snapshotReplacement: nil
        )

        // Assert
        guard case .snapshotPhysicalCapacityExceeded = rejected else {
            Issue.record("Expected physical snapshot-byte rejection")
            return
        }
        #expect(before.latestSequence == 2)
        #expect(after.latestSequence == before.latestSequence)
        #expect(after.admission.offered == before.admission.offered + 1)
        #expect(after.admission.rejectedCapacity == before.admission.rejectedCapacity + 1)
        #expect(after.admission.admitted == before.admission.admitted)
        #expect(after.cleanupByteCount == before.cleanupByteCount)
        #expect(admittedSequence(next) == 3)
    }

    @Test("snapshot configuration guarantees one maximum-size replacement overlap")
    func snapshotConfigurationGuaranteesMaximumReplacementOverlap() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = try OrderedFactJournal<JournalFact, JournalSnapshot>(
            generation: generation,
            maximumRetainedFacts: 4,
            maximumRetainedBytes: 8,
            snapshotLimits: OrderedFactSnapshotLimits(
                maximumSnapshotBytes: 8,
                maximumPhysicalSnapshotCount: 2,
                maximumPhysicalSnapshotBytes: 16
            ),
            maximumDrainFacts: 4,
            cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 1, maximumBytes: 8),
            initialSnapshot: nil,
            initialSnapshotBytes: 0
        )

        // Act
        let first = journal.producerPort.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 0,
            snapshotReplacement: snapshotReplacement("first-maximum", bytes: 8)
        )
        let replacement = journal.producerPort.offer(
            generation: generation,
            fact: .finished(0),
            estimatedFactBytes: 0,
            snapshotReplacement: snapshotReplacement("second-maximum", bytes: 8)
        )

        // Assert
        #expect(admittedSequence(first) == 1)
        #expect(admittedSequence(replacement) == 2)
        #expect(journal.lifecyclePort.diagnostics.physicalRetainedSnapshotCount == 2)
        #expect(journal.lifecyclePort.diagnostics.physicalRetainedSnapshotByteCount == 16)
    }

    @Test("snapshot configuration rejects insufficient and overflowing overlap budgets")
    func snapshotConfigurationRejectsInvalidOverlapBudgets() {
        // Arrange / Act
        let insufficientCount = snapshotConfigurationError(
            maximumSnapshotBytes: 8,
            maximumPhysicalSnapshotCount: 1,
            maximumPhysicalSnapshotBytes: 16
        )
        let insufficientBytes = snapshotConfigurationError(
            maximumSnapshotBytes: 8,
            maximumPhysicalSnapshotCount: 2,
            maximumPhysicalSnapshotBytes: 15
        )
        let overflowingProduct = snapshotConfigurationError(
            maximumSnapshotBytes: Int.max,
            maximumPhysicalSnapshotCount: 2,
            maximumPhysicalSnapshotBytes: Int.max
        )

        // Assert
        #expect(insufficientCount == .rejected(.invalidSnapshotLimits))
        #expect(insufficientBytes == .rejected(.invalidSnapshotLimits))
        #expect(overflowingProduct == .rejected(.invalidSnapshotLimits))
    }

    @Test("queued cleanup precedes creation of a journal delivery lease")
    func queuedCleanupPrecedesNewDeliveryLease() {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedBytes: 8,
            maximumSnapshotBytes: 8,
            snapshotLimits: OrderedFactSnapshotLimits(
                maximumSnapshotBytes: 8,
                maximumPhysicalSnapshotCount: 2,
                maximumPhysicalSnapshotBytes: 16
            ),
            cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 1, maximumBytes: 8)
        )
        _ = offerSnapshot("first", bytes: 8, to: journal, generation: generation)
        _ = offerSnapshot("second", bytes: 8, to: journal, generation: generation)
        let binding = journal.consumer.bindConsumer().binding

        // Act
        let blocked = journal.consumer.takeDrain(binding: binding, generation: generation)
        let beforeCleanup = journal.lifecycle.diagnostics
        let cleanup = journal.consumer.performCleanup(generation: generation)
        let delivery = journal.consumer.takeDrain(binding: binding, generation: generation)

        // Assert
        guard case .cleanupRequired = blocked else {
            Issue.record("Expected queued cleanup to precede a new journal lease")
            return
        }
        #expect(beforeCleanup.leasedFactCount == 0)
        guard case .performed = cleanup else {
            Issue.record("Expected one bounded cleanup turn")
            return
        }
        guard case .drain = delivery else {
            Issue.record("Expected delivery after cleanup finalized")
            return
        }
    }

    @Test("recovery snapshot physical pressure preserves gap and succeeds after cleanup")
    func recoverySnapshotPhysicalPressureIsAtomicAndRecoverable() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: 0,
            maximumRetainedBytes: 0,
            maximumSnapshotBytes: 8,
            snapshotLimits: OrderedFactSnapshotLimits(
                maximumSnapshotBytes: 8,
                maximumPhysicalSnapshotCount: 2,
                maximumPhysicalSnapshotBytes: 16
            ),
            cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 1, maximumBytes: 8),
            initialSnapshot: JournalSnapshot(value: "initial"),
            initialSnapshotBytes: 8
        )
        let gapResult = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 0,
            snapshotReplacement: OrderedFactSnapshotReplacement(
                snapshot: JournalSnapshot(value: "replacement"),
                estimatedBytes: 8
            )
        )
        let gap = try #require(gapCommittedResult(gapResult)?.gap)
        let before = journal.lifecycle.diagnostics

        // Act
        let rejected = journal.consumer.resynchronize(
            generation: generation,
            gapToken: gap.token,
            throughSequence: gap.missingSequences.upperBound,
            snapshot: JournalSnapshot(value: "recovery"),
            estimatedSnapshotBytes: 8
        )
        let afterRejection = journal.lifecycle.diagnostics
        let cleanup = journal.lifecycle.performCleanup(generation: generation)
        let recovered = journal.consumer.resynchronize(
            generation: generation,
            gapToken: gap.token,
            throughSequence: gap.missingSequences.upperBound,
            snapshot: JournalSnapshot(value: "recovery"),
            estimatedSnapshotBytes: 8
        )

        // Assert
        #expect(rejected == .snapshotPhysicalCapacityExceeded)
        #expect(
            AdmissionCounterSnapshot(afterRejection.admission)
                == AdmissionCounterSnapshot(before.admission)
        )
        #expect(afterRejection.latestSequence == before.latestSequence)
        #expect(afterRejection.productGap == before.productGap)
        #expect(afterRejection.cleanupSnapshotCount == before.cleanupSnapshotCount)
        #expect(cleanup == .performed(.init(releasedEntryCount: 1, releasedByteCount: 8, wake: .noWake)))
        #expect(recovered == .recovered)
    }

    @Test("second replay reader is rejected without mutation")
    func secondReplayReaderIsMutationFreeReplayInProgress() {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(generation: generation)
        _ = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 1,
            snapshotReplacement: nil
        )
        let firstCapture = journal.journal.captureReplay(
            after: 0,
            generation: generation,
            recovery: .exactHistory
        )
        let before = journal.lifecycle.diagnostics

        // Act
        let secondCapture = journal.journal.captureReplay(
            after: 0,
            generation: generation,
            recovery: .exactHistory
        )
        let secondCompletion = journal.journal.completeReplay(secondCapture)
        let after = journal.lifecycle.diagnostics

        // Assert
        guard case .replayInProgress = secondCompletion.result else {
            Issue.record("Expected typed replay-reader contention")
            _ = journal.journal.completeReplay(firstCapture)
            return
        }
        #expect(secondCompletion.wake == .noWake)
        #expect(after.latestSequence == before.latestSequence)
        #expect(after.retainedFactCount == before.retainedFactCount)
        #expect(after.cleanupFactCount == before.cleanupFactCount)
        #expect(after.activeReplayReaderCount == 1)
        _ = journal.journal.completeReplay(firstCapture)
    }

    @Test("replay reader pins queued fact and snapshot cleanup until completion wake")
    func replayReaderPinsQueuedCleanupUntilCompletionWake() {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            initialSnapshot: JournalSnapshot(value: "captured"),
            initialSnapshotBytes: 1
        )
        _ = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 1,
            snapshotReplacement: nil
        )
        let capture = journal.journal.captureReplay(
            after: 0,
            generation: generation,
            recovery: .currentSnapshot
        )
        #expect(journal.lifecycle.invalidate(generation: generation) == .applied)
        let before = journal.lifecycle.diagnostics

        // Act
        let blocked = journal.lifecycle.performCleanup(generation: generation)
        let afterBlocked = journal.lifecycle.diagnostics
        let completion = journal.journal.completeReplay(capture)
        let cleanup = journal.lifecycle.performCleanup(generation: generation)

        // Assert
        #expect(blocked == .blockedByReplayReader)
        #expect(afterBlocked.cleanupFactCount == before.cleanupFactCount)
        #expect(before.cleanupFactCount == 1)
        #expect(afterBlocked.cleanupSnapshotCount == before.cleanupSnapshotCount)
        #expect(before.cleanupSnapshotCount == 1)
        #expect(afterBlocked.cleanupByteCount == before.cleanupByteCount)
        #expect(completion.wake == .scheduleDrain)
        guard case .facts = completion.result else {
            Issue.record("Expected captured fixed-tail replay after invalidation")
            return
        }
        guard case .performed = cleanup else {
            Issue.record("Expected reader completion to make cleanup eligible")
            return
        }
    }

    @Test("in-flight cleanup stays charged and finalizes while replay pins later cleanup")
    func inFlightCleanupIsExclusiveAcrossReplayOverlap() {
        // Arrange
        let generation = makeGeneration(1)
        let gate = JournalCleanupGate()
        let reentrantResult = JournalCleanupResultBox<AdmissionCleanupTurnResult>()
        let outerResult = JournalCleanupResultBox<AdmissionCleanupTurnResult>()
        let journalBox = ReentrantJournalBox()
        var blockingPayload: ReentrantJournalFact? = ReentrantJournalFact(
            identifier: "blocking-snapshot"
        ) {
            if let journal = journalBox.journal {
                reentrantResult.store(journal.lifecyclePort.performCleanup(generation: generation))
            }
            gate.entered.signal()
            gate.release.wait()
        }
        let journal: JournalTestHarness<ReentrantJournalFact, ReentrantJournalSnapshot> =
            JournalTestHarness(
                journal: try! OrderedFactJournal(
                    generation: generation,
                    maximumRetainedFacts: 4,
                    maximumRetainedBytes: 4,
                    snapshotLimits: OrderedFactSnapshotLimits(
                        maximumSnapshotBytes: 1,
                        maximumPhysicalSnapshotCount: 2,
                        maximumPhysicalSnapshotBytes: 2
                    ),
                    maximumDrainFacts: 1,
                    cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 1, maximumBytes: 4),
                    initialSnapshot: ReentrantJournalSnapshot(payload: blockingPayload!),
                    initialSnapshotBytes: 1
                ))
        journalBox.journal = journal.journal
        blockingPayload = nil
        _ = journal.producer.offer(
            generation: generation,
            fact: ReentrantJournalFact(identifier: "captured-fact") {},
            estimatedFactBytes: 1,
            snapshotReplacement: OrderedFactSnapshotReplacement(
                snapshot: ReentrantJournalSnapshot(
                    payload: ReentrantJournalFact(identifier: "later-snapshot") {}
                ),
                estimatedBytes: 1
            )
        )
        let binding = journal.consumer.bindConsumer().binding
        DispatchQueue(label: "agentstudio.tests.journal-cleanup").async {
            outerResult.store(journal.lifecycle.performCleanup(generation: generation))
            gate.completed.signal()
        }
        let enteredDestructor = gate.entered.wait(timeout: .now() + 2) == .success
        #expect(enteredDestructor)
        guard enteredDestructor else {
            gate.release.signal()
            return
        }
        let capacityRejected = journal.producer.offer(
            generation: generation,
            fact: ReentrantJournalFact(identifier: "capacity-rejected") {},
            estimatedFactBytes: 0,
            snapshotReplacement: OrderedFactSnapshotReplacement(
                snapshot: ReentrantJournalSnapshot(
                    payload: ReentrantJournalFact(identifier: "capacity-snapshot") {}
                ),
                estimatedBytes: 1
            )
        )
        let deliveryDuringCleanup = journal.consumer.takeDrain(binding: binding, generation: generation)
        let capture = journal.journal.captureReplay(
            after: 0,
            generation: generation,
            recovery: .exactHistory
        )
        #expect(journal.lifecycle.invalidate(generation: generation) == .applied)

        // Act
        let concurrent = journal.lifecycle.performCleanup(generation: generation)
        let during = journal.lifecycle.diagnostics
        gate.release.signal()
        #expect(gate.completed.wait(timeout: .now() + 2) == .success)
        let afterIncumbent = journal.lifecycle.diagnostics
        let blocked = journal.lifecycle.performCleanup(generation: generation)
        let completion = journal.journal.completeReplay(capture)

        // Assert
        #expect(reentrantResult.value == .alreadyCleaning)
        #expect(concurrent == .alreadyCleaning)
        expectCleanupRequired(deliveryDuringCleanup)
        guard case .snapshotPhysicalCapacityExceeded = capacityRejected else {
            Issue.record("Expected in-flight snapshot custody to preserve capacity pressure")
            return
        }
        #expect(during.outstandingCleanupTurnCount == 1)
        #expect(during.cleanupSnapshotCount == 2)
        #expect(during.physicalRetainedSnapshotCount == 2)
        #expect(outerResult.value == .performed(.init(releasedEntryCount: 1, releasedByteCount: 1, wake: .noWake)))
        #expect(afterIncumbent.outstandingCleanupTurnCount == 0)
        #expect(afterIncumbent.cleanupSnapshotCount == 1)
        #expect(blocked == .blockedByReplayReader)
        #expect(completion.wake == .scheduleDrain)
        guard case .facts = completion.result else {
            Issue.record("Expected captured replay to materialize after incumbent cleanup")
            return
        }
    }

    private func offerSnapshot(
        _ value: String,
        bytes: Int,
        to journal: JournalTestHarness<JournalFact, JournalSnapshot>,
        generation: AdmissionGeneration
    ) -> OrderedFactOfferResult {
        journal.producer.offer(
            generation: generation,
            fact: .command(value),
            estimatedFactBytes: 0,
            snapshotReplacement: OrderedFactSnapshotReplacement(
                snapshot: JournalSnapshot(value: value),
                estimatedBytes: bytes
            )
        )
    }

    private func expectCleanupRequired<Fact: Sendable>(
        _ result: OrderedFactTakeDrainResult<Fact>
    ) {
        guard case .cleanupRequired = result else {
            Issue.record("Expected in-flight cleanup to precede a new journal lease")
            return
        }
    }

    private func snapshotConfigurationError(
        maximumSnapshotBytes: Int,
        maximumPhysicalSnapshotCount: Int,
        maximumPhysicalSnapshotBytes: Int
    ) -> SnapshotConfigurationOutcome {
        do {
            _ = try OrderedFactJournal<JournalFact, JournalSnapshot>(
                generation: makeGeneration(1),
                maximumRetainedFacts: 1,
                maximumRetainedBytes: 1,
                snapshotLimits: OrderedFactSnapshotLimits(
                    maximumSnapshotBytes: maximumSnapshotBytes,
                    maximumPhysicalSnapshotCount: maximumPhysicalSnapshotCount,
                    maximumPhysicalSnapshotBytes: maximumPhysicalSnapshotBytes
                ),
                maximumDrainFacts: 1,
                cleanupQuantum: AdmissionCleanupQuantum(
                    maximumEntries: 1,
                    maximumBytes: maximumSnapshotBytes
                ),
                initialSnapshot: nil,
                initialSnapshotBytes: 0
            )
            return .accepted
        } catch let error as OrderedFactJournalConfigurationError {
            return .rejected(error)
        } catch {
            Issue.record("Unexpected journal configuration error: \(error)")
            return .accepted
        }
    }
}
