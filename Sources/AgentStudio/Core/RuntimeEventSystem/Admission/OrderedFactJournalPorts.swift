struct OrderedFactProducerPort<Fact: Sendable, Snapshot: Sendable>: Sendable {
    private let journal: OrderedFactJournal<Fact, Snapshot>

    init(journal: OrderedFactJournal<Fact, Snapshot>) {
        self.journal = journal
    }

    func offer(
        generation: AdmissionGeneration,
        fact: Fact,
        estimatedFactBytes: Int,
        snapshotReplacement: OrderedFactSnapshotReplacement<Snapshot>?
    ) -> OrderedFactOfferResult {
        journal.offer(
            generation: generation,
            fact: fact,
            estimatedFactBytes: estimatedFactBytes,
            snapshotReplacement: snapshotReplacement
        )
    }
}

struct OrderedFactConsumerPort<Fact: Sendable, Snapshot: Sendable>:
    AdmissionCleanupConsumer, AdmissionConsumerBindingSource
{
    private let journal: OrderedFactJournal<Fact, Snapshot>

    init(journal: OrderedFactJournal<Fact, Snapshot>) {
        self.journal = journal
    }

    func bindConsumer() -> AdmissionConsumerBindResult {
        journal.bindConsumer()
    }

    func takeDrain(
        binding: AdmissionConsumerBinding,
        generation: AdmissionGeneration
    ) -> OrderedFactTakeDrainResult<Fact> {
        journal.takeDrain(binding: binding, generation: generation)
    }

    func acknowledge(
        _ token: AdmissionDrainToken,
        disposition: AdmissionDrainDisposition
    ) -> AdmissionDrainAcknowledgement {
        journal.acknowledge(token, disposition: disposition)
    }

    func replay(
        after sequence: UInt64,
        generation: AdmissionGeneration,
        recovery: OrderedFactReplayRecovery
    ) -> OrderedFactReplayCompletion<Fact, Snapshot> {
        journal.replay(after: sequence, generation: generation, recovery: recovery)
    }

    func performCleanup(
        generation: AdmissionGeneration
    ) -> AdmissionCleanupTurnResult {
        journal.performCleanup(generation: generation)
    }

    func currentState(
        generation: AdmissionGeneration
    ) -> OrderedFactCurrentStateResult<Snapshot> {
        journal.currentState(generation: generation)
    }

    func resynchronize(
        generation: AdmissionGeneration,
        gapToken: FactGapToken,
        throughSequence: UInt64,
        snapshot: Snapshot,
        estimatedSnapshotBytes: Int
    ) -> OrderedFactRecoveryResult {
        journal.resynchronize(
            generation: generation,
            gapToken: gapToken,
            throughSequence: throughSequence,
            snapshot: snapshot,
            estimatedSnapshotBytes: estimatedSnapshotBytes
        )
    }
}

struct OrderedFactLifecyclePort<Fact: Sendable, Snapshot: Sendable>:
    AdmissionCleanupConsumer
{
    private let journal: OrderedFactJournal<Fact, Snapshot>

    init(journal: OrderedFactJournal<Fact, Snapshot>) {
        self.journal = journal
    }

    func seal(generation: AdmissionGeneration) -> AdmissionControlResult {
        journal.seal(generation: generation)
    }

    func invalidate(generation: AdmissionGeneration) -> AdmissionControlResult {
        journal.invalidate(generation: generation)
    }

    func performCleanup(
        generation: AdmissionGeneration
    ) -> AdmissionCleanupTurnResult {
        journal.performCleanup(generation: generation)
    }

    var diagnostics: OrderedFactJournalDiagnostics {
        journal.diagnostics
    }

    var authoritySnapshot: OrderedFactJournalAuthoritySnapshot {
        journal.authoritySnapshot
    }

    var operationSnapshot: OrderedFactJournalOperationSnapshot {
        journal.operationSnapshot
    }
}

extension OrderedFactJournal {
    var producerPort: OrderedFactProducerPort<Fact, Snapshot> {
        OrderedFactProducerPort(journal: self)
    }

    var consumerPort: OrderedFactConsumerPort<Fact, Snapshot> {
        OrderedFactConsumerPort(journal: self)
    }

    var lifecyclePort: OrderedFactLifecyclePort<Fact, Snapshot> {
        OrderedFactLifecyclePort(journal: self)
    }
}
