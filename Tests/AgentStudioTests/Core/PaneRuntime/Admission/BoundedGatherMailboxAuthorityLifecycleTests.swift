import Foundation
import Testing

@testable import AgentStudio

extension AdmissionBoundedGatherMailboxTests {
    @Test("rebind re-presents an incumbent lease before queued cleanup")
    func rebindRepresentsIncumbentLeaseBeforeQueuedCleanup() {
        // Arrange
        let mailbox = makeMailbox(
            declaredKeys: [.alpha],
            limits: GatherMailboxLimits(
                maximumDeclaredKeys: 1,
                maximumRetainedContributions: 2,
                maximumRetainedItems: 2,
                maximumRetainedBytes: 2,
                maximumRetainedContributionsPerKey: 2,
                maximumRetainedItemsPerKey: 2,
                maximumRetainedBytesPerKey: 2,
                maximumContributionsPerLease: 1,
                maximumItemsPerLease: 1,
                maximumBytesPerLease: 1,
                cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 1, maximumBytes: 1)
            )
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let firstBinding = consumer.bindConsumer().binding
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "incumbent", items: 1, bytes: 1)
        )
        let incumbentLease = requireLease(
            consumer.takeDrain(binding: firstBinding, generation: generation)
        )
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "retired", items: 1, bytes: 1)
        )
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "recovery", items: 1, bytes: 1)
        )

        // Act
        let replacementBinding = consumer.bindConsumer().binding
        let representedLease = requireLease(
            consumer.takeDrain(binding: replacementBinding, generation: generation)
        )
        let diagnostics = mailbox.lifecyclePort.diagnostics

        // Assert
        #expect(incumbentLease?.contributions.map(\.payload.label) == ["incumbent"])
        #expect(representedLease?.contributions.map(\.payload.label) == ["incumbent"])
        #expect(representedLease?.contributions.map(\.footprint) == incumbentLease?.contributions.map(\.footprint))
        #expect(representedLease?.token != incumbentLease?.token)
        #expect(diagnostics.cleanupContributionCount == 1)
        #expect(diagnostics.leasedContributionCount == 1)
        #expect(diagnostics.recoverySlotCount == 1)
    }

    @Test("empty-key recovery rollover commits without publishing partial metadata")
    func emptyKeyRecoveryRolloverCommitsWithoutPublishingPartialMetadata() {
        // Arrange
        let mailbox = BoundedGatherMailbox<GatherTestKey, GatherTestPayload>(
            generation: generation,
            declaredKeys: [.alpha],
            limits: generousLimits,
            clock: TestPushClock(),
            authoritySeed: GatherMailboxAuthoritySeed(
                recoveryCustodySequence: UInt64.max
            )
        )
        let initialAuthority = mailbox.lifecyclePort.authoritySnapshot

        // Act
        let offer = mailbox.producerPort.offer(
            generation: generation,
            contribution: contribution(
                key: .alpha,
                label: "rollover",
                items: 1,
                bytes: 1,
                recoverySignal: .authoritativeRecoveryRequired
            )
        )
        let rotatedAuthority = mailbox.lifecyclePort.authoritySnapshot
        let diagnostics = mailbox.lifecyclePort.diagnostics

        // Assert
        #expect(requireAdmission(offer.receipt)?.payload == .retained)
        #expect(initialAuthority.recoveryCustodyEpoch != rotatedAuthority.recoveryCustodyEpoch)
        #expect(rotatedAuthority.recoveryCustodySequence == 1)
        #expect(diagnostics.admission.pendingKeyCount == 1)
        #expect(diagnostics.recoverySlotCount == 1)
        #expect(diagnostics.admission.oldestPendingAge == .exact(.zero))
    }

    @Test("binding lease and recovery authority rotate without aliasing or losing debt")
    func authorityExhaustionRotatesEpochsAndPreservesRecoveryDebt() {
        // Arrange
        let clock = TestPushClock()
        let mailbox: BoundedGatherMailbox<GatherTestKey, GatherTestPayload> = BoundedGatherMailbox(
            generation: generation,
            declaredKeys: Set([GatherTestKey.alpha]),
            limits: generousLimits,
            clock: clock,
            authoritySeed: GatherMailboxAuthoritySeed(
                bindingSequence: UInt64.max - 1,
                leaseSequence: UInt64.max - 1,
                recoveryCustodySequence: .max,
                recoveryStampsByKey: [.alpha: .sequenced(.max)]
            )
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let initialAuthority = mailbox.lifecyclePort.authoritySnapshot
        let firstBinding = consumer.bindConsumer().binding
        let maximumBindingAuthority = mailbox.lifecyclePort.authoritySnapshot
        let maximumLease = requireLease(
            consumer.takeDrain(binding: firstBinding, generation: generation)
        )
        let maximumLeaseAuthority = mailbox.lifecyclePort.authoritySnapshot
        let exhaustedOffer = producer.offer(
            generation: generation,
            contribution: contribution(
                key: .alpha,
                label: "must-contract",
                items: 1,
                bytes: 1,
                recoverySignal: .authoritativeRecoveryRequired
            )
        )
        let rotatedRecoveryAuthority = mailbox.lifecyclePort.authoritySnapshot

        // Act
        let replacementBinding = consumer.bindConsumer().binding
        let rotatedBindingAuthority = mailbox.lifecyclePort.authoritySnapshot
        let replacementMaximumLease = requireLease(
            consumer.takeDrain(binding: replacementBinding, generation: generation)
        )
        let lateAcknowledgement = maximumLease.map {
            consumer.acknowledge(token: $0.token, disposition: .transferred)
        }
        let replacementAcknowledgement = replacementMaximumLease.map {
            consumer.acknowledge(token: $0.token, disposition: .transferred)
        }
        let exhaustedLease = requireLease(
            consumer.takeDrain(binding: replacementBinding, generation: generation)
        )
        let rotatedLeaseAuthority = mailbox.lifecyclePort.authoritySnapshot
        let exhaustedAcknowledgement = exhaustedLease.map {
            consumer.acknowledge(token: $0.token, disposition: .transferred)
        }
        let laterOrdinary = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "still-sealed", items: 1, bytes: 1)
        )
        let diagnostics = mailbox.lifecyclePort.diagnostics

        // Assert
        let exhaustedReceipt = requireAdmission(exhaustedOffer.receipt)
        let laterReceipt = requireAdmission(laterOrdinary.receipt)
        #expect(exhaustedReceipt?.payload == .contractedToRecovery)
        #expect(laterReceipt?.payload == .contractedToRecovery)
        #expect(exhaustedReceipt?.recoveryRevision == laterReceipt?.recoveryRevision)
        #expect(replacementMaximumLease?.token != maximumLease?.token)
        #expect(lateAcknowledgement == .invalidToken)
        #expect(replacementAcknowledgement == .accepted(wake: .scheduleDrain))
        #expect(exhaustedLease?.recoveryRevision == exhaustedReceipt?.recoveryRevision)
        #expect(exhaustedAcknowledgement == .accepted(wake: .noWake))
        #expect(initialAuthority.bindingEpoch == maximumBindingAuthority.bindingEpoch)
        #expect(rotatedBindingAuthority.bindingEpoch != maximumBindingAuthority.bindingEpoch)
        #expect(rotatedBindingAuthority.bindingSequence == 1)
        #expect(initialAuthority.leaseEpoch == maximumLeaseAuthority.leaseEpoch)
        #expect(rotatedLeaseAuthority.leaseEpoch != maximumLeaseAuthority.leaseEpoch)
        #expect(rotatedLeaseAuthority.leaseSequence == 1)
        #expect(rotatedRecoveryAuthority.recoveryCustodyEpoch != initialAuthority.recoveryCustodyEpoch)
        #expect(rotatedRecoveryAuthority.recoveryCustodySequence == 1)
        #expect(diagnostics.admission.offered == 2)
        #expect(diagnostics.admission.admitted == 2)
        #expect(diagnostics.admission.contracted == 2)
        #expect(diagnostics.admission.repairEscalations == 1)
        #expect(diagnostics.recoverySlotCount == 1)
    }

    @Test("every recovery advance mints nonaliasing debt identity across exhaustion")
    func everyRecoveryAdvanceMintsNonaliasingDebtIdentityAcrossExhaustion() {
        // Arrange
        let mailbox: BoundedGatherMailbox<GatherTestKey, GatherTestPayload> = BoundedGatherMailbox(
            generation: generation,
            declaredKeys: [.alpha],
            limits: generousLimits,
            clock: TestPushClock(),
            authoritySeed: GatherMailboxAuthoritySeed(
                recoveryCustodySequence: UInt64.max - 1,
                recoveryStampsByKey: [.alpha: .sequenced(UInt64.max - 1)]
            )
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding
        let initialAuthority = mailbox.lifecyclePort.authoritySnapshot
        let maximumMinusOneLease = requireLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )

        // Act
        let maximumOffer = producer.offer(
            generation: generation,
            contribution: contribution(
                key: .alpha,
                label: "maximum-debt",
                items: 1,
                bytes: 1,
                recoverySignal: .authoritativeRecoveryRequired
            )
        )
        let maximumAuthority = mailbox.lifecyclePort.authoritySnapshot
        let maximumMinusOneAcknowledgement = maximumMinusOneLease.map {
            consumer.acknowledge(token: $0.token, disposition: .transferred)
        }
        let afterMaximumMinusOneAcknowledgement = mailbox.lifecyclePort.diagnostics
        let maximumLease = requireLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )
        let exhaustedOffer = producer.offer(
            generation: generation,
            contribution: contribution(
                key: .alpha,
                label: "first-exhausted-debt",
                items: 1,
                bytes: 1,
                recoverySignal: .authoritativeRecoveryRequired
            )
        )
        let exhaustedAuthority = mailbox.lifecyclePort.authoritySnapshot
        let maximumAcknowledgement = maximumLease.map {
            consumer.acknowledge(token: $0.token, disposition: .transferred)
        }
        let afterMaximumAcknowledgement = mailbox.lifecyclePort.diagnostics
        let exhaustedLease = requireLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )
        let newerExhaustedOffer = producer.offer(
            generation: generation,
            contribution: contribution(
                key: .alpha,
                label: "newer-exhausted-debt",
                items: 1,
                bytes: 1
            )
        )
        let newerExhaustedAuthority = mailbox.lifecyclePort.authoritySnapshot
        let exhaustedAcknowledgement = exhaustedLease.map {
            consumer.acknowledge(token: $0.token, disposition: .transferred)
        }
        let afterExhaustedAcknowledgement = mailbox.lifecyclePort.diagnostics
        let newerExhaustedLease = requireLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )

        // Assert
        let maximumReceipt = requireAdmission(maximumOffer.receipt)
        let exhaustedReceipt = requireAdmission(exhaustedOffer.receipt)
        let newerExhaustedReceipt = requireAdmission(newerExhaustedOffer.receipt)
        #expect(maximumReceipt?.payload == .retained)
        #expect(maximumReceipt?.recoveryRevision != maximumMinusOneLease?.recoveryRevision)
        #expect(maximumMinusOneAcknowledgement == .accepted(wake: .scheduleDrain))
        #expect(afterMaximumMinusOneAcknowledgement.recoverySlotCount == 1)
        #expect(maximumLease?.recoveryRevision == maximumReceipt?.recoveryRevision)
        #expect(exhaustedReceipt?.payload == .contractedToRecovery)
        #expect(exhaustedReceipt?.recoveryRevision != maximumReceipt?.recoveryRevision)
        #expect(maximumAcknowledgement == .accepted(wake: .scheduleDrain))
        #expect(afterMaximumAcknowledgement.recoverySlotCount == 1)
        #expect(exhaustedLease?.recoveryRevision == exhaustedReceipt?.recoveryRevision)
        #expect(newerExhaustedReceipt?.payload == .contractedToRecovery)
        #expect(newerExhaustedReceipt?.recoveryRevision == exhaustedReceipt?.recoveryRevision)
        #expect(exhaustedAcknowledgement == .accepted(wake: .scheduleDrain))
        #expect(afterExhaustedAcknowledgement.recoverySlotCount == 1)
        #expect(newerExhaustedLease?.recoveryRevision == newerExhaustedReceipt?.recoveryRevision)
        #expect(newerExhaustedLease?.token != exhaustedLease?.token)
        #expect(maximumAuthority.recoveryCustodyEpoch == initialAuthority.recoveryCustodyEpoch)
        #expect(maximumAuthority.recoveryCustodySequence == UInt64.max)
        #expect(exhaustedAuthority.recoveryCustodyEpoch != maximumAuthority.recoveryCustodyEpoch)
        #expect(exhaustedAuthority.recoveryCustodySequence == 1)
        #expect(newerExhaustedAuthority.recoveryCustodyEpoch == exhaustedAuthority.recoveryCustodyEpoch)
        #expect(newerExhaustedAuthority.recoveryCustodySequence == 2)
        #expect(afterExhaustedAcknowledgement.admission.offered == 3)
        #expect(afterExhaustedAcknowledgement.admission.contracted == 2)
        #expect(afterExhaustedAcknowledgement.admission.repairEscalations == 2)
    }

    @Test("injected gather clock reenters outside protected state")
    func injectedGatherClockReentersOutsideProtectedState() {
        // Arrange
        let clockProbe = GatherReentrantClockProbe()
        let mailbox = BoundedGatherMailbox<GatherTestKey, GatherTestPayload>(
            generation: generation,
            declaredKeys: [.alpha],
            limits: generousLimits,
            clock: GatherReentrantClock(probe: clockProbe)
        )
        clockProbe.mailbox = mailbox

        // Act
        _ = mailbox.producerPort.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "clock-reentry", items: 1, bytes: 1)
        )
        _ = mailbox.lifecyclePort.diagnostics
        let invalidation = mailbox.lifecyclePort.invalidate(generation: generation)

        // Assert
        #expect(invalidation == .applied)
        #expect(clockProbe.reentryCount == 2)
    }

    @Test("empty take does not consume lease authority before epoch rotation")
    func emptyTakeDoesNotConsumeLeaseAuthority() {
        // Arrange
        let mailbox: BoundedGatherMailbox<GatherTestKey, GatherTestPayload> = BoundedGatherMailbox(
            generation: generation,
            declaredKeys: Set([GatherTestKey.alpha]),
            limits: generousLimits,
            clock: TestPushClock(),
            authoritySeed: GatherMailboxAuthoritySeed<GatherTestKey>(
                leaseSequence: UInt64.max - 1
            )
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding
        let initialAuthority = mailbox.lifecyclePort.authoritySnapshot

        // Act
        let empty = consumer.takeDrain(binding: binding, generation: generation)
        let afterEmpty = mailbox.lifecyclePort.authoritySnapshot
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "last-sequence", items: 1, bytes: 1)
        )
        let maximumLease = requireLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )
        let maximumLeaseAuthority = mailbox.lifecyclePort.authoritySnapshot
        let maximumAcknowledgement = maximumLease.map {
            consumer.acknowledge(token: $0.token, disposition: .transferred)
        }
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "new-epoch", items: 1, bytes: 1)
        )
        let rotatedLease = requireLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )
        let rotatedLeaseAuthority = mailbox.lifecyclePort.authoritySnapshot

        // Assert
        guard case .empty = empty else {
            Issue.record("Expected empty take before any contribution")
            return
        }
        #expect(afterEmpty.leaseSequence == UInt64.max - 1)
        #expect(maximumAcknowledgement == .accepted(wake: .noWake))
        #expect(maximumLeaseAuthority.leaseEpoch == initialAuthority.leaseEpoch)
        #expect(maximumLeaseAuthority.leaseSequence == .max)
        #expect(rotatedLeaseAuthority.leaseEpoch != maximumLeaseAuthority.leaseEpoch)
        #expect(rotatedLeaseAuthority.leaseSequence == 1)
        #expect(rotatedLease?.token != maximumLease?.token)
    }

    @Test("overflow retirement defers increasing-depth payload destruction to consumer work")
    func overflowRetirementDefersPayloadDestructionToConsumerWork() {
        for retainedDepth in [1, 16, 128] {
            // Arrange
            let recorder = GatherPayloadReleaseRecorder()
            let mailboxBox = WeakGatherPayloadMailboxBox()
            let limits = GatherMailboxLimits(
                maximumDeclaredKeys: 1,
                maximumRetainedContributions: retainedDepth,
                maximumRetainedItems: retainedDepth,
                maximumRetainedBytes: retainedDepth,
                maximumRetainedContributionsPerKey: retainedDepth,
                maximumRetainedItemsPerKey: retainedDepth,
                maximumRetainedBytesPerKey: retainedDepth,
                maximumContributionsPerLease: retainedDepth,
                maximumItemsPerLease: retainedDepth,
                maximumBytesPerLease: retainedDepth,
                cleanupQuantum: AdmissionCleanupQuantum(
                    maximumEntries: max(1, min(retainedDepth, 17)),
                    maximumBytes: max(1, retainedDepth)
                )
            )
            let mailbox = BoundedGatherMailbox<GatherTestKey, ReentrantGatherPayload>(
                generation: generation,
                declaredKeys: [.alpha],
                limits: limits
            )
            mailboxBox.mailbox = mailbox
            let producer = mailbox.producerPort
            let consumer = mailbox.consumerPort
            let binding = consumer.bindConsumer().binding
            for retainedIndex in 0..<retainedDepth {
                let identifier = String(retainedIndex)
                _ = producer.offer(
                    generation: generation,
                    contribution: GatherContribution(
                        key: .alpha,
                        payload: ReentrantGatherPayload(identifier: identifier) {
                            _ = mailboxBox.mailbox?.lifecyclePort.diagnostics
                            recorder.record(identifier)
                        },
                        footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                        recoverySignal: .ordinary
                    )
                )
            }

            // Act
            let overflow = producer.offer(
                generation: generation,
                contribution: GatherContribution(
                    key: .alpha,
                    payload: ReentrantGatherPayload(identifier: "overflow") {},
                    footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                    recoverySignal: .ordinary
                )
            )
            let releasesAfterOffer = recorder.identifiers
            let cleanupPrecedence = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
            var releasedContributionCount = 0
            var observedCleanupFollowUpWake = false
            while releasedContributionCount < retainedDepth {
                let releasedBeforeTurn = recorder.identifiers.count
                guard case .performed(let turn) = consumer.performCleanup(generation: generation) else {
                    Issue.record("Expected bounded gather cleanup turn")
                    break
                }
                #expect(turn.releasedEntryCount > 0)
                #expect(turn.releasedEntryCount <= 17)
                #expect(turn.releasedByteCount == turn.releasedEntryCount)
                #expect(recorder.identifiers.count - releasedBeforeTurn == turn.releasedEntryCount)
                releasedContributionCount += turn.releasedEntryCount
                if releasedContributionCount < retainedDepth {
                    #expect(turn.wake == .scheduleDrain)
                    observedCleanupFollowUpWake = true
                } else {
                    #expect(turn.wake == .noWake)
                }
            }
            let recoveryLease = requireReentrantLease(
                consumer.takeDrain(binding: binding, generation: generation)
            )

            // Assert
            #expect(requireGenericAdmission(overflow.receipt)?.payload == .contractedToRecovery)
            #expect(releasesAfterOffer.isEmpty)
            guard case .cleanupRequired = cleanupPrecedence else {
                Issue.record("Expected cleanup-first gather service after overflow retirement")
                return
            }
            #expect(observedCleanupFollowUpWake == (retainedDepth > 17))
            #expect(consumer.performCleanup(generation: generation) == .empty)
            #expect(recorder.identifiers.count == retainedDepth)
            #expect(Set(recorder.identifiers) == Set((0..<retainedDepth).map(String.init)))
            #expect(recoveryLease?.contributions.isEmpty == true)
            #expect(recoveryLease?.recoveryRevision != nil)
        }
    }

    @Test("invalidation moves pending retry and active lease custody into bounded cleanup")
    func invalidationMovesEveryContributionCustodyShapeIntoCleanup() {
        // Arrange
        let clock = TestPushClock()
        let recorder = GatherPayloadReleaseRecorder()
        let mailboxBox = WeakGatherPayloadMailboxBox()
        let limits = GatherMailboxLimits(
            maximumDeclaredKeys: 3,
            maximumRetainedContributions: 3,
            maximumRetainedItems: 3,
            maximumRetainedBytes: 3,
            maximumRetainedContributionsPerKey: 1,
            maximumRetainedItemsPerKey: 1,
            maximumRetainedBytesPerKey: 1,
            maximumContributionsPerLease: 1,
            maximumItemsPerLease: 1,
            maximumBytesPerLease: 1,
            cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 1, maximumBytes: 1)
        )
        let mailbox = BoundedGatherMailbox<GatherTestKey, ReentrantGatherPayload>(
            generation: generation,
            declaredKeys: [.alpha, .beta, .gamma],
            limits: limits,
            clock: clock
        )
        mailboxBox.mailbox = mailbox
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding
        for (key, identifier) in [
            (GatherTestKey.alpha, "retry"),
            (.beta, "active"),
            (.gamma, "pending"),
        ] {
            _ = producer.offer(
                generation: generation,
                contribution: GatherContribution(
                    key: key,
                    payload: ReentrantGatherPayload(identifier: identifier) {
                        _ = mailboxBox.mailbox?.lifecyclePort.diagnostics
                        recorder.record(identifier)
                    },
                    footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                    recoverySignal: .ordinary
                )
            )
        }
        let alphaToken = requireReentrantLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )?.token
        _ = alphaToken.map {
            consumer.acknowledge(token: $0, disposition: .retry)
        }
        let activeBetaToken = requireReentrantLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )?.token
        clock.advance(by: .seconds(5))

        // Act
        let invalidation = lifecycle.invalidate(generation: generation)
        let afterInvalidation = lifecycle.diagnostics
        let lateAcknowledgement = activeBetaToken.map {
            consumer.acknowledge(token: $0, disposition: .transferred)
        }
        let releasesAfterInvalidation = recorder.identifiers
        var cleanupTurns: [AdmissionCleanupTurn] = []
        for _ in 0..<6 {
            guard case .performed(let turn) = lifecycle.performCleanup(generation: generation) else {
                Issue.record("Expected invalidated gather cleanup custody")
                break
            }
            cleanupTurns.append(turn)
        }
        let afterCleanup = lifecycle.diagnostics

        // Assert
        #expect(invalidation == .applied)
        #expect(releasesAfterInvalidation.isEmpty)
        #expect(afterInvalidation.retainedContributionCount == 0)
        #expect(afterInvalidation.pendingContributionCount == 0)
        #expect(afterInvalidation.leasedContributionCount == 0)
        #expect(afterInvalidation.cleanupContributionCount == 3)
        #expect(afterInvalidation.cleanupMetadataEntryCount == 3)
        #expect(afterInvalidation.physicalRetainedContributionCount == 3)
        #expect(afterInvalidation.cleanupContributionHighWater == 3)
        #expect(afterInvalidation.physicalRetainedContributionHighWater == 3)
        #expect(afterInvalidation.oldestCleanupAge == .exact(.seconds(5)))
        #expect(afterInvalidation.outstandingLeaseCount == 0)
        #expect(afterInvalidation.isQuiescent == false)
        #expect(lateAcknowledgement == .closed)
        #expect(cleanupTurns.count == 6)
        #expect(cleanupTurns.allSatisfy { $0.releasedEntryCount == 1 })
        #expect(cleanupTurns.compactMap(\.releasedByteCount).reduce(0, +) == 3)
        #expect(cleanupTurns.dropLast().allSatisfy { $0.wake == .scheduleDrain })
        #expect(cleanupTurns.last?.wake == .noWake)
        #expect(recorder.identifiers.count == 3)
        #expect(afterCleanup.cleanupContributionCount == 0)
        #expect(afterCleanup.cleanupMetadataEntryCount == 0)
        #expect(afterCleanup.physicalRetainedContributionCount == 0)
        #expect(afterCleanup.isQuiescent)
        #expect(lifecycle.performCleanup(generation: generation) == .empty)
    }

    @Test("seal drains accepted work and invalidation preserves cumulative diagnostics")
    func lifecyclePreservesCumulativeDiagnostics() {
        // Arrange
        let mailbox = makeMailbox(declaredKeys: [.alpha], limits: generousLimits)
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "accepted", items: 2, bytes: 4)
        )

        // Act
        let sealed = mailbox.lifecyclePort.seal(generation: generation)
        let rejected = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "closed", items: 1, bytes: 1)
        )
        let lease = requireLease(consumer.takeDrain(binding: binding, generation: generation))
        let acknowledgement = lease.map {
            consumer.acknowledge(token: $0.token, disposition: .transferred)
        }
        let closedDrain = consumer.takeDrain(binding: binding, generation: generation)
        let invalidated = mailbox.lifecyclePort.invalidate(generation: generation)
        let diagnostics = mailbox.lifecyclePort.diagnostics

        // Assert
        #expect(sealed == .applied)
        guard case .closed = rejected.receipt else {
            Issue.record("Expected offer after seal to be closed")
            return
        }
        #expect(acknowledgement == .accepted(wake: .noWake))
        guard case .closed = closedDrain else {
            Issue.record("Expected sealed drained mailbox to close")
            return
        }
        #expect(invalidated == .applied)
        #expect(diagnostics.admission.offered == 2)
        #expect(diagnostics.admission.admitted == 1)
        #expect(diagnostics.admission.rejectedClosed == 1)
        #expect(diagnostics.retainedContributionCount == 0)
        #expect(diagnostics.retainedContributionHighWater == 1)
        #expect(diagnostics.retainedItemHighWater == 2)
        #expect(diagnostics.retainedByteHighWater == 4)
        #expect(diagnostics.outstandingLeaseCount == 0)
    }
}
