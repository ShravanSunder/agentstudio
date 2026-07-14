import Dispatch
import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation retirement fence")
struct FilesystemObservationRetirementFenceTests {
    @Test("observations precede the exact final retirement fence across lease quanta")
    func observationsPrecedeFinalRetirementFence() async throws {
        let fixture = try makeRetirementFenceFixture()
        let generation = try requireCreatedGeneration(fixture.creationResult)
        let acceptingNativeLifetime = try requireStartedLifetime(await generation.start())

        try admitObservation(eventID: 1, path: "/retirement/a", fixture: fixture)
        try admitObservation(eventID: 2, path: "/retirement/b", fixture: fixture)
        let receipt = try requireClosedReceipt(await generation.close())

        let request = fixture.mailbox.lifecyclePort.requestRetirementFence(receipt)
        let installedLifetime = try requireInstalledLifetime(request)
        let installedFence = installedLifetime.fence
        #expect(installedFence.binding == acceptingNativeLifetime.binding)
        #expect(installedFence.identity.isUUIDv7)
        #expect(fixture.controlBlock.acquireCallbackLease() == .closing)

        let consumer = fixture.mailbox.actorConsumerPort
        let binding = consumer.bindConsumer().binding
        let firstLease = requireLease(consumer.takeDrain(binding: binding))
        let secondLease: FilesystemObservationDrainLease
        let thirdLease: FilesystemObservationDrainLease

        #expect(contributionKind(in: firstLease) == .observation(eventID: 1))
        #expect(
            try credentialedTransferAcknowledgement(
                for: firstLease,
                consumerPort: consumer
            ) == .transferredAuthoritative(wake: .scheduleDrain)
        )
        secondLease = requireLease(consumer.takeDrain(binding: binding))
        #expect(contributionKind(in: secondLease) == .observation(eventID: 2))
        #expect(
            try credentialedTransferAcknowledgement(
                for: secondLease,
                consumerPort: consumer
            ) == .transferredAuthoritative(wake: .scheduleDrain)
        )
        thirdLease = requireLease(consumer.takeDrain(binding: binding))
        #expect(contributionKind(in: thirdLease) == .retirementFence(installedFence))
        #expect(
            contributions(in: thirdLease).last?.identity
                == installedLifetime.contributionIdentity
        )
    }

    @Test("a shared drain batch preserves observations before its exact final fence")
    func sharedBatchEndsWithExactRetirementFence() async throws {
        // Arrange
        let fixture = try makeRetirementFenceFixture(
            generationValue: 710,
            limits: sharedBatchLimits()
        )
        let generation = try requireCreatedGeneration(fixture.creationResult)
        _ = try requireStartedLifetime(await generation.start())
        try admitObservation(eventID: 40, path: "/retirement/shared-a", fixture: fixture)
        try admitObservation(eventID: 41, path: "/retirement/shared-b", fixture: fixture)
        let receipt = try requireClosedReceipt(await generation.close())
        let installedLifetime = try requireInstalledLifetime(
            fixture.mailbox.lifecyclePort.requestRetirementFence(receipt)
        )

        // Act
        let consumer = fixture.mailbox.actorConsumerPort
        let consumerBinding = consumer.bindConsumer().binding
        let lease = requireLease(consumer.takeDrain(binding: consumerBinding))
        let retainedContributions = contributions(in: lease)

        // Assert
        #expect(
            retainedContributions.map(contributionKind) == [
                .observation(eventID: 40),
                .observation(eventID: 41),
                .retirementFence(installedLifetime.fence),
            ]
        )
        #expect(retainedContributions.last?.identity == installedLifetime.contributionIdentity)
    }

    @Test("a repeated request preserves one contracted pending fence without retrying")
    func repeatedRequestDoesNotRetryContractedFence() async throws {
        // Arrange
        let fixture = try makeRetirementFenceFixture(
            generationValue: 702,
            limits: contractionLimits()
        )
        let generation = try requireCreatedGeneration(fixture.creationResult)
        _ = try requireStartedLifetime(await generation.start())
        try admitObservation(eventID: 10, path: "/retirement/contracted", fixture: fixture)
        let receipt = try requireClosedReceipt(await generation.close())
        let pendingLifetime = try requireContractedPendingFence(
            fixture.mailbox.lifecyclePort.requestRetirementFence(receipt)
        )
        let diagnosticsBeforeRepeatedRequest = fixture.mailbox.lifecyclePort.diagnostics

        // Act
        let repeatedRequest = fixture.mailbox.lifecyclePort.requestRetirementFence(receipt)
        let diagnosticsAfterRepeatedRequest = fixture.mailbox.lifecyclePort.diagnostics

        // Assert
        #expect(repeatedRequest == .alreadyPending(pendingLifetime))
        #expect(
            diagnosticsAfterRepeatedRequest.gather.admission.offered
                == diagnosticsBeforeRepeatedRequest.gather.admission.offered
        )
        #expect(
            diagnosticsAfterRepeatedRequest.recoveryEvidence(
                for: pendingLifetime.binding.physicalSlotID
            )
                == diagnosticsBeforeRepeatedRequest.recoveryEvidence(
                    for: pendingLifetime.binding.physicalSlotID
                )
        )
    }

    @Test("a foreign drain receipt is rejected without changing local custody")
    func foreignReceiptHasNoLocalSideEffects() async throws {
        // Arrange
        let localFixture = try makeRetirementFenceFixture(generationValue: 703)
        let foreignFixture = try makeRetirementFenceFixture(generationValue: 704)
        let localGeneration = try requireCreatedGeneration(localFixture.creationResult)
        let foreignGeneration = try requireCreatedGeneration(foreignFixture.creationResult)
        _ = try requireStartedLifetime(await localGeneration.start())
        _ = try requireStartedLifetime(await foreignGeneration.start())
        let foreignReceipt = try requireClosedReceipt(await foreignGeneration.close())
        let diagnosticsBeforeRequest = localFixture.mailbox.lifecyclePort.diagnostics
        let localSlotStateBeforeRequest = localFixture.mailbox.physicalSlotState(
            of: localFixture.startingNativeLifetime.binding.physicalSlotID
        )

        // Act
        let result = localFixture.mailbox.lifecyclePort.requestRetirementFence(foreignReceipt)

        // Assert
        #expect(result == .foreignFleet)
        #expect(
            localFixture.mailbox.physicalSlotState(
                of: localFixture.startingNativeLifetime.binding.physicalSlotID
            ) == localSlotStateBeforeRequest
        )
        #expect(
            localFixture.mailbox.lifecyclePort.diagnostics.gather.admission.offered
                == diagnosticsBeforeRequest.gather.admission.offered
        )

        _ = await localGeneration.close()
    }

    @Test("retiring lifecycle remains exact nonquiescent shutdown debt after fence transfer")
    func retiringLifecycleRemainsExactShutdownDebt() async throws {
        // Arrange
        let fixture = try makeRetirementFenceFixture(generationValue: 705)
        let generation = try requireCreatedGeneration(fixture.creationResult)
        _ = try requireStartedLifetime(await generation.start())
        let receipt = try requireClosedReceipt(await generation.close())
        let installedFence = try requireInstalledFence(
            fixture.mailbox.lifecyclePort.requestRetirementFence(receipt)
        )
        let consumer = fixture.mailbox.actorConsumerPort
        let consumerBinding = consumer.bindConsumer().binding
        let fenceLease = requireLease(consumer.takeDrain(binding: consumerBinding))
        #expect(
            try credentialedTransferAcknowledgement(
                for: fenceLease,
                consumerPort: consumer
            ) == .transferredAuthoritative(wake: .noWake)
        )
        let harness = try FilesystemObservationDrainHarnessActor(
            mailbox: fixture.mailbox,
            bindings: [fixture.startingNativeLifetime.binding],
            maximumContributionsPerLease: 1
        )
        let lifecycle = FilesystemObservationFleetLifecycle()
        _ = requireAppliedShutdownDebtSnapshot(
            lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )

        // Act
        let capturedDebt = await lifecycle.shutdownDebtSnapshot(
            mailbox: fixture.mailbox,
            drainPort: await harness.fleetShutdownDrainPort
        )

        // Assert
        guard case .captured(let snapshot, let turnPlan) = capturedDebt,
            let slot = snapshot.mailbox.slots.first,
            case .retiredAwaitingContextRelease(let retirement, .oldest) =
                slot.registry.lifecycle,
            case .fenceBacked(let fenceIdentity, _, _) = retirement.disposition
        else {
            Issue.record("Completed retirement was not retained as exact context-release debt")
            return
        }
        #expect(retirement.native.binding == fixture.startingNativeLifetime.binding)
        #expect(fenceIdentity == installedFence.identity)
        #expect(!slot.isQuiescent)
        #expect(!snapshot.mailbox.isQuiescent)
        #expect(!snapshot.isQuiescent)
        #expect(turnPlan == .advanceMailbox)
    }

    @Test("a contracted fence retries only after cleanup becomes quiescent")
    func contractedFenceWaitsForCleanupBeforeRetry() async throws {
        // Arrange
        let fixture = try makeRetirementFenceFixture(
            generationValue: 706,
            limits: contractionLimits()
        )
        let generation = try requireCreatedGeneration(fixture.creationResult)
        _ = try requireStartedLifetime(await generation.start())
        try admitObservation(eventID: 20, path: "/retirement/cleanup", fixture: fixture)
        let receipt = try requireClosedReceipt(await generation.close())
        let pendingLifetime = try requireContractedPendingFence(
            fixture.mailbox.lifecyclePort.requestRetirementFence(receipt)
        )
        let offeredAfterContraction = fixture.mailbox.lifecyclePort.diagnostics.gather.admission
            .offered
        let consumer = fixture.mailbox.actorConsumerPort
        let consumerBinding = consumer.bindConsumer().binding
        let invalidToken = makeInvalidDrainToken(generation: fixture.generation)

        // Act / Assert: neither an invalid acknowledgement nor queued cleanup retries the fence.
        #expect(
            consumer.acknowledge(token: invalidToken, disposition: .retry)
                == .invalidToken
        )
        #expect(
            fixture.mailbox.lifecyclePort.diagnostics.gather.admission.offered
                == offeredAfterContraction
        )
        let fenceLease = try drainCleanupUntilFenceLease(
            consumer: consumer,
            consumerBinding: consumerBinding,
            mailbox: fixture.mailbox,
            offeredAfterContraction: offeredAfterContraction
        )

        // Assert: the first post-cleanup semantic lease contains the exact pending fence and repair.
        #expect(contributionKind(in: fenceLease) == .retirementFence(pendingLifetime.fence))
        let recovery = requireRecovery(fenceLease)
        #expect(recovery.evidence.contains(.retirementFenceAdmissionContraction))
        #expect(
            fixture.mailbox.lifecyclePort.diagnostics.gather.admission.offered
                == offeredAfterContraction + 1
        )
    }

    @Test("ordinary contraction progress does not require a retirement fence")
    func ordinaryContractionProgressWithoutRetirementFence() async throws {
        // Arrange
        let fixture = try makeRetirementFenceFixture(
            generationValue: 709,
            limits: ordinaryContractionLimits()
        )
        let generation = try requireCreatedGeneration(fixture.creationResult)
        _ = try requireStartedLifetime(await generation.start())
        try admitObservation(eventID: 30, path: "/retirement/ordinary-a", fixture: fixture)
        try admitObservation(eventID: 31, path: "/retirement/ordinary-b", fixture: fixture)
        _ = requireContractedRecovery(
            try captureObservation(
                eventID: 32,
                path: "/retirement/ordinary-c",
                fixture: fixture
            )
        )
        let offeredBeforeProgress = fixture.mailbox.lifecyclePort.diagnostics.gather.admission
            .offered
        let consumer = fixture.mailbox.actorConsumerPort
        let consumerBinding = consumer.bindConsumer().binding

        // Act: cleanup and acknowledgement are both ordinary progress turns with no fence queue.
        guard case .performed = consumer.performCleanup() else {
            throw RetirementFenceTestFailure.cleanupDidNotAdvance
        }
        guard case .performed = consumer.performCleanup() else {
            throw RetirementFenceTestFailure.cleanupDidNotAdvance
        }
        let observationLease = requireLease(consumer.takeDrain(binding: consumerBinding))
        var sourceGate = FilesystemSourceGate(binding: observationLease.binding)
        let acknowledgement = try credentialedTransferAcknowledgement(
            for: observationLease,
            consumerPort: consumer,
            sourceGate: &sourceGate,
            recoveryContext: requiredRecoveryAdmissionContext()
        )

        // Assert
        guard case .transferredRecovery = acknowledgement else {
            throw RetirementFenceTestFailure.progressDidNotAdvance
        }
        #expect(
            fixture.mailbox.lifecyclePort.diagnostics.gather.admission.offered
                == offeredBeforeProgress
        )

        _ = await generation.close()
    }

    @Test("a successor retirement fence waits for its installed predecessor")
    func successorRetirementFenceAwaitsInstalledPredecessor() async throws {
        // Arrange: N+1 becomes configuration-current while N still accepts callbacks.
        let fixture = try makeRetirementFenceFixture(
            generationValue: 707,
            replacementReserveSlotCount: 1
        )
        let generationN = try requireCreatedGeneration(fixture.creationResult)
        _ = try requireStartedLifetime(await generationN.start())
        let registrationNPlusOne = makeRegistration(registrationGeneration: 708)
        _ = fixture.mailbox.installTestConfiguration(registrationNPlusOne)
        let receiptN = try requireClosedReceipt(await generationN.close())

        // Act: installing N's fence promotes N+1 into the replacement reserve slot.
        let installedN = try requireInstalledLifetime(
            fixture.mailbox.lifecyclePort.requestRetirementFence(receiptN)
        )
        let generationNPlusOne = try await makeAndStartNextGeneration(
            mailbox: fixture.mailbox,
            captureLimits: fixture.captureLimits
        )
        let acceptingNPlusOne = generationNPlusOne.acceptingNativeLifetime
        #expect(acceptingNPlusOne.binding.registration == registrationNPlusOne)
        #expect(
            acceptingNPlusOne.binding.physicalSlotID
                != installedN.binding.physicalSlotID
        )
        #expect(
            fixture.mailbox.physicalSlotState(of: installedN.binding.physicalSlotID)
                == .retirementFenceInstalled(installedN)
        )

        let receiptNPlusOne = try requireClosedReceipt(
            await generationNPlusOne.generation.close()
        )
        let offeredBeforeSuccessorRequest = fixture.mailbox.lifecyclePort.diagnostics.gather
            .admission.offered
        let successorRequest = fixture.mailbox.lifecyclePort.requestRetirementFence(
            receiptNPlusOne
        )

        // Assert: N+1 contributes no fence until N leaves the generalized retirement chain.
        let awaitingNPlusOne = try requireAwaitingPredecessor(successorRequest)
        #expect(awaitingNPlusOne.binding == acceptingNPlusOne.binding)
        #expect(
            fixture.mailbox.lifecyclePort.diagnostics.gather.admission.offered
                == offeredBeforeSuccessorRequest
        )
        #expect(
            fixture.mailbox.physicalSlotState(of: installedN.binding.physicalSlotID)
                == .retirementFenceInstalled(installedN)
        )
        #expect(
            fixture.mailbox.physicalSlotState(of: awaitingNPlusOne.binding.physicalSlotID)
                == .closingAwaitingPredecessor(awaitingNPlusOne)
        )
        #expect(
            fixture.mailbox.lifecyclePort.requestRetirementFence(receiptN)
                == .alreadyInstalled(installedN)
        )
        #expect(
            fixture.mailbox.lifecyclePort.requestRetirementFence(receiptNPlusOne)
                == .alreadyAwaitingPredecessor(awaitingNPlusOne)
        )
        #expect(
            fixture.mailbox.lifecyclePort.diagnostics.gather.admission.offered
                == offeredBeforeSuccessorRequest
        )
    }

    @Test("contracted retirement fences rotate one queue head per progress turn")
    func contractedRetirementFencesRotateAcrossSources() async throws {
        // Arrange: A and B are empty retiring sources; C permanently occupies capacity.
        let mailbox = try FilesystemObservationMailbox(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 711),
            maximumSimultaneousSourceCount: 3,
            replacementReserveSlotCount: 0,
            limits: multiSourceContractionLimits()
        )
        let captureLimits = try makeCaptureLimits()
        let registrationA = makeDistinctRegistration(sourceOrdinal: 1, generation: 711)
        let registrationB = makeDistinctRegistration(sourceOrdinal: 2, generation: 711)
        let registrationC = makeDistinctRegistration(sourceOrdinal: 3, generation: 711)
        let generationA = try await recordAndStartGeneration(
            registrationA,
            mailbox: mailbox,
            captureLimits: captureLimits
        )
        let generationB = try await recordAndStartGeneration(
            registrationB,
            mailbox: mailbox,
            captureLimits: captureLimits
        )
        let generationC = try await recordAndStartGeneration(
            registrationC,
            mailbox: mailbox,
            captureLimits: captureLimits
        )
        expectRetainedCallback(
            try captureObservation(
                eventID: 50,
                path: "/retirement/capacity-blocker",
                registration: registrationC,
                controlBlock: generationC.controlBlock,
                callbackAdmissionPort: generationC.callbackAdmissionPort,
                captureLimits: captureLimits
            )
        )
        let receiptA = try requireClosedReceipt(await generationA.generation.close())
        let receiptB = try requireClosedReceipt(await generationB.generation.close())
        let pendingA = try requireContractedPendingFence(
            mailbox.lifecyclePort.requestRetirementFence(receiptA)
        )
        let pendingB = try requirePendingFence(
            mailbox.lifecyclePort.requestRetirementFence(receiptB)
        )
        let consumer = mailbox.actorConsumerPort
        let consumerBinding = consumer.bindConsumer().binding

        // First progress contracts B, so both independent source fences now carry evidence.
        try retryOneLease(consumer: consumer, binding: consumerBinding)
        let recoveryAAfterSeeding = try requireRetainedRecovery(
            mailbox.lifecyclePort.diagnostics.recoveryEvidence(
                for: pendingA.binding.physicalSlotID
            )
        )
        let recoveryBAfterSeeding = try requireRetainedRecovery(
            mailbox.lifecyclePort.diagnostics.recoveryEvidence(
                for: pendingB.binding.physicalSlotID
            )
        )
        #expect(recoveryAAfterSeeding.evidence.contains(.retirementFenceAdmissionContraction))
        #expect(recoveryBAfterSeeding.evidence.contains(.retirementFenceAdmissionContraction))

        // Act: each successful acknowledgement attempts exactly one queue head.
        let offeredBeforeA = mailbox.lifecyclePort.diagnostics.gather.admission.offered
        try retryOneLease(consumer: consumer, binding: consumerBinding)
        let recoveryAAfterA = try requireRetainedRecovery(
            mailbox.lifecyclePort.diagnostics.recoveryEvidence(
                for: pendingA.binding.physicalSlotID
            )
        )
        let recoveryBAfterA = try requireRetainedRecovery(
            mailbox.lifecyclePort.diagnostics.recoveryEvidence(
                for: pendingB.binding.physicalSlotID
            )
        )

        // Assert: A advanced, B did not; the next progress turn rotates to B.
        #expect(mailbox.lifecyclePort.diagnostics.gather.admission.offered == offeredBeforeA + 1)
        #expect(recoveryAAfterA != recoveryAAfterSeeding)
        #expect(recoveryBAfterA == recoveryBAfterSeeding)
        let offeredBeforeB = mailbox.lifecyclePort.diagnostics.gather.admission.offered
        try retryOneLease(consumer: consumer, binding: consumerBinding)
        let recoveryAAfterB = try requireRetainedRecovery(
            mailbox.lifecyclePort.diagnostics.recoveryEvidence(
                for: pendingA.binding.physicalSlotID
            )
        )
        let recoveryBAfterB = try requireRetainedRecovery(
            mailbox.lifecyclePort.diagnostics.recoveryEvidence(
                for: pendingB.binding.physicalSlotID
            )
        )
        #expect(mailbox.lifecyclePort.diagnostics.gather.admission.offered == offeredBeforeB + 1)
        #expect(recoveryAAfterB == recoveryAAfterA)
        #expect(recoveryBAfterB != recoveryBAfterA)
        #expect(
            mailbox.physicalSlotState(of: pendingA.binding.physicalSlotID)
                == .retirementFencePending(pendingA)
        )
        #expect(
            mailbox.physicalSlotState(of: pendingB.binding.physicalSlotID)
                == .retirementFencePending(pendingB)
        )

        _ = await generationC.generation.close()
    }

}

extension FilesystemObservationRetirementFenceTests {
    fileprivate enum ContributionKind: Equatable {
        case observation(eventID: FSEventStreamEventId)
        case retirementFence(FilesystemObservationSlotRetirementFence)
    }

    private struct RetirementFenceFixture {
        let generation: AdmissionGeneration
        let mailbox: FilesystemObservationMailbox
        let registration: FSEventRegistrationToken
        let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
        let controlBlock: FSEventRegistrationControlBlock
        let callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort
        let captureLimits: FSEventCaptureLimits
        let creationResult: DarwinFSEventNativeOwnerCreationResult
    }

    private struct StartedGeneration {
        let generation: DarwinFSEventRegistrationGeneration
        let acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
        let controlBlock: FSEventRegistrationControlBlock
        let callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort
    }

    private func makeRetirementFenceFixture(
        generationValue: UInt64 = 701,
        replacementReserveSlotCount: Int = 0,
        limits: GatherMailboxLimits? = nil
    ) throws -> RetirementFenceFixture {
        let generation = AdmissionGeneration(
            owner: .filesystemObservation,
            value: generationValue
        )
        let registration = makeRegistration(registrationGeneration: generationValue)
        let captureLimits = try makeCaptureLimits()
        let mailbox = try FilesystemObservationMailbox(
            generation: generation,
            maximumSimultaneousSourceCount: 1,
            replacementReserveSlotCount: replacementReserveSlotCount,
            limits: limits
                ?? GatherMailboxLimits(
                    maximumDeclaredKeys: 1 + replacementReserveSlotCount,
                    maximumRetainedContributions: 8,
                    maximumRetainedItems: 8,
                    maximumRetainedBytes: 65_536,
                    maximumRetainedContributionsPerKey: 8,
                    maximumRetainedItemsPerKey: 8,
                    maximumRetainedBytesPerKey: 65_536,
                    maximumContributionsPerLease: 1,
                    maximumItemsPerLease: 8,
                    maximumBytesPerLease: 65_536,
                    cleanupQuantum: .entriesAndBytes(maximumEntries: 8, maximumBytes: 65_536)
                )
        )
        _ = mailbox.installTestConfiguration(registration)
        guard case .selected(let selection) = mailbox.selectNextDesiredSource(),
            case .committed(let startingNativeLifetime) = mailbox.beginNativeLifetime(
                selection.reservation
            ),
            case .created(let nativeGenerationPorts) = mailbox.nativeGenerationPorts(
                for: startingNativeLifetime
            )
        else {
            throw RetirementFenceTestFailure.fixtureConstructionFailed
        }
        let controlBlock = try makeControlBlock(
            startingNativeLifetime: startingNativeLifetime,
            captureLimits: captureLimits,
            callbackQueueLabel: "test.filesystem-observation-retirement-fence"
        )
        let adapter = RetirementFenceCallbackAdapter(
            controlBlock: controlBlock,
            callbackAdmissionPort: nativeGenerationPorts.callbackAdmissionPort
        )
        let creationResult = nativeGenerationPorts.nativeOwner.createOrReplay(
            controlBlock: controlBlock,
            adapter: adapter,
            nativeDriver: RetirementFenceNativeDriver(),
            callbackQueueBarrier: RetirementFenceCallbackQueueBarrier()
        )
        return RetirementFenceFixture(
            generation: generation,
            mailbox: mailbox,
            registration: registration,
            startingNativeLifetime: startingNativeLifetime,
            controlBlock: controlBlock,
            callbackAdmissionPort: nativeGenerationPorts.callbackAdmissionPort,
            captureLimits: captureLimits,
            creationResult: creationResult
        )
    }

    private func makeAndStartNextGeneration(
        mailbox: FilesystemObservationMailbox,
        captureLimits: FSEventCaptureLimits
    ) async throws -> StartedGeneration {
        guard case .selected(let selection) = mailbox.selectNextDesiredSource(),
            case .committed(let startingNativeLifetime) = mailbox.beginNativeLifetime(
                selection.reservation
            ),
            case .created(let nativeGenerationPorts) = mailbox.nativeGenerationPorts(
                for: startingNativeLifetime
            )
        else {
            throw RetirementFenceTestFailure.fixtureConstructionFailed
        }
        let controlBlock = try makeControlBlock(
            startingNativeLifetime: startingNativeLifetime,
            captureLimits: captureLimits,
            callbackQueueLabel: "test.filesystem-observation-retirement-fence.successor"
        )
        let adapter = RetirementFenceCallbackAdapter(
            controlBlock: controlBlock,
            callbackAdmissionPort: nativeGenerationPorts.callbackAdmissionPort
        )
        let generation = try requireCreatedGeneration(
            nativeGenerationPorts.nativeOwner.createOrReplay(
                controlBlock: controlBlock,
                adapter: adapter,
                nativeDriver: RetirementFenceNativeDriver(),
                callbackQueueBarrier: RetirementFenceCallbackQueueBarrier()
            )
        )
        let acceptingNativeLifetime = try requireStartedLifetime(await generation.start())
        return StartedGeneration(
            generation: generation,
            acceptingNativeLifetime: acceptingNativeLifetime,
            controlBlock: controlBlock,
            callbackAdmissionPort: nativeGenerationPorts.callbackAdmissionPort
        )
    }

    private func recordAndStartGeneration(
        _ registration: FSEventRegistrationToken,
        mailbox: FilesystemObservationMailbox,
        captureLimits: FSEventCaptureLimits
    ) async throws -> StartedGeneration {
        guard case .enqueued = mailbox.installTestConfiguration(registration) else {
            throw RetirementFenceTestFailure.fixtureConstructionFailed
        }
        let startedGeneration = try await makeAndStartNextGeneration(
            mailbox: mailbox,
            captureLimits: captureLimits
        )
        guard startedGeneration.acceptingNativeLifetime.binding.registration == registration else {
            throw RetirementFenceTestFailure.fixtureConstructionFailed
        }
        return startedGeneration
    }

    private func contractionLimits() -> GatherMailboxLimits {
        GatherMailboxLimits(
            maximumDeclaredKeys: 1,
            maximumRetainedContributions: 1,
            maximumRetainedItems: 8,
            maximumRetainedBytes: 65_536,
            maximumRetainedContributionsPerKey: 1,
            maximumRetainedItemsPerKey: 8,
            maximumRetainedBytesPerKey: 65_536,
            maximumContributionsPerLease: 1,
            maximumItemsPerLease: 8,
            maximumBytesPerLease: 65_536,
            cleanupQuantum: .entriesAndBytes(maximumEntries: 1, maximumBytes: 65_536)
        )
    }

    private func ordinaryContractionLimits() -> GatherMailboxLimits {
        GatherMailboxLimits(
            maximumDeclaredKeys: 1,
            maximumRetainedContributions: 2,
            maximumRetainedItems: 16,
            maximumRetainedBytes: 65_536,
            maximumRetainedContributionsPerKey: 2,
            maximumRetainedItemsPerKey: 16,
            maximumRetainedBytesPerKey: 65_536,
            maximumContributionsPerLease: 2,
            maximumItemsPerLease: 16,
            maximumBytesPerLease: 65_536,
            cleanupQuantum: .entriesAndBytes(maximumEntries: 1, maximumBytes: 65_536)
        )
    }

    private func sharedBatchLimits() -> GatherMailboxLimits {
        GatherMailboxLimits(
            maximumDeclaredKeys: 1,
            maximumRetainedContributions: 8,
            maximumRetainedItems: 8,
            maximumRetainedBytes: 65_536,
            maximumRetainedContributionsPerKey: 8,
            maximumRetainedItemsPerKey: 8,
            maximumRetainedBytesPerKey: 65_536,
            maximumContributionsPerLease: 3,
            maximumItemsPerLease: 8,
            maximumBytesPerLease: 65_536,
            cleanupQuantum: .entriesAndBytes(maximumEntries: 8, maximumBytes: 65_536)
        )
    }

    private func multiSourceContractionLimits() -> GatherMailboxLimits {
        GatherMailboxLimits(
            maximumDeclaredKeys: 3,
            maximumRetainedContributions: 1,
            maximumRetainedItems: 8,
            maximumRetainedBytes: 65_536,
            maximumRetainedContributionsPerKey: 1,
            maximumRetainedItemsPerKey: 8,
            maximumRetainedBytesPerKey: 65_536,
            maximumContributionsPerLease: 1,
            maximumItemsPerLease: 8,
            maximumBytesPerLease: 65_536,
            cleanupQuantum: .entriesAndBytes(maximumEntries: 1, maximumBytes: 65_536)
        )
    }

    private func makeDistinctRegistration(
        sourceOrdinal: Int,
        generation: UInt64
    ) -> FSEventRegistrationToken {
        FSEventRegistrationToken(
            sourceID: FilesystemSourceID(
                kind: .registeredWorktreeContent,
                rootID: UUID(
                    uuidString: String(
                        format: "00000000-0000-0000-0000-%012d",
                        sourceOrdinal
                    )
                )!
            ),
            registrationGeneration: generation,
            rootGeneration: generation
        )
    }

    private func admitObservation(
        eventID: FSEventStreamEventId,
        path: String,
        fixture: RetirementFenceFixture
    ) throws {
        expectRetainedCallback(
            try captureObservation(eventID: eventID, path: path, fixture: fixture)
        )
    }

    private func captureObservation(
        eventID: FSEventStreamEventId,
        path: String,
        fixture: RetirementFenceFixture
    ) throws -> DarwinFSEventObservationCaptureResult {
        try captureObservation(
            eventID: eventID,
            path: path,
            registration: fixture.registration,
            controlBlock: fixture.controlBlock,
            callbackAdmissionPort: fixture.callbackAdmissionPort,
            captureLimits: fixture.captureLimits
        )
    }

    private func captureObservation(
        eventID: FSEventStreamEventId,
        path: String,
        registration: FSEventRegistrationToken,
        controlBlock: FSEventRegistrationControlBlock,
        callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort,
        captureLimits: FSEventCaptureLimits
    ) throws -> DarwinFSEventObservationCaptureResult {
        guard case .acquired(let lease) = controlBlock.acquireCallbackLease() else {
            throw RetirementFenceTestFailure.callbackLeaseUnavailable
        }
        defer { _ = lease.release() }
        let observation = try makeObservation(
            registration: registration,
            path: path,
            eventID: eventID
        )
        return callbackAdmissionPort.admit(
            using: lease,
            preflight: FilesystemObservationCallbackPreflight(
                captureLimits: captureLimits
            )
        ) {
            .offer(.authoritative(observation))
        }
    }

    private func retryOneLease(
        consumer: FilesystemObservationActorConsumerPort,
        binding: AdmissionConsumerBinding
    ) throws {
        let lease = requireLease(consumer.takeDrain(binding: binding))
        guard case .retried = consumer.acknowledge(token: lease.token, disposition: .retry) else {
            throw RetirementFenceTestFailure.progressDidNotAdvance
        }
    }

    private func contributionKind(
        in lease: FilesystemObservationDrainLease
    ) -> ContributionKind {
        let retainedContributions = contributions(in: lease)
        #expect(retainedContributions.count == 1)
        return contributionKind(retainedContributions[0])
    }

    private func contributions(
        in lease: FilesystemObservationDrainLease
    ) -> [FilesystemObservationMailboxContribution] {
        switch lease.payload {
        case .contributions(let batch), .contributionsWithRecovery(let batch, _):
            return [batch.first] + batch.remaining
        case .recovery:
            preconditionFailure("retirement FIFO test requires a contribution lease")
        }
    }

    private func contributionKind(
        _ contribution: FilesystemObservationMailboxContribution
    ) -> ContributionKind {
        switch contribution {
        case .observation(_, let observation):
            guard let eventID = observation.records.first?.eventID else {
                preconditionFailure("test observation must contain one event ID")
            }
            return .observation(eventID: eventID)
        case .retirementFence(_, let fence):
            return .retirementFence(fence)
        }
    }

    private func requireCreatedGeneration(
        _ result: DarwinFSEventNativeOwnerCreationResult
    ) throws -> DarwinFSEventRegistrationGeneration {
        guard case .created(let generation) = result else {
            throw RetirementFenceTestFailure.fixtureConstructionFailed
        }
        return generation
    }

    private func requireStartedLifetime(
        _ result: DarwinFSEventRegistrationGenerationStartResult
    ) throws -> FilesystemObservationAcceptingNativeLifetime {
        guard case .started(let acceptingNativeLifetime) = result else {
            throw RetirementFenceTestFailure.nativeStartFailed
        }
        return acceptingNativeLifetime
    }

    private func requireClosedReceipt(
        _ result: DarwinFSEventRegistrationGenerationCloseResult
    ) throws -> DarwinFSEventRegistrationLeaseDrainReceipt {
        guard case .closed(let receipt) = result else {
            throw RetirementFenceTestFailure.nativeCloseFailed
        }
        return receipt
    }

    private func requireInstalledFence(
        _ result: FilesystemObservationRetirementFenceRequestResult
    ) throws -> FilesystemObservationSlotRetirementFence {
        try requireInstalledLifetime(result).fence
    }

    private func requireInstalledLifetime(
        _ result: FilesystemObservationRetirementFenceRequestResult
    ) throws -> FilesystemRetirementFenceInstalledLifetime {
        guard case .installed(let installedLifetime) = result else {
            throw RetirementFenceTestFailure.fenceWasNotInstalled
        }
        return installedLifetime
    }

    private func requireAwaitingPredecessor(
        _ result: FilesystemObservationRetirementFenceRequestResult
    ) throws -> FilesystemClosingAwaitingPredecessorLifetime {
        guard case .awaitingPredecessor(let awaitingLifetime) = result else {
            throw RetirementFenceTestFailure.successorDidNotAwaitPredecessor
        }
        return awaitingLifetime
    }

    private func requireContractedPendingFence(
        _ result: FilesystemObservationRetirementFenceRequestResult
    ) throws -> FilesystemRetirementFencePendingLifetime {
        guard case .pendingAfterContraction(let pendingLifetime, let recovery) = result else {
            throw RetirementFenceTestFailure.fenceWasNotContracted
        }
        #expect(recovery.evidence.contains(.retirementFenceAdmissionContraction))
        return pendingLifetime
    }

    private func requirePendingFence(
        _ result: FilesystemObservationRetirementFenceRequestResult
    ) throws -> FilesystemRetirementFencePendingLifetime {
        guard case .pending(let pendingLifetime) = result else {
            throw RetirementFenceTestFailure.fenceWasNotPending
        }
        return pendingLifetime
    }

    private func requireRetainedRecovery(
        _ result: FixedFilesystemRecoveryEvidenceSnapshotResult
    ) throws -> FixedFilesystemRecoveryEvidenceSnapshot {
        guard case .retained(let recovery) = result else {
            throw RetirementFenceTestFailure.recoveryWasNotRetained
        }
        return recovery
    }

    private func makeInvalidDrainToken(
        generation: AdmissionGeneration
    ) -> AdmissionDrainToken {
        AdmissionDrainToken(
            generation: generation,
            mailboxIdentity: AdmissionOpaqueIdentity(),
            bindingEpoch: AdmissionOpaqueIdentity(),
            bindingSequence: 1,
            leaseEpoch: AdmissionOpaqueIdentity(),
            leaseSequence: 1
        )
    }

    private func drainCleanupUntilFenceLease(
        consumer: FilesystemObservationActorConsumerPort,
        consumerBinding: AdmissionConsumerBinding,
        mailbox: FilesystemObservationMailbox,
        offeredAfterContraction: UInt64
    ) throws -> FilesystemObservationDrainLease {
        for _ in 0..<4 {
            switch consumer.takeDrain(binding: consumerBinding) {
            case .cleanupRequired:
                guard case .performed = consumer.performCleanup() else {
                    throw RetirementFenceTestFailure.cleanupDidNotAdvance
                }
                let diagnostics = mailbox.lifecyclePort.diagnostics.gather
                if diagnostics.cleanupContributionCount > 0
                    || diagnostics.cleanupMetadataEntryCount > 0
                    || diagnostics.outstandingCleanupTurnCount > 0
                {
                    #expect(diagnostics.admission.offered == offeredAfterContraction)
                }
            case .lease(let lease):
                return lease
            case .empty, .alreadyLeased, .closed:
                throw RetirementFenceTestFailure.fenceLeaseUnavailable
            }
        }
        throw RetirementFenceTestFailure.cleanupDidNotQuiesce
    }
}

private enum RetirementFenceTestFailure: Error {
    case fixtureConstructionFailed
    case callbackLeaseUnavailable
    case nativeStartFailed
    case nativeCloseFailed
    case fenceWasNotInstalled
    case successorDidNotAwaitPredecessor
    case fenceWasNotContracted
    case fenceWasNotPending
    case recoveryWasNotRetained
    case cleanupDidNotAdvance
    case cleanupDidNotQuiesce
    case fenceLeaseUnavailable
    case progressDidNotAdvance
}

private final class RetirementFenceCallbackAdapter:
    DarwinFSEventRegistrationCallbackAdapter,
    @unchecked Sendable
{
    let controlBlock: FSEventRegistrationControlBlock
    let callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort

    init(
        controlBlock: FSEventRegistrationControlBlock,
        callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort
    ) {
        self.controlBlock = controlBlock
        self.callbackAdmissionPort = callbackAdmissionPort
    }

    func capture(
        input _: DarwinFSEventNativeCallbackInput
    ) -> DarwinFSEventObservationCaptureResult {
        .ignoredEmptyCallback
    }
}

private struct RetirementFenceNativeDriver: DarwinFSEventNativeDriver {
    func createStream(
        request _: DarwinFSEventNativeStreamCreationRequest
    ) -> Result<DarwinFSEventNativeStreamHandle, DarwinFSEventNativeStreamCreationFailure> {
        .success(.testHandle())
    }

    func startStream(_: DarwinFSEventNativeStreamHandle) -> Bool { true }
    func stopStream(_: DarwinFSEventNativeStreamHandle) {}
    func invalidateStream(_: DarwinFSEventNativeStreamHandle) {}
    func releaseStream(_: DarwinFSEventNativeStreamHandle) {}
}

private struct RetirementFenceCallbackQueueBarrier: DarwinFSEventCallbackQueueBarrier {
    func waitForBarrier(on _: DispatchQueue) async {}
}
