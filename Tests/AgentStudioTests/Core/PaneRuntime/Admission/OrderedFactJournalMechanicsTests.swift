import Foundation
import Testing

@testable import AgentStudio

extension AdmissionOrderedFactJournalTests {
    @Test("consumer rebind re-presents exact fact custody and rejects the old acknowledgement")
    func consumerRebindRepresentsExactFactCustody() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(generation: generation, maximumDrainFacts: 1)
        _ = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let oldDrain = try #require(
            factDrain(
                journal.consumer.takeDrain(
                    binding: journal.binding,
                    generation: generation
                )))
        let authorityBeforeRebind = journal.lifecycle.authoritySnapshot

        // Act
        let reboundBinding = journal.consumer.bindConsumer().binding
        let authorityAfterRebind = journal.lifecycle.authoritySnapshot
        let oldAcknowledgement = journal.consumer.acknowledge(
            oldDrain.token,
            disposition: .transferred
        )
        let reboundDrain = try #require(
            factDrain(
                journal.consumer.takeDrain(
                    binding: reboundBinding,
                    generation: generation
                )))
        let reboundAcknowledgement = journal.consumer.acknowledge(
            reboundDrain.token,
            disposition: .transferred
        )

        // Assert
        #expect(authorityAfterRebind.bindingSequence == authorityBeforeRebind.bindingSequence + 1)
        #expect(authorityAfterRebind.nextLeaseSequence == authorityBeforeRebind.nextLeaseSequence + 1)
        #expect(oldAcknowledgement == .invalidToken)
        #expect(sequenceOracle(reboundDrain.facts) == sequenceOracle(oldDrain.facts))
        #expect(reboundDrain.token != oldDrain.token)
        #expect(reboundAcknowledgement == .accepted(wake: .noWake))
        #expect(journal.lifecycle.diagnostics.pendingFactCount == 0)
    }

    @Test("binding authority rotates its epoch without aliasing active gap custody")
    func bindingAuthorityRotationRepresentsExactGapCustody() throws {
        // Arrange
        let generation = makeGeneration(1)
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: 0,
            authoritySeeds: OrderedFactJournalAuthoritySeeds(
                bindingSequence: UInt64.max - 1,
                nextLeaseSequence: 1,
                nextGapRevision: 1
            )
        )
        _ = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let oldDrain = try #require(
            persistentGapDrain(
                journal.consumer.takeDrain(
                    binding: journal.binding,
                    generation: generation
                )))
        let maximumBindingAuthority = journal.lifecycle.authoritySnapshot

        // Act
        let rotatedBinding = journal.consumer.bindConsumer().binding
        let rotatedAuthority = journal.lifecycle.authoritySnapshot
        let oldAcknowledgement = journal.consumer.acknowledge(
            oldDrain.token,
            disposition: .transferred
        )
        let reboundDrain = try #require(
            persistentGapDrain(
                journal.consumer.takeDrain(
                    binding: rotatedBinding,
                    generation: generation
                )))
        let reboundAcknowledgement = journal.consumer.acknowledge(
            reboundDrain.token,
            disposition: .transferred
        )
        let afterTransfer = journal.consumer.takeDrain(
            binding: rotatedBinding,
            generation: generation
        )

        // Assert
        #expect(maximumBindingAuthority.bindingSequence == UInt64.max)
        #expect(rotatedAuthority.bindingSequence == 1)
        #expect(rotatedAuthority.bindingEpoch != maximumBindingAuthority.bindingEpoch)
        #expect(oldAcknowledgement == .invalidToken)
        #expect(reboundDrain.gap == oldDrain.gap)
        #expect(reboundDrain.token != oldDrain.token)
        #expect(reboundAcknowledgement == .accepted(wake: .noWake))
        #expect(isEmptyDrain(afterTransfer))
        #expect(journal.lifecycle.diagnostics.currentness == .nonCurrent(oldDrain.gap))
    }

    @Test("offer take and diagnostics sample a reentrant injected clock outside the journal lock")
    func injectedClockCanReenterJournalOutsideLock() throws {
        // Arrange
        let generation = makeGeneration(1)
        let box = JournalClockReentryBox()
        let recorder = JournalClockRecorder()
        let journal = makeReentrantClockJournal(
            generation: generation,
            box: box,
            recorder: recorder
        )

        // Act
        _ = journal.producer.offer(
            generation: generation,
            fact: .started,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        let drain = try #require(
            factDrain(
                journal.consumer.takeDrain(
                    binding: journal.binding,
                    generation: generation
                )))
        let diagnostics = journal.lifecycle.diagnostics

        // Assert
        #expect(sequenceOracle(drain.facts) == [.init(sequence: 1, fact: .started)])
        #expect(diagnostics.pendingFactCount == 1)
        #expect(recorder.sampleCount == 3)
    }

    @Test("offer take acknowledgement and transferred-prefix eviction have fixed operation shape")
    func journalOperationsHaveFixedShapeAcrossHistoryDepths() throws {
        // Arrange
        let generation = makeGeneration(1)
        let historyDepths = [1, 100, 300]
        var observedDeltas: [[UInt64]] = []

        // Act
        for historyDepth in historyDepths {
            let journal = makeJournal(
                generation: generation,
                maximumRetainedFacts: historyDepth,
                maximumRetainedBytes: historyDepth * 8,
                maximumDrainFacts: 1
            )
            for sequence in 0..<historyDepth {
                _ = journal.producer.offer(
                    generation: generation,
                    fact: .command("\(sequence)"),
                    estimatedFactBytes: 8,
                    snapshotReplacement: nil
                )
            }

            let beforeTake = journal.lifecycle.operationSnapshot
            let measuredDrain = try #require(
                factDrain(
                    journal.consumer.takeDrain(
                        binding: journal.binding,
                        generation: generation
                    )))
            let afterTake = journal.lifecycle.operationSnapshot
            _ = journal.consumer.acknowledge(
                measuredDrain.token,
                disposition: .transferred
            )
            let afterAcknowledgement = journal.lifecycle.operationSnapshot

            for _ in 1..<historyDepth {
                let drain = try #require(
                    factDrain(
                        journal.consumer.takeDrain(
                            binding: journal.binding,
                            generation: generation
                        )))
                _ = journal.consumer.acknowledge(
                    drain.token,
                    disposition: .transferred
                )
            }

            let beforeEvictionOffer = journal.lifecycle.operationSnapshot
            _ = journal.producer.offer(
                generation: generation,
                fact: .closed,
                estimatedFactBytes: 8,
                snapshotReplacement: nil
            )
            let afterEvictionOffer = journal.lifecycle.operationSnapshot
            observedDeltas.append([
                afterEvictionOffer.offerNodeVisits - beforeEvictionOffer.offerNodeVisits,
                afterTake.takeNodeVisits - beforeTake.takeNodeVisits,
                afterAcknowledgement.acknowledgementNodeVisits
                    - afterTake.acknowledgementNodeVisits,
                afterEvictionOffer.evictionNodeVisits - beforeEvictionOffer.evictionNodeVisits,
            ])
        }

        // Assert
        #expect(observedDeltas == [[0, 1, 1, 1], [0, 1, 1, 1], [0, 1, 1, 1]])
    }

    @Test("large byte pressure detaches the whole transferred prefix in one operation")
    func largeBytePressureDetachesTransferredPrefixInOneOperation() throws {
        // Arrange
        let generation = makeGeneration(1)
        let retainedHistoryDepth = 300
        let retainedByteCapacity = retainedHistoryDepth * 8
        let journal = makeJournal(
            generation: generation,
            maximumRetainedFacts: retainedHistoryDepth,
            maximumRetainedBytes: retainedByteCapacity,
            maximumDrainFacts: retainedHistoryDepth
        )
        for sequence in 0..<retainedHistoryDepth {
            _ = journal.producer.offer(
                generation: generation,
                fact: .command("\(sequence)"),
                estimatedFactBytes: 8,
                snapshotReplacement: nil
            )
        }
        let transferredHistory = try #require(
            factDrain(
                journal.consumer.takeDrain(
                    binding: journal.binding,
                    generation: generation
                )))
        _ = journal.consumer.acknowledge(
            transferredHistory.token,
            disposition: .transferred
        )
        let beforePressureOffer = journal.lifecycle.operationSnapshot

        // Act
        let pressureOffer = journal.producer.offer(
            generation: generation,
            fact: .closed,
            estimatedFactBytes: retainedByteCapacity,
            snapshotReplacement: nil
        )
        let afterPressureOffer = journal.lifecycle.operationSnapshot
        let replay = journal.consumer.replay(
            after: 0,
            generation: generation,
            recovery: .exactHistory
        )

        // Assert
        let productGap = try #require(gapCommittedResult(pressureOffer))
        #expect(
            productGap.gap.missingSequences
                == UInt64(retainedHistoryDepth + 1)...UInt64(retainedHistoryDepth + 1)
        )
        #expect(
            afterPressureOffer.evictionNodeVisits - beforePressureOffer.evictionNodeVisits == 1
        )
        #expect(persistentReplayGap(replay) == productGap.gap)
    }
}
