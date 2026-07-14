import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem source gate shutdown debt")
struct FilesystemSourceGateShutdownDebtTests {
    @Test("read-only debt projects every repair lifecycle state exactly")
    func projectionExhaustivelyMapsRepairLifecycleStates() throws {
        // Arrange / Act / Assert — healthy
        let registration = makeRegistration()
        var healthyGate = makeSourceGate(registration: registration)
        assertStableSnapshot(
            of: healthyGate,
            lifecycle: .repairAdmissionOpen(.noOutstandingRepair),
            readiness: .ready
        )
        let expectedClosedSnapshot = FilesystemSourceGateShutdownDebtSnapshot(
            binding: healthyGate.binding,
            repairLifecycle: .repairAdmissionClosed(
                FilesystemSourceGateShutdown(
                    registration: registration,
                    debt: .noOutstandingRepair
                )
            ),
            mailboxRecoveryReplay: .vacant,
            continuityRepairReplay: .vacant
        )
        #expect(healthyGate.beginShutdown() == .applied(expectedClosedSnapshot))
        #expect(healthyGate.beginShutdown() == .alreadyApplied(expectedClosedSnapshot))

        // Arrange / Act / Assert — dirty
        var dirtyGate = makeSourceGate(registration: registration)
        let dirtyRepair = try admitRepair(to: &dirtyGate, watermark: .recoveryRevision(11))
        assertStableSnapshot(
            of: dirtyGate,
            lifecycle: .repairAdmissionOpen(.dirty(dirtyRepair)),
            readiness: .awaitingRepairLifecycle
        )
        assertOutstandingShutdownBegin(of: &dirtyGate)

        // Arrange / Act / Assert — reconciling
        var reconcilingGate = makeSourceGate(registration: registration)
        let reconcilingRepair = try admitRepair(
            to: &reconcilingGate,
            watermark: .recoveryRevision(21)
        )
        #expect(reconcilingGate.beginReconciliation(reconcilingRepair.id) == .applied)
        assertStableSnapshot(
            of: reconcilingGate,
            lifecycle: .repairAdmissionOpen(.reconciling(reconcilingRepair)),
            readiness: .awaitingRepairLifecycle
        )
        assertOutstandingShutdownBegin(of: &reconcilingGate)

        // Arrange / Act / Assert — reconciling with newer dirty debt
        var reconcilingAndDirtyGate = makeSourceGate(registration: registration)
        let activeRepair = try admitRepair(
            to: &reconcilingAndDirtyGate,
            watermark: .recoveryRevision(31)
        )
        #expect(reconcilingAndDirtyGate.beginReconciliation(activeRepair.id) == .applied)
        let pendingRepair = try admitRepair(
            to: &reconcilingAndDirtyGate,
            trigger: .callbackGateOverflow,
            watermark: .recoveryRevision(32)
        )
        assertStableSnapshot(
            of: reconcilingAndDirtyGate,
            lifecycle: .repairAdmissionOpen(
                .reconcilingAndDirty(active: activeRepair, pending: pendingRepair)
            ),
            readiness: .awaitingRepairLifecycle
        )
        assertOutstandingShutdownBegin(of: &reconcilingAndDirtyGate)

        // Arrange / Act / Assert — awaiting acknowledgements
        var awaitingGate = makeSourceGate(registration: registration)
        let awaitingRepair = try admitRepair(to: &awaitingGate, watermark: .recoveryRevision(41))
        #expect(awaitingGate.beginReconciliation(awaitingRepair.id) == .applied)
        #expect(awaitingGate.completeReconciliation(awaitingRepair.id) == .applied)
        let awaiting = AwaitingFilesystemRepairAcknowledgements(
            generation: awaitingRepair,
            pendingParticipants: awaitingRepair.participants
        )
        assertStableSnapshot(
            of: awaitingGate,
            lifecycle: .repairAdmissionOpen(.awaitingAcknowledgements(awaiting)),
            readiness: .awaitingRepairLifecycle
        )
        assertOutstandingShutdownBegin(of: &awaitingGate)

        // Arrange / Act / Assert — repair failed
        var failedGate = makeSourceGate(registration: registration)
        let failedRepair = try admitRepair(to: &failedGate, watermark: .recoveryRevision(51))
        #expect(failedGate.beginReconciliation(failedRepair.id) == .applied)
        #expect(
            failedGate.failReconciliation(
                failedRepair.id,
                failure: .authoritativeResultRejected
            ) == .applied
        )
        let failure = FailedFilesystemRepair(
            failedGeneration: failedRepair,
            retryGeneration: failedRepair,
            failure: .authoritativeResultRejected
        )
        assertStableSnapshot(
            of: failedGate,
            lifecycle: .repairAdmissionOpen(.repairFailed(failure)),
            readiness: .awaitingRepairLifecycle
        )
        assertOutstandingShutdownBegin(of: &failedGate)
    }

    @Test("continuity replay remains exact but does not block shutdown after repair completes")
    func continuityReplayIsTruthWithoutPermanentProgressDebt() throws {
        // Arrange
        let registration = makeRegistration()
        var gate = makeSourceGate(registration: registration)
        let authority = FilesystemContinuityRepairHandoffAuthority(
            acceptingBinding: gate.binding,
            handoffIdentity: FilesystemContinuityRepairHandoffIdentity(value: UUIDv7.generate()),
            desiredIdentity: FilesystemObservationDesiredIdentity(value: UUIDv7.generate()),
            acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(value: 71)
        )
        let participants = makeRequiredParticipants()
        let trigger = FilesystemRepairTriggerClass.continuityLoss
        let watermark = FilesystemRepairWatermark.recoveryRevision(72)

        // Act
        let admission = gate.acceptContinuityRepairHandoff(
            authority,
            trigger: trigger,
            watermark: watermark,
            participants: participants
        )
        guard case .admitted(let acceptance) = admission else {
            Issue.record("continuity repair handoff was not admitted: \(admission)")
            return
        }
        let retainedSnapshot = gate.shutdownDebtSnapshot
        let replay = gate.acceptContinuityRepairHandoff(
            authority,
            trigger: trigger,
            watermark: watermark,
            participants: participants
        )
        #expect(gate.beginReconciliation(acceptance.repairGeneration.id) == .applied)
        #expect(gate.completeReconciliation(acceptance.repairGeneration.id) == .applied)
        acknowledgeAll(acceptance.repairGeneration, in: &gate)
        let completedSnapshot = gate.shutdownDebtSnapshot
        let beginResult = gate.beginShutdown()
        let replayAfterShutdown = gate.acceptContinuityRepairHandoff(
            authority,
            trigger: trigger,
            watermark: watermark,
            participants: participants
        )

        // Assert
        let exactReplay = SourceGateContinuityReplayDebt.retained(
            SourceGateRetainedContinuityDebt(
                request: SourceGateContinuityRequestDebt(
                    authority: authority,
                    trigger: trigger,
                    watermark: watermark,
                    participants: participants
                ),
                acceptance: acceptance
            )
        )
        #expect(retainedSnapshot.continuityRepairReplay == exactReplay)
        #expect(retainedSnapshot.shutdownBeginReadiness == .awaitingRepairLifecycle)
        #expect(replay == admission)
        #expect(completedSnapshot.repairLifecycle == .repairAdmissionOpen(.noOutstandingRepair))
        #expect(completedSnapshot.continuityRepairReplay == exactReplay)
        #expect(completedSnapshot.shutdownBeginReadiness == .ready)
        guard case .applied(let closedSnapshot) = beginResult else {
            Issue.record("retained continuity replay blocked ready shutdown: \(beginResult)")
            return
        }
        #expect(closedSnapshot.shutdownBeginReadiness == .alreadyBegan)
        #expect(closedSnapshot.continuityRepairReplay == exactReplay)
        #expect(replayAfterShutdown == admission)
    }

    @Test("mailbox recovery replay blocks shutdown until exact transfer clears custody")
    func mailboxRecoveryReplayProjectsAndClearsExactly() throws {
        // Arrange
        let registration = makeRegistration()
        let fixture = try makeFixedSlotMailboxFixture(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 81),
            registrations: [registration],
            limits: mailboxLimits(),
            captureLimits: makeCaptureLimits(),
            callbackQueueLabel: "test.filesystem-source-gate-shutdown-debt"
        )
        let evidence = requireRetainedRecovery(
            try fixture.admitCallback(
                .requiresRecovery(
                    makeObservation(
                        registration: registration,
                        path: "/projection-must-not-retain-this-path",
                        eventID: 1
                    ),
                    evidence: .continuityLoss
                )
            )
        )
        var gate = FilesystemSourceGate(binding: evidence.revision.binding)
        let participants = makeRequiredParticipants()
        let trigger = FilesystemRepairTriggerClass.continuityLoss
        let watermark = FilesystemRepairWatermark.eventIDsAndRecoveryRevision(
            .inspected(first: 1, last: 1),
            recoveryRevision: 82
        )
        let admission = gate.acceptMailboxRecovery(
            evidence,
            trigger: trigger,
            watermark: watermark,
            participants: participants
        )
        guard case .admitted(let acceptance) = admission else {
            Issue.record("mailbox recovery was not admitted: \(admission)")
            return
        }

        // Act
        let retainedSnapshot = gate.shutdownDebtSnapshot
        let combinedDebtResult = gate.beginShutdown()
        #expect(gate.beginReconciliation(acceptance.repairGeneration.id) == .applied)
        #expect(gate.completeReconciliation(acceptance.repairGeneration.id) == .applied)
        acknowledgeAll(acceptance.repairGeneration, in: &gate)
        let mailboxOnlySnapshot = gate.shutdownDebtSnapshot
        let mailboxOnlyDebtResult = gate.beginShutdown()
        let consumerPort = fixture.mailbox.actorConsumerPort
        let consumerBinding = consumerPort.bindConsumer().binding
        let lease = requireLease(consumerPort.takeDrain(binding: consumerBinding))
        let transferAcknowledgement = try credentialedTransferAcknowledgement(
            for: lease,
            consumerPort: consumerPort,
            sourceGate: &gate,
            recoveryContext: .required(
                trigger: trigger,
                watermark: watermark,
                participants: participants
            )
        )
        let clearedSnapshot = gate.shutdownDebtSnapshot
        let appliedResult = gate.beginShutdown()

        // Assert
        let exactReplay = SourceGateMailboxRecoveryReplayDebt.retained(
            SourceGateRetainedMailboxRecoveryDebt(
                request: SourceGateMailboxRecoveryRequestDebt(
                    evidence: evidence,
                    trigger: trigger,
                    watermark: watermark,
                    participants: participants
                ),
                acceptance: acceptance
            )
        )
        #expect(retainedSnapshot.mailboxRecoveryReplay == exactReplay)
        #expect(
            retainedSnapshot.shutdownBeginReadiness
                == .awaitingRepairLifecycleAndMailboxRecoveryTransfer
        )
        #expect(combinedDebtResult == .outstandingDebt(retainedSnapshot))
        #expect(mailboxOnlySnapshot.shutdownBeginReadiness == .awaitingMailboxRecoveryTransfer)
        #expect(mailboxOnlyDebtResult == .outstandingDebt(mailboxOnlySnapshot))
        guard case .transferredRecovery = transferAcknowledgement else {
            Issue.record("exact recovery transfer did not acknowledge recovery custody")
            return
        }
        #expect(clearedSnapshot.mailboxRecoveryReplay == .vacant)
        #expect(clearedSnapshot.repairLifecycle == .repairAdmissionOpen(.noOutstandingRepair))
        #expect(clearedSnapshot.shutdownBeginReadiness == .ready)
        guard case .applied(let closedSnapshot) = appliedResult else {
            Issue.record("cleared SourceGate did not begin shutdown: \(appliedResult)")
            return
        }
        #expect(closedSnapshot.shutdownBeginReadiness == .alreadyBegan)
    }

    private func assertStableSnapshot(
        of gate: FilesystemSourceGate,
        lifecycle: FilesystemSourceGateRepairLifecycleShutdownDebt,
        readiness: FilesystemSourceGateShutdownBeginReadiness,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let first = gate.shutdownDebtSnapshot
        let replay = gate.shutdownDebtSnapshot
        #expect(first.binding == gate.binding, sourceLocation: sourceLocation)
        #expect(first.registration == gate.registration, sourceLocation: sourceLocation)
        #expect(first.repairLifecycle == lifecycle, sourceLocation: sourceLocation)
        #expect(first.mailboxRecoveryReplay == .vacant, sourceLocation: sourceLocation)
        #expect(first.continuityRepairReplay == .vacant, sourceLocation: sourceLocation)
        #expect(first.shutdownBeginReadiness == readiness, sourceLocation: sourceLocation)
        #expect(replay == first, sourceLocation: sourceLocation)
    }

    private func assertOutstandingShutdownBegin(
        of gate: inout FilesystemSourceGate,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let stateBeforeBegin = gate.state
        let snapshotBeforeBegin = gate.shutdownDebtSnapshot
        #expect(
            gate.beginShutdown() == .outstandingDebt(snapshotBeforeBegin),
            sourceLocation: sourceLocation
        )
        #expect(gate.state == stateBeforeBegin, sourceLocation: sourceLocation)
        #expect(gate.shutdownDebtSnapshot == snapshotBeforeBegin, sourceLocation: sourceLocation)
    }

    private func acknowledgeAll(
        _ repair: RepairGeneration,
        in gate: inout FilesystemSourceGate
    ) {
        for participant in repair.participants {
            #expect(
                gate.acknowledge(
                    FilesystemRepairAcknowledgementToken(
                        repairGenerationID: repair.id,
                        participant: participant
                    )
                ) == .applied
            )
        }
    }

    private func admitRepair(
        to gate: inout FilesystemSourceGate,
        trigger: FilesystemRepairTriggerClass = .continuityLoss,
        watermark: FilesystemRepairWatermark
    ) throws -> RepairGeneration {
        switch gate.recordRepair(
            trigger: trigger,
            watermark: watermark,
            participants: makeRequiredParticipants()
        ) {
        case .admitted(let repair):
            return repair
        case .rejected(let rejection):
            Issue.record("repair admission rejected: \(rejection)")
        case .generationExhausted:
            Issue.record("repair generation unexpectedly exhausted")
        case .shuttingDown:
            Issue.record("repair admission unexpectedly reached shutdown")
        }
        throw TestFailure.repairNotAdmitted
    }

    private func makeRequiredParticipants() -> Set<FilesystemRepairParticipantToken> {
        [
            makeParticipant(.contentRepairProjector, generation: 1),
            makeParticipant(.gitWorkingDirectoryProjector, generation: 2),
            makeParticipant(.paneFilesystemProjection, generation: 3),
        ]
    }

    private func makeParticipant(
        _ kind: FilesystemRepairParticipantKind,
        generation: UInt64
    ) -> FilesystemRepairParticipantToken {
        FilesystemRepairParticipantToken(
            kind: kind,
            participantID: UUIDv7.generate(),
            participantGeneration: generation
        )
    }

    private func makeRegistration() -> FSEventRegistrationToken {
        FSEventRegistrationToken(
            sourceID: FilesystemSourceID(
                kind: .registeredWorktreeContent,
                rootID: UUIDv7.generate()
            ),
            registrationGeneration: 5,
            rootGeneration: 9
        )
    }

    private func makeSourceGate(
        registration: FSEventRegistrationToken
    ) -> FilesystemSourceGate {
        FilesystemSourceGate(
            binding: FilesystemObservationSlotBinding(
                fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity(
                    value: UUIDv7.generate()
                ),
                physicalSlotID: FilesystemObservationPhysicalSlotID(value: UUIDv7.generate()),
                identity: FilesystemObservationSlotBindingIdentity(value: UUIDv7.generate()),
                registration: registration,
                controlBlockIdentity: FilesystemObservationControlBlockIdentity(
                    value: UUIDv7.generate()
                )
            )
        )
    }

    private enum TestFailure: Error {
        case repairNotAdmitted
    }
}
