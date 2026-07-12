import Dispatch
import Foundation
import Testing
import os

@testable import AgentStudio

@Suite("Admission LatestValueMailbox cleanup finalization")
struct AdmissionLatestCleanupFinalizationTests {
    private let generation = AdmissionGeneration(owner: .terminalViewport, value: 37)

    @Test("finalization reserves released auxiliary capacity before producer refill")
    // swiftlint:disable:next function_body_length
    func finalizationReservesBeforeProducerRefill() {
        let gate = LatestFinalizationDeinitGate()
        let resultBox = LatestFinalizationResultBox<AdmissionCleanupTurnResult>()
        let mailbox = makePayloadMailbox(
            declaredKeys: [0, 1, 2, 3],
            deliveryLimit: 2,
            auxiliaryLimit: 4
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding

        _ = producer.offer(
            generation: generation,
            key: 0,
            value: LatestFinalizationPayload(identity: 0)
        )
        _ = producer.offer(
            generation: generation,
            key: 1,
            value: LatestFinalizationPayload(identity: 1)
        )
        guard
            let initialToken = takePayloadToken(
                consumer: consumer,
                binding: binding,
                expectedIdentities: [0: 0, 1: 1]
            )
        else { return }

        _ = producer.offer(
            generation: generation,
            key: 2,
            value: LatestFinalizationPayload(identity: 20, deinitGate: gate)
        )
        _ = producer.offer(
            generation: generation,
            key: 3,
            value: LatestFinalizationPayload(identity: 30)
        )
        _ = producer.offer(
            generation: generation,
            key: 2,
            value: LatestFinalizationPayload(identity: 21)
        )
        _ = producer.offer(
            generation: generation,
            key: 3,
            value: LatestFinalizationPayload(identity: 31)
        )
        #expect(
            consumer.acknowledge(initialToken, disposition: .transferred)
                == .accepted(wake: .scheduleDrain)
        )
        #expect(lifecycle.diagnostics.pendingValueCount == 2)
        #expect(lifecycle.diagnostics.leasedValueCount == 0)
        #expect(lifecycle.diagnostics.cleanupValueCount == 4)

        let leaseSequenceBeforeCleanup = lifecycle.authoritySnapshot.leaseSequence
        DispatchQueue(label: "agentstudio.tests.latest-finalization-cleanup").async {
            resultBox.store(consumer.performCleanup(generation: generation))
            gate.completed.signal()
        }
        guard waitForSignal(gate.entered, message: "cleanup payload did not enter deinit") else {
            gate.release.signal()
            return
        }

        let firstOfferWhileInFlight = producer.offer(
            generation: generation,
            key: 0,
            value: LatestFinalizationPayload(identity: 10)
        )
        let secondOfferWhileInFlight = producer.offer(
            generation: generation,
            key: 1,
            value: LatestFinalizationPayload(identity: 11)
        )
        #expect(firstOfferWhileInFlight.receipt == .admitted)
        #expect(firstOfferWhileInFlight.wake == .noWake)
        #expect(secondOfferWhileInFlight.receipt == .admitted)
        #expect(secondOfferWhileInFlight.wake == .noWake)
        #expect(lifecycle.diagnostics.pendingValueCount == 4)
        #expect(lifecycle.diagnostics.leasedValueCount == 0)
        #expect(lifecycle.diagnostics.cleanupValueCount == 4)
        #expect(lifecycle.diagnostics.physicalRetainedValueCount == 8)
        #expect(lifecycle.diagnostics.outstandingCleanupTurnCount == 1)

        gate.release.signal()
        guard waitForSignal(gate.completed, message: "cleanup finalization did not complete") else {
            return
        }
        #expect(
            resultBox.load()
                == .performed(
                    AdmissionCleanupTurn(
                        releasedEntryCount: 1,
                        releasedByteCount: nil,
                        wake: .scheduleDrain
                    )
                )
        )
        #expect(lifecycle.diagnostics.pendingValueCount == 3)
        #expect(lifecycle.diagnostics.leasedValueCount == 1)
        #expect(lifecycle.diagnostics.cleanupValueCount == 3)
        #expect(lifecycle.diagnostics.physicalRetainedValueCount == 7)
        #expect(lifecycle.authoritySnapshot.leaseSequence == leaseSequenceBeforeCleanup + 1)

        let refillAfterReservation = producer.offer(
            generation: generation,
            key: 2,
            value: LatestFinalizationPayload(identity: 22)
        )
        #expect(refillAfterReservation.receipt == .admitted)
        #expect(refillAfterReservation.wake == .noWake)
        #expect(lifecycle.diagnostics.pendingValueCount == 4)
        #expect(lifecycle.diagnostics.leasedValueCount == 1)
        #expect(lifecycle.diagnostics.cleanupValueCount == 3)
        #expect(lifecycle.diagnostics.physicalRetainedValueCount == 8)

        let reservedLeaseSequence = lifecycle.authoritySnapshot.leaseSequence
        guard
            case .drain(let reservedDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected finalization-reserved lease while cleanup remained")
            return
        }
        #expect(reservedDrain.valuesByKey.mapValues(\.identity) == [2: 21])
        #expect(lifecycle.authoritySnapshot.leaseSequence == reservedLeaseSequence)
        #expect(lifecycle.diagnostics.pendingValueCount == 4)
        #expect(lifecycle.diagnostics.leasedValueCount == 1)
        #expect(lifecycle.diagnostics.cleanupValueCount == 3)
    }

    @Test("sealed final cleanup batch reserves and wakes delivery without another offer")
    func sealedFinalBatchReservesAndWakesDelivery() {
        let mailbox = makeIntegerMailbox(declaredKeys: [0, 1])
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding

        _ = producer.offer(generation: generation, key: 0, value: 0)
        guard
            let initialToken = takeIntegerToken(
                consumer: consumer,
                binding: binding,
                expectedValues: [0: 0]
            )
        else { return }
        _ = producer.offer(generation: generation, key: 1, value: 1)
        #expect(
            consumer.acknowledge(initialToken, disposition: .transferred)
                == .accepted(wake: .scheduleDrain)
        )
        #expect(lifecycle.seal(generation: generation) == .applied)

        let leaseSequenceBeforeCleanup = lifecycle.authoritySnapshot.leaseSequence
        #expect(
            consumer.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        releasedEntryCount: 1,
                        releasedByteCount: nil,
                        wake: .scheduleDrain
                    )
                )
        )
        #expect(lifecycle.diagnostics.pendingValueCount == 0)
        #expect(lifecycle.diagnostics.leasedValueCount == 1)
        #expect(lifecycle.diagnostics.cleanupValueCount == 0)
        #expect(lifecycle.authoritySnapshot.leaseSequence == leaseSequenceBeforeCleanup + 1)
        #expect(
            producer.offer(generation: generation, key: 0, value: 2).receipt == .closed
        )

        let reservedLeaseSequence = lifecycle.authoritySnapshot.leaseSequence
        guard
            case .drain(let drain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected sealed accepted work reserved by final cleanup")
            return
        }
        #expect(drain.valuesByKey == [1: 1])
        #expect(lifecycle.authoritySnapshot.leaseSequence == reservedLeaseSequence)
    }

    @Test("rebind before and after reservation preserves one lease and refreshes only when required")
    func rebindBeforeAndAfterReservationPreservesOneLease() {
        let before = makePendingBehindCleanupMailbox()
        let bindingBeforeReservation = before.consumer.bindConsumer().binding
        let sequenceBeforeFinalization = before.lifecycle.authoritySnapshot.leaseSequence
        #expect(
            before.consumer.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        releasedEntryCount: 1,
                        releasedByteCount: nil,
                        wake: .scheduleDrain
                    )
                )
        )
        #expect(before.lifecycle.diagnostics.leasedValueCount == 1)
        #expect(
            before.lifecycle.authoritySnapshot.leaseSequence == sequenceBeforeFinalization + 1
        )
        #expect(
            isLatestAlreadyDraining(
                before.consumer.takeDrain(
                    binding: before.originalBinding,
                    generation: generation
                )
            )
        )
        let sequenceBeforeInitialPresentation = before.lifecycle.authoritySnapshot.leaseSequence
        guard
            case .drain(let beforeDrain) = before.consumer.takeDrain(
                binding: bindingBeforeReservation,
                generation: generation
            )
        else {
            Issue.record("Expected reservation to use the binding installed before finalization")
            return
        }
        #expect(beforeDrain.valuesByKey == [1: 1])
        #expect(
            before.lifecycle.authoritySnapshot.leaseSequence
                == sequenceBeforeInitialPresentation
        )

        let after = makePendingBehindCleanupMailbox()
        let sequenceBeforeAfterFinalization = after.lifecycle.authoritySnapshot.leaseSequence
        #expect(
            after.consumer.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        releasedEntryCount: 1,
                        releasedByteCount: nil,
                        wake: .scheduleDrain
                    )
                )
        )
        #expect(after.lifecycle.diagnostics.leasedValueCount == 1)
        #expect(
            after.lifecycle.authoritySnapshot.leaseSequence
                == sequenceBeforeAfterFinalization + 1
        )
        let sequenceBeforeRebind = after.lifecycle.authoritySnapshot.leaseSequence
        let bindingAfterReservation = after.consumer.bindConsumer().binding
        #expect(
            isLatestAlreadyDraining(
                after.consumer.takeDrain(
                    binding: after.originalBinding,
                    generation: generation
                )
            )
        )
        guard
            case .drain(let afterDrain) = after.consumer.takeDrain(
                binding: bindingAfterReservation,
                generation: generation
            )
        else {
            Issue.record("Expected rebind to present the identical reserved custody")
            return
        }
        #expect(afterDrain.valuesByKey == [1: 1])
        #expect(after.lifecycle.authoritySnapshot.leaseSequence == sequenceBeforeRebind + 1)
        #expect(after.lifecycle.diagnostics.outstandingLeaseCount == 1)
    }

    @Test("cleanup overlapping an incumbent lease preserves its token and reserves only later")
    func incumbentLeaseSurvivesCleanupFinalization() {
        let mailbox = makeIntegerMailbox(declaredKeys: [0, 1])
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding

        _ = producer.offer(generation: generation, key: 0, value: 0)
        guard
            case .drain(let incumbentDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected incumbent lease")
            return
        }
        _ = producer.offer(generation: generation, key: 1, value: 10)
        _ = producer.offer(generation: generation, key: 1, value: 11)

        let incumbentSequence = lifecycle.authoritySnapshot.leaseSequence
        #expect(
            consumer.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        releasedEntryCount: 1,
                        releasedByteCount: nil,
                        wake: .noWake
                    )
                )
        )
        #expect(lifecycle.authoritySnapshot.leaseSequence == incumbentSequence)
        #expect(lifecycle.diagnostics.pendingValueCount == 1)
        #expect(lifecycle.diagnostics.leasedValueCount == 1)
        #expect(lifecycle.diagnostics.cleanupValueCount == 0)
        #expect(
            isLatestAlreadyDraining(
                consumer.takeDrain(binding: binding, generation: generation)
            )
        )
        #expect(
            consumer.acknowledge(incumbentDrain.token, disposition: .transferred)
                == .accepted(wake: .scheduleDrain)
        )

        #expect(
            consumer.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        releasedEntryCount: 1,
                        releasedByteCount: nil,
                        wake: .scheduleDrain
                    )
                )
        )
        #expect(lifecycle.diagnostics.pendingValueCount == 0)
        #expect(lifecycle.diagnostics.leasedValueCount == 1)
        guard
            case .drain(let pendingDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected pending value to reserve after incumbent acknowledgement")
            return
        }
        #expect(pendingDrain.valuesByKey == [1: 11])
    }

    @Test("empty pending and invalidated lifecycle never create a reserved lease")
    func zeroEligibilityBranchesDoNotReserve() {
        let cleanupOnly = makeIntegerMailbox(declaredKeys: [0])
        let cleanupOnlyProducer = cleanupOnly.producerPort
        let cleanupOnlyConsumer = cleanupOnly.consumerPort
        let cleanupOnlyLifecycle = cleanupOnly.lifecyclePort
        let cleanupOnlyBinding = cleanupOnlyConsumer.bindConsumer().binding
        _ = cleanupOnlyProducer.offer(generation: generation, key: 0, value: 0)
        guard
            let cleanupOnlyToken = takeIntegerToken(
                consumer: cleanupOnlyConsumer,
                binding: cleanupOnlyBinding,
                expectedValues: [0: 0]
            )
        else { return }
        _ = cleanupOnlyConsumer.acknowledge(cleanupOnlyToken, disposition: .transferred)
        #expect(
            cleanupOnlyConsumer.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        releasedEntryCount: 1,
                        releasedByteCount: nil,
                        wake: .noWake
                    )
                )
        )
        #expect(cleanupOnlyLifecycle.diagnostics.leasedValueCount == 0)
        #expect(cleanupOnlyLifecycle.diagnostics.isQuiescent)

        let invalidated = makeIntegerMailbox(declaredKeys: [0])
        let invalidatedProducer = invalidated.producerPort
        let invalidatedConsumer = invalidated.consumerPort
        let invalidatedLifecycle = invalidated.lifecyclePort
        let invalidatedBinding = invalidatedConsumer.bindConsumer().binding
        _ = invalidatedProducer.offer(generation: generation, key: 0, value: 0)
        _ = invalidatedProducer.offer(generation: generation, key: 0, value: 1)
        #expect(invalidatedLifecycle.invalidate(generation: generation) == .applied)
        #expect(
            invalidatedConsumer.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        releasedEntryCount: 1,
                        releasedByteCount: nil,
                        wake: .scheduleDrain
                    )
                )
        )
        #expect(invalidatedLifecycle.diagnostics.leasedValueCount == 0)
        #expect(
            invalidatedConsumer.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        releasedEntryCount: 1,
                        releasedByteCount: nil,
                        wake: .noWake
                    )
                )
        )
        #expect(invalidatedLifecycle.diagnostics.leasedValueCount == 0)
        #expect(
            isLatestClosed(
                invalidatedConsumer.takeDrain(
                    binding: invalidatedBinding,
                    generation: generation
                )
            )
        )
    }

    private func makeIntegerMailbox(
        declaredKeys: Set<Int>
    ) -> LatestValueMailbox<Int, Int> {
        LatestValueMailbox(
            generation: generation,
            declaredKeys: declaredKeys,
            limits: LatestValueLimits(
                maximumValuesPerLease: 1,
                maximumAuxiliaryRetainedValues: 2,
                cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 1, maximumBytes: nil)
            )
        )
    }

    private func makePayloadMailbox(
        declaredKeys: Set<Int>,
        deliveryLimit: Int,
        auxiliaryLimit: Int
    ) -> LatestValueMailbox<Int, LatestFinalizationPayload> {
        LatestValueMailbox(
            generation: generation,
            declaredKeys: declaredKeys,
            limits: LatestValueLimits(
                maximumValuesPerLease: deliveryLimit,
                maximumAuxiliaryRetainedValues: auxiliaryLimit,
                cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 1, maximumBytes: nil)
            )
        )
    }

    private func makePendingBehindCleanupMailbox() -> PendingBehindCleanupMailbox {
        let mailbox = makeIntegerMailbox(declaredKeys: [0, 1])
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let originalBinding = consumer.bindConsumer().binding
        _ = producer.offer(generation: generation, key: 0, value: 0)
        let token = takeIntegerToken(
            consumer: consumer,
            binding: originalBinding,
            expectedValues: [0: 0]
        )
        _ = producer.offer(generation: generation, key: 1, value: 1)
        if let token {
            _ = consumer.acknowledge(token, disposition: .transferred)
        }
        return PendingBehindCleanupMailbox(
            consumer: consumer,
            lifecycle: lifecycle,
            originalBinding: originalBinding
        )
    }

    private func takeIntegerToken(
        consumer: LatestValueConsumerPort<Int, Int>,
        binding: AdmissionConsumerBinding,
        expectedValues: [Int: Int]
    ) -> AdmissionDrainToken? {
        guard
            case .drain(let drain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected integer latest-value drain")
            return nil
        }
        #expect(drain.valuesByKey == expectedValues)
        return drain.token
    }

    private func takePayloadToken(
        consumer: LatestValueConsumerPort<Int, LatestFinalizationPayload>,
        binding: AdmissionConsumerBinding,
        expectedIdentities: [Int: Int]
    ) -> AdmissionDrainToken? {
        guard
            case .drain(let drain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected payload latest-value drain")
            return nil
        }
        #expect(drain.valuesByKey.mapValues(\.identity) == expectedIdentities)
        return drain.token
    }
}

private struct PendingBehindCleanupMailbox {
    let consumer: LatestValueConsumerPort<Int, Int>
    let lifecycle: LatestValueLifecyclePort<Int, Int>
    let originalBinding: AdmissionConsumerBinding
}

private final class LatestFinalizationDeinitGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let completed = DispatchSemaphore(value: 0)
}

private final class LatestFinalizationPayload: @unchecked Sendable {
    let identity: Int
    private let deinitGate: LatestFinalizationDeinitGate?

    init(identity: Int, deinitGate: LatestFinalizationDeinitGate? = nil) {
        self.identity = identity
        self.deinitGate = deinitGate
    }

    deinit {
        guard let deinitGate else { return }
        deinitGate.entered.signal()
        _ = deinitGate.release.wait(timeout: .now() + 2)
    }
}

private final class LatestFinalizationResultBox<Value: Sendable>: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<Value?>(initialState: nil)

    func store(_ value: Value) {
        lock.withLock { storedValue in
            storedValue = value
        }
    }

    func load() -> Value? {
        lock.withLock { $0 }
    }
}

private func waitForSignal(
    _ semaphore: DispatchSemaphore,
    message: String
) -> Bool {
    guard semaphore.wait(timeout: .now() + 2) == .success else {
        Issue.record(Comment(rawValue: message))
        return false
    }
    return true
}

private func isLatestAlreadyDraining<Key, Value>(
    _ result: LatestValueDrainResult<Key, Value>
) -> Bool where Key: Hashable & Sendable, Value: Sendable {
    if case .alreadyDraining = result { return true }
    return false
}

private func isLatestClosed<Key, Value>(
    _ result: LatestValueDrainResult<Key, Value>
) -> Bool where Key: Hashable & Sendable, Value: Sendable {
    if case .closed = result { return true }
    return false
}
