import Foundation
import Testing

@testable import AgentStudio

@Suite("Admission OrderedFactJournal Corrections")
struct AdmissionOrderedFactJournalCorrectionTests {
    @Test("negative initial snapshot size is a distinct configuration rejection")
    func negativeInitialSnapshotSizeIsRejected() {
        // Arrange
        let generation = makeGeneration(1)

        // Act
        let result: Result<OrderedFactJournal<JournalFact, JournalSnapshot>, Error>
        do {
            result = .success(
                try makeJournalValidatingInitialSnapshot(
                    generation: generation,
                    maximumSnapshotBytes: 16,
                    initialSnapshotReplacement: OrderedFactSnapshotReplacement(
                        snapshot: JournalSnapshot(value: "must-not-become-current"),
                        estimatedBytes: -1
                    )
                ))
        } catch {
            result = .failure(error)
        }

        // Assert
        guard case .failure(let error) = result else {
            Issue.record("Expected a negative initial snapshot size to reject configuration")
            return
        }
        #expect(
            error as? OrderedFactJournalConfigurationError
                == .initialSnapshotInvalidSize
        )
    }

    @Test("negative fact size rejects before sequence state wake and counter mutation")
    func negativeFactSizeIsAtomicInvalidSizeRejection() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(generation: generation)

        // Act
        let rejected = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: -1,
            snapshotReplacement: nil
        )
        let stateAfterRejection = try #require(
            currentState(journal.consumer.currentState(generation: generation))
        )
        let diagnosticsAfterRejection = journal.lifecycle.diagnostics
        let firstAccepted = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 1,
            snapshotReplacement: nil
        )

        // Assert
        guard case .invalidSize = rejected else {
            Issue.record("Expected a typed invalid-size fact rejection")
            return
        }
        #expect(stateAfterRejection.latestSequence == 0)
        #expect(stateAfterRejection.snapshot == nil)
        #expect(diagnosticsAfterRejection.admission.offered == 1)
        #expect(diagnosticsAfterRejection.admission.admitted == 0)
        #expect(diagnosticsAfterRejection.admission.rejectedInvalid == 1)
        #expect(diagnosticsAfterRejection.retainedFactCount == 0)
        #expect(diagnosticsAfterRejection.currentness == .current)
        #expect(admittedSequence(firstAccepted) == 1)
        #expect(admittedWake(firstAccepted) == .scheduleDrain)
    }

    @Test("negative atomic snapshot size rejects the whole offer before mutation")
    func negativeAtomicSnapshotSizeIsAtomicInvalidSizeRejection() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(generation: generation)

        // Act
        let rejected = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 1,
            snapshotReplacement: OrderedFactSnapshotReplacement(
                snapshot: JournalSnapshot(value: "must-not-become-current"),
                estimatedBytes: -1
            )
        )
        let stateAfterRejection = try #require(
            currentState(journal.consumer.currentState(generation: generation))
        )
        let diagnosticsAfterRejection = journal.lifecycle.diagnostics
        let firstAccepted = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 1,
            snapshotReplacement: nil
        )

        // Assert
        guard case .invalidSize = rejected else {
            Issue.record("Expected a typed invalid-size atomic snapshot rejection")
            return
        }
        #expect(stateAfterRejection.latestSequence == 0)
        #expect(stateAfterRejection.snapshot == nil)
        #expect(diagnosticsAfterRejection.admission.offered == 1)
        #expect(diagnosticsAfterRejection.admission.admitted == 0)
        #expect(diagnosticsAfterRejection.admission.rejectedInvalid == 1)
        #expect(diagnosticsAfterRejection.retainedFactCount == 0)
        #expect(diagnosticsAfterRejection.currentness == .current)
        #expect(admittedSequence(firstAccepted) == 1)
        #expect(admittedWake(firstAccepted) == .scheduleDrain)
    }

    @Test("negative recovery snapshot size preserves the exact current gap and wake level")
    func negativeRecoverySnapshotSizePreservesGapAndWakeState() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: 0
        )
        let firstOffer = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 1,
            snapshotReplacement: nil
        )
        let firstGap = try #require(gapCommittedResult(firstOffer)).gap
        let gapDrain = try #require(
            persistentGapDrain(
                journal.consumer.takeDrain(
                    binding: journal.binding,
                    generation: generation
                )
            )
        )
        #expect(
            journal.consumer.acknowledge(gapDrain.token, disposition: .transferred)
                == .accepted(wake: .noWake)
        )

        // Act
        let rejected = journal.consumer.resynchronize(
            generation: generation,
            gapToken: firstGap.token,
            throughSequence: firstGap.missingSequences.upperBound,
            snapshot: JournalSnapshot(value: "must-not-become-current"),
            estimatedSnapshotBytes: -1
        )
        let gapAfterRejection = try #require(
            nonCurrentGap(journal.consumer.currentState(generation: generation))
        )
        let diagnosticsAfterRejection = journal.lifecycle.diagnostics
        let laterOffer = journal.producer.offer(
            generation: generation,
            fact: .closed,
            estimatedFactBytes: 1,
            snapshotReplacement: nil
        )
        let widenedGap = try #require(gapCommittedResult(laterOffer))

        // Assert
        #expect(rejected == .invalidSize)
        #expect(gapAfterRejection == firstGap)
        #expect(diagnosticsAfterRejection.latestSequence == 1)
        #expect(diagnosticsAfterRejection.currentness == .nonCurrent(firstGap))
        #expect(diagnosticsAfterRejection.admission.offered == 1)
        #expect(diagnosticsAfterRejection.admission.admitted == 1)
        #expect(diagnosticsAfterRejection.admission.rejectedInvalid == 0)
        #expect(widenedGap.gap.missingSequences == 1...2)
        #expect(widenedGap.wake == .scheduleDrain)
    }

    @Test("replay capture fixes its stop tail and survives later invalidation")
    func replayCaptureLinearizesBeforeLaterOfferAndInvalidation() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: 8
        )
        _ = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 1,
            snapshotReplacement: nil
        )
        _ = journal.producer.offer(
            generation: generation,
            fact: .command("captured-tail"),
            estimatedFactBytes: 1,
            snapshotReplacement: nil
        )

        // Act: capture is the deterministic barrier before later mutations.
        let capture = journal.journal.captureReplay(
            after: 0,
            generation: generation,
            recovery: .exactHistory
        )
        let diagnosticsAfterCapture = journal.lifecycle.diagnostics
        _ = journal.producer.offer(
            generation: generation,
            fact: .closed,
            estimatedFactBytes: 1,
            snapshotReplacement: nil
        )
        #expect(journal.lifecycle.invalidate(generation: generation) == .applied)
        let diagnosticsAfterInvalidation = journal.lifecycle.diagnostics
        let completion = journal.journal.completeReplay(capture)
        let diagnosticsAfterCompletion = journal.lifecycle.diagnostics

        // Assert
        guard case .registered(let replayResult, let wake) = completion,
            case .facts(let facts, let nextSequence) = replayResult
        else {
            Issue.record("Expected the pre-invalidation replay reader to finish exact history")
            return
        }
        #expect(
            sequenceOracle(facts) == [
                .init(sequence: 1, fact: .started),
                .init(sequence: 2, fact: .command("captured-tail")),
            ]
        )
        #expect(nextSequence == 2)
        #expect(diagnosticsAfterCapture.activeReplayReaderCount == 1)
        #expect(diagnosticsAfterInvalidation.activeReplayReaderCount == 1)
        #expect(diagnosticsAfterCompletion.activeReplayReaderCount == 0)
        #expect(wake == .scheduleDrain)
    }

    @Test("replay capture after invalidation registers no reader authority")
    func replayCaptureAfterInvalidationIsRejected() {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(generation: generation)
        #expect(journal.lifecycle.invalidate(generation: generation) == .applied)
        let diagnosticsBeforeCapture = journal.lifecycle.diagnostics

        // Act
        let rejectedCapture = journal.journal.captureReplay(
            after: 0,
            generation: generation,
            recovery: .exactHistory
        )
        let diagnosticsAfterCapture = journal.lifecycle.diagnostics
        let completion = journal.journal.completeReplay(rejectedCapture)
        let diagnosticsAfterCompletion = journal.lifecycle.diagnostics

        // Assert
        guard case .immediate(.invalidated) = completion else {
            Issue.record("Expected replay capture after invalidation to be rejected")
            return
        }
        #expect(diagnosticsBeforeCapture.activeReplayReaderCount == 0)
        #expect(diagnosticsAfterCapture.activeReplayReaderCount == 0)
        #expect(diagnosticsAfterCompletion.activeReplayReaderCount == 0)
    }
}
