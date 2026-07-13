import Foundation
import Testing
import os

@testable import AgentStudio

@Suite("Admission BoundedGatherMailbox")
struct AdmissionBoundedGatherMailboxTests {
    @Test("value-only admission retains opaque payload without domain algebra")
    func valueOnlyAdmissionRetainsOpaquePayloadWithoutDomainAlgebra() {
        // Arrange
        let clock = TestPushClock()
        let mailbox = makeMailbox(
            declaredKeys: [.alpha],
            limits: generousLimits,
            clock: clock
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding

        // Act
        let offer = producer.offer(
            generation: generation,
            contribution: contribution(
                key: .alpha,
                label: "opaque-a",
                items: 1,
                bytes: 8
            )
        )
        let drain = consumer.takeDrain(binding: binding, generation: generation)

        // Assert
        let receipt = requireAdmission(offer)
        expectRetainedWithoutRecovery(receipt)
        guard case .admitted(_, wake: .scheduleDrain) = offer else {
            Issue.record("Expected admitted gather offer to schedule a drain")
            return
        }
        let lease = requireLease(drain)
        #expect(lease.key == .alpha)
        #expect(
            requireContributions(lease).testValues.map(\.payload)
                == [GatherTestPayload(label: "opaque-a")]
        )
        guard case .contributions = lease.payload else {
            Issue.record("Expected contribution-only gather lease")
            return
        }
    }

    @Test("global retained capacity counts pending plus leased custody at bound and bound plus one")
    func globalRetainedCapacityCountsPendingPlusLeasedCustody() {
        // Arrange
        let mailbox = makeMailbox(
            declaredKeys: [.alpha, .beta, .gamma],
            limits: GatherMailboxLimits(
                maximumDeclaredKeys: 3,
                maximumRetainedContributions: 2,
                maximumRetainedItems: 2,
                maximumRetainedBytes: 4,
                maximumRetainedContributionsPerKey: 2,
                maximumRetainedItemsPerKey: 2,
                maximumRetainedBytesPerKey: 4,
                maximumContributionsPerLease: 1,
                maximumItemsPerLease: 1,
                maximumBytesPerLease: 2,
                cleanupQuantum: .entriesAndBytes(maximumEntries: 1, maximumBytes: 2)
            )
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "leased", items: 1, bytes: 2)
        )
        let firstLease = requireLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .beta, label: "pending", items: 1, bytes: 2)
        )

        // Act
        let atBound = mailbox.lifecyclePort.diagnostics
        let overflow = producer.offer(
            generation: generation,
            contribution: contribution(key: .gamma, label: "overflow", items: 1, bytes: 1)
        )
        let afterOverflow = mailbox.lifecyclePort.diagnostics

        // Assert
        #expect(firstLease.key == .alpha)
        #expect(atBound.retainedContributionCount == 2)
        #expect(atBound.retainedItemCount == 2)
        #expect(atBound.retainedByteCount == 4)
        #expect(atBound.pendingContributionCount == 1)
        #expect(atBound.leasedContributionCount == 1)
        let overflowReceipt = requireAdmission(overflow)
        _ = requireContractedRecoveryRevision(overflowReceipt)
        #expect(afterOverflow.retainedContributionCount == 2)
        #expect(afterOverflow.retainedItemCount == 2)
        #expect(afterOverflow.retainedByteCount == 4)
        #expect(afterOverflow.recoverySlotCount == 1)
    }

    @Test("per-key retained capacity counts an active lease and contracts only that key")
    func perKeyRetainedCapacityCountsActiveLease() {
        // Arrange
        let mailbox = makeMailbox(
            declaredKeys: [.alpha, .beta],
            limits: GatherMailboxLimits(
                maximumDeclaredKeys: 2,
                maximumRetainedContributions: 4,
                maximumRetainedItems: 4,
                maximumRetainedBytes: 8,
                maximumRetainedContributionsPerKey: 2,
                maximumRetainedItemsPerKey: 2,
                maximumRetainedBytesPerKey: 4,
                maximumContributionsPerLease: 1,
                maximumItemsPerLease: 1,
                maximumBytesPerLease: 2,
                cleanupQuantum: .entriesAndBytes(maximumEntries: 1, maximumBytes: 2)
            )
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "alpha-leased", items: 1, bytes: 2)
        )
        let leasedAlpha = requireLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "alpha-pending", items: 1, bytes: 2)
        )
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .beta, label: "beta-pending", items: 1, bytes: 2)
        )

        // Act
        let overflow = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "alpha-overflow", items: 1, bytes: 1)
        )
        let diagnostics = mailbox.lifecyclePort.diagnostics

        // Assert
        #expect(leasedAlpha.key == .alpha)
        let receipt = requireAdmission(overflow)
        _ = requireContractedRecoveryRevision(receipt)
        #expect(diagnostics.retainedContributionCount == 2)
        #expect(diagnostics.leasedContributionCount == 1)
        #expect(diagnostics.pendingContributionCount == 1)
        #expect(diagnostics.recoverySlotCount == 1)
    }

    @Test("one drain lease contains one key and respects the turn quantum")
    func oneDrainLeaseContainsOneKeyAndRespectsTurnQuantum() {
        // Arrange
        let mailbox = makeMailbox(
            declaredKeys: [.alpha, .beta],
            limits: GatherMailboxLimits(
                maximumDeclaredKeys: 2,
                maximumRetainedContributions: 4,
                maximumRetainedItems: 8,
                maximumRetainedBytes: 32,
                maximumRetainedContributionsPerKey: 3,
                maximumRetainedItemsPerKey: 6,
                maximumRetainedBytesPerKey: 24,
                maximumContributionsPerLease: 2,
                maximumItemsPerLease: 3,
                maximumBytesPerLease: 12,
                cleanupQuantum: .entriesAndBytes(maximumEntries: 2, maximumBytes: 12)
            )
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "alpha-1", items: 1, bytes: 4)
        )
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "alpha-2", items: 2, bytes: 8)
        )
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .beta, label: "beta-1", items: 1, bytes: 4)
        )

        // Act
        let firstDrain = consumer.takeDrain(binding: binding, generation: generation)

        // Assert
        let lease = requireLease(firstDrain)
        let leasedContributions = requireContributions(lease).testValues
        #expect(lease.key == .alpha)
        #expect(leasedContributions.map(\.payload.label) == ["alpha-1", "alpha-2"])
        #expect(leasedContributions.reduce(0) { $0 + $1.footprint.itemCount } == 3)
        #expect(leasedContributions.reduce(0) { $0 + $1.footprint.byteCount } == 12)
        #expect(mailbox.lifecyclePort.diagnostics.admission.pendingKeyCount == 2)
        #expect(mailbox.lifecyclePort.diagnostics.outstandingLeaseCount == 1)
    }

    @Test("payload and recovery dispositions produce orthogonal literal counters")
    func payloadAndRecoveryDispositionsProduceOrthogonalCounters() {
        // Arrange
        let mailbox = makeMailbox(
            declaredKeys: [.alpha, .beta],
            limits: GatherMailboxLimits(
                maximumDeclaredKeys: 2,
                maximumRetainedContributions: 2,
                maximumRetainedItems: 2,
                maximumRetainedBytes: 2,
                maximumRetainedContributionsPerKey: 1,
                maximumRetainedItemsPerKey: 1,
                maximumRetainedBytesPerKey: 1,
                maximumContributionsPerLease: 1,
                maximumItemsPerLease: 1,
                maximumBytesPerLease: 1,
                cleanupQuantum: .entriesAndBytes(maximumEntries: 1, maximumBytes: 1)
            )
        )
        let producer = mailbox.producerPort

        // Act
        let ordinary = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "ordinary", items: 1, bytes: 1)
        )
        let explicitRecovery = producer.offer(
            generation: generation,
            contribution: contribution(
                key: .beta,
                label: "explicit-recovery",
                items: 1,
                bytes: 1,
                recoverySignal: .authoritativeRecoveryRequired
            )
        )
        let capacityContraction = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "contracted", items: 1, bytes: 1)
        )
        let diagnostics = mailbox.lifecyclePort.diagnostics.admission

        // Assert
        expectRetainedWithoutRecovery(requireAdmission(ordinary))
        _ = requireRetainedRecoveryRevision(requireAdmission(explicitRecovery))
        let capacityContractionReceipt = requireAdmission(capacityContraction)
        _ = requireContractedRecoveryRevision(capacityContractionReceipt)
        #expect(requireContractionCause(capacityContractionReceipt) == .capacityPressure)
        #expect(diagnostics.offered == 3)
        #expect(diagnostics.admitted == 3)
        #expect(diagnostics.contracted == 1)
        #expect(diagnostics.repairEscalations == 2)
        #expect(diagnostics.rejectedStale == 0)
        #expect(diagnostics.rejectedUndeclared == 0)
        #expect(diagnostics.rejectedInvalid == 0)
        #expect(diagnostics.rejectedClosed == 0)
    }

    @Test("consumer rebind re-presents custody and a late old token clears nothing")
    func consumerRebindRePresentsCustodyAndRejectsLateOldToken() {
        // Arrange
        let mailbox = makeMailbox(declaredKeys: [.alpha], limits: generousLimits)
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let oldBinding = consumer.bindConsumer().binding
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "retained", items: 1, bytes: 4)
        )
        let oldLease = requireLease(
            consumer.takeDrain(binding: oldBinding, generation: generation)
        )

        // Act
        let replacementBinding = consumer.bindConsumer().binding
        let replacementLease = requireLease(
            consumer.takeDrain(binding: replacementBinding, generation: generation)
        )
        let lateOldAcknowledgement = consumer.acknowledge(
            token: oldLease.token,
            disposition: .transferred
        )
        let afterLateOldAcknowledgement = mailbox.lifecyclePort.diagnostics
        let replacementAcknowledgement = consumer.acknowledge(
            token: replacementLease.token,
            disposition: .transferred
        )

        // Assert
        #expect(requireContributions(oldLease).testValues.map(\.payload.label) == ["retained"])
        #expect(
            requireContributions(replacementLease).testValues.map(\.payload.label) == ["retained"]
        )
        #expect(replacementLease.token != oldLease.token)
        #expect(lateOldAcknowledgement == .invalidToken)
        #expect(afterLateOldAcknowledgement.retainedContributionCount == 1)
        #expect(afterLateOldAcknowledgement.outstandingLeaseCount == 1)
        #expect(replacementAcknowledgement == .accepted(wake: .noWake))
        #expect(mailbox.lifecyclePort.diagnostics.retainedContributionCount == 0)
    }

    @Test("stale generation foreign and double acknowledgements never clear current custody")
    func invalidAcknowledgementsNeverClearCurrentCustody() {
        // Arrange
        let mailbox = makeMailbox(declaredKeys: [.alpha], limits: generousLimits)
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding
        _ = mailbox.producerPort.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "current", items: 1, bytes: 1)
        )
        let currentLease = requireLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )

        let staleGeneration = AdmissionGeneration(owner: .filesystemObservation, value: 42)
        let staleMailbox = BoundedGatherMailbox<GatherTestKey, GatherTestPayload>(
            generation: staleGeneration,
            declaredKeys: [.alpha],
            limits: generousLimits
        )
        let staleConsumer = staleMailbox.consumerPort
        let staleBinding = staleConsumer.bindConsumer().binding
        _ = staleMailbox.producerPort.offer(
            generation: staleGeneration,
            contribution: contribution(key: .alpha, label: "stale", items: 1, bytes: 1)
        )
        let staleLease = requireLease(
            staleConsumer.takeDrain(binding: staleBinding, generation: staleGeneration)
        )

        let foreignMailbox = makeMailbox(declaredKeys: [.alpha], limits: generousLimits)
        let foreignConsumer = foreignMailbox.consumerPort
        let foreignBinding = foreignConsumer.bindConsumer().binding
        _ = foreignMailbox.producerPort.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "foreign", items: 1, bytes: 1)
        )
        let foreignLease = requireLease(
            foreignConsumer.takeDrain(binding: foreignBinding, generation: generation)
        )

        // Act
        let staleAcknowledgement = consumer.acknowledge(
            token: staleLease.token,
            disposition: .transferred
        )
        let foreignAcknowledgement = consumer.acknowledge(
            token: foreignLease.token,
            disposition: .transferred
        )
        let afterInvalidAcknowledgements = mailbox.lifecyclePort.diagnostics
        let acceptedAcknowledgement = consumer.acknowledge(
            token: currentLease.token,
            disposition: .transferred
        )
        let doubleAcknowledgement = consumer.acknowledge(
            token: currentLease.token,
            disposition: .transferred
        )

        // Assert
        #expect(staleAcknowledgement == .staleGeneration)
        #expect(foreignAcknowledgement == .invalidToken)
        #expect(afterInvalidAcknowledgements.retainedContributionCount == 1)
        #expect(afterInvalidAcknowledgements.outstandingLeaseCount == 1)
        #expect(acceptedAcknowledgement == .accepted(wake: .noWake))
        #expect(doubleAcknowledgement == .invalidToken)
        #expect(mailbox.lifecyclePort.diagnostics.retainedContributionCount == 0)
    }

    @Test("retry rotates behind unrelated ready keys and stays ahead of newer same-key work")
    func retryOrderingPreservesFairnessAndSameKeyOrder() {
        // Arrange
        let mailbox = makeMailbox(
            declaredKeys: [.alpha, .beta],
            limits: GatherMailboxLimits(
                maximumDeclaredKeys: 2,
                maximumRetainedContributions: 4,
                maximumRetainedItems: 4,
                maximumRetainedBytes: 16,
                maximumRetainedContributionsPerKey: 3,
                maximumRetainedItemsPerKey: 3,
                maximumRetainedBytesPerKey: 12,
                maximumContributionsPerLease: 1,
                maximumItemsPerLease: 1,
                maximumBytesPerLease: 4,
                cleanupQuantum: .entriesAndBytes(maximumEntries: 1, maximumBytes: 4)
            )
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "alpha-retry", items: 1, bytes: 4)
        )
        let alphaLease = requireLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .beta, label: "beta-ready", items: 1, bytes: 4)
        )
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "alpha-newer", items: 1, bytes: 4)
        )

        // Act
        let retryAcknowledgement = consumer.acknowledge(
            token: alphaLease.token,
            disposition: .retry
        )
        let betaLease = requireLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )
        let betaAcknowledgement = consumer.acknowledge(
            token: betaLease.token,
            disposition: .transferred
        )
        let retriedAlphaLease = requireLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )
        let retriedAlphaAcknowledgement = consumer.acknowledge(
            token: retriedAlphaLease.token,
            disposition: .transferred
        )
        let newerAlphaLease = requireLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )

        // Assert
        #expect(retryAcknowledgement == .accepted(wake: .scheduleDrain))
        #expect(betaLease.key == .beta)
        #expect(requireContributions(betaLease).testValues.map(\.payload.label) == ["beta-ready"])
        #expect(betaAcknowledgement == .accepted(wake: .scheduleDrain))
        #expect(retriedAlphaLease.key == .alpha)
        #expect(
            requireContributions(retriedAlphaLease).testValues.map(\.payload.label)
                == ["alpha-retry"]
        )
        #expect(retriedAlphaAcknowledgement == .accepted(wake: .scheduleDrain))
        #expect(newerAlphaLease.key == .alpha)
        #expect(
            requireContributions(newerAlphaLease).testValues.map(\.payload.label)
                == ["alpha-newer"]
        )
    }

    @Test("diagnostics preserve retained equals pending plus leased with mailbox-stamped age")
    func diagnosticsPreserveRetainedEquationAndMailboxStampedAge() {
        // Arrange
        let clock = TestPushClock()
        let mailbox = makeMailbox(
            declaredKeys: [.alpha, .beta],
            limits: generousLimits,
            clock: clock
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "oldest", items: 2, bytes: 6)
        )
        clock.advance(by: .seconds(2))
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .beta, label: "newer", items: 1, bytes: 3)
        )
        _ = consumer.takeDrain(binding: binding, generation: generation)
        clock.advance(by: .seconds(3))

        // Act
        let diagnostics = mailbox.lifecyclePort.diagnostics

        // Assert
        #expect(
            diagnostics.retainedContributionCount
                == diagnostics.pendingContributionCount + diagnostics.leasedContributionCount
        )
        #expect(diagnostics.retainedItemCount == diagnostics.pendingItemCount + diagnostics.leasedItemCount)
        #expect(diagnostics.retainedByteCount == diagnostics.pendingByteCount + diagnostics.leasedByteCount)
        #expect(diagnostics.retainedContributionCount == 2)
        #expect(diagnostics.retainedItemCount == 3)
        #expect(diagnostics.retainedByteCount == 9)
        #expect(diagnostics.retainedContributionHighWater == 2)
        #expect(diagnostics.retainedItemHighWater == 3)
        #expect(diagnostics.retainedByteHighWater == 9)
        #expect(diagnostics.admission.oldestPendingAge == .exact(.seconds(5)))
        #expect(diagnostics.outstandingLeaseCount == 1)
    }

    @Test("invalid footprint is one typed rejection and retains no custody")
    func invalidFootprintIsTypedRejectionWithoutCustody() {
        // Arrange
        let mailbox = makeMailbox(declaredKeys: [.alpha], limits: generousLimits)
        let producer = mailbox.producerPort

        // Act
        let negativeItems = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "negative-items", items: -1, bytes: 1)
        )
        let negativeBytes = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "negative-bytes", items: 1, bytes: -1)
        )
        let diagnostics = mailbox.lifecyclePort.diagnostics

        // Assert
        expectInvalidFootprint(negativeItems)
        expectInvalidFootprint(negativeBytes)
        #expect(diagnostics.admission.offered == 2)
        #expect(diagnostics.admission.admitted == 0)
        #expect(diagnostics.admission.rejectedInvalid == 2)
        #expect(diagnostics.retainedContributionCount == 0)
        #expect(diagnostics.recoverySlotCount == 0)
    }

    @Test("near Int maximum capacity arithmetic contracts without trapping")
    func nearIntMaximumCapacityArithmeticContractsWithoutTrapping() {
        // Arrange
        let maximumLimits = GatherMailboxLimits(
            maximumDeclaredKeys: 1,
            maximumRetainedContributions: 2,
            maximumRetainedItems: .max,
            maximumRetainedBytes: .max,
            maximumRetainedContributionsPerKey: 2,
            maximumRetainedItemsPerKey: .max,
            maximumRetainedBytesPerKey: .max,
            maximumContributionsPerLease: 2,
            maximumItemsPerLease: .max,
            maximumBytesPerLease: .max,
            cleanupQuantum: .entriesAndBytes(maximumEntries: 2, maximumBytes: .max)
        )
        let mailbox = makeMailbox(declaredKeys: [.alpha], limits: maximumLimits)
        let producer = mailbox.producerPort
        _ = producer.offer(
            generation: generation,
            contribution: contribution(
                key: .alpha,
                label: "maximum",
                items: .max,
                bytes: .max
            )
        )

        // Act
        let overflow = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "overflow", items: 1, bytes: 1)
        )
        let diagnostics = mailbox.lifecyclePort.diagnostics

        // Assert
        _ = requireContractedRecoveryRevision(requireAdmission(overflow))
        #expect(diagnostics.retainedContributionCount == 0)
        #expect(diagnostics.pendingContributionCount == 0)
        #expect(diagnostics.recoverySlotCount == 1)
        #expect(diagnostics.retainedItemHighWater == .max)
        #expect(diagnostics.retainedByteHighWater == .max)
    }

    @Test("declared-key scale and same-key depth keep key operation shape constant")
    func declaredKeyScaleAndSameKeyDepthKeepKeyOperationShapeConstant() {
        // Arrange / Act
        var fixedShapeKeyOperationCounts: [Int] = []
        for declaredKeyCount in [1, 100, 300] {
            let probe = GatherHashProbe()
            let keys = Set(
                (0..<declaredKeyCount).map {
                    GatherHashProbeKey(identifier: $0, probe: probe)
                })
            let mailbox = BoundedGatherMailbox<GatherHashProbeKey, Int>(
                generation: generation,
                declaredKeys: keys,
                limits: hashProbeLimits(
                    maximumDeclaredKeys: declaredKeyCount,
                    maximumContributions: 1
                )
            )
            probe.reset {
                _ = mailbox.lifecyclePort.diagnostics
            }
            let key = GatherHashProbeKey(identifier: 0, probe: probe)
            _ = mailbox.producerPort.offer(
                generation: generation,
                contribution: GatherContribution(
                    key: key,
                    payload: 1,
                    footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                    recoverySignal: .ordinary
                )
            )
            fixedShapeKeyOperationCounts.append(probe.operationCount)
        }

        let depthProbe = GatherHashProbe()
        let depthKey = GatherHashProbeKey(identifier: 0, probe: depthProbe)
        let depthMailbox = BoundedGatherMailbox<GatherHashProbeKey, Int>(
            generation: generation,
            declaredKeys: [depthKey],
            limits: hashProbeLimits(maximumDeclaredKeys: 1, maximumContributions: 300)
        )
        depthProbe.reset()
        for payload in 0..<300 {
            _ = depthMailbox.producerPort.offer(
                generation: generation,
                contribution: GatherContribution(
                    key: depthKey,
                    payload: payload,
                    footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                    recoverySignal: .ordinary
                )
            )
        }

        // Assert
        #expect(fixedShapeKeyOperationCounts.allSatisfy { $0 <= 16 })
        #expect(depthProbe.operationCount <= 900)
        #expect(depthMailbox.lifecyclePort.diagnostics.retainedContributionCount == 300)
    }

    @Test("ordinary retained offers do not advance recovery custody authority")
    func ordinaryRetainedOffersDoNotAdvanceRecoveryCustodyAuthority() {
        // Arrange
        let retainedDepth = 128
        let mailbox = BoundedGatherMailbox<GatherTestKey, GatherTestPayload>(
            generation: generation,
            declaredKeys: [.alpha],
            limits: hashProbeLimits(
                maximumDeclaredKeys: 1,
                maximumContributions: retainedDepth
            )
        )
        let initialAuthority = mailbox.lifecyclePort.authoritySnapshot

        // Act
        for retainedIndex in 0..<retainedDepth {
            _ = mailbox.producerPort.offer(
                generation: generation,
                contribution: contribution(
                    key: .alpha,
                    label: String(retainedIndex),
                    items: 1,
                    bytes: 1
                )
            )
        }
        let retainedAuthority = mailbox.lifecyclePort.authoritySnapshot

        // Assert
        #expect(retainedAuthority.recoveryCustodyEpoch == initialAuthority.recoveryCustodyEpoch)
        #expect(retainedAuthority.recoveryCustodySequence == initialAuthority.recoveryCustodySequence)
        #expect(mailbox.lifecyclePort.diagnostics.retainedContributionCount == retainedDepth)
    }

    @Test("semantic retirement keeps a conservative upper bound when the next global age is unknown")
    func semanticRetirementKeepsConservativeUpperBound() {
        // Arrange
        let clock = TestPushClock()
        let mailbox = makeMailbox(declaredKeys: [.alpha, .beta], limits: generousLimits, clock: clock)
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "oldest", items: 1, bytes: 1)
        )
        clock.advance(by: .seconds(1))
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .beta, label: "remaining", items: 1, bytes: 1)
        )
        let oldestLease = requireLease(consumer.takeDrain(binding: binding, generation: generation))
        clock.advance(by: .seconds(1))

        // Act
        let acknowledgement = consumer.acknowledge(
            token: oldestLease.token,
            disposition: .transferred
        )
        let diagnostics = mailbox.lifecyclePort.diagnostics

        // Assert
        #expect(acknowledgement == .accepted(wake: .scheduleDrain))
        #expect(diagnostics.retainedContributionCount == 1)
        #expect(diagnostics.admission.oldestPendingAge == .pressureConservative(.seconds(2)))
    }

    @Test("quantum-one cleanup never understates the literal oldest remaining contribution")
    func quantumOneCleanupNeverUnderstatesRemainingAge() {
        // Arrange
        let clock = TestPushClock()
        let mailbox = makeMailbox(
            declaredKeys: [.alpha, .beta],
            limits: GatherMailboxLimits(
                maximumDeclaredKeys: 2,
                maximumRetainedContributions: 2,
                maximumRetainedItems: 2,
                maximumRetainedBytes: 2,
                maximumRetainedContributionsPerKey: 1,
                maximumRetainedItemsPerKey: 1,
                maximumRetainedBytesPerKey: 1,
                maximumContributionsPerLease: 1,
                maximumItemsPerLease: 1,
                maximumBytesPerLease: 1,
                cleanupQuantum: .entriesAndBytes(maximumEntries: 1, maximumBytes: 1)
            ),
            clock: clock
        )
        let producer = mailbox.producerPort
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "oldest", items: 1, bytes: 1)
        )
        clock.advance(by: .seconds(1))
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .beta, label: "newer", items: 1, bytes: 1)
        )
        clock.advance(by: .seconds(1))
        _ = mailbox.lifecyclePort.invalidate(generation: generation)

        // Act
        let beforeCleanup = mailbox.lifecyclePort.diagnostics
        let firstTurn = mailbox.lifecyclePort.performCleanup(generation: generation)
        let afterFirstTurn = mailbox.lifecyclePort.diagnostics
        let secondTurn = mailbox.lifecyclePort.performCleanup(generation: generation)
        let afterSecondTurn = mailbox.lifecyclePort.diagnostics
        let thirdTurn = mailbox.lifecyclePort.performCleanup(generation: generation)
        let fourthTurn = mailbox.lifecyclePort.performCleanup(generation: generation)
        let afterFourthTurn = mailbox.lifecyclePort.diagnostics

        // Assert
        #expect(beforeCleanup.oldestCleanupAge == .exact(.seconds(2)))
        #expect(
            firstTurn
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entriesAndBytes(count: 1, bytes: 1),
                        wake: .scheduleDrain
                    )
                )
        )
        #expect(afterFirstTurn.oldestCleanupAge == .pressureConservative(.seconds(2)))
        #expect(
            secondTurn
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entriesAndBytes(count: 1, bytes: 0),
                        wake: .scheduleDrain
                    )
                )
        )
        #expect(afterSecondTurn.oldestCleanupAge == .pressureConservative(.seconds(2)))
        #expect(afterSecondTurn.isQuiescent == false)
        #expect(
            thirdTurn
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entriesAndBytes(count: 1, bytes: 1),
                        wake: .scheduleDrain
                    )
                )
        )
        #expect(
            fourthTurn
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entriesAndBytes(count: 1, bytes: 0),
                        wake: .noWake
                    )
                )
        )
        #expect(afterFourthTurn.oldestCleanupAge == nil)
        #expect(afterFourthTurn.isQuiescent)
    }

    @Test("interleaved recovery clearing keeps a conservative upper bound")
    func interleavedRecoveryClearingKeepsConservativeUpperBound() {
        // Arrange
        let clock = TestPushClock()
        let mailbox = makeMailbox(declaredKeys: [.alpha, .beta], limits: generousLimits, clock: clock)
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(
            generation: generation,
            contribution: contribution(
                key: .alpha,
                label: "oldest-recovery",
                items: 1,
                bytes: 1,
                recoverySignal: .authoritativeRecoveryRequired
            )
        )
        clock.advance(by: .seconds(1))
        _ = producer.offer(
            generation: generation,
            contribution: contribution(
                key: .beta,
                label: "remaining-recovery",
                items: 1,
                bytes: 1,
                recoverySignal: .authoritativeRecoveryRequired
            )
        )
        let oldestLease = requireLease(consumer.takeDrain(binding: binding, generation: generation))
        clock.advance(by: .seconds(1))

        // Act
        let acknowledgement = consumer.acknowledge(
            token: oldestLease.token,
            disposition: .transferred
        )
        let diagnostics = mailbox.lifecyclePort.diagnostics

        // Assert
        #expect(acknowledgement == .accepted(wake: .scheduleDrain))
        #expect(diagnostics.recoverySlotCount == 1)
        #expect(diagnostics.oldestRecoveryAge == .pressureConservative(.seconds(2)))
        #expect(diagnostics.admission.oldestPendingAge == .pressureConservative(.seconds(2)))
    }

    @Test("bulk invalidation inherits conservative semantic age precision")
    func bulkInvalidationInheritsConservativeSemanticAgePrecision() {
        // Arrange
        let clock = TestPushClock()
        let mailbox = makeMailbox(declaredKeys: [.alpha, .beta], limits: generousLimits, clock: clock)
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "oldest", items: 1, bytes: 1)
        )
        clock.advance(by: .seconds(1))
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .beta, label: "remaining", items: 1, bytes: 1)
        )
        let oldestLease = requireLease(consumer.takeDrain(binding: binding, generation: generation))
        _ = consumer.acknowledge(token: oldestLease.token, disposition: .transferred)
        clock.advance(by: .seconds(1))

        // Act
        let beforeInvalidation = mailbox.lifecyclePort.diagnostics
        let invalidation = mailbox.lifecyclePort.invalidate(generation: generation)
        let afterInvalidation = mailbox.lifecyclePort.diagnostics

        // Assert
        #expect(beforeInvalidation.admission.oldestPendingAge == .pressureConservative(.seconds(2)))
        #expect(invalidation == .applied)
        #expect(afterInvalidation.admission.oldestPendingAge == nil)
        #expect(afterInvalidation.oldestCleanupAge == .pressureConservative(.seconds(2)))
    }

    let generation = AdmissionGeneration(owner: .filesystemObservation, value: 41)

    var generousLimits: GatherMailboxLimits {
        GatherMailboxLimits(
            maximumDeclaredKeys: 8,
            maximumRetainedContributions: 16,
            maximumRetainedItems: 64,
            maximumRetainedBytes: 1024,
            maximumRetainedContributionsPerKey: 8,
            maximumRetainedItemsPerKey: 32,
            maximumRetainedBytesPerKey: 512,
            maximumContributionsPerLease: 8,
            maximumItemsPerLease: 32,
            maximumBytesPerLease: 512,
            cleanupQuantum: .entriesAndBytes(maximumEntries: 8, maximumBytes: 512)
        )
    }

    func makeMailbox(
        declaredKeys: Set<GatherTestKey>,
        limits: GatherMailboxLimits,
        clock: TestPushClock = TestPushClock()
    ) -> BoundedGatherMailbox<GatherTestKey, GatherTestPayload> {
        BoundedGatherMailbox(
            generation: generation,
            declaredKeys: declaredKeys,
            limits: limits,
            clock: clock
        )
    }

}

extension AdmissionBoundedGatherMailboxTests {
    @Test("selected-key offer never touches unrelated declared-key sentinels")
    func selectedKeyOfferHasFixedPerKeyOperationVectorAcrossDeclaredScale() throws {
        // Arrange / Act
        let outcomes = try [1, 100, 300, 301].map { declaredKeyCount in
            let probes = (0..<declaredKeyCount).map { _ in GatherHashProbe() }
            let keys = (0..<declaredKeyCount).map {
                GatherHashProbeKey(identifier: $0, probe: probes[$0])
            }
            let mailbox = BoundedGatherMailbox<GatherHashProbeKey, Int>(
                generation: generation,
                declaredKeys: Set(keys),
                limits: hashProbeLimits(
                    maximumDeclaredKeys: declaredKeyCount,
                    maximumContributions: 1
                )
            )
            for probe in probes {
                probe.reset()
            }
            let selectedKey = try #require(keys.last)

            let result = mailbox.producerPort.offer(
                generation: generation,
                contribution: GatherContribution(
                    key: selectedKey,
                    payload: 1,
                    footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                    recoverySignal: .ordinary
                )
            )

            expectRetainedWithoutRecovery(requireGenericAdmission(result))
            return GatherSelectedKeyScaleOutcome(
                declaredKeyCount: declaredKeyCount,
                selectedKeyOperationVector: probes[declaredKeyCount - 1].operationVector,
                unrelatedKeyOperationVectors: probes.dropLast().map(\.operationVector)
            )
        }

        // Assert
        #expect(outcomes.map(\.declaredKeyCount) == [1, 100, 300, 301])
        #expect(Set(outcomes.map(\.selectedKeyOperationVector)).count == 1)
        #expect(outcomes.allSatisfy { $0.selectedKeyOperationVector != .untouched })
        #expect(
            outcomes.allSatisfy {
                $0.unrelatedKeyOperationVectors.allSatisfy { $0.hashCount == 0 }
            }
        )
    }
}

private struct GatherSelectedKeyScaleOutcome {
    let declaredKeyCount: Int
    let selectedKeyOperationVector: GatherKeyOperationVector
    let unrelatedKeyOperationVectors: [GatherKeyOperationVector]
}

func contribution(
    key: GatherTestKey,
    label: String,
    items: Int,
    bytes: Int,
    recoverySignal: GatherRecoverySignal = .ordinary
) -> GatherContribution<GatherTestKey, GatherTestPayload> {
    GatherContribution(
        key: key,
        payload: GatherTestPayload(label: label),
        footprint: GatherFootprint(itemCount: items, byteCount: bytes),
        recoverySignal: recoverySignal
    )
}
