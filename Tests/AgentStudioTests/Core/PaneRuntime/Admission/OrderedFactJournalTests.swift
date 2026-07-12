import Foundation
import Testing

@testable import AgentStudio

@Suite("Admission OrderedFactJournal")
struct AdmissionOrderedFactJournalTests {
    @Test("offer commits the assigned sequence and replacement snapshot before returning")
    func offerCommitsSequenceAndSnapshotBeforeReturning() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(generation: generation)

        // Act
        let result = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: snapshotReplacement("running", bytes: 16)
        )

        // Assert
        let admitted = try #require(admittedResult(result))
        #expect(admitted.sequence == 1)
        #expect(admitted.wake == .scheduleDrain)

        let state = try #require(currentState(journal.consumer.currentState(generation: generation)))
        #expect(state.latestSequence == 1)
        #expect(state.snapshot?.throughSequence == 1)
        #expect(state.snapshot?.snapshot == JournalSnapshot(value: "running"))

        let replay = try #require(
            exactReplay(journal.consumer.replay(after: 0, generation: generation, recovery: .exactHistory)))
        #expect(replay.nextSequence == 1)
        #expect(sequenceOracle(replay.facts) == [.init(sequence: 1, fact: .started)])
    }

    @Test("a stale generation cannot advance sequence or mutate current state")
    func staleGenerationCannotAdvanceSequenceOrMutateSnapshot() throws {
        // Arrange
        let generation = makeGeneration(8)
        let staleGeneration = makeGeneration(7)
        let journal = makeJournal(
            generation: generation,
            initialSnapshot: JournalSnapshot(value: "idle")
        )

        // Act
        let result = journal.producer.offer(
            generation: staleGeneration,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: snapshotReplacement("wrong", bytes: 16)
        )

        // Assert
        #expect(isStaleGeneration(result))
        let state = try #require(currentState(journal.consumer.currentState(generation: generation)))
        #expect(state.latestSequence == 0)
        #expect(state.snapshot?.throughSequence == 0)
        #expect(state.snapshot?.snapshot == JournalSnapshot(value: "idle"))
        #expect(journal.lifecycle.diagnostics.admission.offered == 1)
        #expect(journal.lifecycle.diagnostics.admission.admitted == 0)
        #expect(journal.lifecycle.diagnostics.admission.rejectedStale == 1)
    }

    @Test("partial drains retry the identical literal sequence before later facts")
    func partialDrainRetryPreservesLiteralSequenceOracle() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: 8,
            maximumDrainFacts: 2
        )
        let expectedFirstDrain: [SequencedFactOracle] = [
            .init(sequence: 1, fact: .started),
            .init(sequence: 2, fact: .command("build")),
        ]
        let expectedSecondDrain: [SequencedFactOracle] = [
            .init(sequence: 3, fact: .finished(0)),
            .init(sequence: 4, fact: .closed),
        ]

        // Act
        let firstOffer = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let secondOffer = journal.producer.offer(
            generation: generation,
            fact: .command("build"),
            estimatedFactBytes: 16,
            snapshotReplacement: nil
        )
        let thirdOffer = journal.producer.offer(
            generation: generation,
            fact: .finished(0),
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let fourthOffer = journal.producer.offer(
            generation: generation,
            fact: .closed,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )

        let firstDrain = try #require(
            factDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))
        let retryResult = journal.consumer.acknowledge(firstDrain.token, disposition: .retry)
        let retriedDrain = try #require(
            factDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))
        let firstTransfer = journal.consumer.acknowledge(retriedDrain.token, disposition: .transferred)
        let secondDrain = try #require(
            factDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))

        // Assert
        #expect(admittedSequence(firstOffer) == 1)
        #expect(admittedSequence(secondOffer) == 2)
        #expect(admittedSequence(thirdOffer) == 3)
        #expect(admittedSequence(fourthOffer) == 4)
        #expect(sequenceOracle(firstDrain.facts) == expectedFirstDrain)
        #expect(retryResult == .accepted(wake: .scheduleDrain))
        #expect(sequenceOracle(retriedDrain.facts) == expectedFirstDrain)
        #expect(firstTransfer == .accepted(wake: .scheduleDrain))
        #expect(sequenceOracle(secondDrain.facts) == expectedSecondDrain)
    }

    @Test("unacknowledged count overflow commits a persistent range-bearing gap")
    func unacknowledgedCountOverflowCommitsPersistentGap() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: 2,
            maximumRetainedBytes: 1024
        )

        // Act
        _ = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: snapshotReplacement("running", bytes: 16)
        )
        _ = journal.producer.offer(
            generation: generation,
            fact: .command("build"),
            estimatedFactBytes: 16,
            snapshotReplacement: nil
        )
        let overflow = journal.producer.offer(
            generation: generation,
            fact: .finished(0),
            estimatedFactBytes: 8,
            snapshotReplacement: snapshotReplacement("finished", bytes: 16)
        )

        // Assert
        let committedGap = try #require(gapCommittedResult(overflow))
        #expect(committedGap.gap.generation == generation)
        #expect(committedGap.gap.missingSequences == 1...3)
        #expect(committedGap.wake == .noWake)

        let stateGap = try #require(nonCurrentGap(journal.consumer.currentState(generation: generation)))
        #expect(stateGap == committedGap.gap)
        #expect(journal.lifecycle.diagnostics.latestSequence == 3)
        #expect(journal.lifecycle.diagnostics.productGap == committedGap.gap)
        #expect(journal.lifecycle.diagnostics.admission.repairEscalations == 1)
    }

    @Test("unacknowledged byte overflow commits a gap even below the fact-count limit")
    func unacknowledgedByteOverflowCommitsPersistentGap() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: 8,
            maximumRetainedBytes: 24
        )

        // Act
        _ = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 16,
            snapshotReplacement: nil
        )
        let overflow = journal.producer.offer(
            generation: generation,
            fact: .command("build"),
            estimatedFactBytes: 16,
            snapshotReplacement: nil
        )

        // Assert
        let committedGap = try #require(gapCommittedResult(overflow))
        #expect(committedGap.gap.missingSequences == 1...2)
        #expect(journal.lifecycle.diagnostics.retainedFactCount == 0)
        #expect(journal.lifecycle.diagnostics.retainedByteCount <= 24)
        #expect(journal.lifecycle.diagnostics.productGap == committedGap.gap)
    }

    @Test("overflow supersedes an overlapping fact lease")
    func overflowSupersedesOverlappingLease() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: 2,
            maximumDrainFacts: 2
        )
        _ = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        _ = journal.producer.offer(
            generation: generation,
            fact: .command("build"),
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let leasedDrain = try #require(
            factDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))

        // Act
        let overflow = journal.producer.offer(
            generation: generation,
            fact: .finished(0),
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let staleAcknowledgement = journal.consumer.acknowledge(leasedDrain.token, disposition: .transferred)

        // Assert
        let committedGap = try #require(gapCommittedResult(overflow))
        #expect(committedGap.gap.missingSequences == 1...3)
        #expect(staleAcknowledgement == .invalidToken)
        performJournalCleanupToQuiescence(journal.lifecycle, generation: generation)
        let gapDrain = try #require(
            persistentGapDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))
        #expect(gapDrain.gap == committedGap.gap)
    }

    @Test("transferring a gap drain does not evict or clear repair debt")
    func transferredGapRemainsNonEvictable() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeGappedJournal(generation: generation)
        let gapBeforeDrain = try #require(nonCurrentGap(journal.consumer.currentState(generation: generation)))
        let drain = try #require(
            persistentGapDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))

        // Act
        let acknowledgement = journal.consumer.acknowledge(drain.token, disposition: .transferred)

        // Assert
        #expect(acknowledgement == .accepted(wake: .noWake))
        #expect(nonCurrentGap(journal.consumer.currentState(generation: generation)) == gapBeforeDrain)
        #expect(journal.lifecycle.diagnostics.productGap == gapBeforeDrain)
        #expect(isEmptyDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))
    }

    @Test("later offers widen the persistent gap and invalidate its captured token")
    func laterOffersWidenGapAndInvalidateCapturedToken() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeGappedJournal(generation: generation)
        let firstGap = try #require(nonCurrentGap(journal.consumer.currentState(generation: generation)))
        let firstGapDrain = try #require(
            persistentGapDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))

        // Act
        let widened = journal.producer.offer(
            generation: generation,
            fact: .closed,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let staleAcknowledgement = journal.consumer.acknowledge(firstGapDrain.token, disposition: .transferred)

        // Assert
        let widenedGap = try #require(gapCommittedResult(widened))
        #expect(widenedGap.gap.missingSequences == 1...4)
        #expect(widenedGap.gap.token != firstGap.token)
        #expect(widenedGap.wake == .scheduleDrain)
        #expect(staleAcknowledgement == .invalidToken)
        #expect(nonCurrentGap(journal.consumer.currentState(generation: generation)) == widenedGap.gap)
        let counters = journal.lifecycle.diagnostics.admission
        #expect(counters.offered == 4 && counters.admitted == 4)
        #expect(counters.contracted == 2 && counters.repairEscalations == 2)
    }

    @Test("only the current exact gap token and upper sequence can recover")
    func exactGapRecoveryIsRequired() throws {
        // Arrange
        let generation = makeGeneration(4)
        let staleGeneration = makeGeneration(3)
        let journal = makeGappedJournal(generation: generation)
        let firstGap = try #require(nonCurrentGap(journal.consumer.currentState(generation: generation)))
        let widenedOffer = journal.producer.offer(
            generation: generation,
            fact: .closed,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let currentGap = try #require(gapCommittedResult(widenedOffer)).gap

        // Act
        let staleGenerationResult = journal.consumer.resynchronize(
            generation: staleGeneration,
            gapToken: currentGap.token,
            throughSequence: currentGap.missingSequences.upperBound,
            snapshot: JournalSnapshot(value: "recovered"),
            estimatedSnapshotBytes: 16
        )
        let staleTokenResult = journal.consumer.resynchronize(
            generation: generation,
            gapToken: firstGap.token,
            throughSequence: currentGap.missingSequences.upperBound,
            snapshot: JournalSnapshot(value: "recovered"),
            estimatedSnapshotBytes: 16
        )
        let wrongUpperSequenceResult = journal.consumer.resynchronize(
            generation: generation,
            gapToken: currentGap.token,
            throughSequence: currentGap.missingSequences.upperBound - 1,
            snapshot: JournalSnapshot(value: "recovered"),
            estimatedSnapshotBytes: 16
        )
        let oversizedSnapshotResult = journal.consumer.resynchronize(
            generation: generation,
            gapToken: currentGap.token,
            throughSequence: currentGap.missingSequences.upperBound,
            snapshot: JournalSnapshot(value: "oversized"),
            estimatedSnapshotBytes: 2048
        )
        let recovered = journal.consumer.resynchronize(
            generation: generation,
            gapToken: currentGap.token,
            throughSequence: currentGap.missingSequences.upperBound,
            snapshot: JournalSnapshot(value: "recovered"),
            estimatedSnapshotBytes: 16
        )
        performJournalCleanupToQuiescence(journal.lifecycle, generation: generation)
        let nextOffer = journal.producer.offer(
            generation: generation,
            fact: .command("next"),
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )

        // Assert
        #expect(staleGenerationResult == .staleGeneration)
        #expect(staleTokenResult == .staleGapToken)
        #expect(wrongUpperSequenceResult == .incorrectSequence)
        #expect(oversizedSnapshotResult == .snapshotTooLarge)
        #expect(recovered == .recovered)
        #expect(admittedSequence(nextOffer) == 5)

        let state = try #require(currentState(journal.consumer.currentState(generation: generation)))
        #expect(state.latestSequence == 5)
        #expect(state.snapshot?.throughSequence == 4)
        #expect(state.snapshot?.snapshot == JournalSnapshot(value: "recovered"))
        #expect(journal.lifecycle.diagnostics.productGap == nil)
    }

    @Test("successful gap recovery preserves unavailable exact history when no fact records remain")
    func gapRecoveryPreservesUnavailableExactHistoryWithEmptyRecords() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeGappedJournal(generation: generation)
        let gap = try #require(nonCurrentGap(journal.consumer.currentState(generation: generation)))

        // Act
        let recovery = journal.consumer.resynchronize(
            generation: generation,
            gapToken: gap.token,
            throughSequence: gap.missingSequences.upperBound,
            snapshot: JournalSnapshot(value: "recovered"),
            estimatedSnapshotBytes: 16
        )
        let exactReplay = journal.consumer.replay(
            after: 0,
            generation: generation,
            recovery: .exactHistory
        )

        // Assert
        #expect(recovery == .recovered)
        let historyGap = try #require(replayHistoryGap(exactReplay))
        #expect(historyGap.missingSequences == 1...3)
        #expect(historyGap.availableFacts.isEmpty)
        #expect(historyGap.nextSequence == 3)
        #expect(journal.lifecycle.diagnostics.retainedFactCount == 0)
        #expect(journal.lifecycle.diagnostics.productGap == nil)
        #expect(journal.lifecycle.diagnostics.isCurrent)
    }

    @Test("exact replay at the unavailable-history watermark remains explicitly gapped")
    func exactReplayAtUnavailableHistoryWatermarkReportsGap() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeGappedJournal(generation: generation)
        let productGap = try #require(nonCurrentGap(journal.consumer.currentState(generation: generation)))
        let watermark = productGap.missingSequences.upperBound
        _ = journal.consumer.resynchronize(
            generation: generation,
            gapToken: productGap.token,
            throughSequence: watermark,
            snapshot: JournalSnapshot(value: "recovered"),
            estimatedSnapshotBytes: 16
        )

        // Act
        let replay = journal.consumer.replay(
            after: watermark,
            generation: generation,
            recovery: .exactHistory
        )

        // Assert
        let historyGap = try #require(replayHistoryGap(replay))
        #expect(historyGap.missingSequences == watermark...watermark)
        #expect(historyGap.availableFacts.isEmpty)
        #expect(historyGap.nextSequence == watermark)
    }

    @Test("oversized initial snapshot is rejected instead of becoming current")
    func oversizedInitialSnapshotIsRejected() {
        // Arrange
        let generation = makeGeneration(1)

        // Act
        let result: Result<OrderedFactJournal<JournalFact, JournalSnapshot>, Error>
        do {
            result = .success(
                try makeJournalValidatingInitialSnapshot(
                    generation: generation,
                    maximumSnapshotBytes: 8,
                    initialSnapshot: JournalSnapshot(value: "oversized"),
                    initialSnapshotBytes: 16
                ))
        } catch {
            result = .failure(error)
        }

        // Assert
        guard case .failure(let error) = result else {
            Issue.record("Expected oversized initial snapshot configuration rejection")
            return
        }
        #expect(error as? OrderedFactJournalConfigurationError == .initialSnapshotTooLarge)
    }

    @Test("oversized atomic replacement rejects the entire offer before sequence assignment")
    func oversizedAtomicSnapshotReplacementRejectsBeforeSequenceAssignment() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: 4,
            maximumRetainedBytes: 16,
            maximumSnapshotBytes: 16
        )

        // Act
        let result = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: snapshotReplacement("oversized", bytes: 32)
        )

        // Assert
        #expect(isTypedSnapshotOfferRejection(result))
        let state = try #require(currentState(journal.consumer.currentState(generation: generation)))
        #expect(state.latestSequence == 0)
        #expect(state.snapshot == nil)
        let replay = try #require(
            exactReplay(journal.consumer.replay(after: 0, generation: generation, recovery: .exactHistory)))
        #expect(replay.facts.isEmpty)
        #expect(replay.nextSequence == 0)
        #expect(journal.lifecycle.diagnostics.admission.offered == 1)
        #expect(journal.lifecycle.diagnostics.admission.admitted == 0)
        #expect(journal.lifecycle.diagnostics.retainedFactCount == 0)
        #expect(journal.lifecycle.diagnostics.retainedByteCount == 0)
    }

    @Test("persistent product gap precedes invalid and future cursor validation")
    func persistentGapPrecedesInvalidAndFutureCursorValidation() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeGappedJournal(generation: generation)
        let expectedGap = try #require(nonCurrentGap(journal.consumer.currentState(generation: generation)))

        // Act
        let futureExactReplay = journal.consumer.replay(
            after: UInt64.max,
            generation: generation,
            recovery: .exactHistory
        )
        let futureSnapshotReplay = journal.consumer.replay(
            after: UInt64.max,
            generation: generation,
            recovery: .currentSnapshot
        )

        // Assert
        #expect(persistentReplayGap(futureExactReplay) == expectedGap)
        #expect(persistentReplayGap(futureSnapshotReplay) == expectedGap)
    }

    @Test("acknowledged history eviction stays current and returns a query-local history gap")
    func acknowledgedHistoryEvictionStaysCurrent() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: 2,
            maximumDrainFacts: 2,
            initialSnapshot: JournalSnapshot(value: "idle")
        )
        _ = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: snapshotReplacement("running", bytes: 16)
        )
        _ = journal.producer.offer(
            generation: generation,
            fact: .command("build"),
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        performJournalCleanupToQuiescence(journal.lifecycle, generation: generation)
        let initialDrain = try #require(
            factDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))
        _ = journal.consumer.acknowledge(initialDrain.token, disposition: .transferred)

        // Act
        let pressureOffer = journal.producer.offer(
            generation: generation,
            fact: .finished(0),
            estimatedFactBytes: 8,
            snapshotReplacement: snapshotReplacement("finished", bytes: 16)
        )
        let productGap = try #require(gapCommittedResult(pressureOffer)).gap
        performJournalCleanupToQuiescence(journal.lifecycle, generation: generation)
        #expect(
            journal.consumer.resynchronize(
                generation: generation,
                gapToken: productGap.token,
                throughSequence: productGap.missingSequences.upperBound,
                snapshot: JournalSnapshot(value: "finished"),
                estimatedSnapshotBytes: 16
            ) == .recovered
        )
        _ = journal.producer.offer(
            generation: generation,
            fact: .closed,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let replay = journal.consumer.replay(after: 0, generation: generation, recovery: .exactHistory)

        // Assert
        let historyGap = try #require(replayHistoryGap(replay))
        #expect(historyGap.missingSequences == 1...3)
        #expect(
            sequenceOracle(historyGap.availableFacts) == [
                .init(sequence: 4, fact: .closed)
            ])
        #expect(historyGap.nextSequence == 4)
        #expect(journal.lifecycle.diagnostics.productGap == nil)
        #expect(currentState(journal.consumer.currentState(generation: generation)) != nil)
    }

    @Test("snapshot recovery is explicit and exact-history occurrence queries still report history gaps")
    func snapshotAndOccurrenceReplayHaveDistinctContracts() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: 2,
            maximumDrainFacts: 2,
            initialSnapshot: JournalSnapshot(value: "idle")
        )
        admitAndTransferThreeFacts(journal, generation: generation, finalSnapshot: "finished")
        let productGap = try #require(
            nonCurrentGap(journal.consumer.currentState(generation: generation))
        )
        performJournalCleanupToQuiescence(journal.lifecycle, generation: generation)
        #expect(
            journal.consumer.resynchronize(
                generation: generation,
                gapToken: productGap.token,
                throughSequence: productGap.missingSequences.upperBound,
                snapshot: JournalSnapshot(value: "finished"),
                estimatedSnapshotBytes: 16
            ) == .recovered
        )

        // Act
        let occurrenceReplay = journal.consumer.replay(after: 0, generation: generation, recovery: .exactHistory)
        let snapshotReplay = journal.consumer.replay(after: 0, generation: generation, recovery: .currentSnapshot)

        // Assert
        let historyGap = try #require(replayHistoryGap(occurrenceReplay))
        #expect(historyGap.missingSequences == 1...3)

        let resynchronized = try #require(snapshotReplayResult(snapshotReplay))
        #expect(resynchronized.snapshot.throughSequence == 3)
        #expect(resynchronized.snapshot.snapshot == JournalSnapshot(value: "finished"))
        #expect(resynchronized.followingFacts.isEmpty)
        #expect(resynchronized.nextSequence == 3)
    }

    @Test("a persistent product gap dominates snapshot and exact-history replay")
    func persistentGapDominatesEveryReplayMode() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeGappedJournal(generation: generation)
        let expectedGap = try #require(nonCurrentGap(journal.consumer.currentState(generation: generation)))

        // Act
        let exactReplay = journal.consumer.replay(after: 0, generation: generation, recovery: .exactHistory)
        let snapshotReplay = journal.consumer.replay(after: 0, generation: generation, recovery: .currentSnapshot)

        // Assert
        #expect(persistentReplayGap(exactReplay) == expectedGap)
        #expect(persistentReplayGap(snapshotReplay) == expectedGap)
    }

    @Test("a burst schedules one wake and acknowledgement releases one follow-up wake")
    func oneWakeAndOneFollowUpWake() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: 8,
            maximumDrainFacts: 1
        )

        // Act
        let first = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let second = journal.producer.offer(
            generation: generation,
            fact: .command("one"),
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let firstDrain = try #require(
            factDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))
        let third = journal.producer.offer(
            generation: generation,
            fact: .command("two"),
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let whileDraining = journal.consumer.takeDrain(binding: journal.binding, generation: generation)
        let acknowledgement = journal.consumer.acknowledge(firstDrain.token, disposition: .transferred)

        // Assert
        #expect(admittedWake(first) == .scheduleDrain)
        #expect(admittedWake(second) == AdmissionWakeDirective.noWake)
        #expect(admittedWake(third) == AdmissionWakeDirective.noWake)
        #expect(isAlreadyDraining(whileDraining))
        #expect(acknowledgement == .accepted(wake: .scheduleDrain))
        #expect(journal.lifecycle.diagnostics.outstandingDrainCount == 0)
    }

    @Test("seal rejects new offers while allowing accepted facts to drain")
    func sealRejectsOffersAndAllowsDrain() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(generation: generation)
        _ = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )

        // Act
        let sealed = journal.lifecycle.seal(generation: generation)
        let rejected = journal.producer.offer(
            generation: generation,
            fact: .closed,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let drain = try #require(
            factDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))
        let acknowledgement = journal.consumer.acknowledge(drain.token, disposition: .transferred)
        let afterDrain = journal.consumer.takeDrain(binding: journal.binding, generation: generation)

        // Assert
        #expect(sealed == .applied)
        #expect(isClosedOffer(rejected))
        #expect(sequenceOracle(drain.facts) == [.init(sequence: 1, fact: .started)])
        #expect(acknowledgement == .accepted(wake: .noWake))
        #expect(isClosedDrain(afterDrain))
        let state = try #require(currentState(journal.consumer.currentState(generation: generation)))
        #expect(state.isSealed)
    }

    @Test("invalidate revokes an active drain and current snapshot")
    func invalidateRevokesDrainAndSnapshot() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            initialSnapshot: JournalSnapshot(value: "idle")
        )
        _ = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: snapshotReplacement("running", bytes: 16)
        )
        performJournalCleanupToQuiescence(journal.lifecycle, generation: generation)
        let drain = try #require(
            factDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))

        // Act
        let invalidated = journal.lifecycle.invalidate(generation: generation)
        let acknowledgement = journal.consumer.acknowledge(drain.token, disposition: .transferred)
        let replay = journal.consumer.replay(after: 0, generation: generation, recovery: .currentSnapshot)

        // Assert
        #expect(invalidated == .applied)
        #expect(acknowledgement == .closed)
        #expect(isInvalidatedState(journal.consumer.currentState(generation: generation)))
        #expect(isInvalidatedReplay(replay))
        #expect(journal.lifecycle.diagnostics.retainedFactCount == 0)
        #expect(journal.lifecycle.diagnostics.retainedByteCount == 0)
        #expect(journal.lifecycle.diagnostics.isCurrent == false)
    }

    @Test("diagnostics use the injected clock and retain leased depth until acknowledgement")
    func diagnosticsUseInjectedClock() throws {
        // Arrange
        let clock = TestPushClock()
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: 4,
            maximumRetainedBytes: 128,
            maximumDrainFacts: 1,
            clock: clock
        )

        // Act
        _ = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        clock.advance(by: .seconds(3))
        _ = journal.producer.offer(
            generation: generation,
            fact: .command("build"),
            estimatedFactBytes: 16,
            snapshotReplacement: nil
        )
        let beforeDrain = journal.lifecycle.diagnostics
        let drain = try #require(
            factDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))
        let duringDrain = journal.lifecycle.diagnostics
        _ = journal.consumer.acknowledge(drain.token, disposition: .transferred)
        let afterAcknowledgement = journal.lifecycle.diagnostics

        // Assert
        #expect(beforeDrain.admission.offered == 2)
        #expect(beforeDrain.admission.admitted == 2)
        #expect(beforeDrain.admission.contracted == 0)
        #expect(beforeDrain.admission.pendingKeyCount == 2)
        #expect(beforeDrain.admission.pendingKeyHighWater == 2)
        #expect(beforeDrain.admission.oldestPendingAge == .exact(.seconds(3)))
        #expect(beforeDrain.retainedFactCount == 2)
        #expect(beforeDrain.retainedByteCount == 24)
        #expect(duringDrain.admission.pendingKeyCount == 2)
        #expect(duringDrain.outstandingDrainCount == 1)
        #expect(afterAcknowledgement.admission.pendingKeyCount == 1)
        #expect(afterAcknowledgement.outstandingDrainCount == 0)
    }

    @Test("invalidation releases retained fact custody outside the journal lock")
    func invalidationReleasesFactCustodyOutsideLock() {
        // Arrange
        let generation = makeGeneration(1)
        let recorder = JournalReleaseRecorder()
        let box = ReentrantJournalBox()
        let journal = makeReentrantJournal(generation: generation)
        box.journal = journal.journal
        _ = journal.producer.offer(
            generation: generation,
            fact: makeReentrantFact(identifier: "invalidated", box: box, recorder: recorder),
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )

        // Act
        let result = journal.lifecycle.invalidate(generation: generation)
        let releasesBeforeCleanup = recorder.identifiers
        performJournalCleanupToQuiescence(journal.lifecycle, generation: generation)

        // Assert
        #expect(result == .applied)
        #expect(releasesBeforeCleanup.isEmpty)
        #expect(recorder.identifiers == ["invalidated"])
    }

    @Test("acknowledged-history eviction releases fact custody outside the journal lock")
    func acknowledgedHistoryEvictionReleasesFactCustodyOutsideLock() throws {
        // Arrange
        let generation = makeGeneration(1)
        let recorder = JournalReleaseRecorder()
        let box = ReentrantJournalBox()
        let journal = makeReentrantJournal(
            generation: generation,
            maximumRetainedFacts: 1,
            maximumDrainFacts: 1
        )
        box.journal = journal.journal
        _ = journal.producer.offer(
            generation: generation,
            fact: makeReentrantFact(identifier: "evicted", box: box, recorder: recorder),
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let token = try #require(
            reentrantFactDrainToken(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))
        _ = journal.consumer.acknowledge(token, disposition: .transferred)

        // Act
        let result = journal.producer.offer(
            generation: generation,
            fact: makeReentrantFact(identifier: "retained", box: box, recorder: recorder),
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let releasesBeforeCleanup = recorder.identifiers
        performJournalCleanupToQuiescence(journal.lifecycle, generation: generation)

        // Assert
        #expect(gapCommittedResult(result) != nil)
        #expect(releasesBeforeCleanup == ["retained"])
        #expect(recorder.identifiers.contains("evicted"))
        #expect(journal.lifecycle.diagnostics.retainedFactCount == 0)
    }

    @Test("persistent-gap commit releases superseded fact custody outside the journal lock")
    func persistentGapCommitReleasesFactCustodyOutsideLock() {
        // Arrange
        let generation = makeGeneration(1)
        let recorder = JournalReleaseRecorder()
        let box = ReentrantJournalBox()
        let journal = makeReentrantJournal(
            generation: generation,
            maximumRetainedFacts: 1
        )
        box.journal = journal.journal
        _ = journal.producer.offer(
            generation: generation,
            fact: makeReentrantFact(identifier: "superseded", box: box, recorder: recorder),
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )

        // Act
        let result = journal.producer.offer(
            generation: generation,
            fact: makeReentrantFact(identifier: "contracted", box: box, recorder: recorder),
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let releasesBeforeCleanup = recorder.identifiers
        performJournalCleanupToQuiescence(journal.lifecycle, generation: generation)

        // Assert
        #expect(gapCommittedResult(result) != nil)
        #expect(releasesBeforeCleanup == ["contracted"])
        #expect(recorder.identifiers.contains("superseded"))
    }

    @Test("snapshot replacement releases superseded snapshot custody outside the journal lock")
    func snapshotReplacementReleasesSnapshotCustodyOutsideLock() {
        // Arrange
        let generation = makeGeneration(1)
        let recorder = JournalReleaseRecorder()
        let box = ReentrantJournalBox()
        let journal = makeReentrantJournal(generation: generation)
        box.journal = journal.journal
        _ = journal.producer.offer(
            generation: generation,
            fact: makeReentrantFact(identifier: "first-fact", box: box, recorder: recorder),
            estimatedFactBytes: 8,
            snapshotReplacement: OrderedFactSnapshotReplacement(
                snapshot: ReentrantJournalSnapshot(
                    payload: makeReentrantFact(
                        identifier: "superseded-snapshot",
                        box: box,
                        recorder: recorder
                    )),
                estimatedBytes: 8
            )
        )

        // Act
        _ = journal.producer.offer(
            generation: generation,
            fact: makeReentrantFact(identifier: "second-fact", box: box, recorder: recorder),
            estimatedFactBytes: 8,
            snapshotReplacement: OrderedFactSnapshotReplacement(
                snapshot: ReentrantJournalSnapshot(
                    payload: makeReentrantFact(
                        identifier: "current-snapshot",
                        box: box,
                        recorder: recorder
                    )),
                estimatedBytes: 8
            )
        )
        let releasesBeforeCleanup = recorder.identifiers
        _ = journal.lifecycle.performCleanup(generation: generation)

        // Assert
        #expect(releasesBeforeCleanup.contains("superseded-snapshot") == false)
        #expect(recorder.identifiers.contains("superseded-snapshot"))
    }

}
