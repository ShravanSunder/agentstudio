import Dispatch
import Foundation
import Testing

@testable import AgentStudio

@Suite("Admission LatestValueMailbox authoritative currentness")
struct AdmissionLatestAuthoritativeCurrentnessTests {
    private let generation = AdmissionGeneration(owner: .terminalViewport, value: 43)

    @Test("compile-time dispositions separate lossy and authoritative wrappers")
    func overloadDispositionsSeparateLossyAndAuthoritativeWrappers() {
        let lossyMailbox = makeSaturatedMailbox()
        let lossyWrapper = LatestValueLossyTestWrapper(
            producer: LatestValueTestProducer<LatestValueLossyPresentation, Int>(
                producer: lossyMailbox.producerPort
            )
        )
        let lossyResult = lossyWrapper.offer(key: 0, value: 3)
        #expect(lossyResult.receipt == .physicalCapacityExceeded)

        let authoritativeWrapper = makeSaturatedAuthoritativeWrapper()
        let revisionOwner = authoritativeWrapper.revisionOwner
        let firstResult = authoritativeWrapper.offerAdvancedSource(key: 0, value: 3)
        #expect(firstResult.offerResult.receipt == .physicalCapacityExceeded)
        guard let firstSourceRevision = firstResult.sourceRevision else {
            Issue.record("Expected a declared authoritative source revision")
            return
        }
        #expect(
            revisionOwner.snapshot(for: 0).dirtyRevision
                == firstSourceRevision
        )

        let repeatedResult = authoritativeWrapper.reofferCurrentSource(
            key: 0,
            value: 3,
            sourceRevision: firstSourceRevision
        )
        #expect(repeatedResult.receipt == .physicalCapacityExceeded)
        #expect(
            revisionOwner.snapshot(for: 0).dirtyRevision
                == firstSourceRevision
        )
        #expect(revisionOwner.dirtyKeyCount == 1)
    }

    @Test("authoritative wrapper preserves typed rejection for undeclared keys")
    func authoritativeWrapperPreservesTypedRejectionForUndeclaredKeys() {
        let wrapper = makeSaturatedAuthoritativeWrapper()
        let revisionOwner = wrapper.revisionOwner

        let result = wrapper.offerAdvancedSource(key: 1, value: 3)

        #expect(result.offerResult.receipt == .undeclaredKey)
        #expect(result.sourceRevision == nil)
        #expect(revisionOwner.snapshotIfDeclared(for: 1) == nil)
        #expect(revisionOwner.dirtyKeyCount == 0)
        #expect(
            revisionOwner.snapshot(for: 0)
                == LatestValueCurrentnessSnapshot(
                    currentSourceRevision: LatestValueTestSourceRevision(
                        generation: 1,
                        revision: 0
                    ),
                    dirtyRevision: nil
                )
        )
    }

    @Test("capacity rejection recreates cleared dirty debt through wrapper")
    func capacityRejectionRecreatesClearedDirtyDebtThroughWrapper() {
        let wrapper = makeSaturatedAuthoritativeWrapper()
        let revisionOwner = wrapper.revisionOwner
        let currentRevision = revisionOwner.advanceSource(for: 0)
        #expect(
            revisionOwner.completeTransfer(
                for: 0,
                transferredRevision: currentRevision
            )
        )
        #expect(revisionOwner.snapshot(for: 0).dirtyRevision == nil)

        let result = wrapper.reofferCurrentSource(
            key: 0,
            value: 3,
            sourceRevision: currentRevision
        )

        #expect(result.receipt == .physicalCapacityExceeded)
        #expect(revisionOwner.snapshot(for: 0).dirtyRevision == currentRevision)
        #expect(revisionOwner.dirtyKeyCount == 1)
    }

    @Test("authoritative wrapper shares one manifest across mailbox and currentness")
    func authoritativeWrapperSharesOneManifestAcrossMailboxAndCurrentness() {
        let wrapper = LatestValueAuthoritativeTestWrapper<Int>(
            admissionGeneration: generation,
            currentnessGeneration: 1,
            declaredKeys: [0, 1],
            limits: LatestValueLimits(
                maximumValuesPerLease: 1,
                maximumAuxiliaryRetainedValues: 2,
                cleanupQuantum: AdmissionCleanupQuantum(
                    maximumEntries: 1,
                    maximumBytes: nil
                )
            )
        )

        let firstDeclared = wrapper.offerAdvancedSource(key: 0, value: 1)
        let secondDeclared = wrapper.offerAdvancedSource(key: 1, value: 1)
        let undeclared = wrapper.offerAdvancedSource(key: 2, value: 1)

        #expect(firstDeclared.offerResult.receipt == .admitted)
        #expect(firstDeclared.sourceRevision != nil)
        #expect(secondDeclared.offerResult.receipt == .admitted)
        #expect(secondDeclared.sourceRevision != nil)
        #expect(undeclared.offerResult.receipt == .undeclaredKey)
        #expect(undeclared.sourceRevision == nil)
        #expect(
            wrapper.revisionOwner.snapshotIfDeclared(for: 0)?.currentSourceRevision.revision == 1
        )
        #expect(
            wrapper.revisionOwner.snapshotIfDeclared(for: 1)?.currentSourceRevision.revision == 1
        )
        #expect(wrapper.revisionOwner.snapshotIfDeclared(for: 2) == nil)
    }

    @Test("transfer clearing requires every currentness term")
    func transferClearRequiresEveryCurrentnessTerm() {
        let generationOneRevisionOne = LatestValueTestSourceRevision(
            generation: 1,
            revision: 1
        )
        let generationOneRevisionTwo = LatestValueTestSourceRevision(
            generation: 1,
            revision: 2
        )
        let generationTwoRevisionOne = LatestValueTestSourceRevision(
            generation: 2,
            revision: 1
        )

        #expect(
            LatestValueAuthoritativeRevisionOwner.shouldClear(
                dirtyRevision: generationOneRevisionOne,
                transferredRevision: generationOneRevisionOne,
                currentSourceRevision: generationOneRevisionOne
            )
        )
        #expect(
            !LatestValueAuthoritativeRevisionOwner.shouldClear(
                dirtyRevision: generationOneRevisionOne,
                transferredRevision: generationOneRevisionTwo,
                currentSourceRevision: generationOneRevisionTwo
            )
        )
        #expect(
            !LatestValueAuthoritativeRevisionOwner.shouldClear(
                dirtyRevision: generationOneRevisionOne,
                transferredRevision: generationOneRevisionTwo,
                currentSourceRevision: generationOneRevisionOne
            )
        )
        #expect(
            !LatestValueAuthoritativeRevisionOwner.shouldClear(
                dirtyRevision: generationOneRevisionOne,
                transferredRevision: generationOneRevisionOne,
                currentSourceRevision: generationOneRevisionTwo
            )
        )
        #expect(
            !LatestValueAuthoritativeRevisionOwner.shouldClear(
                dirtyRevision: generationOneRevisionOne,
                transferredRevision: generationTwoRevisionOne,
                currentSourceRevision: generationTwoRevisionOne
            )
        )
    }

    @Test("dirty revisions coalesce and survive generation rotation")
    func dirtyRevisionCoalescesAndSurvivesGenerationRotation() {
        let owner = LatestValueAuthoritativeRevisionOwner(
            generation: 1,
            declaredKeys: [0]
        )
        let firstRevision = owner.advanceSource(for: 0)
        owner.recordCapacityRejection(for: 0, attemptedRevision: firstRevision)
        owner.recordCapacityRejection(for: 0, attemptedRevision: firstRevision)
        #expect(owner.snapshot(for: 0).dirtyRevision == firstRevision)
        #expect(owner.dirtyKeyCount == 1)

        let secondRevision = owner.advanceSource(for: 0)
        #expect(owner.snapshot(for: 0).dirtyRevision == secondRevision)
        owner.recordCapacityRejection(for: 0, attemptedRevision: firstRevision)
        #expect(owner.snapshot(for: 0).dirtyRevision == secondRevision)

        let rotatedRevision = owner.rotateGeneration(to: 2)
        #expect(
            rotatedRevision == LatestValueTestSourceRevision(generation: 2, revision: 1)
        )
        #expect(owner.snapshot(for: 0).dirtyRevision == rotatedRevision)
        #expect(
            !owner.completeTransfer(
                for: 0,
                transferredRevision: secondRevision
            )
        )
        #expect(owner.snapshot(for: 0).dirtyRevision == rotatedRevision)
        #expect(
            owner.completeTransfer(
                for: 0,
                transferredRevision: rotatedRevision
            )
        )
        #expect(owner.snapshot(for: 0).dirtyRevision == nil)
    }

    @Test("source advance cannot be lost across compare and clear")
    func sourceAdvanceCannotBeLostAcrossCompareAndClear() {
        let owner = LatestValueAuthoritativeRevisionOwner(
            generation: 1,
            declaredKeys: [0]
        )
        let firstRevision = owner.advanceSource(for: 0)
        let gate = LatestValueCurrentnessComparisonGate()
        let completionResult = LatestValueCurrentnessResultBox<Bool>()
        let contenderProbe = LatestValueCurrentnessContenderProbe()

        DispatchQueue(label: "agentstudio.tests.latest-currentness-clear").async {
            completionResult.store(
                owner.completeTransfer(
                    for: 0,
                    transferredRevision: firstRevision,
                    comparisonGate: gate
                )
            )
            gate.completionFinished.signal()
        }
        guard waitForCurrentnessSignal(gate.comparisonReached) else {
            gate.releaseComparison.signal()
            return
        }

        DispatchQueue(label: "agentstudio.tests.latest-currentness-advance").async {
            _ = owner.advanceSource(for: 0, contenderProbe: contenderProbe)
        }
        guard waitForCurrentnessSignal(contenderProbe.classified) else {
            gate.releaseComparison.signal()
            return
        }
        let contenderFinishedBeforeRelease =
            contenderProbe.disposition == .acquiredImmediately
        if contenderFinishedBeforeRelease {
            guard waitForCurrentnessSignal(contenderProbe.finished) else {
                gate.releaseComparison.signal()
                return
            }
        }
        #expect(contenderProbe.disposition == .blocked)
        gate.releaseComparison.signal()
        guard waitForCurrentnessSignal(gate.completionFinished) else { return }
        if !contenderFinishedBeforeRelease {
            guard waitForCurrentnessSignal(contenderProbe.finished) else { return }
        }

        #expect(completionResult.value == true)
        #expect(
            owner.snapshot(for: 0).currentSourceRevision
                == LatestValueTestSourceRevision(generation: 1, revision: 2)
        )
        #expect(
            owner.snapshot(for: 0).dirtyRevision
                == LatestValueTestSourceRevision(generation: 1, revision: 2)
        )
    }

    @Test("rejection cannot be lost across compare and clear")
    func rejectionCannotBeLostAcrossCompareAndClear() {
        let owner = LatestValueAuthoritativeRevisionOwner(
            generation: 1,
            declaredKeys: [0]
        )
        let firstRevision = owner.advanceSource(for: 0)
        let gate = LatestValueCurrentnessComparisonGate()
        let completionResult = LatestValueCurrentnessResultBox<Bool>()
        let contenderProbe = LatestValueCurrentnessContenderProbe()

        DispatchQueue(label: "agentstudio.tests.latest-currentness-rejection-clear").async {
            completionResult.store(
                owner.completeTransfer(
                    for: 0,
                    transferredRevision: firstRevision,
                    comparisonGate: gate
                )
            )
            gate.completionFinished.signal()
        }
        guard waitForCurrentnessSignal(gate.comparisonReached) else {
            gate.releaseComparison.signal()
            return
        }

        DispatchQueue(label: "agentstudio.tests.latest-currentness-rejection").async {
            owner.recordCapacityRejection(
                for: 0,
                attemptedRevision: firstRevision,
                contenderProbe: contenderProbe
            )
        }
        guard waitForCurrentnessSignal(contenderProbe.classified) else {
            gate.releaseComparison.signal()
            return
        }
        let contenderFinishedBeforeRelease =
            contenderProbe.disposition == .acquiredImmediately
        if contenderFinishedBeforeRelease {
            guard waitForCurrentnessSignal(contenderProbe.finished) else {
                gate.releaseComparison.signal()
                return
            }
        }
        #expect(contenderProbe.disposition == .blocked)
        gate.releaseComparison.signal()
        guard waitForCurrentnessSignal(gate.completionFinished) else { return }
        if !contenderFinishedBeforeRelease {
            guard waitForCurrentnessSignal(contenderProbe.finished) else { return }
        }

        #expect(completionResult.value == true)
        #expect(owner.snapshot(for: 0).dirtyRevision == firstRevision)
    }

    private func makeSaturatedMailbox() -> LatestValueMailbox<Int, Int> {
        let mailbox = LatestValueMailbox<Int, Int>(
            generation: generation,
            declaredKeys: [0],
            limits: saturatedLatestValueLimits
        )
        saturate(
            producer: mailbox.producerPort,
            consumer: mailbox.consumerPort
        )
        return mailbox
    }

    private func makeSaturatedAuthoritativeWrapper()
        -> LatestValueAuthoritativeTestWrapper<Int>
    {
        let wrapper = LatestValueAuthoritativeTestWrapper<Int>(
            admissionGeneration: generation,
            currentnessGeneration: 1,
            declaredKeys: [0],
            limits: saturatedLatestValueLimits
        )
        saturate(
            producer: wrapper.setupProducerPort,
            consumer: wrapper.setupConsumerPort
        )
        return wrapper
    }

    private var saturatedLatestValueLimits: LatestValueLimits {
        LatestValueLimits(
            maximumValuesPerLease: 1,
            maximumAuxiliaryRetainedValues: 2,
            cleanupQuantum: AdmissionCleanupQuantum(
                maximumEntries: 1,
                maximumBytes: nil
            )
        )
    }

    private func saturate(
        producer: LatestValueProducerPort<Int, Int>,
        consumer: LatestValueConsumerPort<Int, Int>
    ) {
        let binding = consumer.bindConsumer().binding
        #expect(producer.offer(generation: generation, key: 0, value: 0).receipt == .admitted)
        guard
            case .drain = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected saturation lease")
            return
        }
        #expect(producer.offer(generation: generation, key: 0, value: 1).receipt == .admitted)
        #expect(
            producer.offer(generation: generation, key: 0, value: 2).receipt
                == .replacedPrevious
        )
    }
}

private struct LatestValueTestProducer<Disposition, Value>: Sendable
where Disposition: LatestValueOverloadDisposition, Value: Sendable {
    let producer: LatestValueProducerPort<Int, Value>
}

private struct LatestValueLossyTestWrapper<Value: Sendable>: Sendable {
    let producer: LatestValueTestProducer<LatestValueLossyPresentation, Value>

    func offer(key: Int, value: Value) -> LatestValueOfferResult {
        producer.producer.offer(
            generation: AdmissionGeneration(owner: .terminalViewport, value: 43),
            key: key,
            value: value
        )
    }
}

private struct LatestValueAuthoritativeTestWrapper<Value: Sendable>: Sendable {
    private let admissionGeneration: AdmissionGeneration
    let producer: LatestValueTestProducer<LatestValueAuthoritativeResample, Value>
    let setupConsumerPort: LatestValueConsumerPort<Int, Value>
    let revisionOwner: LatestValueAuthoritativeRevisionOwner

    init(
        admissionGeneration: AdmissionGeneration,
        currentnessGeneration: UInt64,
        declaredKeys: Set<Int>,
        limits: LatestValueLimits
    ) {
        let mailbox = LatestValueMailbox<Int, Value>(
            generation: admissionGeneration,
            declaredKeys: declaredKeys,
            limits: limits
        )
        self.admissionGeneration = admissionGeneration
        self.producer = LatestValueTestProducer(producer: mailbox.producerPort)
        self.setupConsumerPort = mailbox.consumerPort
        self.revisionOwner = LatestValueAuthoritativeRevisionOwner(
            generation: currentnessGeneration,
            declaredKeys: declaredKeys
        )
    }

    var setupProducerPort: LatestValueProducerPort<Int, Value> {
        producer.producer
    }

    func offerAdvancedSource(
        key: Int,
        value: Value
    ) -> LatestValueAuthoritativeOfferResult {
        guard revisionOwner.containsDeclaredKey(key) else {
            return LatestValueAuthoritativeOfferResult(
                sourceRevision: nil,
                offerResult: producer.producer.offer(
                    generation: admissionGeneration,
                    key: key,
                    value: value
                )
            )
        }
        let sourceRevision = revisionOwner.advanceSource(for: key)
        let offerResult = reofferCurrentSource(
            key: key,
            value: value,
            sourceRevision: sourceRevision
        )
        return LatestValueAuthoritativeOfferResult(
            sourceRevision: sourceRevision,
            offerResult: offerResult
        )
    }

    func reofferCurrentSource(
        key: Int,
        value: Value,
        sourceRevision: LatestValueTestSourceRevision
    ) -> LatestValueOfferResult {
        let result = producer.producer.offer(
            generation: admissionGeneration,
            key: key,
            value: value
        )
        if result.receipt == .physicalCapacityExceeded {
            revisionOwner.recordCapacityRejection(
                for: key,
                attemptedRevision: sourceRevision
            )
        }
        return result
    }
}

private struct LatestValueAuthoritativeOfferResult: Sendable {
    let sourceRevision: LatestValueTestSourceRevision?
    let offerResult: LatestValueOfferResult
}

private struct LatestValueTestSourceRevision: Sendable, Equatable {
    let generation: UInt64
    let revision: UInt64
}

private struct LatestValueCurrentnessSnapshot: Sendable, Equatable {
    let currentSourceRevision: LatestValueTestSourceRevision
    let dirtyRevision: LatestValueTestSourceRevision?
}

private final class LatestValueAuthoritativeRevisionOwner: @unchecked Sendable {
    private struct SlotState {
        var currentRevision: UInt64
        var dirtyRevision: LatestValueTestSourceRevision?
    }

    private let lock = NSLock()
    private let declaredKeys: Set<Int>
    private var generation: UInt64
    private var slotsByKey: [Int: SlotState]

    init(generation: UInt64, declaredKeys: Set<Int>) {
        self.declaredKeys = declaredKeys
        self.generation = generation
        self.slotsByKey = Dictionary(
            uniqueKeysWithValues: declaredKeys.map {
                ($0, SlotState(currentRevision: 0, dirtyRevision: nil))
            }
        )
    }

    var dirtyKeyCount: Int {
        lock.withLock {
            slotsByKey.values.lazy.filter { $0.dirtyRevision != nil }.count
        }
    }

    func containsDeclaredKey(_ key: Int) -> Bool {
        declaredKeys.contains(key)
    }

    func advanceSource(
        for key: Int,
        contenderProbe: LatestValueCurrentnessContenderProbe? = nil
    ) -> LatestValueTestSourceRevision {
        withCurrentnessLock(contenderProbe: contenderProbe) {
            guard var slot = slotsByKey[key] else {
                preconditionFailure("Currentness source advanced an undeclared test key")
            }
            let nextRevision = slot.currentRevision.addingReportingOverflow(1)
            precondition(nextRevision.overflow == false)
            slot.currentRevision = nextRevision.partialValue
            let revision = LatestValueTestSourceRevision(
                generation: generation,
                revision: slot.currentRevision
            )
            slot.dirtyRevision = revision
            slotsByKey[key] = slot
            return revision
        }
    }

    func recordCapacityRejection(
        for key: Int,
        attemptedRevision: LatestValueTestSourceRevision,
        contenderProbe: LatestValueCurrentnessContenderProbe? = nil
    ) {
        withCurrentnessLock(contenderProbe: contenderProbe) {
            guard var slot = slotsByKey[key] else {
                preconditionFailure("Currentness rejection referenced an undeclared test key")
            }
            guard attemptedRevision.generation == generation else { return }
            slot.dirtyRevision = LatestValueTestSourceRevision(
                generation: generation,
                revision: slot.currentRevision
            )
            slotsByKey[key] = slot
        }
    }

    func rotateGeneration(to nextGeneration: UInt64) -> LatestValueTestSourceRevision {
        lock.withLock {
            generation = nextGeneration
            let revision = LatestValueTestSourceRevision(
                generation: nextGeneration,
                revision: 1
            )
            for key in slotsByKey.keys {
                slotsByKey[key] = SlotState(
                    currentRevision: 1,
                    dirtyRevision: revision
                )
            }
            return revision
        }
    }

    func completeTransfer(
        for key: Int,
        transferredRevision: LatestValueTestSourceRevision,
        comparisonGate: LatestValueCurrentnessComparisonGate? = nil
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var slot = slotsByKey[key] else {
            preconditionFailure("Currentness transfer referenced an undeclared test key")
        }
        let currentRevision = LatestValueTestSourceRevision(
            generation: generation,
            revision: slot.currentRevision
        )
        let shouldClear = Self.shouldClear(
            dirtyRevision: slot.dirtyRevision,
            transferredRevision: transferredRevision,
            currentSourceRevision: currentRevision
        )
        if let comparisonGate {
            comparisonGate.comparisonReached.signal()
            guard comparisonGate.releaseComparison.wait(timeout: .now() + 2) == .success else {
                return false
            }
        }
        guard shouldClear else { return false }
        slot.dirtyRevision = nil
        slotsByKey[key] = slot
        return true
    }

    func snapshot(for key: Int) -> LatestValueCurrentnessSnapshot {
        guard let snapshot = snapshotIfDeclared(for: key) else {
            preconditionFailure("Currentness snapshot referenced an undeclared test key")
        }
        return snapshot
    }

    func snapshotIfDeclared(for key: Int) -> LatestValueCurrentnessSnapshot? {
        guard containsDeclaredKey(key) else { return nil }
        return lock.withLock {
            guard let slot = slotsByKey[key] else { return nil }
            return currentnessSnapshot(for: slot)
        }
    }

    private func currentnessSnapshot(for slot: SlotState) -> LatestValueCurrentnessSnapshot {
        LatestValueCurrentnessSnapshot(
            currentSourceRevision: LatestValueTestSourceRevision(
                generation: generation,
                revision: slot.currentRevision
            ),
            dirtyRevision: slot.dirtyRevision
        )
    }

    private func withCurrentnessLock<Result>(
        contenderProbe: LatestValueCurrentnessContenderProbe?,
        _ operation: () -> Result
    ) -> Result {
        guard let contenderProbe else {
            return lock.withLock(operation)
        }
        if lock.try() {
            contenderProbe.store(.acquiredImmediately)
        } else {
            contenderProbe.store(.blocked)
            lock.lock()
        }
        defer {
            lock.unlock()
            contenderProbe.finished.signal()
        }
        return operation()
    }

    static func shouldClear(
        dirtyRevision: LatestValueTestSourceRevision?,
        transferredRevision: LatestValueTestSourceRevision,
        currentSourceRevision: LatestValueTestSourceRevision
    ) -> Bool {
        dirtyRevision == transferredRevision
            && transferredRevision == currentSourceRevision
    }
}

private final class LatestValueCurrentnessComparisonGate: @unchecked Sendable {
    let comparisonReached = DispatchSemaphore(value: 0)
    let releaseComparison = DispatchSemaphore(value: 0)
    let completionFinished = DispatchSemaphore(value: 0)
}

private enum LatestValueCurrentnessContenderDisposition: Sendable, Equatable {
    case acquiredImmediately
    case blocked
}

private final class LatestValueCurrentnessContenderProbe: @unchecked Sendable {
    let classified = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)

    private let dispositionBox =
        LatestValueCurrentnessResultBox<LatestValueCurrentnessContenderDisposition>()

    var disposition: LatestValueCurrentnessContenderDisposition? {
        dispositionBox.value
    }

    func store(_ disposition: LatestValueCurrentnessContenderDisposition) {
        dispositionBox.store(disposition)
        classified.signal()
    }
}

private final class LatestValueCurrentnessResultBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value?

    var value: Value? {
        lock.withLock { storedValue }
    }

    func store(_ value: Value) {
        lock.withLock {
            storedValue = value
        }
    }
}

private func waitForCurrentnessSignal(_ semaphore: DispatchSemaphore) -> Bool {
    guard semaphore.wait(timeout: .now() + 2) == .success else {
        Issue.record("Expected deterministic currentness transition signal")
        return false
    }
    return true
}
