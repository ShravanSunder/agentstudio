import Dispatch
import Foundation
import Testing
import os

@testable import AgentStudio

@Suite("Admission unlock release matrix")
struct AdmissionUnlockReleaseMatrixTests {
    private let latestGeneration = AdmissionGeneration(owner: .terminalViewport, value: 701)
    private let gatherGeneration = AdmissionGeneration(owner: .filesystemObservation, value: 702)
    private let journalGeneration = AdmissionGeneration(owner: .runtimeFacts, value: 703)

    @Test("latest rejected value releases after unlock without mutation or wake")
    func latestRejectedValueReleasesAfterUnlock() {
        let gate = UnlockReleaseGate()
        let recorder = UnlockReleaseRecorder()
        let operationResult = UnlockResultBox<LatestValueOfferResult>()
        let mailbox = makeLatestMailbox(generation: latestGeneration)
        let mailboxReference = UnlockLatestMailboxReference(mailbox: mailbox)
        let producer = mailbox.producerPort
        let before = mailbox.lifecyclePort.diagnostics

        DispatchQueue(label: "admission.unlock.latest-rejected").async {
            operationResult.store(
                producer.offer(
                    generation: AdmissionGeneration(owner: .terminalViewport, value: 700),
                    key: 0,
                    value: UnlockReleasePayload(identifier: "latest-rejected", gate: gate, recorder: recorder) {
                        mailboxReference.readDiagnostics()
                    }
                ))
            recorder.record(.operationReturned("latest-rejected"))
            gate.signalOperationCompleted()
        }
        defer { gate.releaseAndJoin("latest rejected value deferred cleanup") }

        guard gate.waitForEntered("latest rejected value") else { return }
        guard gate.waitForReentry("latest rejected value") else {
            gate.releaseDestructor()
            return
        }
        let whileBlocked = mailbox.lifecyclePort.diagnostics
        #expect(gate.operationHasNotCompleted)
        #expect(operationResult.isPending)
        #expect(recorder.events == [.entered("latest-rejected"), .reentered("latest-rejected")])
        #expect(whileBlocked.admission.offered == before.admission.offered + 1)
        #expect(whileBlocked.admission.rejectedStale == before.admission.rejectedStale + 1)
        #expect(whileBlocked.admission.admitted == before.admission.admitted)
        #expect(whileBlocked.pendingValueCount == 0)
        #expect(whileBlocked.cleanupValueCount == 0)
        #expect(whileBlocked.outstandingLeaseCount == 0)
        gate.releaseDestructor()
        guard gate.waitForOperationCompletion("latest rejected value") else { return }
        #expect(operationResult.load() == .staleGeneration)
        #expect(
            recorder.events == [
                .entered("latest-rejected"), .reentered("latest-rejected"),
                .released("latest-rejected"), .operationReturned("latest-rejected"),
            ])
    }

    @Test("gather rejected contribution releases after unlock without mutation or wake")
    func gatherRejectedContributionReleasesAfterUnlock() {
        let gate = UnlockReleaseGate()
        let recorder = UnlockReleaseRecorder()
        let operationResult = UnlockResultBox<GatherOfferResult<Int>>()
        let mailbox = makeGatherMailbox(generation: gatherGeneration, maximumRetainedContributions: 2)
        let mailboxReference = UnlockGatherMailboxReference(mailbox: mailbox)
        let producer = mailbox.producerPort
        let before = mailbox.lifecyclePort.diagnostics

        DispatchQueue(label: "admission.unlock.gather-rejected").async {
            operationResult.store(
                producer.offer(
                    generation: AdmissionGeneration(owner: .filesystemObservation, value: 701),
                    contribution: GatherContribution(
                        key: 0,
                        payload: UnlockReleasePayload(identifier: "gather-rejected", gate: gate, recorder: recorder) {
                            mailboxReference.readDiagnostics()
                        },
                        footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                        recoverySignal: .ordinary
                    )
                ))
            recorder.record(.operationReturned("gather-rejected"))
            gate.signalOperationCompleted()
        }
        defer { gate.releaseAndJoin("gather rejected contribution deferred cleanup") }

        guard gate.waitForEntered("gather rejected contribution") else { return }
        guard gate.waitForReentry("gather rejected contribution") else {
            gate.releaseDestructor()
            return
        }
        let whileBlocked = mailbox.lifecyclePort.diagnostics
        #expect(gate.operationHasNotCompleted)
        #expect(operationResult.isPending)
        #expect(recorder.events == [.entered("gather-rejected"), .reentered("gather-rejected")])
        #expect(whileBlocked.admission.offered == before.admission.offered + 1)
        #expect(whileBlocked.admission.rejectedStale == before.admission.rejectedStale + 1)
        #expect(whileBlocked.admission.admitted == before.admission.admitted)
        #expect(whileBlocked.retainedContributionCount == 0)
        #expect(whileBlocked.recoverySlotCount == 0)
        #expect(whileBlocked.outstandingLeaseCount == 0)
        gate.releaseDestructor()
        guard gate.waitForOperationCompletion("gather rejected contribution") else { return }
        guard case .staleGeneration = operationResult.load() else {
            Issue.record("Expected stale gather rejection")
            return
        }
        #expect(
            recorder.events == [
                .entered("gather-rejected"), .reentered("gather-rejected"),
                .released("gather-rejected"), .operationReturned("gather-rejected"),
            ])
    }

    @Test("gather contracted contribution releases after unlock and preserves recovery wake")
    func gatherContractedContributionReleasesAfterUnlock() {
        let gate = UnlockReleaseGate()
        let recorder = UnlockReleaseRecorder()
        let operationResult = UnlockResultBox<GatherOfferResult<Int>>()
        let mailbox = makeGatherMailbox(generation: gatherGeneration, maximumRetainedContributions: 0)
        let mailboxReference = UnlockGatherMailboxReference(mailbox: mailbox)
        let producer = mailbox.producerPort

        DispatchQueue(label: "admission.unlock.gather-contracted").async {
            operationResult.store(
                producer.offer(
                    generation: self.gatherGeneration,
                    contribution: GatherContribution(
                        key: 0,
                        payload: UnlockReleasePayload(identifier: "gather-contracted", gate: gate, recorder: recorder) {
                            mailboxReference.readDiagnostics()
                        },
                        footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                        recoverySignal: .ordinary
                    )
                ))
            recorder.record(.operationReturned("gather-contracted"))
            gate.signalOperationCompleted()
        }
        defer { gate.releaseAndJoin("gather contracted contribution deferred cleanup") }

        guard gate.waitForEntered("gather contracted contribution") else { return }
        guard gate.waitForReentry("gather contracted contribution") else {
            gate.releaseDestructor()
            return
        }
        let whileBlocked = mailbox.lifecyclePort.diagnostics
        #expect(gate.operationHasNotCompleted)
        #expect(operationResult.isPending)
        #expect(whileBlocked.admission.offered == 1)
        #expect(whileBlocked.admission.admitted == 1)
        #expect(whileBlocked.admission.contracted == 1)
        #expect(whileBlocked.admission.repairEscalations == 1)
        #expect(whileBlocked.retainedContributionCount == 0)
        #expect(whileBlocked.recoverySlotCount == 1)
        #expect(whileBlocked.admission.pendingKeyCount == 1)
        gate.releaseDestructor()
        guard gate.waitForOperationCompletion("gather contracted contribution") else { return }
        guard
            case .admitted(
                .contractedToRecovery(_, .capacityPressure),
                wake: .scheduleDrain
            ) = operationResult.load()
        else {
            Issue.record("Expected contracted recovery admission with one wake")
            return
        }
        #expect(
            recorder.events == [
                .entered("gather-contracted"), .reentered("gather-contracted"),
                .released("gather-contracted"), .operationReturned("gather-contracted"),
            ])
    }

    @Test("ordered rejected fact releases after unlock without sequence or wake")
    func orderedRejectedFactReleasesAfterUnlock() throws {
        let gate = UnlockReleaseGate()
        let recorder = UnlockReleaseRecorder()
        let operationResult = UnlockResultBox<OrderedFactOfferResult>()
        let journal = try makeUnlockJournal(generation: journalGeneration, maximumRetainedFacts: 2)
        let journalReference = UnlockJournalReference(journal: journal)
        let before = journal.lifecyclePort.diagnostics

        DispatchQueue(label: "admission.unlock.ordered-rejected-fact").async {
            operationResult.store(
                journal.producerPort.offer(
                    generation: AdmissionGeneration(owner: .runtimeFacts, value: 702),
                    fact: UnlockReleasePayload(identifier: "ordered-rejected-fact", gate: gate, recorder: recorder) {
                        journalReference.readDiagnostics()
                    },
                    estimatedFactBytes: 1,
                    snapshotReplacement: nil
                ))
            recorder.record(.operationReturned("ordered-rejected-fact"))
            gate.signalOperationCompleted()
        }
        defer { gate.releaseAndJoin("ordered rejected fact deferred cleanup") }

        guard gate.waitForEntered("ordered rejected fact") else { return }
        guard gate.waitForReentry("ordered rejected fact") else {
            gate.releaseDestructor()
            return
        }
        let whileBlocked = journal.lifecyclePort.diagnostics
        #expect(gate.operationHasNotCompleted)
        #expect(operationResult.isPending)
        #expect(whileBlocked.admission.offered == before.admission.offered + 1)
        #expect(whileBlocked.admission.rejectedStale == before.admission.rejectedStale + 1)
        #expect(whileBlocked.admission.admitted == before.admission.admitted)
        #expect(whileBlocked.latestSequence == before.latestSequence)
        #expect(whileBlocked.retainedFactCount == 0)
        #expect(whileBlocked.cleanupFactCount == 0)
        gate.releaseDestructor()
        guard gate.waitForOperationCompletion("ordered rejected fact") else { return }
        guard case .staleGeneration = operationResult.load() else {
            Issue.record("Expected stale ordered fact rejection")
            return
        }
        #expect(
            recorder.events == [
                .entered("ordered-rejected-fact"), .reentered("ordered-rejected-fact"),
                .released("ordered-rejected-fact"), .operationReturned("ordered-rejected-fact"),
            ])
    }

    @Test("ordered atomic fact and snapshot rejection releases both after unlock")
    func orderedRejectedSnapshotReleasesAtomicallyAfterUnlock() throws {
        let factGate = UnlockReleaseGate()
        let snapshotGate = UnlockReleaseGate()
        let recorder = UnlockReleaseRecorder()
        let operationResult = UnlockResultBox<OrderedFactOfferResult>()
        let journal = try makeUnlockJournal(generation: journalGeneration, maximumRetainedFacts: 2)
        let journalReference = UnlockJournalReference(journal: journal)
        let before = journal.lifecyclePort.diagnostics

        DispatchQueue(label: "admission.unlock.ordered-rejected-snapshot").async {
            operationResult.store(
                journal.producerPort.offer(
                    generation: AdmissionGeneration(owner: .runtimeFacts, value: 702),
                    fact: UnlockReleasePayload(identifier: "ordered-atomic-fact", gate: factGate, recorder: recorder) {
                        journalReference.readDiagnostics()
                    },
                    estimatedFactBytes: 1,
                    snapshotReplacement: OrderedFactSnapshotReplacement(
                        snapshot: UnlockReleaseSnapshot(
                            payload: UnlockReleasePayload(
                                identifier: "ordered-atomic-snapshot",
                                gate: snapshotGate,
                                recorder: recorder
                            ) {
                                journalReference.readDiagnostics()
                            }
                        ),
                        estimatedBytes: 1
                    )
                ))
            recorder.record(.operationReturned("ordered-atomic"))
            factGate.signalOperationCompleted()
            snapshotGate.signalOperationCompleted()
        }
        defer {
            snapshotGate.releaseDestructor()
            factGate.releaseDestructor()
            snapshotGate.releaseAndJoin("ordered rejected snapshot deferred cleanup")
            factGate.releaseAndJoin("ordered rejected fact deferred cleanup")
        }

        guard snapshotGate.waitForEntered("ordered rejected snapshot half") else {
            factGate.releaseDestructor()
            return
        }
        guard snapshotGate.waitForReentry("ordered rejected snapshot half") else {
            snapshotGate.releaseDestructor()
            return
        }
        #expect(factGate.enteredHasNotFired)
        #expect(snapshotGate.operationHasNotCompleted)
        snapshotGate.releaseDestructor()
        guard factGate.waitForEntered("ordered rejected fact half") else {
            factGate.releaseDestructor()
            return
        }
        guard factGate.waitForReentry("ordered rejected fact half") else {
            factGate.releaseDestructor()
            return
        }
        let whileBlocked = journal.lifecyclePort.diagnostics
        #expect(factGate.operationHasNotCompleted)
        #expect(operationResult.isPending)
        #expect(whileBlocked.admission.offered == before.admission.offered + 1)
        #expect(whileBlocked.admission.rejectedStale == before.admission.rejectedStale + 1)
        #expect(whileBlocked.admission.admitted == before.admission.admitted)
        #expect(whileBlocked.latestSequence == before.latestSequence)
        #expect(whileBlocked.retainedFactCount == 0)
        #expect(whileBlocked.physicalRetainedSnapshotCount == 0)
        factGate.releaseDestructor()
        guard factGate.waitForOperationCompletion("ordered atomic rejection") else { return }
        guard case .staleGeneration = operationResult.load() else {
            Issue.record("Expected atomic stale ordered rejection")
            return
        }
        #expect(
            recorder.events == [
                .entered("ordered-atomic-snapshot"), .reentered("ordered-atomic-snapshot"),
                .released("ordered-atomic-snapshot"), .entered("ordered-atomic-fact"),
                .reentered("ordered-atomic-fact"), .released("ordered-atomic-fact"),
                .operationReturned("ordered-atomic"),
            ])
    }

    @Test("ordered gap contraction releases discarded fact after unlock")
    func orderedGapContractionReleasesDiscardedFactAfterUnlock() throws {
        let gate = UnlockReleaseGate()
        let recorder = UnlockReleaseRecorder()
        let operationResult = UnlockResultBox<OrderedFactOfferResult>()
        let journal = try makeUnlockJournal(generation: journalGeneration, maximumRetainedFacts: 0)
        let journalReference = UnlockJournalReference(journal: journal)

        DispatchQueue(label: "admission.unlock.ordered-gap-contraction").async {
            operationResult.store(
                journal.producerPort.offer(
                    generation: self.journalGeneration,
                    fact: UnlockReleasePayload(identifier: "ordered-gap-discard", gate: gate, recorder: recorder) {
                        journalReference.readDiagnostics()
                    },
                    estimatedFactBytes: 1,
                    snapshotReplacement: nil
                ))
            recorder.record(.operationReturned("ordered-gap-discard"))
            gate.signalOperationCompleted()
        }
        defer { gate.releaseAndJoin("ordered gap contraction deferred cleanup") }

        guard gate.waitForEntered("ordered gap contraction") else { return }
        guard gate.waitForReentry("ordered gap contraction") else {
            gate.releaseDestructor()
            return
        }
        let whileBlocked = journal.lifecyclePort.diagnostics
        #expect(gate.operationHasNotCompleted)
        #expect(operationResult.isPending)
        #expect(whileBlocked.admission.offered == 1)
        #expect(whileBlocked.admission.admitted == 1)
        #expect(whileBlocked.admission.contracted == 1)
        #expect(whileBlocked.admission.repairEscalations == 1)
        #expect(whileBlocked.latestSequence == 1)
        #expect(whileBlocked.retainedFactCount == 0)
        guard case .nonCurrent(let productGap) = whileBlocked.currentness else {
            Issue.record("Expected ordered gap contraction to remain noncurrent while blocked")
            return
        }
        #expect(productGap.missingSequences == 1...1)
        gate.releaseDestructor()
        guard gate.waitForOperationCompletion("ordered gap contraction") else { return }
        guard case .gapCommitted(let gap, wake: .scheduleDrain) = operationResult.load() else {
            Issue.record("Expected ordered gap contraction with one wake")
            return
        }
        #expect(gap.missingSequences == 1...1)
        #expect(
            recorder.events == [
                .entered("ordered-gap-discard"), .reentered("ordered-gap-discard"),
                .released("ordered-gap-discard"), .operationReturned("ordered-gap-discard"),
            ])
    }

    @Test("latest detached cleanup remains charged until payload release finalizes")
    func latestDetachedCleanupReleasesAfterUnlock() {
        let gate = UnlockReleaseGate()
        let recorder = UnlockReleaseRecorder()
        let cleanupResult = UnlockResultBox<AdmissionCleanupTurnResult>()
        let reentrantResult = UnlockResultBox<AdmissionCleanupTurnResult>()
        let mailbox = makeLatestMailbox(generation: latestGeneration)
        let mailboxReference = UnlockLatestMailboxReference(mailbox: mailbox)
        _ = mailbox.producerPort.offer(
            generation: latestGeneration,
            key: 0,
            value: UnlockReleasePayload(identifier: "latest-cleanup", gate: gate, recorder: recorder) {
                guard let reentrantMailbox = mailboxReference.mailbox else {
                    preconditionFailure("Latest cleanup mailbox disappeared during reentry")
                }
                reentrantResult.store(
                    reentrantMailbox.lifecyclePort.performCleanup(
                        generation: self.latestGeneration
                    )
                )
            }
        )
        #expect(mailbox.lifecyclePort.invalidate(generation: latestGeneration) == .applied)
        #expect(mailbox.lifecyclePort.diagnostics.cleanupValueCount == 1)

        DispatchQueue(label: "admission.unlock.latest-cleanup").async {
            cleanupResult.store(mailbox.lifecyclePort.performCleanup(generation: self.latestGeneration))
            recorder.record(.operationReturned("latest-cleanup"))
            gate.signalOperationCompleted()
        }
        defer { gate.releaseAndJoin("latest detached cleanup deferred cleanup") }

        guard gate.waitForEntered("latest detached cleanup") else { return }
        guard gate.waitForReentry("latest detached cleanup") else {
            gate.releaseDestructor()
            return
        }
        let whileBlocked = mailbox.lifecyclePort.diagnostics
        #expect(gate.operationHasNotCompleted)
        #expect(cleanupResult.isPending)
        #expect(reentrantResult.load() == .alreadyCleaning)
        #expect(whileBlocked.cleanupValueCount == 1)
        #expect(whileBlocked.physicalRetainedValueCount == 1)
        #expect(whileBlocked.outstandingCleanupTurnCount == 1)
        #expect(whileBlocked.isQuiescent == false)
        gate.releaseDestructor()
        guard gate.waitForOperationCompletion("latest detached cleanup") else { return }
        #expect(cleanupResult.load() == .performed(.init(release: .entries(count: 1), wake: .noWake)))
        let after = mailbox.lifecyclePort.diagnostics
        #expect(after.cleanupValueCount == 0)
        #expect(after.outstandingCleanupTurnCount == 0)
        #expect(after.isQuiescent)
        #expect(
            recorder.events == [
                .entered("latest-cleanup"), .reentered("latest-cleanup"),
                .released("latest-cleanup"), .operationReturned("latest-cleanup"),
            ])
    }

    @Test("gather detached cleanup remains charged until payload release finalizes")
    func gatherDetachedCleanupReleasesAfterUnlock() {
        let gate = UnlockReleaseGate()
        let recorder = UnlockReleaseRecorder()
        let cleanupResult = UnlockResultBox<AdmissionCleanupTurnResult>()
        let reentrantResult = UnlockResultBox<AdmissionCleanupTurnResult>()
        let mailbox = makeGatherMailbox(generation: gatherGeneration, maximumRetainedContributions: 2)
        let mailboxReference = UnlockGatherMailboxReference(mailbox: mailbox)
        _ = mailbox.producerPort.offer(
            generation: gatherGeneration,
            contribution: GatherContribution(
                key: 0,
                payload: UnlockReleasePayload(identifier: "gather-cleanup", gate: gate, recorder: recorder) {
                    guard let reentrantMailbox = mailboxReference.mailbox else {
                        preconditionFailure("Gather cleanup mailbox disappeared during reentry")
                    }
                    reentrantResult.store(
                        reentrantMailbox.lifecyclePort.performCleanup(
                            generation: self.gatherGeneration
                        )
                    )
                },
                footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                recoverySignal: .ordinary
            )
        )
        #expect(mailbox.lifecyclePort.invalidate(generation: gatherGeneration) == .applied)
        #expect(mailbox.lifecyclePort.diagnostics.cleanupContributionCount == 1)

        DispatchQueue(label: "admission.unlock.gather-cleanup").async {
            cleanupResult.store(mailbox.lifecyclePort.performCleanup(generation: self.gatherGeneration))
            recorder.record(.operationReturned("gather-cleanup"))
            gate.signalOperationCompleted()
        }
        defer { gate.releaseAndJoin("gather detached cleanup deferred cleanup") }

        guard gate.waitForEntered("gather detached cleanup") else { return }
        guard gate.waitForReentry("gather detached cleanup") else {
            gate.releaseDestructor()
            return
        }
        let whileBlocked = mailbox.lifecyclePort.diagnostics
        #expect(gate.operationHasNotCompleted)
        #expect(cleanupResult.isPending)
        #expect(reentrantResult.load() == .alreadyCleaning)
        #expect(whileBlocked.cleanupContributionCount == 1)
        #expect(whileBlocked.cleanupByteCount == 1)
        #expect(whileBlocked.physicalRetainedContributionCount == 1)
        #expect(whileBlocked.outstandingCleanupTurnCount == 1)
        #expect(whileBlocked.isQuiescent == false)
        gate.releaseDestructor()
        guard gate.waitForOperationCompletion("gather detached cleanup") else { return }
        #expect(
            cleanupResult.load()
                == .performed(.init(release: .entriesAndBytes(count: 1, bytes: 1), wake: .scheduleDrain))
        )
        let after = mailbox.lifecyclePort.diagnostics
        #expect(after.cleanupContributionCount == 0)
        #expect(after.cleanupMetadataEntryCount == 1)
        #expect(after.outstandingCleanupTurnCount == 0)
        #expect(
            recorder.events == [
                .entered("gather-cleanup"), .reentered("gather-cleanup"),
                .released("gather-cleanup"), .operationReturned("gather-cleanup"),
            ])
    }

    @Test("journal detached fact cleanup remains charged until payload release finalizes")
    func journalDetachedFactCleanupReleasesAfterUnlock() throws {
        let gate = UnlockReleaseGate()
        let recorder = UnlockReleaseRecorder()
        let cleanupResult = UnlockResultBox<AdmissionCleanupTurnResult>()
        let reentrantResult = UnlockResultBox<AdmissionCleanupTurnResult>()
        let journal = try makeUnlockJournal(generation: journalGeneration, maximumRetainedFacts: 2)
        let journalReference = UnlockJournalReference(journal: journal)
        _ = journal.producerPort.offer(
            generation: journalGeneration,
            fact: UnlockReleasePayload(identifier: "journal-fact-cleanup", gate: gate, recorder: recorder) {
                guard let reentrantJournal = journalReference.journal else {
                    preconditionFailure("Journal disappeared during fact cleanup reentry")
                }
                reentrantResult.store(
                    reentrantJournal.lifecyclePort.performCleanup(
                        generation: self.journalGeneration
                    )
                )
            },
            estimatedFactBytes: 1,
            snapshotReplacement: nil
        )
        #expect(journal.lifecyclePort.invalidate(generation: journalGeneration) == .applied)
        #expect(journal.lifecyclePort.diagnostics.cleanupFactCount == 1)

        DispatchQueue(label: "admission.unlock.journal-fact-cleanup").async {
            cleanupResult.store(journal.lifecyclePort.performCleanup(generation: self.journalGeneration))
            recorder.record(.operationReturned("journal-fact-cleanup"))
            gate.signalOperationCompleted()
        }
        defer { gate.releaseAndJoin("journal fact cleanup deferred cleanup") }

        guard gate.waitForEntered("journal detached fact cleanup") else { return }
        guard gate.waitForReentry("journal detached fact cleanup") else {
            gate.releaseDestructor()
            return
        }
        let whileBlocked = journal.lifecyclePort.diagnostics
        #expect(gate.operationHasNotCompleted)
        #expect(cleanupResult.isPending)
        #expect(reentrantResult.load() == .alreadyCleaning)
        #expect(whileBlocked.cleanupFactCount == 1)
        #expect(whileBlocked.cleanupByteCount == 1)
        #expect(whileBlocked.physicalRetainedFactCount == 1)
        #expect(whileBlocked.outstandingCleanupTurnCount == 1)
        #expect(whileBlocked.isQuiescent == false)
        gate.releaseDestructor()
        guard gate.waitForOperationCompletion("journal detached fact cleanup") else { return }
        #expect(
            cleanupResult.load()
                == .performed(.init(release: .entriesAndBytes(count: 1, bytes: 1), wake: .noWake))
        )
        let after = journal.lifecyclePort.diagnostics
        #expect(after.cleanupFactCount == 0)
        #expect(after.outstandingCleanupTurnCount == 0)
        #expect(after.isQuiescent)
        #expect(
            recorder.events == [
                .entered("journal-fact-cleanup"), .reentered("journal-fact-cleanup"),
                .released("journal-fact-cleanup"), .operationReturned("journal-fact-cleanup"),
            ])
    }

    @Test("journal detached snapshot cleanup remains charged until payload release finalizes")
    func journalDetachedSnapshotCleanupReleasesAfterUnlock() throws {
        let gate = UnlockReleaseGate()
        let recorder = UnlockReleaseRecorder()
        let cleanupResult = UnlockResultBox<AdmissionCleanupTurnResult>()
        let reentrantResult = UnlockResultBox<AdmissionCleanupTurnResult>()
        let journalReference = UnlockJournalReference()
        let journal = try makeUnlockJournal(
            generation: journalGeneration,
            maximumRetainedFacts: 2,
            initialSnapshotReplacement: OrderedFactSnapshotReplacement(
                snapshot: UnlockReleaseSnapshot(
                    payload: UnlockReleasePayload(
                        identifier: "journal-snapshot-cleanup",
                        gate: gate,
                        recorder: recorder
                    ) {
                        guard let reentrantJournal = journalReference.journal else {
                            preconditionFailure("Journal disappeared during snapshot cleanup reentry")
                        }
                        reentrantResult.store(
                            reentrantJournal.lifecyclePort.performCleanup(
                                generation: self.journalGeneration
                            )
                        )
                    }
                ),
                estimatedBytes: 1
            )
        )
        journalReference.journal = journal
        #expect(journal.lifecyclePort.invalidate(generation: journalGeneration) == .applied)
        #expect(journal.lifecyclePort.diagnostics.cleanupSnapshotCount == 1)

        DispatchQueue(label: "admission.unlock.journal-snapshot-cleanup").async {
            cleanupResult.store(journal.lifecyclePort.performCleanup(generation: self.journalGeneration))
            recorder.record(.operationReturned("journal-snapshot-cleanup"))
            gate.signalOperationCompleted()
        }
        defer { gate.releaseAndJoin("journal snapshot cleanup deferred cleanup") }

        guard gate.waitForEntered("journal detached snapshot cleanup") else { return }
        guard gate.waitForReentry("journal detached snapshot cleanup") else {
            gate.releaseDestructor()
            return
        }
        let whileBlocked = journal.lifecyclePort.diagnostics
        #expect(gate.operationHasNotCompleted)
        #expect(cleanupResult.isPending)
        #expect(reentrantResult.load() == .alreadyCleaning)
        #expect(whileBlocked.cleanupSnapshotCount == 1)
        #expect(whileBlocked.cleanupSnapshotByteCount == 1)
        #expect(whileBlocked.physicalRetainedSnapshotCount == 1)
        #expect(whileBlocked.outstandingCleanupTurnCount == 1)
        #expect(whileBlocked.isQuiescent == false)
        gate.releaseDestructor()
        guard gate.waitForOperationCompletion("journal detached snapshot cleanup") else { return }
        #expect(
            cleanupResult.load()
                == .performed(.init(release: .entriesAndBytes(count: 1, bytes: 1), wake: .noWake))
        )
        let after = journal.lifecyclePort.diagnostics
        #expect(after.cleanupSnapshotCount == 0)
        #expect(after.outstandingCleanupTurnCount == 0)
        #expect(after.isQuiescent)
        #expect(
            recorder.events == [
                .entered("journal-snapshot-cleanup"), .reentered("journal-snapshot-cleanup"),
                .released("journal-snapshot-cleanup"), .operationReturned("journal-snapshot-cleanup"),
            ])
    }

    private func makeLatestMailbox(
        generation: AdmissionGeneration
    ) -> LatestValueMailbox<Int, UnlockReleasePayload> {
        LatestValueMailbox(
            generation: generation,
            declaredKeys: [0],
            limits: LatestValueLimits(
                maximumValuesPerLease: 1,
                maximumAuxiliaryRetainedValues: 2,
                cleanupQuantum: .entries(maximumEntries: 1)
            )
        )
    }

    private func makeGatherMailbox(
        generation: AdmissionGeneration,
        maximumRetainedContributions: Int
    ) -> BoundedGatherMailbox<Int, UnlockReleasePayload> {
        BoundedGatherMailbox(
            generation: generation,
            declaredKeys: [0],
            limits: GatherMailboxLimits(
                maximumDeclaredKeys: 1,
                maximumRetainedContributions: maximumRetainedContributions,
                maximumRetainedItems: 2,
                maximumRetainedBytes: 2,
                maximumRetainedContributionsPerKey: maximumRetainedContributions,
                maximumRetainedItemsPerKey: 2,
                maximumRetainedBytesPerKey: 2,
                maximumContributionsPerLease: 1,
                maximumItemsPerLease: 2,
                maximumBytesPerLease: 2,
                cleanupQuantum: .entriesAndBytes(maximumEntries: 1, maximumBytes: 2)
            )
        )
    }

    private func makeUnlockJournal(
        generation: AdmissionGeneration,
        maximumRetainedFacts: Int,
        initialSnapshotReplacement: OrderedFactSnapshotReplacement<UnlockReleaseSnapshot>? = nil
    ) throws -> OrderedFactJournal<UnlockReleasePayload, UnlockReleaseSnapshot> {
        try OrderedFactJournal(
            generation: generation,
            maximumRetainedFacts: maximumRetainedFacts,
            maximumRetainedBytes: 2,
            snapshotLimits: OrderedFactSnapshotLimits(
                maximumSnapshotBytes: 2,
                maximumPhysicalSnapshotCount: 2,
                maximumPhysicalSnapshotBytes: 4
            ),
            maximumDrainFacts: 1,
            cleanupQuantum: .entriesAndBytes(maximumEntries: 1, maximumBytes: 2),
            initialSnapshotReplacement: initialSnapshotReplacement
        )
    }
}

private enum UnlockReleaseEvent: Equatable {
    case entered(String)
    case reentered(String)
    case released(String)
    case operationReturned(String)
}

private final class UnlockReleaseRecorder: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [UnlockReleaseEvent]())

    func record(_ event: UnlockReleaseEvent) {
        lock.withLock { $0.append(event) }
    }

    var events: [UnlockReleaseEvent] {
        lock.withLock { $0 }
    }
}

private final class UnlockReleaseGate: @unchecked Sendable {
    private struct State {
        var destructorReleaseSignaled = false
        var operationCompletionConsumed = false
    }

    let entered = DispatchSemaphore(value: 0)
    let reentryCompleted = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private let operationCompleted = DispatchSemaphore(value: 0)
    private let state = OSAllocatedUnfairLock(initialState: State())

    func signalOperationCompleted() {
        operationCompleted.signal()
    }

    func waitForDestructorRelease() {
        release.wait()
    }

    func releaseDestructor() {
        let shouldSignal = state.withLock { state in
            guard state.destructorReleaseSignaled == false else { return false }
            state.destructorReleaseSignaled = true
            return true
        }
        if shouldSignal {
            release.signal()
        }
    }

    var enteredHasNotFired: Bool {
        entered.wait(timeout: .now()) == .timedOut
    }

    var operationHasNotCompleted: Bool {
        if state.withLock({ $0.operationCompletionConsumed }) {
            return false
        }
        guard operationCompleted.wait(timeout: .now()) == .success else { return true }
        state.withLock { $0.operationCompletionConsumed = true }
        return false
    }

    func waitForEntered(_ row: String) -> Bool {
        guard entered.wait(timeout: .now() + 5) == .success else {
            Issue.record("Timed out waiting for \(row) destructor entry")
            releaseDestructor()
            return false
        }
        return true
    }

    func waitForReentry(_ row: String) -> Bool {
        guard reentryCompleted.wait(timeout: .now() + 5) == .success else {
            Issue.record("Timed out waiting for \(row) reentrant operation")
            releaseDestructor()
            return false
        }
        return true
    }

    func waitForOperationCompletion(_ row: String) -> Bool {
        if state.withLock({ $0.operationCompletionConsumed }) {
            return true
        }
        guard operationCompleted.wait(timeout: .now() + 5) == .success else {
            Issue.record("Timed out waiting for \(row) operation completion")
            return false
        }
        state.withLock { $0.operationCompletionConsumed = true }
        return true
    }

    func releaseAndJoin(_ row: String) {
        releaseDestructor()
        _ = waitForOperationCompletion(row)
    }
}

private final class UnlockReleasePayload: @unchecked Sendable {
    let identifier: String
    private let gate: UnlockReleaseGate
    private let recorder: UnlockReleaseRecorder
    private let reenter: @Sendable () -> Void

    init(
        identifier: String,
        gate: UnlockReleaseGate,
        recorder: UnlockReleaseRecorder,
        reenter: @escaping @Sendable () -> Void
    ) {
        self.identifier = identifier
        self.gate = gate
        self.recorder = recorder
        self.reenter = reenter
    }

    deinit {
        recorder.record(.entered(identifier))
        gate.entered.signal()
        reenter()
        recorder.record(.reentered(identifier))
        gate.reentryCompleted.signal()
        gate.waitForDestructorRelease()
        recorder.record(.released(identifier))
    }
}

private struct UnlockReleaseSnapshot: Sendable {
    let payload: UnlockReleasePayload
}

private final class UnlockResultBox<Value: Sendable>: @unchecked Sendable {
    private enum State: Sendable {
        case pending
        case stored(Value)
    }

    private let lock = OSAllocatedUnfairLock(initialState: State.pending)

    func store(_ value: Value) {
        lock.withLock { $0 = .stored(value) }
    }

    func load() -> Value {
        lock.withLock { state in
            guard case .stored(let value) = state else {
                preconditionFailure("Unlock release result was read before completion")
            }
            return value
        }
    }

    var isPending: Bool {
        lock.withLock { state in
            guard case .pending = state else { return false }
            return true
        }
    }
}

private final class UnlockLatestMailboxReference: @unchecked Sendable {
    weak var mailbox: LatestValueMailbox<Int, UnlockReleasePayload>?

    init(mailbox: LatestValueMailbox<Int, UnlockReleasePayload>) {
        self.mailbox = mailbox
    }

    func readDiagnostics() {
        guard let mailbox else {
            preconditionFailure("Latest mailbox disappeared during diagnostic reentry")
        }
        _ = mailbox.lifecyclePort.diagnostics
    }
}

private final class UnlockGatherMailboxReference: @unchecked Sendable {
    weak var mailbox: BoundedGatherMailbox<Int, UnlockReleasePayload>?

    init(mailbox: BoundedGatherMailbox<Int, UnlockReleasePayload>) {
        self.mailbox = mailbox
    }

    func readDiagnostics() {
        guard let mailbox else {
            preconditionFailure("Gather mailbox disappeared during diagnostic reentry")
        }
        _ = mailbox.lifecyclePort.diagnostics
    }
}

private final class UnlockJournalReference: @unchecked Sendable {
    weak var journal: OrderedFactJournal<UnlockReleasePayload, UnlockReleaseSnapshot>?

    init(journal: OrderedFactJournal<UnlockReleasePayload, UnlockReleaseSnapshot>? = nil) {
        self.journal = journal
    }

    func readDiagnostics() {
        guard let journal else {
            preconditionFailure("Journal disappeared during diagnostic reentry")
        }
        _ = journal.lifecyclePort.diagnostics
    }
}
