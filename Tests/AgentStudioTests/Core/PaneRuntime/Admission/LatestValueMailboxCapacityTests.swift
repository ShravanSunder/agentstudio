import Dispatch
import Foundation
import Testing

@testable import AgentStudio

@Suite("Admission LatestValueMailbox capacity")
struct AdmissionLatestValueMailboxCapacityTests {
    private let generation = AdmissionGeneration(owner: .terminalViewport, value: 31)

    @Test("configuration validation rejects D R C and K plus R overflow without trapping")
    func configurationValidationUsesCheckedComponentArithmetic() {
        let validLimits = LatestValueLimits(
            maximumValuesPerLease: 1,
            maximumAuxiliaryRetainedValues: 2,
            cleanupQuantum: .entries(maximumEntries: 1)
        )

        #expect(
            LatestValueMailbox<Int, Int>.isConfigurationValid(
                declaredKeyCount: Int.max - 2,
                limits: validLimits
            )
        )
        #expect(
            LatestValueMailbox<Int, Int>.isConfigurationValid(
                declaredKeyCount: Int.max - 1,
                limits: validLimits
            ) == false
        )
        #expect(
            LatestValueMailbox<Int, Int>.isConfigurationValid(
                declaredKeyCount: 1,
                limits: LatestValueLimits(
                    maximumValuesPerLease: Int.max,
                    maximumAuxiliaryRetainedValues: Int.max,
                    cleanupQuantum: .entries(maximumEntries: 1)
                )
            ) == false
        )
        #expect(
            LatestValueMailbox<Int, Int>.isConfigurationValid(
                declaredKeyCount: 1,
                limits: LatestValueLimits(
                    maximumValuesPerLease: 1,
                    maximumAuxiliaryRetainedValues: 1,
                    cleanupQuantum: .entries(maximumEntries: 1)
                )
            ) == false
        )
        #expect(
            LatestValueMailbox<Int, Int>.isConfigurationValid(
                declaredKeyCount: 1,
                limits: LatestValueLimits(
                    maximumValuesPerLease: 1,
                    maximumAuxiliaryRetainedValues: 2,
                    cleanupQuantum: .entries(maximumEntries: 0)
                )
            ) == false
        )
        #expect(
            LatestValueMailbox<Int, Int>.isConfigurationValid(
                declaredKeyCount: 1,
                limits: LatestValueLimits(
                    maximumValuesPerLease: 1,
                    maximumAuxiliaryRetainedValues: 2,
                    cleanupQuantum: .entriesAndBytes(maximumEntries: 1, maximumBytes: 1)
                )
            ) == false
        )
    }

    @Test("one cleanup-free drain leases at most D and preserves residual pending custody")
    func cleanupFreeDrainIsBoundedByDeliveryLimit() {
        let mailbox = makeIntegerMailbox(
            declaredKeys: [0, 1, 2],
            deliveryLimit: 2,
            auxiliaryLimit: 4,
            cleanupLimit: 1
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding

        for key in 0...2 {
            _ = producer.offer(generation: generation, key: key, value: key)
        }

        guard
            case .drain(let drain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected one bounded latest-value lease")
            return
        }

        #expect(latestValuesByKey(drain).count == 2)
        #expect(lifecycle.diagnostics.pendingValueCount == 1)
        #expect(lifecycle.diagnostics.leasedValueCount == 2)
        #expect(lifecycle.diagnostics.physicalRetainedValueCount == 3)
    }

    // This single history proves precedence across pending, open-empty, sealed, and resumed states.
    @Test("cleanup custody precedes new delivery and empty or sealed results")
    // swiftlint:disable:next function_body_length
    func cleanupCustodyHasTakePrecedence() {
        let pendingMailbox = makeIntegerMailbox(
            declaredKeys: [0],
            deliveryLimit: 1,
            auxiliaryLimit: 2,
            cleanupLimit: 1
        )
        let pendingProducer = pendingMailbox.producerPort
        let pendingConsumer = pendingMailbox.consumerPort
        let pendingBinding = pendingConsumer.bindConsumer().binding

        _ = pendingProducer.offer(generation: generation, key: 0, value: 0)
        _ = pendingProducer.offer(generation: generation, key: 0, value: 1)
        #expect(
            isLatestCleanupRequired(
                pendingConsumer.takeDrain(
                    binding: pendingBinding,
                    generation: generation
                )
            )
        )

        let cleanupOnlyMailbox = makeIntegerMailbox(
            declaredKeys: [0],
            deliveryLimit: 1,
            auxiliaryLimit: 2,
            cleanupLimit: 1
        )
        let cleanupOnlyProducer = cleanupOnlyMailbox.producerPort
        let cleanupOnlyConsumer = cleanupOnlyMailbox.consumerPort
        let cleanupOnlyLifecycle = cleanupOnlyMailbox.lifecyclePort
        let cleanupOnlyBinding = cleanupOnlyConsumer.bindConsumer().binding

        _ = cleanupOnlyProducer.offer(generation: generation, key: 0, value: 0)
        guard
            case .drain(let cleanupOnlyDrain) = cleanupOnlyConsumer.takeDrain(
                binding: cleanupOnlyBinding,
                generation: generation
            )
        else {
            Issue.record("Expected one value to enter cleanup-only custody")
            return
        }
        #expect(
            cleanupOnlyConsumer.acknowledge(
                cleanupOnlyDrain.token,
                disposition: .transferred
            ) == .accepted(wake: .scheduleDrain)
        )
        #expect(
            isLatestCleanupRequired(
                cleanupOnlyConsumer.takeDrain(
                    binding: cleanupOnlyBinding,
                    generation: generation
                )
            )
        )
        #expect(cleanupOnlyLifecycle.seal(generation: generation) == .applied)
        #expect(
            isLatestCleanupRequired(
                cleanupOnlyConsumer.takeDrain(
                    binding: cleanupOnlyBinding,
                    generation: generation
                )
            )
        )
        #expect(
            cleanupOnlyLifecycle.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entries(count: 1),
                        wake: .noWake
                    )
                )
        )
        #expect(
            isLatestClosed(
                cleanupOnlyConsumer.takeDrain(
                    binding: cleanupOnlyBinding,
                    generation: generation
                )
            )
        )

        let resumedMailbox = makeIntegerMailbox(
            declaredKeys: [0],
            deliveryLimit: 1,
            auxiliaryLimit: 2,
            cleanupLimit: 1
        )
        let resumedProducer = resumedMailbox.producerPort
        let resumedConsumer = resumedMailbox.consumerPort
        let resumedLifecycle = resumedMailbox.lifecyclePort
        let resumedBinding = resumedConsumer.bindConsumer().binding

        _ = resumedProducer.offer(generation: generation, key: 0, value: 0)
        _ = resumedProducer.offer(generation: generation, key: 0, value: 1)
        #expect(
            resumedLifecycle.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entries(count: 1),
                        wake: .scheduleDrain
                    )
                )
        )

        guard
            case .drain(let resumedDrain) = resumedConsumer.takeDrain(
                binding: resumedBinding,
                generation: generation
            )
        else {
            Issue.record("Expected delivery after cleanup reached zero")
            return
        }
        #expect(latestValuesByKey(resumedDrain) == [0: 1])
    }

    @Test("cleanup age includes older custody retired behind a younger batch")
    func cleanupAgeDoesNotUnderstateLaterRetiredCustody() {
        let clock = TestPushClock()
        let mailbox = makeIntegerMailbox(
            declaredKeys: [0, 1],
            deliveryLimit: 1,
            auxiliaryLimit: 2,
            cleanupLimit: 1,
            clock: clock
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding

        _ = producer.offer(generation: generation, key: 0, value: 0)
        guard
            case .drain(let olderDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected the older value to enter a lease")
            return
        }
        clock.advance(by: .seconds(5))
        _ = producer.offer(generation: generation, key: 1, value: 10)
        clock.advance(by: .seconds(1))
        _ = producer.offer(generation: generation, key: 1, value: 11)
        clock.advance(by: .seconds(1))
        #expect(
            consumer.acknowledge(olderDrain.token, disposition: .transferred)
                == .accepted(wake: .scheduleDrain)
        )

        #expect(lifecycle.diagnostics.cleanupValueCount == 2)
        #expect(lifecycle.diagnostics.oldestCleanupAge == .exact(.seconds(7)))
    }

    @Test("cleanup age remains conservative after the exact oldest is released")
    func cleanupAgeDowngradesAfterOldestRelease() {
        let clock = TestPushClock()
        let mailbox = makeIntegerMailbox(
            declaredKeys: [0, 1],
            deliveryLimit: 1,
            auxiliaryLimit: 2,
            cleanupLimit: 1,
            clock: clock
        )
        let producer = mailbox.producerPort
        let lifecycle = mailbox.lifecyclePort

        _ = producer.offer(generation: generation, key: 0, value: 0)
        clock.advance(by: .seconds(1))
        _ = producer.offer(generation: generation, key: 0, value: 1)
        _ = producer.offer(generation: generation, key: 1, value: 10)
        clock.advance(by: .seconds(1))
        _ = producer.offer(generation: generation, key: 1, value: 11)
        clock.advance(by: .seconds(1))

        #expect(lifecycle.diagnostics.oldestCleanupAge == .exact(.seconds(3)))
        guard
            case .performed(let firstTurn) = lifecycle.performCleanup(
                generation: generation
            )
        else {
            Issue.record("Expected the exact-oldest cleanup turn")
            return
        }
        #expect(firstTurn.release == .entries(count: 1))
        #expect(
            lifecycle.diagnostics.oldestCleanupAge
                == .pressureConservative(.seconds(3))
        )

        guard
            case .performed(let finalTurn) = lifecycle.performCleanup(
                generation: generation
            )
        else {
            Issue.record("Expected the final cleanup turn")
            return
        }
        #expect(finalTurn.release == .entries(count: 1))
        #expect(lifecycle.diagnostics.oldestCleanupAge == nil)
    }

    @Test("capacity rejection preserves the already represented wake level")
    func capacityRejectionPreservesWakeLevel() {
        let mailbox = makeIntegerMailbox(
            declaredKeys: [0, 1],
            deliveryLimit: 1,
            auxiliaryLimit: 2,
            cleanupLimit: 1
        )
        let producer = mailbox.producerPort

        #expect(
            producer.offer(generation: generation, key: 0, value: 0)
                == .admitted(wake: .scheduleDrain)
        )
        _ = producer.offer(generation: generation, key: 0, value: 1)
        _ = producer.offer(generation: generation, key: 0, value: 2)
        #expect(
            producer.offer(generation: generation, key: 0, value: 3)
                == .physicalCapacityExceeded
        )
        #expect(
            producer.offer(generation: generation, key: 1, value: 10)
                == .admitted(wake: .noWake)
        )
    }

    @Test("sparse maximum valid limits reserve only actual retained custody")
    func sparseMaximumLimitsDoNotAllocateConfigurationSizedBuffers() {
        let mailbox = makeIntegerMailbox(
            declaredKeys: [0],
            deliveryLimit: Int.max / 2,
            auxiliaryLimit: Int.max - 1,
            cleanupLimit: Int.max
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding

        _ = producer.offer(generation: generation, key: 0, value: 1)
        guard
            case .drain(let drain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected sparse custody to drain under maximum valid limits")
            return
        }
        #expect(latestValuesByKey(drain) == [0: 1])
        #expect(
            consumer.acknowledge(drain.token, disposition: .transferred)
                == .accepted(wake: .scheduleDrain)
        )
        #expect(
            lifecycle.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entries(count: 1),
                        wake: .noWake
                    )
                )
        )
        #expect(lifecycle.diagnostics.isQuiescent)
    }

    @Test("full auxiliary wave rejects the next replacement without mutating accepted custody")
    func auxiliaryPressureRejectsWithoutPartialMutation() {
        let clock = TestPushClock()
        let mailbox = makeIntegerMailbox(
            declaredKeys: [0, 1],
            deliveryLimit: 2,
            auxiliaryLimit: 4,
            cleanupLimit: 1,
            clock: clock
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding

        _ = producer.offer(generation: generation, key: 0, value: 0)
        _ = producer.offer(generation: generation, key: 1, value: 10)
        guard
            case .drain(let initialDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected the initial D-sized lease")
            return
        }

        _ = producer.offer(generation: generation, key: 0, value: 1)
        _ = producer.offer(generation: generation, key: 1, value: 11)
        #expect(
            producer.offer(generation: generation, key: 0, value: 2)
                == .replacedPrevious(wake: .noWake)
        )
        #expect(
            producer.offer(generation: generation, key: 1, value: 12)
                == .replacedPrevious(wake: .noWake)
        )

        let authorityBeforeRejection = lifecycle.authoritySnapshot
        let diagnosticsBeforeRejection = lifecycle.diagnostics
        let rejected = producer.offer(generation: generation, key: 0, value: 3)
        let diagnosticsAfterRejection = lifecycle.diagnostics

        #expect(rejected == .physicalCapacityExceeded)
        #expect(lifecycle.authoritySnapshot == authorityBeforeRejection)
        #expect(diagnosticsAfterRejection.admission.offered == 7)
        #expect(diagnosticsAfterRejection.admission.admitted == 6)
        #expect(diagnosticsAfterRejection.admission.contracted == 2)
        #expect(diagnosticsAfterRejection.admission.rejectedCapacity == 1)
        #expect(diagnosticsAfterRejection.pendingValueCount == 2)
        #expect(diagnosticsAfterRejection.leasedValueCount == 2)
        #expect(diagnosticsAfterRejection.cleanupValueCount == 2)
        #expect(diagnosticsAfterRejection.physicalRetainedValueCount == 6)
        #expect(
            diagnosticsAfterRejection.admission.oldestPendingAge
                == diagnosticsBeforeRejection.admission.oldestPendingAge
        )
        #expect(
            diagnosticsAfterRejection.oldestCleanupAge
                == diagnosticsBeforeRejection.oldestCleanupAge
        )

        #expect(
            consumer.acknowledge(initialDrain.token, disposition: .transferred)
                == .accepted(wake: .scheduleDrain)
        )
        #expect(lifecycle.diagnostics.cleanupValueCount == 4)
        #expect(lifecycle.diagnostics.physicalRetainedValueCount == 6)
        #expect(lifecycle.invalidate(generation: generation) == .applied)
        #expect(lifecycle.diagnostics.pendingValueCount == 0)
        #expect(lifecycle.diagnostics.leasedValueCount == 0)
        #expect(lifecycle.diagnostics.cleanupValueCount == 6)
        #expect(lifecycle.diagnostics.physicalRetainedValueCount == 6)

        for remainingCount in stride(from: 5, through: 0, by: -1) {
            guard
                case .performed(let turn) = lifecycle.performCleanup(
                    generation: generation
                )
            else {
                Issue.record("Expected one C-sized terminal cleanup turn")
                return
            }
            #expect(turn.release == .entries(count: 1))
            #expect(lifecycle.diagnostics.cleanupValueCount == remainingCount)
        }
        #expect(lifecycle.performCleanup(generation: generation) == .empty)
        #expect(lifecycle.diagnostics.isQuiescent)
    }

    @Test("residual auxiliary headroom admits one replacement rather than requiring a full wave")
    func residualAuxiliaryHeadroomIsUsable() {
        let mailbox = makeIntegerMailbox(
            declaredKeys: [0, 1],
            deliveryLimit: 2,
            auxiliaryLimit: 5,
            cleanupLimit: 5
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding

        _ = producer.offer(generation: generation, key: 0, value: 0)
        _ = producer.offer(generation: generation, key: 1, value: 10)
        guard
            case .drain(let initialDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected the initial residual-headroom lease")
            return
        }

        _ = producer.offer(generation: generation, key: 0, value: 1)
        _ = producer.offer(generation: generation, key: 1, value: 11)
        #expect(
            producer.offer(generation: generation, key: 0, value: 2)
                == .replacedPrevious(wake: .noWake)
        )
        #expect(
            producer.offer(generation: generation, key: 1, value: 12)
                == .replacedPrevious(wake: .noWake)
        )
        #expect(
            producer.offer(generation: generation, key: 0, value: 3)
                == .replacedPrevious(wake: .noWake)
        )
        let rejected = producer.offer(generation: generation, key: 1, value: 13)

        #expect(rejected == .physicalCapacityExceeded)
        #expect(lifecycle.diagnostics.pendingValueCount == 2)
        #expect(lifecycle.diagnostics.leasedValueCount == 2)
        #expect(lifecycle.diagnostics.cleanupValueCount == 3)
        #expect(lifecycle.diagnostics.physicalRetainedValueCount == 7)
        #expect(lifecycle.diagnostics.admission.contracted == 3)
        #expect(lifecycle.diagnostics.admission.rejectedCapacity == 1)
        #expect(
            consumer.acknowledge(initialDrain.token, disposition: .transferred)
                == .accepted(wake: .scheduleDrain)
        )
        #expect(lifecycle.diagnostics.cleanupValueCount == 5)
        #expect(
            lifecycle.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entries(count: 5),
                        wake: .scheduleDrain
                    )
                )
        )
        guard
            case .drain(let pendingDrain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected pending custody after residual cleanup")
            return
        }
        #expect(latestValuesByKey(pendingDrain) == [0: 3, 1: 12])
    }

    // One destructor barrier must cover authority, diagnostics, admission, and finalization.
    @Test("in-flight destructor custody remains charged and cleanup authority is exclusive")
    // swiftlint:disable:next function_body_length
    func inFlightCleanupRemainsChargedAndExclusive() {
        let recorder = LatestValueCapacityReleaseRecorder()
        let gate = LatestValueCapacityDeinitGate()
        let mailboxReference = LatestValueCapacityMailboxReference()
        let mailbox = LatestValueMailbox<Int, LatestValueCapacityPayload>(
            generation: generation,
            declaredKeys: [0],
            limits: LatestValueLimits(
                maximumValuesPerLease: 1,
                maximumAuxiliaryRetainedValues: 2,
                cleanupQuantum: .entries(maximumEntries: 1)
            )
        )
        mailboxReference.mailbox = mailbox
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding

        _ = producer.offer(
            generation: generation,
            key: 0,
            value: LatestValueCapacityPayload(
                identity: .init(key: 0, version: 0),
                generation: generation,
                mailboxReference: mailboxReference,
                recorder: recorder,
                gate: gate
            )
        )
        let token: AdmissionDrainToken? = {
            guard
                case .drain(let drain) = consumer.takeDrain(
                    binding: binding,
                    generation: generation
                )
            else {
                Issue.record("Expected tracked cleanup custody to lease")
                return nil
            }
            return drain.token
        }()
        guard let token else { return }
        #expect(
            consumer.acknowledge(token, disposition: .transferred)
                == .accepted(wake: .scheduleDrain)
        )

        let outerResult = LatestValueCapacityResultBox<AdmissionCleanupTurnResult>()
        DispatchQueue(label: "agentstudio.tests.latest-capacity-cleanup").async {
            outerResult.store(lifecycle.performCleanup(generation: generation))
            gate.completed.signal()
        }

        let enteredDestructor = gate.entered.wait(timeout: .now() + 2) == .success
        #expect(enteredDestructor)
        guard enteredDestructor else {
            gate.release.signal()
            return
        }

        #expect(recorder.reentrantCleanupResult == .alreadyCleaning)
        #expect(consumer.performCleanup(generation: generation) == .alreadyCleaning)
        #expect(lifecycle.diagnostics.cleanupValueCount == 1)
        #expect(lifecycle.diagnostics.physicalRetainedValueCount == 1)
        #expect(lifecycle.diagnostics.outstandingCleanupTurnCount == 1)
        #expect(lifecycle.diagnostics.isQuiescent == false)
        #expect(
            isLatestCleanupRequired(
                consumer.takeDrain(binding: binding, generation: generation)
            )
        )

        func payload(version: Int) -> LatestValueCapacityPayload {
            LatestValueCapacityPayload(
                identity: .init(key: 0, version: version),
                generation: generation,
                mailboxReference: mailboxReference,
                recorder: recorder,
                gate: nil
            )
        }
        #expect(
            producer.offer(generation: generation, key: 0, value: payload(version: 1))
                == .admitted(wake: .noWake)
        )
        #expect(
            producer.offer(generation: generation, key: 0, value: payload(version: 2))
                == .replacedPrevious(wake: .noWake)
        )
        #expect(
            producer.offer(generation: generation, key: 0, value: payload(version: 3))
                == .physicalCapacityExceeded
        )
        #expect(lifecycle.diagnostics.cleanupValueCount == 2)

        gate.release.signal()
        #expect(gate.completed.wait(timeout: .now() + 2) == .success)
        #expect(
            outerResult.value
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entries(count: 1),
                        wake: .scheduleDrain
                    )
                )
        )
        #expect(
            recorder.releasedIdentities
                == [.init(key: 0, version: 3), .init(key: 0, version: 0)]
        )
        #expect(lifecycle.diagnostics.cleanupValueCount == 1)
        #expect(lifecycle.diagnostics.physicalRetainedValueCount == 2)
        #expect(lifecycle.diagnostics.outstandingCleanupTurnCount == 0)
        #expect(lifecycle.diagnostics.isQuiescent == false)
        #expect(
            producer.offer(generation: generation, key: 0, value: payload(version: 3))
                == .admitted(wake: .noWake)
        )
    }

    @Test("terminal K plus R custody releases exactly one tracked payload per C turn")
    func terminalPhysicalCapacityHasLiteralReleaseHistory() {
        let recorder = LatestValueCapacityReleaseRecorder()
        let mailboxReference = LatestValueCapacityMailboxReference()
        let mailbox = LatestValueMailbox<Int, LatestValueCapacityPayload>(
            generation: generation,
            declaredKeys: [0, 1],
            limits: LatestValueLimits(
                maximumValuesPerLease: 2,
                maximumAuxiliaryRetainedValues: 4,
                cleanupQuantum: .entries(maximumEntries: 1)
            )
        )
        mailboxReference.mailbox = mailbox
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding

        func payload(key: Int, version: Int) -> LatestValueCapacityPayload {
            LatestValueCapacityPayload(
                identity: .init(key: key, version: version),
                generation: generation,
                mailboxReference: mailboxReference,
                recorder: recorder,
                gate: nil
            )
        }

        _ = producer.offer(generation: generation, key: 0, value: payload(key: 0, version: 0))
        _ = producer.offer(generation: generation, key: 1, value: payload(key: 1, version: 0))
        let token: AdmissionDrainToken? = {
            guard
                case .drain(let drain) = consumer.takeDrain(
                    binding: binding,
                    generation: generation
                )
            else {
                Issue.record("Expected tracked full-wave custody to lease")
                return nil
            }
            return drain.token
        }()
        guard let token else { return }

        _ = producer.offer(generation: generation, key: 0, value: payload(key: 0, version: 1))
        _ = producer.offer(generation: generation, key: 1, value: payload(key: 1, version: 1))
        #expect(
            producer.offer(
                generation: generation,
                key: 0,
                value: payload(key: 0, version: 2)
            ) == .replacedPrevious(wake: .noWake)
        )
        #expect(
            producer.offer(
                generation: generation,
                key: 1,
                value: payload(key: 1, version: 2)
            ) == .replacedPrevious(wake: .noWake)
        )
        #expect(
            producer.offer(
                generation: generation,
                key: 0,
                value: payload(key: 0, version: 3)
            ) == .physicalCapacityExceeded
        )
        #expect(recorder.releasedIdentities == [.init(key: 0, version: 3)])

        #expect(
            consumer.acknowledge(token, disposition: .transferred)
                == .accepted(wake: .scheduleDrain)
        )
        #expect(lifecycle.invalidate(generation: generation) == .applied)
        #expect(lifecycle.diagnostics.cleanupValueCount == 6)
        #expect(lifecycle.diagnostics.physicalRetainedValueCount == 6)
        #expect(recorder.releasedIdentities == [.init(key: 0, version: 3)])

        let expectedCleanupOrder: [LatestValueCapacityIdentity] = [
            .init(key: 0, version: 1),
            .init(key: 1, version: 1),
            .init(key: 0, version: 0),
            .init(key: 1, version: 0),
            .init(key: 0, version: 2),
            .init(key: 1, version: 2),
        ]
        for (index, expectedIdentity) in expectedCleanupOrder.enumerated() {
            guard
                case .performed(let turn) = lifecycle.performCleanup(
                    generation: generation
                )
            else {
                Issue.record("Expected one tracked C-sized cleanup turn")
                return
            }
            #expect(turn.release == .entries(count: 1))
            #expect(recorder.releasedIdentities.count == index + 2)
            #expect(recorder.releasedIdentities.last == expectedIdentity)
        }
        #expect(lifecycle.diagnostics.isQuiescent)
    }

    private func makeIntegerMailbox(
        declaredKeys: Set<Int>,
        deliveryLimit: Int,
        auxiliaryLimit: Int,
        cleanupLimit: Int,
        clock: TestPushClock? = nil
    ) -> LatestValueMailbox<Int, Int> {
        let limits = LatestValueLimits(
            maximumValuesPerLease: deliveryLimit,
            maximumAuxiliaryRetainedValues: auxiliaryLimit,
            cleanupQuantum: .entries(maximumEntries: cleanupLimit)
        )
        if let clock {
            return LatestValueMailbox(
                generation: generation,
                declaredKeys: declaredKeys,
                limits: limits,
                clock: clock
            )
        }
        return LatestValueMailbox(
            generation: generation,
            declaredKeys: declaredKeys,
            limits: limits
        )
    }
}

private func isLatestCleanupRequired<Key, Value>(
    _ result: LatestValueDrainResult<Key, Value>
) -> Bool where Key: Hashable & Sendable, Value: Sendable {
    if case .cleanupRequired = result { return true }
    return false
}

private func isLatestClosed<Key, Value>(
    _ result: LatestValueDrainResult<Key, Value>
) -> Bool where Key: Hashable & Sendable, Value: Sendable {
    if case .closed = result { return true }
    return false
}

private struct LatestValueCapacityIdentity: Sendable, Equatable {
    let key: Int
    let version: Int
}

private final class LatestValueCapacityReleaseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedReentrantCleanupResult: AdmissionCleanupTurnResult?
    private var recordedReleasedIdentities: [LatestValueCapacityIdentity] = []

    var reentrantCleanupResult: AdmissionCleanupTurnResult? {
        lock.withLock { recordedReentrantCleanupResult }
    }

    var releasedIdentities: [LatestValueCapacityIdentity] {
        lock.withLock { recordedReleasedIdentities }
    }

    func recordReentrantCleanupResult(_ result: AdmissionCleanupTurnResult) {
        lock.withLock {
            recordedReentrantCleanupResult = result
        }
    }

    func recordRelease(_ identity: LatestValueCapacityIdentity) {
        lock.withLock {
            recordedReleasedIdentities.append(identity)
        }
    }
}

private final class LatestValueCapacityDeinitGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let completed = DispatchSemaphore(value: 0)
}

private final class LatestValueCapacityMailboxReference: @unchecked Sendable {
    weak var mailbox: LatestValueMailbox<Int, LatestValueCapacityPayload>?
}

private final class LatestValueCapacityPayload: @unchecked Sendable {
    private let identity: LatestValueCapacityIdentity
    private let generation: AdmissionGeneration
    private let mailboxReference: LatestValueCapacityMailboxReference
    private let recorder: LatestValueCapacityReleaseRecorder
    private let gate: LatestValueCapacityDeinitGate?

    init(
        identity: LatestValueCapacityIdentity,
        generation: AdmissionGeneration,
        mailboxReference: LatestValueCapacityMailboxReference,
        recorder: LatestValueCapacityReleaseRecorder,
        gate: LatestValueCapacityDeinitGate?
    ) {
        self.identity = identity
        self.generation = generation
        self.mailboxReference = mailboxReference
        self.recorder = recorder
        self.gate = gate
    }

    deinit {
        if gate != nil, let mailbox = mailboxReference.mailbox {
            recorder.recordReentrantCleanupResult(
                mailbox.consumerPort.performCleanup(generation: generation)
            )
        }
        gate?.entered.signal()
        if let gate {
            _ = gate.release.wait(timeout: .now() + 2)
        }
        recorder.recordRelease(identity)
    }
}

private final class LatestValueCapacityResultBox<Value: Sendable>: @unchecked Sendable {
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
