import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation whole lease transfer")
struct FilesystemObservationLeaseTransferTests {
    @Test("ordinary custody rejection retries before any generic transfer")
    func ordinaryCustodyRejectionRetriesBeforeTransfer() async throws {
        // Arrange
        let fixture = try makeOrdinaryFixture(generation: 810)
        let harness = try FilesystemObservationDrainHarnessActor(
            mailbox: fixture.mailbox,
            bindings: [fixture.binding],
            maximumContributionsPerLease: 3
        )
        let firstLease = try await requireLease(from: harness)
        let identity = try #require(contributions(in: firstLease).first?.identity)
        await harness.requestSemanticRetry(before: identity)

        // Act
        let firstResult = await harness.transferLease(
            firstLease,
            recoveryContext: .notRequired
        )

        // Assert
        guard case .completed(.retried) = firstResult else {
            Issue.record("Semantic rejection must retry the complete generic lease")
            return
        }
        #expect(await harness.semanticAcceptanceCount(for: identity) == 0)

        await harness.rebindConsumer()
        let retriedLease = try await requireLease(from: harness)
        #expect(contributions(in: retriedLease).map(\.identity) == [identity])
        let exactResult = await harness.transferLease(
            retriedLease,
            recoveryContext: .notRequired
        )
        let receipt = try requireTransferredReceipt(exactResult)
        #expect(receipt.binding == fixture.binding)
        guard case .ordinaryLease = receipt.outcome else {
            Issue.record("An ordinary lease cannot mint a retirement receipt")
            return
        }
        #expect(await harness.semanticAcceptanceCount(for: identity) == 1)
    }

    @Test("contribution and recovery lease requires both semantic and SourceGate acceptance")
    func contributionAndRecoveryRequiresBothAuthorities() async throws {
        // Arrange
        let registration = makeRegistration(registrationGeneration: 811)
        let fixture = try makeFixedSlotMailboxFixture(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 811),
            registrations: [registration],
            limits: leaseTransferMailboxLimits(),
            captureLimits: makeCaptureLimits(),
            callbackQueueLabel: "test.filesystem-observation-transfer-recovery"
        )
        _ = try fixture.admitCallback(
            .requiresRecovery(
                makeObservation(
                    registration: registration,
                    path: "/transfer/recovery",
                    eventID: 1
                ),
                evidence: .continuityLoss
            )
        )
        let harness = try FilesystemObservationDrainHarnessActor(
            mailbox: fixture.mailbox,
            bindings: [fixture.binding],
            maximumContributionsPerLease: 3
        )
        let firstLease = try await requireLease(from: harness)

        // Act: omit the required recovery context.
        let missingAuthorityResult = await harness.transferLease(
            firstLease,
            recoveryContext: .notRequired
        )

        // Assert
        guard case .completed(.rejected) = missingAuthorityResult else {
            Issue.record("Recovery-bearing transfer must reject missing SourceGate context")
            return
        }
        await harness.rebindConsumer()
        let retriedLease = try await requireLease(from: harness)
        let exactResult = await harness.transferLease(
            retriedLease,
            recoveryContext: requiredRecoveryContext()
        )
        let receipt = try requireTransferredReceipt(exactResult)
        #expect(receipt.binding == fixture.binding)
        guard case .ordinaryLease = receipt.outcome else {
            Issue.record("Recovery without a terminal fence remains an ordinary transfer")
            return
        }
    }

    @Test("wrong ACK retains contribution and recovery replay for exact retry")
    func wrongAcknowledgementRetainsContributionAndRecoveryReplay() async throws {
        // Arrange
        let registration = makeRegistration(registrationGeneration: 816)
        let fixture = try makeFixedSlotMailboxFixture(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 816),
            registrations: [registration],
            limits: leaseTransferMailboxLimits(),
            captureLimits: makeCaptureLimits(),
            callbackQueueLabel: "test.filesystem-observation-transfer-recovery-ack-retry"
        )
        _ = try fixture.admitCallback(
            .requiresRecovery(
                makeObservation(
                    registration: registration,
                    path: "/transfer/recovery-ack-retry",
                    eventID: 1
                ),
                evidence: .continuityLoss
            )
        )
        let harness = try FilesystemObservationDrainHarnessActor(
            mailbox: fixture.mailbox,
            bindings: [fixture.binding],
            maximumContributionsPerLease: 3
        )
        let lease = try await requireLease(from: harness)
        let identity = try #require(contributions(in: lease).first?.identity)
        let recoveryContext = requiredRecoveryContext()
        await harness.rejectNextAcknowledgement()

        // Act: semantic and SourceGate admission succeed, but generic ACK does not.
        let rejectedResult = await harness.transferLease(
            lease,
            recoveryContext: recoveryContext
        )

        // Assert: both replay shells remain and semantic effects occurred exactly once.
        guard case .completed(.rejected(.genericAcknowledgement)) = rejectedResult else {
            Issue.record("Wrong generic ACK must reject before either replay shell clears")
            return
        }
        #expect(await harness.semanticAcceptanceCount(for: identity) == 1)
        let retainedDiagnostics = await harness.transferDiagnostics
        #expect(retainedDiagnostics.semanticReplay.retainedLeaseCount == 1)
        #expect(retainedDiagnostics.semanticReplay.retainedIdentityCount == 1)
        guard
            case .state(.dirty(let retainedRepairGeneration)) = await harness.sourceGateState(
                for: fixture.binding
            )
        else {
            Issue.record("Failed ACK must retain the exact SourceGate repair generation")
            return
        }

        let receipt = try requireTransferredReceipt(
            await harness.transferLease(lease, recoveryContext: recoveryContext)
        )

        #expect(receipt.binding == fixture.binding)
        #expect(await harness.semanticAcceptanceCount(for: identity) == 1)
        let clearedDiagnostics = await harness.transferDiagnostics
        #expect(clearedDiagnostics.semanticReplay.retainedLeaseCount == 0)
        #expect(clearedDiagnostics.semanticReplay.retainedIdentityCount == 0)
        guard
            case .state(.dirty(let reusedRepairGeneration)) = await harness.sourceGateState(
                for: fixture.binding
            )
        else {
            Issue.record("Successful retry must preserve admitted repair state")
            return
        }
        #expect(reusedRepairGeneration == retainedRepairGeneration)
    }

    @Test("stale same-binding ACK cannot clear a later semantic lease")
    func staleSameBindingAcknowledgementCannotClearLaterSemanticLease() async throws {
        // Arrange: complete one lease so the harness retains its exact ACK receipt.
        let registration = makeRegistration(registrationGeneration: 818)
        let fixture = try makeFixedSlotMailboxFixture(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 818),
            registrations: [registration],
            limits: leaseTransferMailboxLimits(),
            captureLimits: makeCaptureLimits(),
            callbackQueueLabel: "test.filesystem-observation-transfer-stale-semantic-ack"
        )
        expectRetainedCallback(
            try fixture.admitCallback(
                .authoritative(
                    makeObservation(
                        registration: registration,
                        path: "/transfer/stale-ack/first",
                        eventID: 1
                    )
                )
            )
        )
        let harness = try FilesystemObservationDrainHarnessActor(
            mailbox: fixture.mailbox,
            bindings: [fixture.binding],
            maximumContributionsPerLease: 3
        )
        let firstLease = try await requireLease(from: harness)
        _ = try requireTransferredReceipt(
            await harness.transferLease(firstLease, recoveryContext: .notRequired)
        )
        _ = requireRetainedRecovery(
            try fixture.admitCallback(
                .requiresRecovery(
                    makeObservation(
                        registration: registration,
                        path: "/transfer/stale-ack/second",
                        eventID: 2
                    ),
                    evidence: .continuityLoss
                )
            )
        )
        let secondLease = try await requireLease(from: harness)
        let secondIdentity = try #require(contributions(in: secondLease).first?.identity)
        let recoveryContext = requiredRecoveryContext()
        #expect(await harness.replayPreviousAcknowledgementReceiptOnce())

        // Act: substitute lease A's ACK receipt for lease B's same-binding ACK.
        let staleResult = await harness.transferLease(
            secondLease,
            recoveryContext: recoveryContext
        )

        // Assert: exact whole-lease authority rejects it before either clear.
        guard case .completed(.rejected(.semanticClear)) = staleResult else {
            Issue.record("Stale same-binding ACK must fail exact semantic clear")
            return
        }
        #expect(await harness.semanticAcceptanceCount(for: secondIdentity) == 1)
        let staleDiagnostics = await harness.transferDiagnostics
        #expect(staleDiagnostics.semanticReplay.retainedLeaseCount == 1)
        _ = try requireTransferredReceipt(
            await harness.transferLease(secondLease, recoveryContext: recoveryContext)
        )
        #expect(await harness.semanticAcceptanceCount(for: secondIdentity) == 1)
    }

    @Test("stale same-binding ACK cannot clear later recovery-only custody")
    func staleSameBindingAcknowledgementCannotClearLaterRecoveryOnlyCustody() async throws {
        // Arrange
        let registration = makeRegistration(registrationGeneration: 819)
        let fixture = try makeFixedSlotMailboxFixture(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 819),
            registrations: [registration],
            limits: recoveryOnlyLeaseTransferMailboxLimits(),
            captureLimits: makeCaptureLimits(),
            callbackQueueLabel: "test.filesystem-observation-transfer-stale-recovery-ack"
        )
        _ = requireContractedRecovery(
            try fixture.admitCallback(
                .authoritative(
                    makeObservation(
                        registration: registration,
                        path: "/transfer/stale-recovery/first",
                        eventID: 1
                    )
                )
            )
        )
        let harness = try FilesystemObservationDrainHarnessActor(
            mailbox: fixture.mailbox,
            bindings: [fixture.binding],
            maximumContributionsPerLease: 1
        )
        let firstLease = try await requireLease(from: harness)
        _ = try requireTransferredReceipt(
            await harness.transferLease(
                firstLease,
                recoveryContext: requiredRecoveryContext()
            )
        )
        _ = requireContractedRecovery(
            try fixture.admitCallback(
                .authoritative(
                    makeObservation(
                        registration: registration,
                        path: "/transfer/stale-recovery/second",
                        eventID: 2
                    )
                )
            )
        )
        let secondLease = try await requireLease(from: harness)
        let recoveryContext = requiredRecoveryContext()
        #expect(await harness.replayPreviousAcknowledgementReceiptOnce())

        // Act
        let staleResult = await harness.transferLease(
            secondLease,
            recoveryContext: recoveryContext
        )

        // Assert
        guard case .completed(.rejected(.sourceGateClear)) = staleResult else {
            Issue.record("Stale same-binding ACK must fail exact SourceGate clear")
            return
        }
        _ = try requireTransferredReceipt(
            await harness.transferLease(secondLease, recoveryContext: recoveryContext)
        )
    }

    @Test("recovery only lease requires exact SourceGate acceptance")
    func recoveryOnlyRequiresExactSourceGateAcceptance() async throws {
        // Arrange
        let registration = makeRegistration(registrationGeneration: 815)
        let fixture = try makeFixedSlotMailboxFixture(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 815),
            registrations: [registration],
            limits: recoveryOnlyLeaseTransferMailboxLimits(),
            captureLimits: makeCaptureLimits(),
            callbackQueueLabel: "test.filesystem-observation-transfer-recovery-only"
        )
        _ = requireContractedRecovery(
            try fixture.admitCallback(
                .authoritative(
                    makeObservation(
                        registration: registration,
                        path: "/transfer/recovery-only",
                        eventID: 1
                    )
                )
            )
        )
        let harness = try FilesystemObservationDrainHarnessActor(
            mailbox: fixture.mailbox,
            bindings: [fixture.binding],
            maximumContributionsPerLease: 1
        )
        let firstLease = try await requireLease(from: harness)
        guard case .recovery = firstLease.payload else {
            Issue.record("Contraction fixture must produce a recovery-only lease")
            return
        }

        // Act / Assert
        let missingAuthority = await harness.transferLease(
            firstLease,
            recoveryContext: .notRequired
        )
        guard case .completed(.rejected) = missingAuthority else {
            Issue.record("Recovery-only transfer cannot bypass SourceGate acceptance")
            return
        }
        await harness.rebindConsumer()
        let retriedLease = try await requireLease(from: harness)
        let receipt = try requireTransferredReceipt(
            await harness.transferLease(
                retriedLease,
                recoveryContext: requiredRecoveryContext()
            )
        )
        #expect(receipt.binding == fixture.binding)
        guard case .ordinaryLease = receipt.outcome else {
            Issue.record("Recovery-only transfer cannot mint a retirement receipt")
            return
        }
    }

    @Test("partial semantic retry and wrong token preserve exact once effects and final receipt")
    func partialRetryAndWrongTokenPreserveExactOnceEffects() async throws {
        // Arrange
        let fixture = try await makeFenceFixture(generation: 812)
        let harness = try FilesystemObservationDrainHarnessActor(
            mailbox: fixture.mailbox,
            bindings: [fixture.binding],
            maximumContributionsPerLease: 3
        )
        let firstLease = try await requireLease(from: harness)
        let firstContributions = contributions(in: firstLease)
        #expect(firstContributions.count == 3)
        let firstIdentity = firstContributions[0].identity
        let secondIdentity = firstContributions[1].identity
        await harness.requestSemanticRetry(before: secondIdentity)

        // Act: A enters semantic custody and B requests a whole-lease retry.
        let prefixResult = await harness.transferLease(
            firstLease,
            recoveryContext: .notRequired
        )
        guard case .completed(.retried) = prefixResult else {
            Issue.record("Partial semantic acceptance must retry the whole lease")
            return
        }
        await harness.rebindConsumer()
        let retriedLease = try await requireLease(from: harness)
        await harness.rejectNextAcknowledgement()
        let wrongTokenResult = await harness.transferLease(
            retriedLease,
            recoveryContext: .notRequired
        )

        // Assert: failed generic ACK cannot clear replay or mint a receipt.
        guard case .completed(.rejected) = wrongTokenResult else {
            Issue.record("Wrong-token acknowledgement must be a typed rejection")
            return
        }
        #expect(await harness.semanticAcceptanceCount(for: firstIdentity) == 1)
        #expect(await harness.semanticAcceptanceCount(for: secondIdentity) == 1)

        let finalResult = await harness.transferLease(
            retriedLease,
            recoveryContext: .notRequired
        )
        let wholeLeaseReceipt = try requireTransferredReceipt(finalResult)
        guard case .retired(let retirementReceipt) = wholeLeaseReceipt.outcome else {
            Issue.record("The exact final fence transfer must mint one retirement receipt")
            return
        }
        #expect(wholeLeaseReceipt.binding == fixture.binding)
        #expect(retirementReceipt.binding == fixture.binding)
        #expect(retirementReceipt.fenceIdentity == fixture.installedFence.identity)
        #expect(retirementReceipt.disposition == .quiescentWithoutRecovery)
        #expect(await harness.semanticAcceptanceCount(for: firstIdentity) == 1)
        #expect(await harness.semanticAcceptanceCount(for: secondIdentity) == 1)
        guard
            case .retired(let replayedRetirementReceipt) = fixture.mailbox.lifecyclePort
                .requestRetirementFence(fixture.leaseDrainReceipt)
        else {
            Issue.record("Lost caller response must replay the retained retirement receipt")
            return
        }
        #expect(replayedRetirementReceipt == retirementReceipt)
        let foreignFixture = try await makeFenceFixture(generation: 814)
        #expect(
            fixture.mailbox.lifecyclePort.requestRetirementFence(
                foreignFixture.leaseDrainReceipt
            ) == .foreignFleet
        )
        guard
            case .retiredAwaitingContextRelease = fixture.mailbox.physicalSlotState(
                of: fixture.binding.physicalSlotID
            )
        else {
            Issue.record("H2 must stop before native context release and slot vacancy")
            return
        }
    }

    @Test("final fence with recovery retires with exact recovery revision")
    func finalFenceWithRecoveryRetainsExactRetirementReceipt() async throws {
        // Arrange
        let fixture = try await makeFenceFixture(generation: 817, includesRecovery: true)
        let harness = try FilesystemObservationDrainHarnessActor(
            mailbox: fixture.mailbox,
            bindings: [fixture.binding],
            maximumContributionsPerLease: 3
        )
        let lease = try await requireLease(from: harness)
        let recoveryRevision: FixedFilesystemRecoveryEvidenceRevision
        switch lease.payload {
        case .contributionsWithRecovery(_, let evidence):
            recoveryRevision = evidence.revision
        case .contributions, .recovery:
            Issue.record("Recovery fence fixture must lease contributions with recovery")
            return
        }

        // Act
        let receipt = try requireTransferredReceipt(
            await harness.transferLease(
                lease,
                recoveryContext: requiredRecoveryContext()
            )
        )

        // Assert
        guard case .retired(let retirementReceipt) = receipt.outcome else {
            Issue.record("Final recovery fence must retire the exact slot lifetime")
            return
        }
        #expect(
            retirementReceipt.disposition
                == .quiescentAfterRecovery(recoveryRevision)
        )
        guard
            case .retired(let replayedReceipt) = fixture.mailbox.lifecyclePort
                .requestRetirementFence(fixture.leaseDrainReceipt)
        else {
            Issue.record("Retired recovery fence must retain an idempotent receipt")
            return
        }
        #expect(replayedReceipt == retirementReceipt)
    }

    @Test("copied wrong token rejects in preflight before new semantic effects")
    func copiedWrongTokenRejectsBeforeSemanticEffects() async throws {
        // Arrange
        let fixture = try makeOrdinaryFixture(generation: 813)
        let harness = try FilesystemObservationDrainHarnessActor(
            mailbox: fixture.mailbox,
            bindings: [fixture.binding],
            maximumContributionsPerLease: 3
        )
        let exactLease = try await requireLease(from: harness)
        let identity = try #require(contributions(in: exactLease).first?.identity)
        let copiedWrongTokenLease = FilesystemObservationDrainLease(
            token: invalidDrainToken(
                generation: AdmissionGeneration(owner: .filesystemObservation, value: 813)
            ),
            binding: exactLease.binding,
            payload: exactLease.payload
        )
        let slotStateBeforePreflight = fixture.mailbox.physicalSlotState(
            of: fixture.binding.physicalSlotID
        )

        // Act
        let result = await harness.transferLease(
            copiedWrongTokenLease,
            recoveryContext: .notRequired
        )

        // Assert
        guard case .completed(.rejected) = result else {
            Issue.record("Copied token must reject before semantic presentation")
            return
        }
        #expect(await harness.semanticAcceptanceCount(for: identity) == 0)
        #expect(
            fixture.mailbox.physicalSlotState(of: fixture.binding.physicalSlotID)
                == slotStateBeforePreflight,
            "Wrong-token preflight changed slot lifecycle custody"
        )
    }

    @Test("nonfinal and duplicate fences reject before semantic effects")
    func malformedFenceMatrixRejectsBeforeEffects() async throws {
        for malformedShape in MalformedFenceShape.allCases {
            // Arrange
            let fixture = try await makeFenceFixture(
                generation: 820 + UInt64(malformedShape.rawValue)
            )
            let harness = try FilesystemObservationDrainHarnessActor(
                mailbox: fixture.mailbox,
                bindings: [fixture.binding],
                maximumContributionsPerLease: 4
            )
            let exactLease = try await requireLease(from: harness)
            let retained = contributions(in: exactLease)
            let malformedContributions: [FilesystemObservationMailboxContribution]
            switch malformedShape {
            case .fenceInMiddle:
                malformedContributions = [retained[0], retained[2], retained[1]]
            case .duplicateFence:
                malformedContributions = [retained[0], retained[2], retained[2]]
            case .foreignInstalledIdentity:
                let foreignFixture = try await makeFenceFixture(
                    generation: 920 + UInt64(malformedShape.rawValue)
                )
                let foreignHarness = try FilesystemObservationDrainHarnessActor(
                    mailbox: foreignFixture.mailbox,
                    bindings: [foreignFixture.binding],
                    maximumContributionsPerLease: 3
                )
                let foreignLease = try await requireLease(from: foreignHarness)
                let foreignFence = try #require(contributions(in: foreignLease).last)
                malformedContributions = [retained[0], retained[1], foreignFence]
            }
            let malformedLease = replacingContributions(
                in: exactLease,
                with: malformedContributions
            )

            // Act
            let result = await harness.transferLease(
                malformedLease,
                recoveryContext: .notRequired
            )

            // Assert
            guard case .completed(.rejected) = result else {
                Issue.record("Malformed fence shape \(malformedShape) must be rejected")
                continue
            }
            #expect(
                await harness.semanticAcceptanceCount(for: retained[0].identity) == 0
            )
            #expect(
                await harness.semanticAcceptanceCount(for: retained[1].identity) == 0
            )
            guard
                case .retirementFenceInstalled = fixture.mailbox.physicalSlotState(
                    of: fixture.binding.physicalSlotID
                )
            else {
                Issue.record("Malformed preflight must retain installed-fence custody")
                continue
            }
        }
    }

    private enum MalformedFenceShape: Int, CaseIterable {
        case fenceInMiddle
        case duplicateFence
        case foreignInstalledIdentity
    }

    private struct OrdinaryFixture {
        let mailbox: FilesystemObservationMailbox
        let binding: FilesystemObservationSlotBinding
    }

    private struct FenceFixture {
        let mailbox: FilesystemObservationMailbox
        let binding: FilesystemObservationSlotBinding
        let installedFence: FilesystemObservationSlotRetirementFence
        let leaseDrainReceipt: DarwinFSEventRegistrationLeaseDrainReceipt
        let nativeGeneration: DarwinFSEventRegistrationGeneration
    }

    private func makeOrdinaryFixture(generation: UInt64) throws -> OrdinaryFixture {
        let registration = makeRegistration(registrationGeneration: generation)
        let fixture = try makeFixedSlotMailboxFixture(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: generation),
            registrations: [registration],
            limits: leaseTransferMailboxLimits(),
            captureLimits: makeCaptureLimits(),
            callbackQueueLabel: "test.filesystem-observation-transfer-ordinary"
        )
        expectRetainedCallback(
            try fixture.admitCallback(
                .authoritative(
                    makeObservation(
                        registration: registration,
                        path: "/transfer/ordinary",
                        eventID: 1
                    )
                )
            )
        )
        return OrdinaryFixture(mailbox: fixture.mailbox, binding: fixture.binding)
    }

    private func makeFenceFixture(
        generation: UInt64,
        includesRecovery: Bool = false
    ) async throws -> FenceFixture {
        let admissionGeneration = AdmissionGeneration(
            owner: .filesystemObservation,
            value: generation
        )
        let registration = makeRegistration(registrationGeneration: generation)
        let mailbox = try FilesystemObservationMailbox(
            generation: admissionGeneration,
            maximumSimultaneousSourceCount: 1,
            replacementReserveSlotCount: 0,
            limits: leaseTransferMailboxLimits()
        )
        guard case .enqueued = mailbox.installTestConfiguration(registration),
            case .selected(let selection) = mailbox.selectNextDesiredSource(),
            case .committed(let startingLifetime) = mailbox.beginNativeLifetime(
                selection.reservation
            ),
            case .created(let nativePorts) = mailbox.nativeGenerationPorts(
                for: startingLifetime
            )
        else {
            throw LeaseTransferTestFailure.fixtureConstructionFailed
        }
        let captureLimits = try makeCaptureLimits()
        let controlBlock = try makeControlBlock(
            startingNativeLifetime: startingLifetime,
            captureLimits: captureLimits,
            callbackQueueLabel: "test.filesystem-observation-transfer-fence"
        )
        let adapter = LeaseTransferCallbackAdapter(
            controlBlock: controlBlock,
            callbackAdmissionPort: nativePorts.callbackAdmissionPort
        )
        guard
            case .created(let nativeGeneration) = nativePorts.nativeOwner.createOrReplay(
                controlBlock: controlBlock,
                adapter: adapter,
                nativeDriver: LeaseTransferNativeDriver(),
                callbackQueueBarrier: LeaseTransferCallbackQueueBarrier()
            ),
            case .started = await nativeGeneration.start()
        else {
            throw LeaseTransferTestFailure.nativeGenerationFailed
        }
        try admitObservation(
            registration: registration,
            eventID: 1,
            controlBlock: controlBlock,
            callbackPort: nativePorts.callbackAdmissionPort,
            captureLimits: captureLimits
        )
        if includesRecovery {
            try admitRecoveryObservation(
                registration: registration,
                eventID: 2,
                controlBlock: controlBlock,
                callbackPort: nativePorts.callbackAdmissionPort,
                captureLimits: captureLimits
            )
        } else {
            try admitObservation(
                registration: registration,
                eventID: 2,
                controlBlock: controlBlock,
                callbackPort: nativePorts.callbackAdmissionPort,
                captureLimits: captureLimits
            )
        }
        guard case .closed(let leaseDrainReceipt) = await nativeGeneration.close(),
            case .installed(let installedLifetime) = mailbox.lifecyclePort
                .requestRetirementFence(leaseDrainReceipt)
        else {
            throw LeaseTransferTestFailure.retirementFenceUnavailable
        }
        return FenceFixture(
            mailbox: mailbox,
            binding: startingLifetime.binding,
            installedFence: installedLifetime.fence,
            leaseDrainReceipt: leaseDrainReceipt,
            nativeGeneration: nativeGeneration
        )
    }

    private func admitObservation(
        registration: FSEventRegistrationToken,
        eventID: UInt64,
        controlBlock: FSEventRegistrationControlBlock,
        callbackPort: FilesystemObservationCallbackAdmissionPort,
        captureLimits: FSEventCaptureLimits
    ) throws {
        guard case .acquired(let callbackLease) = controlBlock.acquireCallbackLease() else {
            throw LeaseTransferTestFailure.callbackLeaseUnavailable
        }
        defer { _ = callbackLease.release() }
        let observation = try makeObservation(
            registration: registration,
            path: "/transfer/fence/\(eventID)",
            eventID: eventID
        )
        let result = callbackPort.admit(
            using: callbackLease,
            preflight: FilesystemObservationCallbackPreflight(captureLimits: captureLimits)
        ) {
            .offer(.authoritative(observation))
        }
        expectRetainedCallback(result)
    }

    private func admitRecoveryObservation(
        registration: FSEventRegistrationToken,
        eventID: UInt64,
        controlBlock: FSEventRegistrationControlBlock,
        callbackPort: FilesystemObservationCallbackAdmissionPort,
        captureLimits: FSEventCaptureLimits
    ) throws {
        guard case .acquired(let callbackLease) = controlBlock.acquireCallbackLease() else {
            throw LeaseTransferTestFailure.callbackLeaseUnavailable
        }
        defer { _ = callbackLease.release() }
        let observation = try makeObservation(
            registration: registration,
            path: "/transfer/fence/\(eventID)",
            eventID: eventID
        )
        let result = callbackPort.admit(
            using: callbackLease,
            preflight: FilesystemObservationCallbackPreflight(captureLimits: captureLimits)
        ) {
            .offer(.requiresRecovery(observation, evidence: .continuityLoss))
        }
        _ = requireRetainedRecovery(result)
    }

    private func requiredRecoveryContext() -> FilesystemObservationRecoveryAdmissionContext {
        .required(
            trigger: .continuityLoss,
            watermark: .recoveryRevision(1),
            participants: makeRequiredParticipants()
        )
    }

    private func contributions(
        in lease: FilesystemObservationDrainLease
    ) -> [FilesystemObservationMailboxContribution] {
        switch lease.payload {
        case .contributions(let batch), .contributionsWithRecovery(let batch, _):
            return [batch.first] + batch.remaining
        case .recovery:
            preconditionFailure("Expected a contribution-bearing lease")
        }
    }

    private func replacingContributions(
        in lease: FilesystemObservationDrainLease,
        with contributions: [FilesystemObservationMailboxContribution]
    ) -> FilesystemObservationDrainLease {
        guard let first = contributions.first else {
            preconditionFailure("Malformed fence fixture must remain nonempty")
        }
        return FilesystemObservationDrainLease(
            token: lease.token,
            binding: lease.binding,
            payload: .contributions(
                NonEmptyAdmissionBatch(
                    first: first,
                    remaining: Array(contributions.dropFirst())
                )
            )
        )
    }

    private func invalidDrainToken(generation: AdmissionGeneration) -> AdmissionDrainToken {
        AdmissionDrainToken(
            generation: generation,
            mailboxIdentity: AdmissionOpaqueIdentity(),
            bindingEpoch: AdmissionOpaqueIdentity(),
            bindingSequence: 1,
            leaseEpoch: AdmissionOpaqueIdentity(),
            leaseSequence: 1
        )
    }

    private func requireLease(
        from harness: FilesystemObservationDrainHarnessActor
    ) async throws -> FilesystemObservationDrainLease {
        guard case .lease(let lease) = await harness.takeLease() else {
            throw LeaseTransferTestFailure.leaseUnavailable
        }
        return lease
    }

    private func requireTransferredReceipt(
        _ result: FilesystemObservationDrainHarnessTransferResult
    ) throws -> FilesystemObservationWholeLeaseTransferReceipt {
        guard case .completed(.transferred(let receipt)) = result else {
            throw LeaseTransferTestFailure.transferDidNotComplete
        }
        return receipt
    }
}

private enum LeaseTransferTestFailure: Error {
    case fixtureConstructionFailed
    case nativeGenerationFailed
    case callbackLeaseUnavailable
    case retirementFenceUnavailable
    case leaseUnavailable
    case transferDidNotComplete
}
