import Foundation
import Testing

@testable import AgentStudio

@Suite("Admission LatestValueMailbox")
struct AdmissionLatestValueMailboxTests {
    enum SampleKey: String, CaseIterable, Sendable {
        case primary
        case secondary
        case tertiary
    }

    let generation = AdmissionGeneration(
        owner: .terminalViewport,
        value: 7
    )
    let cleanupQuantum = AdmissionCleanupQuantum(maximumEntries: 17, maximumBytes: nil)

    @Test("pressure stream identity is a closed manifest with static telemetry names")
    func pressureStreamIdentityIsClosedAndStatic() {
        let expectedTelemetryNames: [PressureStreamID: String] = [
            .filesystemObservation: "filesystem_observation",
            .filesystemRepair: "filesystem_repair",
            .filesystemGitInvalidation: "filesystem_git_invalidation",
            .terminalViewport: "terminal_viewport",
            .terminalActivity: "terminal_activity",
            .runtimeFacts: "runtime_facts",
            .bridgeInvalidation: "bridge_invalidation",
            .performanceEvidence: "performance_evidence",
        ]

        let actualTelemetryNames = Dictionary(
            uniqueKeysWithValues: PressureStreamID.allCases.map { streamID in
                (streamID, String(describing: streamID.telemetryName))
            }
        )

        #expect(actualTelemetryNames == expectedTelemetryNames)
    }

    @Test("consumer rebind re-presents identical custody and rejects the old binding token")
    func consumerRebindPreservesCustodyAndRevokesOldToken() {
        let mailbox = makeMailbox()
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let firstBinding = consumer.bindConsumer().binding
        _ = producer.offer(generation: generation, key: .primary, value: 41)
        guard
            case .drain(let firstDrain) = consumer.takeDrain(
                binding: firstBinding,
                generation: generation
            )
        else {
            Issue.record("Expected the first binding to lease retained custody")
            return
        }

        let replacementBinding = consumer.bindConsumer().binding
        let oldAcknowledgement = consumer.acknowledge(
            firstDrain.token,
            disposition: .transferred
        )
        guard
            case .drain(let replacementDrain) = consumer.takeDrain(
                binding: replacementBinding,
                generation: generation
            )
        else {
            Issue.record("Expected replacement binding to receive identical custody")
            return
        }

        #expect(oldAcknowledgement == .invalidToken)
        #expect(replacementDrain.valuesByKey == firstDrain.valuesByKey)
        #expect(replacementDrain.token != firstDrain.token)
        #expect(
            consumer.acknowledge(replacementDrain.token, disposition: .transferred)
                == .accepted(wake: .scheduleDrain)
        )
    }

    @Test("same-key offer during a lease remains independently drainable and admitted")
    func sameKeyOfferDuringLeaseRemainsIndependentlyDrainable() {
        let mailbox = makeMailbox()
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(generation: generation, key: .primary, value: 1)
        guard
            case .drain(let leasedDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected the first value to be leased")
            return
        }

        let offerDuringLease = producer.offer(generation: generation, key: .primary, value: 2)
        let diagnosticsDuringLease = lifecycle.diagnostics.admission
        let acknowledgement = consumer.acknowledge(
            leasedDrain.token,
            disposition: .transferred
        )
        performAllLatestCleanup(lifecycle, generation: generation)
        guard
            case .drain(let pendingDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected the newer same-key value to remain independently drainable")
            return
        }

        #expect(offerDuringLease.receipt == .admitted)
        #expect(offerDuringLease.wake == .noWake)
        #expect(diagnosticsDuringLease.offered == 2)
        #expect(diagnosticsDuringLease.admitted == 2)
        #expect(diagnosticsDuringLease.contracted == 0)
        #expect(acknowledgement == .accepted(wake: .scheduleDrain))
        #expect(pendingDrain.valuesByKey == [.primary: 2])
    }

    @Test("stale undeclared and closed offers increment mutually exclusive rejection reasons")
    func rejectedOffersHaveMutuallyExclusiveCounters() {
        let mailbox = LatestValueMailbox<SampleKey, Int>(
            generation: generation,
            declaredKeys: [.primary],
            limits: makeLatestValueTestLimits(cleanupQuantum: cleanupQuantum)
        )
        let producer = mailbox.producerPort
        let lifecycle = mailbox.lifecyclePort
        let staleGeneration = AdmissionGeneration(owner: generation.owner, value: generation.value - 1)

        let staleOffer = producer.offer(generation: staleGeneration, key: .primary, value: 1)
        let undeclaredOffer = producer.offer(generation: generation, key: .secondary, value: 2)
        #expect(lifecycle.seal(generation: generation) == .applied)
        let closedOffer = producer.offer(generation: generation, key: .primary, value: 3)

        let diagnostics = lifecycle.diagnostics.admission
        #expect(staleOffer.receipt == .staleGeneration)
        #expect(undeclaredOffer.receipt == .undeclaredKey)
        #expect(closedOffer.receipt == .closed)
        #expect(diagnostics.offered == 3)
        #expect(diagnostics.admitted == 0)
        #expect(diagnostics.rejectedStale == 1)
        #expect(diagnostics.rejectedUndeclared == 1)
        #expect(diagnostics.rejectedInvalid == 0)
        #expect(diagnostics.rejectedClosed == 1)
    }

    @Test("replacement retains only the latest value and reports contraction")
    func replacementRetainsOnlyLatestValue() {
        let mailbox = makeMailbox()
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding

        let firstOffer = producer.offer(generation: generation, key: .primary, value: 10)
        let replacementOffer = producer.offer(generation: generation, key: .primary, value: 20)
        performAllLatestCleanup(lifecycle, generation: generation)
        let drainResult = consumer.takeDrain(binding: binding, generation: generation)

        #expect(firstOffer.receipt == .admitted)
        #expect(firstOffer.wake == .scheduleDrain)
        #expect(replacementOffer.receipt == .replacedPrevious)
        #expect(replacementOffer.wake == .noWake)
        guard case .drain(let drain) = drainResult else {
            Issue.record("Expected the latest retained value to be drainable")
            return
        }
        #expect(drain.valuesByKey == [.primary: 20])

        let diagnostics = lifecycle.diagnostics.admission
        #expect(diagnostics.offered == 2)
        #expect(diagnostics.admitted == 2)
        #expect(diagnostics.contracted == 1)
        #expect(diagnostics.pendingKeyCount == 1)
    }

    @Test("accepted offers schedule exactly one wake before a drain")
    func acceptedOffersScheduleExactlyOneWakeBeforeDrain() {
        let mailbox = makeMailbox()
        let producer = mailbox.producerPort

        let wakeDirectives = [
            producer.offer(generation: generation, key: .primary, value: 1).wake,
            producer.offer(generation: generation, key: .secondary, value: 2).wake,
            producer.offer(generation: generation, key: .primary, value: 3).wake,
            producer.offer(generation: generation, key: .tertiary, value: 4).wake,
        ]

        #expect(wakeDirectives.filter { $0 == .scheduleDrain }.count == 1)
        #expect(wakeDirectives.filter { $0 == .noWake }.count == 3)
    }

    @Test("offers during a drain are released by one acknowledgement wake")
    func offersDuringDrainProduceOneAcknowledgementWake() {
        let mailbox = makeMailbox()
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(generation: generation, key: .primary, value: 1)
        guard
            case .drain(let firstDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected the initial value to create a drain lease")
            return
        }

        let replacementDuringDrain = producer.offer(generation: generation, key: .primary, value: 2)
        let newKeyDuringDrain = producer.offer(generation: generation, key: .secondary, value: 3)
        let acknowledgement = consumer.acknowledge(firstDrain.token, disposition: .transferred)
        let laterReplacement = producer.offer(generation: generation, key: .secondary, value: 4)

        #expect(replacementDuringDrain.wake == .noWake)
        #expect(newKeyDuringDrain.wake == .noWake)
        #expect(acknowledgement == .accepted(wake: .scheduleDrain))
        #expect(laterReplacement.wake == .noWake)
        performAllLatestCleanup(mailbox.lifecyclePort, generation: generation)
        guard
            case .drain(let followUpDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected acknowledgement to release retained follow-up work")
            return
        }
        #expect(followUpDrain.valuesByKey == [.primary: 2, .secondary: 4])
    }

    @Test("transfer clears a lease and retry requeues only when no newer value exists")
    func transferAndRetryRespectLatestValueOwnership() {
        let mailbox = makeMailbox()
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(generation: generation, key: .primary, value: 1)
        guard
            case .drain(let retryDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected a drain to retry")
            return
        }

        let retryAcknowledgement = consumer.acknowledge(retryDrain.token, disposition: .retry)
        #expect(retryAcknowledgement == .accepted(wake: .scheduleDrain))
        guard
            case .drain(let repeatedDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected retry to retain the leased value")
            return
        }
        #expect(repeatedDrain.valuesByKey == [.primary: 1])

        _ = producer.offer(generation: generation, key: .primary, value: 2)
        let secondRetryAcknowledgement = consumer.acknowledge(
            repeatedDrain.token,
            disposition: .retry
        )
        #expect(secondRetryAcknowledgement == .accepted(wake: .scheduleDrain))
        performAllLatestCleanup(lifecycle, generation: generation)
        guard
            case .drain(let latestDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected the newer pending value after retry")
            return
        }
        #expect(latestDrain.valuesByKey == [.primary: 2])

        let transferAcknowledgement = consumer.acknowledge(
            latestDrain.token,
            disposition: .transferred
        )
        #expect(transferAcknowledgement == .accepted(wake: .scheduleDrain))
        #expect(lifecycle.diagnostics.admission.pendingKeyCount == 0)
        performAllLatestCleanup(lifecycle, generation: generation)
        guard
            case .empty = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected an open mailbox without retained work to be empty")
            return
        }
    }

    @Test("stale foreign and duplicate tokens are rejected without mutating the active lease")
    func invalidTokensCannotMutateCurrentState() {
        let mailbox = makeMailbox()
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(generation: generation, key: .primary, value: 1)
        guard
            case .drain(let currentDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected the current mailbox drain")
            return
        }

        let foreignMailbox = makeMailbox()
        let foreignProducer = foreignMailbox.producerPort
        let foreignConsumer = foreignMailbox.consumerPort
        let foreignBinding = foreignConsumer.bindConsumer().binding
        _ = foreignProducer.offer(generation: generation, key: .primary, value: 2)
        guard
            case .drain(let foreignDrain) = foreignConsumer.takeDrain(
                binding: foreignBinding,
                generation: generation
            )
        else {
            Issue.record("Expected the foreign mailbox drain")
            return
        }

        let staleGeneration = AdmissionGeneration(owner: generation.owner, value: generation.value - 1)
        let staleMailbox = LatestValueMailbox<SampleKey, Int>(
            generation: staleGeneration,
            declaredKeys: Set(SampleKey.allCases),
            limits: makeLatestValueTestLimits(cleanupQuantum: cleanupQuantum)
        )
        let staleProducer = staleMailbox.producerPort
        let staleConsumer = staleMailbox.consumerPort
        let staleBinding = staleConsumer.bindConsumer().binding
        _ = staleProducer.offer(generation: staleGeneration, key: .primary, value: 3)
        guard
            case .drain(let staleDrain) = staleConsumer.takeDrain(
                binding: staleBinding,
                generation: staleGeneration
            )
        else {
            Issue.record("Expected the stale-generation mailbox drain")
            return
        }

        #expect(consumer.acknowledge(foreignDrain.token, disposition: .transferred) == .invalidToken)
        #expect(consumer.acknowledge(staleDrain.token, disposition: .transferred) == .staleGeneration)
        #expect(lifecycle.diagnostics.admission.pendingKeyCount == 1)
        guard
            case .alreadyDraining = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected rejected tokens to leave the active lease unchanged")
            return
        }

        #expect(
            consumer.acknowledge(currentDrain.token, disposition: .transferred)
                == .accepted(wake: .scheduleDrain)
        )
        #expect(consumer.acknowledge(currentDrain.token, disposition: .transferred) == .invalidToken)
        #expect(lifecycle.diagnostics.admission.pendingKeyCount == 0)
    }

    @Test("fixed generation rejects stale offers and control operations without closing current state")
    func fixedGenerationRejectsStaleOperations() {
        let mailbox = makeMailbox()
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding
        let staleGeneration = AdmissionGeneration(owner: generation.owner, value: generation.value - 1)

        let staleOffer = producer.offer(generation: staleGeneration, key: .primary, value: 1)
        let staleDrain = consumer.takeDrain(binding: binding, generation: staleGeneration)
        let staleSeal = lifecycle.seal(generation: staleGeneration)
        let staleInvalidate = lifecycle.invalidate(generation: staleGeneration)
        let currentOffer = producer.offer(generation: generation, key: .primary, value: 2)

        #expect(staleOffer.receipt == .staleGeneration)
        #expect(staleOffer.wake == .noWake)
        guard case .staleGeneration = staleDrain else {
            Issue.record("Expected a stale-generation drain rejection")
            return
        }
        #expect(staleSeal == .staleGeneration)
        #expect(staleInvalidate == .staleGeneration)
        #expect(currentOffer.receipt == .admitted)
        #expect(currentOffer.wake == .scheduleDrain)
        let diagnostics = lifecycle.diagnostics.admission
        #expect(diagnostics.offered == 2)
        #expect(diagnostics.rejectedStale == 1)
        #expect(diagnostics.pendingKeyCount == 1)
    }

    @Test("declared key set bounds retained state and undeclared keys are explicit rejections")
    func declaredKeysBoundRetainedState() {
        let declaredKeys = Set(0..<4)
        let mailbox = LatestValueMailbox<Int, Int>(
            generation: generation,
            declaredKeys: declaredKeys,
            limits: makeLatestValueTestLimits(cleanupQuantum: cleanupQuantum)
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding

        var undeclaredReceipts: [AdmissionReceipt] = []
        for key in 0..<32 {
            let result = producer.offer(generation: generation, key: key, value: key * 10)
            if declaredKeys.contains(key) == false {
                undeclaredReceipts.append(result.receipt)
                #expect(result.wake == .noWake)
            }
        }

        #expect(undeclaredReceipts == Array(repeating: .undeclaredKey, count: 28))
        let diagnostics = lifecycle.diagnostics.admission
        #expect(diagnostics.offered == 32)
        #expect(diagnostics.admitted == 4)
        #expect(diagnostics.rejectedUndeclared == 28)
        #expect(diagnostics.pendingKeyCount == 4)
        #expect(diagnostics.pendingKeyHighWater == 4)
        guard
            case .drain(let drain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected the bounded declared-key values")
            return
        }
        #expect(drain.valuesByKey == [0: 0, 1: 10, 2: 20, 3: 30])
    }

    @Test("seal rejects new offers while accepted work drains gracefully")
    func sealDrainsAcceptedWorkGracefully() {
        let mailbox = makeMailbox()
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(generation: generation, key: .primary, value: 1)

        #expect(lifecycle.seal(generation: generation) == .applied)
        #expect(lifecycle.seal(generation: generation) == .alreadyClosed)
        let closedOffer = producer.offer(generation: generation, key: .secondary, value: 2)
        #expect(closedOffer.receipt == .closed)
        #expect(closedOffer.wake == .noWake)

        guard
            case .drain(let drain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected sealed accepted work to remain drainable")
            return
        }
        #expect(drain.valuesByKey == [.primary: 1])
        #expect(
            consumer.acknowledge(drain.token, disposition: .transferred)
                == .accepted(wake: .scheduleDrain)
        )
        performAllLatestCleanup(lifecycle, generation: generation)
        guard
            case .closed = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected a fully drained sealed mailbox to be closed")
            return
        }
    }

    @Test("invalidate discards pending state and revokes an outstanding token immediately")
    func invalidateDiscardsStateImmediately() {
        let mailbox = makeMailbox()
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(generation: generation, key: .primary, value: 1)
        guard
            case .drain(let drain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected an outstanding drain before invalidation")
            return
        }

        #expect(lifecycle.invalidate(generation: generation) == .applied)
        #expect(lifecycle.invalidate(generation: generation) == .alreadyClosed)
        #expect(consumer.acknowledge(drain.token, disposition: .transferred) == .closed)
        guard
            case .closed = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected invalidation to revoke drain access")
            return
        }
        let closedOffer = producer.offer(generation: generation, key: .secondary, value: 2)
        #expect(closedOffer.receipt == .closed)
        #expect(lifecycle.diagnostics.admission.pendingKeyCount == 0)
    }

    @Test("diagnostics retain current high-water and oldest pressure age without payloads")
    func diagnosticsReportPressureWithoutPayloads() {
        let clock = TestPushClock()
        let mailbox = LatestValueMailbox<String, String>(
            generation: generation,
            declaredKeys: ["sensitive-key", "other-key"],
            limits: makeLatestValueTestLimits(cleanupQuantum: cleanupQuantum),
            clock: clock
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(generation: generation, key: "sensitive-key", value: "sensitive-payload")
        clock.advance(by: .seconds(2))
        _ = producer.offer(generation: generation, key: "sensitive-key", value: "replacement-payload")
        clock.advance(by: .seconds(1))
        _ = producer.offer(generation: generation, key: "other-key", value: "other-payload")
        clock.advance(by: .seconds(4))

        let pendingDiagnostics = lifecycle.diagnostics
        #expect(pendingDiagnostics.admission.pendingKeyCount == 2)
        #expect(pendingDiagnostics.admission.pendingKeyHighWater == 2)
        #expect(pendingDiagnostics.admission.oldestPendingAge == .exact(.seconds(7)))
        #expect(pendingDiagnostics.admission.offered == 3)
        #expect(pendingDiagnostics.admission.admitted == 3)
        #expect(pendingDiagnostics.admission.contracted == 1)
        #expect(pendingDiagnostics.semanticRetainedValueCount == 2)
        #expect(pendingDiagnostics.semanticRetainedValueHighWater == 2)
        #expect(pendingDiagnostics.pendingValueCount == 2)
        #expect(pendingDiagnostics.leasedValueCount == 0)
        #expect(pendingDiagnostics.cleanupValueCount == 1)
        #expect(pendingDiagnostics.cleanupValueHighWater == 1)
        #expect(pendingDiagnostics.physicalRetainedValueCount == 3)
        #expect(pendingDiagnostics.physicalRetainedValueHighWater == 3)
        #expect(pendingDiagnostics.oldestCleanupAge == .exact(.seconds(7)))
        #expect(pendingDiagnostics.outstandingLeaseCount == 0)
        #expect(pendingDiagnostics.isQuiescent == false)
        let diagnosticDescription = String(reflecting: pendingDiagnostics)
        #expect(diagnosticDescription.contains("sensitive-key") == false)
        #expect(diagnosticDescription.contains("replacement-payload") == false)
        performAllLatestCleanup(lifecycle, generation: generation)

        guard
            case .drain(let drain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected retained diagnostic work to drain")
            return
        }
        #expect(drain.oldestRetainedAge == .exact(.seconds(7)))
        clock.advance(by: .seconds(2))
        #expect(lifecycle.diagnostics.admission.oldestPendingAge == .exact(.seconds(9)))
        #expect(
            consumer.acknowledge(drain.token, disposition: .transferred)
                == .accepted(wake: .scheduleDrain)
        )
        let clearedDiagnostics = lifecycle.diagnostics
        #expect(clearedDiagnostics.admission.pendingKeyCount == 0)
        #expect(clearedDiagnostics.admission.pendingKeyHighWater == 2)
        #expect(clearedDiagnostics.admission.oldestPendingAge == nil)
        #expect(clearedDiagnostics.semanticRetainedValueCount == 0)
        #expect(clearedDiagnostics.pendingValueCount == 0)
        #expect(clearedDiagnostics.leasedValueCount == 0)
        #expect(clearedDiagnostics.cleanupValueCount == 2)
        #expect(clearedDiagnostics.cleanupValueHighWater == 2)
        #expect(clearedDiagnostics.physicalRetainedValueCount == 2)
        #expect(clearedDiagnostics.oldestCleanupAge == .exact(.seconds(9)))
        #expect(clearedDiagnostics.outstandingLeaseCount == 0)
        #expect(clearedDiagnostics.isQuiescent == false)
        #expect(
            lifecycle.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        releasedEntryCount: 2,
                        releasedByteCount: nil,
                        wake: .noWake
                    )
                )
        )
        #expect(lifecycle.diagnostics.isQuiescent)
    }

    @Test("concurrent offers preserve one bounded latest slot without task or time waits")
    func concurrentOffersPreserveSingleSlotInvariant() async {
        let currentGeneration = generation
        let mailbox = LatestValueMailbox<SampleKey, Int>(
            generation: currentGeneration,
            declaredKeys: [.primary],
            limits: makeLatestValueTestLimits(cleanupQuantum: cleanupQuantum)
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding
        let offerCount = 256

        await withTaskGroup(of: Void.self) { group in
            for value in 0..<offerCount {
                group.addTask {
                    _ = producer.offer(
                        generation: currentGeneration,
                        key: .primary,
                        value: value
                    )
                }
            }
        }

        let diagnostics = lifecycle.diagnostics.admission
        #expect(diagnostics.offered == UInt64(offerCount))
        #expect(diagnostics.admitted == UInt64(offerCount))
        #expect(diagnostics.contracted == UInt64(offerCount - 1))
        #expect(diagnostics.pendingKeyCount == 1)
        #expect(diagnostics.pendingKeyHighWater == 1)
        performAllLatestCleanup(lifecycle, generation: currentGeneration)
        guard
            case .drain(let drain) = consumer.takeDrain(
                binding: binding,
                generation: currentGeneration
            )
        else {
            Issue.record("Expected one retained value after concurrent offers")
            return
        }
        #expect(drain.valuesByKey.count == 1)
        let retainedValue = drain.valuesByKey[.primary]
        #expect(retainedValue.map { (0..<offerCount).contains($0) } == true)
    }

    private func makeMailbox() -> LatestValueMailbox<SampleKey, Int> {
        LatestValueMailbox(
            generation: generation,
            declaredKeys: Set(SampleKey.allCases),
            limits: makeLatestValueTestLimits(cleanupQuantum: cleanupQuantum)
        )
    }
}

private func performAllLatestCleanup<Key, Value>(
    _ lifecycle: LatestValueLifecyclePort<Key, Value>,
    generation: AdmissionGeneration
) where Key: Hashable & Sendable, Value: Sendable {
    var remainingTurns = lifecycle.diagnostics.cleanupValueCount
    while lifecycle.diagnostics.cleanupValueCount > 0 {
        guard remainingTurns > 0 else {
            Issue.record("Latest cleanup did not make bounded progress")
            return
        }
        remainingTurns -= 1
        guard case .performed = lifecycle.performCleanup(generation: generation) else {
            Issue.record("Expected a latest cleanup turn")
            return
        }
    }
}

extension AdmissionLatestValueMailboxTests {
    @Test("producer consumer and lifecycle ports preserve separate authority")
    func capabilityPortsPreserveSeparateAuthority() {
        let mailbox = makeMailbox()
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding

        let offer = producer.offer(generation: generation, key: .primary, value: 11)
        guard
            case .drain(let drain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected the consumer capability to drain producer custody")
            return
        }

        #expect(offer.receipt == .admitted)
        #expect(
            consumer.acknowledge(drain.token, disposition: .transferred)
                == .accepted(wake: .scheduleDrain)
        )
        #expect(lifecycle.diagnostics.admission.pendingKeyCount == 0)
        #expect(lifecycle.seal(generation: generation) == .applied)
    }

    @Test("retry contracts the discarded lease and retains the newer value age")
    func retryWithNewerPendingValueReportsTruthfulContractionAndAge() {
        let clock = TestPushClock()
        let mailbox = LatestValueMailbox<SampleKey, Int>(
            generation: generation,
            declaredKeys: [.primary],
            limits: makeLatestValueTestLimits(cleanupQuantum: cleanupQuantum),
            clock: clock
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(generation: generation, key: .primary, value: 1)
        guard
            case .drain(let leasedDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected the original value to lease")
            return
        }

        clock.advance(by: .seconds(2))
        _ = producer.offer(generation: generation, key: .primary, value: 2)
        clock.advance(by: .seconds(3))
        let acknowledgement = consumer.acknowledge(
            leasedDrain.token,
            disposition: .retry
        )
        performAllLatestCleanup(lifecycle, generation: generation)
        guard
            case .drain(let newerDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected the independently admitted newer value")
            return
        }

        #expect(acknowledgement == .accepted(wake: .scheduleDrain))
        #expect(lifecycle.diagnostics.admission.contracted == 1)
        #expect(lifecycle.diagnostics.admission.oldestPendingAge == .exact(.seconds(3)))
        #expect(newerDrain.valuesByKey == [.primary: 2])
        #expect(newerDrain.oldestRetainedAge == .exact(.seconds(3)))
    }

    @Test("binding and lease authority roll over without aliasing or losing custody")
    func authorityRolloverPreservesCustodyAndRejectsOldAcknowledgements() {
        let mailbox = LatestValueMailbox<SampleKey, Int>(
            generation: generation,
            declaredKeys: [.primary],
            limits: makeLatestValueTestLimits(cleanupQuantum: cleanupQuantum),
            initialBindingSequence: .max - 1,
            initialLeaseSequence: .max - 1
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let firstBinding = consumer.bindConsumer().binding
        let maximumBindingAuthority = lifecycle.authoritySnapshot
        _ = producer.offer(generation: generation, key: .primary, value: 1)
        guard
            case .drain(let firstDrain) = consumer.takeDrain(
                binding: firstBinding,
                generation: generation
            )
        else {
            Issue.record("Expected the terminal pre-rollover lease authority")
            return
        }
        let maximumLeaseAuthority = lifecycle.authoritySnapshot

        let replacementBinding = consumer.bindConsumer().binding
        let rotatedBindingAuthority = lifecycle.authoritySnapshot
        let oldAcknowledgement = consumer.acknowledge(
            firstDrain.token,
            disposition: .transferred
        )
        guard
            case .drain(let replacementDrain) = consumer.takeDrain(
                binding: replacementBinding,
                generation: generation
            )
        else {
            Issue.record("Expected custody after binding and lease epoch rollover")
            return
        }

        #expect(firstBinding != replacementBinding)
        #expect(firstDrain.token != replacementDrain.token)
        #expect(maximumBindingAuthority.bindingSequence == .max)
        #expect(rotatedBindingAuthority.bindingSequence == 1)
        #expect(maximumBindingAuthority.bindingEpoch != rotatedBindingAuthority.bindingEpoch)
        #expect(rotatedBindingAuthority.bindingEpochRotationCount == 1)
        let rotatedLeaseAuthority = lifecycle.authoritySnapshot
        #expect(rotatedLeaseAuthority.leaseSequence == 1)
        #expect(maximumLeaseAuthority.leaseEpoch != rotatedLeaseAuthority.leaseEpoch)
        #expect(rotatedLeaseAuthority.leaseEpochRotationCount == 1)
        #expect(oldAcknowledgement == .invalidToken)
        #expect(replacementDrain.valuesByKey == [.primary: 1])
        #expect(
            consumer.acknowledge(replacementDrain.token, disposition: .transferred)
                == .accepted(wake: .scheduleDrain)
        )
        performAllLatestCleanup(lifecycle, generation: generation)

        _ = producer.offer(generation: generation, key: .primary, value: 2)
        guard
            case .drain(let laterDrain) = consumer.takeDrain(
                binding: replacementBinding,
                generation: generation
            )
        else {
            Issue.record("Expected later custody under renewed authority")
            return
        }
        #expect(
            consumer.acknowledge(replacementDrain.token, disposition: .transferred)
                == .invalidToken
        )
        #expect(
            consumer.acknowledge(laterDrain.token, disposition: .transferred)
                == .accepted(wake: .scheduleDrain)
        )
    }

    @Test("empty drains do not exhaust terminal lease authority")
    func emptyDrainDoesNotAllocateLeaseAuthority() {
        let mailbox = LatestValueMailbox<SampleKey, Int>(
            generation: generation,
            declaredKeys: [.primary],
            limits: makeLatestValueTestLimits(cleanupQuantum: cleanupQuantum),
            initialBindingSequence: 0,
            initialLeaseSequence: .max
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding

        guard
            case .empty = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected an empty poll before authority allocation")
            return
        }
        let authorityAfterEmptyPoll = lifecycle.authoritySnapshot
        _ = producer.offer(generation: generation, key: .primary, value: 7)
        guard
            case .drain(let drain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected work to drain after lease epoch rollover")
            return
        }
        #expect(authorityAfterEmptyPoll.leaseSequence == .max)
        #expect(lifecycle.authoritySnapshot.leaseSequence == 1)
        #expect(drain.valuesByKey == [.primary: 7])
    }

}
