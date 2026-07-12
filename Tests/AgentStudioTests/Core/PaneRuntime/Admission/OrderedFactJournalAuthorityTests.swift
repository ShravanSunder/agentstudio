import Foundation
import Testing

@testable import AgentStudio

extension AdmissionOrderedFactJournalTests {
    @Test("an empty drain poll consumes no lease authority and lease authority rotates without stranding custody")
    func leaseAuthorityRotatesWithoutStrandingCustody() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            authoritySeeds: OrderedFactJournalAuthoritySeeds(
                nextLeaseSequence: UInt64.max,
                nextGapRevision: 1
            )
        )

        // Act
        let emptyPoll = journal.consumer.takeDrain(binding: journal.binding, generation: generation)
        _ = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let maximumLease = try #require(
            factDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))
        let retried = journal.consumer.acknowledge(maximumLease.token, disposition: .retry)
        let rotatedLease = try #require(
            factDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))
        let transferred = journal.consumer.acknowledge(rotatedLease.token, disposition: .transferred)

        // Assert
        #expect(isEmptyDrain(emptyPoll))
        #expect(retried == .accepted(wake: .scheduleDrain))
        #expect(maximumLease.token != rotatedLease.token)
        #expect(sequenceOracle(rotatedLease.facts) == [.init(sequence: 1, fact: .started)])
        #expect(transferred == .accepted(wake: .noWake))
        #expect(journal.lifecycle.diagnostics.outstandingDrainCount == 0)
    }

    @Test("gap authority rotates without aliasing and an older acknowledgement cannot clear newer debt")
    func gapAuthorityRotatesWithoutAliasingOrLostDebt() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: 0,
            authoritySeeds: OrderedFactJournalAuthoritySeeds(
                nextLeaseSequence: 1,
                nextGapRevision: UInt64.max
            )
        )
        let firstOffer = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let firstGap = try #require(gapCommittedResult(firstOffer)).gap
        let olderLease = try #require(
            persistentGapDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))

        // Act
        let secondOffer = journal.producer.offer(
            generation: generation,
            fact: .closed,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let secondGap = try #require(gapCommittedResult(secondOffer)).gap
        let olderAcknowledgement = journal.consumer.acknowledge(
            olderLease.token,
            disposition: .transferred
        )
        let currentLease = try #require(
            persistentGapDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))

        // Assert
        #expect(firstGap.token.revision == UInt64.max)
        #expect(secondGap.token.revision == 1)
        #expect(firstGap.token.journalIdentity != secondGap.token.journalIdentity)
        #expect(secondGap.missingSequences == 1...2)
        #expect(olderAcknowledgement == .invalidToken)
        #expect(currentLease.gap == secondGap)
        #expect(nonCurrentGap(journal.consumer.currentState(generation: generation)) == secondGap)
    }

    @Test("sequence exhaustion closes admission without wrapping to zero")
    func sequenceExhaustionDoesNotWrap() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: 4,
            initialSequence: UInt64.max - 1
        )

        // Act
        let maximumSequenceOffer = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let overflowOffer = journal.producer.offer(
            generation: generation,
            fact: .closed,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )

        // Assert
        #expect(admittedSequence(maximumSequenceOffer) == UInt64.max)
        #expect(isAuthorityExhaustedOffer(overflowOffer))
        #expect(journal.lifecycle.diagnostics.latestSequence == UInt64.max)
        #expect(journal.lifecycle.diagnostics.latestSequence != 0)
        let drain = try #require(
            factDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))
        #expect(drain.facts.map(\.sequence) == [UInt64.max])
    }

    @Test("near-maximum sequence preserves newer gap custody against an older lease acknowledgement")
    func nearMaximumSequencePreservesNewerGapAuthority() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: 1,
            maximumRetainedBytes: 16,
            maximumDrainFacts: 1,
            initialSequence: UInt64.max - 2
        )
        let firstOffer = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let olderLease = try #require(
            factDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))

        // Act
        let maximumSequenceOffer = journal.producer.offer(
            generation: generation,
            fact: .closed,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let gap = try #require(gapCommittedResult(maximumSequenceOffer)).gap
        let olderAcknowledgement = journal.consumer.acknowledge(
            olderLease.token,
            disposition: .transferred
        )
        let exhaustedOffer = journal.producer.offer(
            generation: generation,
            fact: .command("must-not-wrap"),
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let currentGap = try #require(nonCurrentGap(journal.consumer.currentState(generation: generation)))
        performJournalCleanupToQuiescence(journal.lifecycle, generation: generation)
        let gapLease = try #require(
            persistentGapDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)))

        // Assert
        #expect(admittedSequence(firstOffer) == UInt64.max - 1)
        #expect(gap.missingSequences == (UInt64.max - 1)...UInt64.max)
        #expect(olderAcknowledgement == .invalidToken)
        #expect(isAuthorityExhaustedOffer(exhaustedOffer))
        #expect(journal.lifecycle.diagnostics.latestSequence == UInt64.max)
        #expect(currentGap == gap)
        #expect(gapLease.gap == gap)
        #expect(gapLease.token != olderLease.token)
    }
}
