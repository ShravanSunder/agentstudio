import Foundation
import Testing

@testable import AgentStudio

@Suite("Admission Rebind Doorbell Composition")
struct AdmissionRebindDoorbellCompositionTests {
    private enum RebindKey: Hashable, Sendable {
        case primary
    }

    private enum RebindFact: Equatable, Sendable {
        case started
    }

    private struct RebindSnapshot: Equatable, Sendable {
        let value: String
    }

    @Test("latest rebind reconstructs a consumed doorbell level without a new offer")
    func latestRebindReconstructsConsumedDoorbellLevel() async throws {
        // Arrange
        let generation = AdmissionGeneration(owner: .terminalViewport, value: 101)
        let mailbox = LatestValueMailbox<RebindKey, Int>(
            generation: generation,
            declaredKeys: [.primary],
            limits: makeLatestValueTestLimits(
                cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 1, maximumBytes: nil)
            )
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let doorbell = AdmissionDoorbell()
        let doorbellOwner = doorbell.ownerPort
        let doorbellConsumer = doorbell.consumerPort
        let doorbellLifecycle = doorbell.lifecyclePort
        let bindingCoordinator = AdmissionBindingDoorbellCoordinator(
            doorbellOwner: doorbellOwner
        )
        let firstBind = bindingCoordinator.bind(consumer)
        let offer = producer.offer(generation: generation, key: .primary, value: 41)
        doorbellOwner.apply(offer.wake)
        #expect(
            try await consumePendingSignal(
                consumer: doorbellConsumer,
                lifecycle: doorbellLifecycle
            ) == .signaled
        )
        let oldDrain = try requireLatestDrain(
            consumer.takeDrain(binding: firstBind.binding, generation: generation)
        )

        // Act
        let replacementBind = bindingCoordinator.bind(consumer)
        #expect(
            try await consumePendingSignal(
                consumer: doorbellConsumer,
                lifecycle: doorbellLifecycle
            ) == .signaled
        )
        let replacementDrain = try requireLatestDrain(
            consumer.takeDrain(binding: replacementBind.binding, generation: generation)
        )
        let oldAcknowledgement = consumer.acknowledge(
            oldDrain.token,
            disposition: .transferred
        )
        let replacementAcknowledgement = consumer.acknowledge(
            replacementDrain.token,
            disposition: .transferred
        )
        doorbellOwner.apply(acknowledgementWake(replacementAcknowledgement))

        // Assert
        #expect(replacementBind.wake == .scheduleDrain)
        #expect(replacementDrain.valuesByKey == oldDrain.valuesByKey)
        #expect(replacementDrain.token != oldDrain.token)
        #expect(oldAcknowledgement == .invalidToken)
        #expect(replacementAcknowledgement == .accepted(wake: .scheduleDrain))
        #expect(doorbellLifecycle.stateSnapshot.hasPendingSignal)
        doorbellLifecycle.finish()
    }

    @Test("gather recovery rebind reconstructs a consumed doorbell level without a new offer")
    func gatherRecoveryRebindReconstructsConsumedDoorbellLevel() async throws {
        // Arrange
        let generation = AdmissionGeneration(owner: .filesystemRepair, value: 102)
        let mailbox = BoundedGatherMailbox<RebindKey, Int>(
            generation: generation,
            declaredKeys: [.primary],
            limits: GatherMailboxLimits(
                maximumDeclaredKeys: 1,
                maximumRetainedContributions: 0,
                maximumRetainedItems: 0,
                maximumRetainedBytes: 0,
                maximumRetainedContributionsPerKey: 0,
                maximumRetainedItemsPerKey: 0,
                maximumRetainedBytesPerKey: 0,
                maximumContributionsPerLease: 1,
                maximumItemsPerLease: 1,
                maximumBytesPerLease: 1,
                cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 1, maximumBytes: 1)
            )
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let doorbell = AdmissionDoorbell()
        let doorbellOwner = doorbell.ownerPort
        let doorbellConsumer = doorbell.consumerPort
        let doorbellLifecycle = doorbell.lifecyclePort
        let bindingCoordinator = AdmissionBindingDoorbellCoordinator(
            doorbellOwner: doorbellOwner
        )
        let firstBind = bindingCoordinator.bind(consumer)
        let offer = producer.offer(
            generation: generation,
            contribution: GatherContribution(
                key: RebindKey.primary,
                payload: 7,
                footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                recoverySignal: .authoritativeRecoveryRequired
            )
        )
        doorbellOwner.apply(offer.wake)
        #expect(
            try await consumePendingSignal(
                consumer: doorbellConsumer,
                lifecycle: doorbellLifecycle
            ) == .signaled
        )
        let oldLease = try requireGatherLease(
            consumer.takeDrain(binding: firstBind.binding, generation: generation)
        )

        // Act
        let replacementBind = bindingCoordinator.bind(consumer)
        #expect(
            try await consumePendingSignal(
                consumer: doorbellConsumer,
                lifecycle: doorbellLifecycle
            ) == .signaled
        )
        let replacementLease = try requireGatherLease(
            consumer.takeDrain(binding: replacementBind.binding, generation: generation)
        )
        let oldAcknowledgement = consumer.acknowledge(
            token: oldLease.token,
            disposition: .transferred
        )
        let replacementAcknowledgement = consumer.acknowledge(
            token: replacementLease.token,
            disposition: .transferred
        )
        doorbellOwner.apply(acknowledgementWake(replacementAcknowledgement))

        // Assert
        #expect(replacementBind.wake == .scheduleDrain)
        #expect(oldLease.contributions.isEmpty)
        #expect(oldLease.recoveryRevision != nil)
        #expect(replacementLease.contributions.isEmpty)
        #expect(replacementLease.recoveryRevision == oldLease.recoveryRevision)
        #expect(replacementLease.token != oldLease.token)
        #expect(oldAcknowledgement == .invalidToken)
        #expect(replacementAcknowledgement == .accepted(wake: .noWake))
        #expect(doorbellLifecycle.stateSnapshot.hasPendingSignal == false)
        doorbellLifecycle.finish()
    }

    @Test("journal fact rebind reconstructs a consumed doorbell level without a new offer")
    func journalFactRebindReconstructsConsumedDoorbellLevel() async throws {
        // Arrange
        let generation = AdmissionGeneration(owner: .runtimeFacts, value: 103)
        let journal = try OrderedFactJournal<RebindFact, RebindSnapshot>(
            generation: generation,
            maximumRetainedFacts: 1,
            maximumRetainedBytes: 8,
            snapshotLimits: OrderedFactSnapshotLimits(
                maximumSnapshotBytes: 8,
                maximumPhysicalSnapshotCount: Int.max,
                maximumPhysicalSnapshotBytes: Int.max
            ),
            maximumDrainFacts: 1,
            cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 1, maximumBytes: 8),
            initialSnapshot: nil,
            initialSnapshotBytes: 0
        )
        let producer = journal.producerPort
        let consumer = journal.consumerPort
        let doorbell = AdmissionDoorbell()
        let doorbellOwner = doorbell.ownerPort
        let doorbellConsumer = doorbell.consumerPort
        let doorbellLifecycle = doorbell.lifecyclePort
        let bindingCoordinator = AdmissionBindingDoorbellCoordinator(
            doorbellOwner: doorbellOwner
        )
        let firstBind = bindingCoordinator.bind(consumer)
        let offer = producer.offer(
            generation: generation,
            fact: RebindFact.started,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        doorbellOwner.apply(offerWake(offer))
        #expect(
            try await consumePendingSignal(
                consumer: doorbellConsumer,
                lifecycle: doorbellLifecycle
            ) == .signaled
        )
        let oldDrain = try requireJournalFactDrain(
            consumer.takeDrain(binding: firstBind.binding, generation: generation)
        )

        // Act
        let replacementBind = bindingCoordinator.bind(consumer)
        #expect(
            try await consumePendingSignal(
                consumer: doorbellConsumer,
                lifecycle: doorbellLifecycle
            ) == .signaled
        )
        let replacementDrain = try requireJournalFactDrain(
            consumer.takeDrain(binding: replacementBind.binding, generation: generation)
        )
        let oldAcknowledgement = consumer.acknowledge(
            oldDrain.token,
            disposition: .transferred
        )
        let replacementAcknowledgement = consumer.acknowledge(
            replacementDrain.token,
            disposition: .transferred
        )
        doorbellOwner.apply(acknowledgementWake(replacementAcknowledgement))

        // Assert
        #expect(replacementBind.wake == .scheduleDrain)
        #expect(replacementDrain.facts.map(\.sequence) == oldDrain.facts.map(\.sequence))
        #expect(replacementDrain.facts.map(\.fact) == oldDrain.facts.map(\.fact))
        #expect(replacementDrain.token != oldDrain.token)
        #expect(oldAcknowledgement == .invalidToken)
        #expect(replacementAcknowledgement == .accepted(wake: .noWake))
        #expect(doorbellLifecycle.stateSnapshot.hasPendingSignal == false)
        doorbellLifecycle.finish()
    }

    @Test("journal gap rebind reconstructs a consumed doorbell level without a new offer")
    func journalGapRebindReconstructsConsumedDoorbellLevel() async throws {
        // Arrange
        let generation = AdmissionGeneration(owner: .runtimeFacts, value: 104)
        let journal = try OrderedFactJournal<RebindFact, RebindSnapshot>(
            generation: generation,
            maximumRetainedFacts: 0,
            maximumRetainedBytes: 0,
            snapshotLimits: OrderedFactSnapshotLimits(
                maximumSnapshotBytes: 8,
                maximumPhysicalSnapshotCount: Int.max,
                maximumPhysicalSnapshotBytes: Int.max
            ),
            maximumDrainFacts: 1,
            cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 1, maximumBytes: 8),
            initialSnapshot: nil,
            initialSnapshotBytes: 0
        )
        let producer = journal.producerPort
        let consumer = journal.consumerPort
        let doorbell = AdmissionDoorbell()
        let doorbellOwner = doorbell.ownerPort
        let doorbellConsumer = doorbell.consumerPort
        let doorbellLifecycle = doorbell.lifecyclePort
        let bindingCoordinator = AdmissionBindingDoorbellCoordinator(
            doorbellOwner: doorbellOwner
        )
        let firstBind = bindingCoordinator.bind(consumer)
        let offer = producer.offer(
            generation: generation,
            fact: RebindFact.started,
            estimatedFactBytes: 8,
            snapshotReplacement: nil
        )
        doorbellOwner.apply(offerWake(offer))
        #expect(
            try await consumePendingSignal(
                consumer: doorbellConsumer,
                lifecycle: doorbellLifecycle
            ) == .signaled
        )
        let oldDrain = try requireJournalGapDrain(
            consumer.takeDrain(binding: firstBind.binding, generation: generation)
        )

        // Act
        let replacementBind = bindingCoordinator.bind(consumer)
        #expect(
            try await consumePendingSignal(
                consumer: doorbellConsumer,
                lifecycle: doorbellLifecycle
            ) == .signaled
        )
        let replacementDrain = try requireJournalGapDrain(
            consumer.takeDrain(binding: replacementBind.binding, generation: generation)
        )
        let oldAcknowledgement = consumer.acknowledge(
            oldDrain.token,
            disposition: .transferred
        )
        let replacementAcknowledgement = consumer.acknowledge(
            replacementDrain.token,
            disposition: .transferred
        )
        doorbellOwner.apply(acknowledgementWake(replacementAcknowledgement))

        // Assert
        #expect(replacementBind.wake == .scheduleDrain)
        #expect(replacementDrain.gap == oldDrain.gap)
        #expect(replacementDrain.token != oldDrain.token)
        #expect(oldAcknowledgement == .invalidToken)
        #expect(replacementAcknowledgement == .accepted(wake: .noWake))
        #expect(doorbellLifecycle.stateSnapshot.hasPendingSignal == false)
        doorbellLifecycle.finish()
    }

    private func requireLatestDrain(
        _ result: LatestValueDrainResult<RebindKey, Int>
    ) throws -> LatestValueDrain<RebindKey, Int> {
        guard case .drain(let drain) = result else {
            Issue.record("Expected a latest-value drain, got \(String(reflecting: result))")
            throw AdmissionRebindDoorbellTestError.expectedDrain
        }
        return drain
    }

    private func requireGatherLease(
        _ result: GatherTakeDrainResult<RebindKey, Int>
    ) throws -> GatherDrainLease<RebindKey, Int> {
        guard case .lease(let lease) = result else {
            Issue.record("Expected a gather recovery lease, got \(String(reflecting: result))")
            throw AdmissionRebindDoorbellTestError.expectedDrain
        }
        return lease
    }

    private func requireJournalFactDrain(
        _ result: OrderedFactTakeDrainResult<RebindFact>
    ) throws -> (token: AdmissionDrainToken, facts: [SequencedFact<RebindFact>]) {
        guard case .drain(let drain) = result,
            case .facts(let facts) = drain.payload
        else {
            Issue.record("Expected an ordered fact drain, got \(String(reflecting: result))")
            throw AdmissionRebindDoorbellTestError.expectedDrain
        }
        return (drain.token, facts)
    }

    private func requireJournalGapDrain(
        _ result: OrderedFactTakeDrainResult<RebindFact>
    ) throws -> (token: AdmissionDrainToken, gap: FactGap) {
        guard case .drain(let drain) = result,
            case .gap(let gap) = drain.payload
        else {
            Issue.record("Expected an ordered persistent-gap drain, got \(String(reflecting: result))")
            throw AdmissionRebindDoorbellTestError.expectedDrain
        }
        return (drain.token, gap)
    }

    private func offerWake(_ result: OrderedFactOfferResult) -> AdmissionWakeDirective {
        if case .admitted(_, let wake) = result { return wake }
        if case .gapCommitted(_, let wake) = result { return wake }
        return .noWake
    }

    private func acknowledgementWake(
        _ acknowledgement: AdmissionDrainAcknowledgement
    ) -> AdmissionWakeDirective {
        guard case .accepted(let wake) = acknowledgement else { return .noWake }
        return wake
    }

    private func consumePendingSignal(
        consumer: AdmissionDoorbellConsumerPort,
        lifecycle: AdmissionDoorbellLifecyclePort
    ) async throws -> AdmissionDoorbellResult {
        guard lifecycle.stateSnapshot.hasPendingSignal else {
            Issue.record("Expected a concrete pending doorbell level before waiting")
            throw AdmissionRebindDoorbellTestError.expectedPendingDoorbellLevel
        }
        return await consumer.nextSignal()
    }
}

private enum AdmissionRebindDoorbellTestError: Error {
    case expectedDrain
    case expectedPendingDoorbellLevel
}
