import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem source gate")
struct FilesystemSourceGateTests {
    @Test("reconciliation completion waits for every captured acknowledgement")
    func reconciliationCompletionDoesNotClearRepairDebt() throws {
        var gate = FilesystemSourceGate(registration: makeRegistration())
        let projection = makeParticipant(.paneFilesystemProjection, generation: 11)
        let git = makeParticipant(.gitWorkingDirectoryProjector, generation: 7)
        let repair = try admitRepair(to: &gate, participants: [projection, git])

        #expect(gate.beginReconciliation(repair.id) == .applied)
        #expect(gate.completeReconciliation(repair.id) == .applied)
        #expect(
            gate.state
                == .awaitingAcknowledgements(
                    AwaitingFilesystemRepairAcknowledgements(
                        generation: repair,
                        pendingParticipants: repair.participants
                    )
                )
        )

        #expect(gate.acknowledge(makeAcknowledgement(repair, projection)) == .applied)
        #expect(
            gate.state
                == .awaitingAcknowledgements(
                    AwaitingFilesystemRepairAcknowledgements(
                        generation: repair,
                        pendingParticipants: repair.participants.subtracting([projection])
                    )
                )
        )
        #expect(gate.acknowledge(makeAcknowledgement(repair, git)) == .applied)
        for participant in repair.participants.subtracting([projection, git]) {
            #expect(gate.acknowledge(makeAcknowledgement(repair, participant)) == .applied)
        }
        #expect(gate.state == .healthy(makeRegistration()))
    }

    @Test("foreign stale and duplicate acknowledgements cannot clear debt")
    func invalidAcknowledgementsPreserveDebt() throws {
        var gate = FilesystemSourceGate(registration: makeRegistration())
        let projection = makeParticipant(.paneFilesystemProjection, generation: 4)
        let repair = try admitRepair(to: &gate, participants: [projection])
        #expect(gate.beginReconciliation(repair.id) == .applied)
        #expect(gate.completeReconciliation(repair.id) == .applied)

        let foreign = makeParticipant(.gitWorkingDirectoryProjector, generation: 4)
        #expect(
            gate.acknowledge(makeAcknowledgement(repair, foreign))
                == .unknownParticipant(foreign)
        )
        let staleRepairID = RepairGenerationID(
            registration: repair.id.registration,
            sequence: repair.id.sequence + 1
        )
        #expect(
            gate.acknowledge(
                FilesystemRepairAcknowledgementToken(
                    repairGenerationID: staleRepairID,
                    participant: projection
                )
            ) == .staleGeneration
        )
        #expect(gate.acknowledge(makeAcknowledgement(repair, projection)) == .applied)
        #expect(
            gate.acknowledge(makeAcknowledgement(repair, projection))
                == .alreadyApplied
        )
    }

    @Test("new trigger while reconciling supersedes the completed older scan")
    func triggerDuringReconciliationRequiresNewestRepair() throws {
        var gate = FilesystemSourceGate(registration: makeRegistration())
        let participant = makeParticipant(.paneFilesystemProjection, generation: 1)
        let first = try admitRepair(to: &gate, participants: [participant])
        #expect(gate.beginReconciliation(first.id) == .applied)

        let second = try admitRepair(
            to: &gate,
            trigger: .callbackGateOverflow,
            watermark: .recoveryRevision(2),
            participants: [participant]
        )
        #expect(gate.state == .reconcilingAndDirty(active: first, pending: second))

        #expect(gate.completeReconciliation(first.id) == .applied)
        #expect(gate.state == .dirty(second))
        #expect(gate.acknowledge(makeAcknowledgement(first, participant)) == .invalidState(.dirty(second)))
    }

    @Test("new trigger while awaiting acknowledgements invalidates old receipts")
    func triggerWhileAwaitingAcknowledgementsCreatesNewDebt() throws {
        var gate = FilesystemSourceGate(registration: makeRegistration())
        let participant = makeParticipant(.gitWorkingDirectoryProjector, generation: 3)
        let first = try admitRepair(to: &gate, participants: [participant])
        #expect(gate.beginReconciliation(first.id) == .applied)
        #expect(gate.completeReconciliation(first.id) == .applied)

        let second = try admitRepair(
            to: &gate,
            trigger: .captureTruncation,
            watermark: .eventIDs(.inspected(first: 90, last: 110)),
            participants: [participant]
        )
        #expect(gate.state == .dirty(second))
        #expect(gate.acknowledge(makeAcknowledgement(first, participant)) == .invalidState(.dirty(second)))
    }

    @Test("failed reconciliation retains retryable repair generation")
    func failedReconciliationRetainsDebt() throws {
        var gate = FilesystemSourceGate(registration: makeRegistration())
        let participant = makeParticipant(.contentRepairProjector, generation: 2)
        let repair = try admitRepair(to: &gate, participants: [participant])
        #expect(gate.beginReconciliation(repair.id) == .applied)

        #expect(
            gate.failReconciliation(repair.id, failure: .authoritativeScanFailed)
                == .applied
        )
        #expect(
            gate.state
                == .repairFailed(
                    FailedFilesystemRepair(
                        failedGeneration: repair,
                        retryGeneration: repair,
                        failure: .authoritativeScanFailed
                    )
                )
        )
        #expect(gate.beginReconciliation(repair.id) == .applied)
        #expect(gate.state == .reconciling(repair))
    }

    @Test("failure while newer debt exists retries the newest generation")
    func failedActiveRepairPreservesNewestPendingDebt() throws {
        var gate = FilesystemSourceGate(registration: makeRegistration())
        let participant = makeParticipant(.contentRepairProjector, generation: 3)
        let active = try admitRepair(to: &gate, participants: [participant])
        #expect(gate.beginReconciliation(active.id) == .applied)
        let pending = try admitRepair(
            to: &gate,
            trigger: .captureTruncation,
            watermark: .recoveryRevision(2),
            participants: [participant]
        )

        #expect(
            gate.failReconciliation(active.id, failure: .authoritativeResultPartial)
                == .applied
        )
        #expect(
            gate.state
                == .repairFailed(
                    FailedFilesystemRepair(
                        failedGeneration: active,
                        retryGeneration: pending,
                        failure: .authoritativeResultPartial
                    )
                )
        )
        #expect(gate.beginReconciliation(pending.id) == .applied)
        #expect(gate.state == .reconciling(pending))
    }

    @Test("rejected acknowledgement returns the same generation to dirty")
    func rejectedAcknowledgementPreservesSameGenerationDebt() throws {
        var gate = FilesystemSourceGate(registration: makeRegistration())
        let participant = makeParticipant(.gitWorkingDirectoryProjector, generation: 8)
        let repair = try admitRepair(to: &gate, participants: [participant])
        #expect(gate.beginReconciliation(repair.id) == .applied)
        #expect(gate.completeReconciliation(repair.id) == .applied)

        #expect(
            gate.rejectAcknowledgement(
                makeAcknowledgement(repair, participant),
                failure: .currentnessApplyFailed
            ) == .applied
        )
        #expect(gate.state == .dirty(repair))
    }

    @Test("shutdown is terminal and retains exact outstanding debt")
    func shutdownRejectsFurtherTransitions() throws {
        var gate = FilesystemSourceGate(registration: makeRegistration())
        let participant = makeParticipant(.contentRepairProjector, generation: 6)
        let repair = try admitRepair(to: &gate, participants: [participant])

        #expect(gate.beginShutdown() == .applied)
        let shutdown = FilesystemSourceGateShutdown(
            registration: makeRegistration(),
            debt: .dirty(repair)
        )
        #expect(gate.state == .shuttingDown(shutdown))
        #expect(gate.beginReconciliation(repair.id) == .shuttingDown)
        #expect(
            gate.recordRepair(
                trigger: .continuityLoss,
                watermark: .recoveryRevision(99),
                participants: [participant]
            ) == .shuttingDown
        )
        #expect(gate.beginShutdown() == .alreadyApplied)
    }

    @Test("empty participant capture is rejected")
    func emptyRepairAdmissionDoesNotMutateHealthyState() {
        var gate = FilesystemSourceGate(registration: makeRegistration())

        #expect(
            gate.recordRepair(
                trigger: .continuityLoss,
                watermark: .recoveryRevision(1),
                participants: []
            ) == .rejected(.emptyParticipantSet)
        )
        #expect(gate.state == .healthy(makeRegistration()))
    }

    @Test("source kinds reject recovery owners from the other repair matrix")
    func sourceKindsCannotBorrowRecoveryOwners() {
        let registeredWorktreeRegistration = makeRegistration()
        var registeredWorktreeGate = FilesystemSourceGate(
            registration: registeredWorktreeRegistration
        )
        let watchedParentOwner = makeParticipant(.canonicalTopologyCommit, generation: 1)
        let secondWatchedParentOwner = makeParticipant(.scanScheduler, generation: 2)
        #expect(
            registeredWorktreeGate.recordRepair(
                trigger: .continuityLoss,
                watermark: .recoveryRevision(1),
                participants: [watchedParentOwner, secondWatchedParentOwner]
            )
                == .rejected(
                    .participantsNotApplicableToSource([
                        watchedParentOwner,
                        secondWatchedParentOwner,
                    ])
                )
        )
        #expect(registeredWorktreeGate.state == .healthy(registeredWorktreeRegistration))

        let watchedParentRegistration = makeRegistration(kind: .watchedParentMembership)
        var watchedParentGate = FilesystemSourceGate(registration: watchedParentRegistration)
        let registeredWorktreeOwner = makeParticipant(
            .gitWorkingDirectoryProjector,
            generation: 1
        )
        #expect(
            watchedParentGate.recordRepair(
                trigger: .continuityLoss,
                watermark: .recoveryRevision(1),
                participants: [registeredWorktreeOwner]
            ) == .rejected(.participantsNotApplicableToSource([registeredWorktreeOwner]))
        )
        #expect(watchedParentGate.state == .healthy(watchedParentRegistration))
    }

    @Test("source kinds require their complete mandatory owner matrix")
    func sourceKindsRequireMandatoryOwners() {
        var registeredWorktreeGate = FilesystemSourceGate(registration: makeRegistration())
        let projector = makeParticipant(.contentRepairProjector, generation: 1)
        #expect(
            registeredWorktreeGate.recordRepair(
                trigger: .continuityLoss,
                watermark: .recoveryRevision(1),
                participants: [projector]
            )
                == .rejected(
                    .missingRequiredParticipantKinds([
                        .gitWorkingDirectoryProjector,
                        .paneFilesystemProjection,
                    ])
                )
        )

        let required = makeRequiredParticipants(for: .registeredWorktreeContent)
        #expect(
            registeredWorktreeGate.recordRepair(
                trigger: .registrationReplaced,
                watermark: .recoveryRevision(2),
                participants: required
            ) == .rejected(.missingRequiredParticipantKinds([.registrationOwner]))
        )
    }

    private func admitRepair(
        to gate: inout FilesystemSourceGate,
        trigger: FilesystemRepairTriggerClass = .continuityLoss,
        watermark: FilesystemRepairWatermark = .recoveryRevision(1),
        participants: Set<FilesystemRepairParticipantToken>
    ) throws -> RepairGeneration {
        let completeParticipants = participants.union(
            makeRequiredParticipants(
                for: gate.registration.sourceID.kind,
                preservingKindsFrom: participants
            )
        )
        switch gate.recordRepair(
            trigger: trigger,
            watermark: watermark,
            participants: completeParticipants
        ) {
        case .admitted(let repair):
            return repair
        case .rejected(let reason):
            Issue.record("repair admission rejected: \(reason)")
        case .generationExhausted:
            Issue.record("repair generation unexpectedly exhausted")
        case .shuttingDown:
            Issue.record("repair admission unexpectedly reached shutdown")
        }
        throw TestFailure.repairNotAdmitted
    }

    private func makeRequiredParticipants(
        for sourceKind: FilesystemSourceKind,
        preservingKindsFrom existingParticipants: Set<FilesystemRepairParticipantToken> = []
    ) -> Set<FilesystemRepairParticipantToken> {
        let requiredKinds: Set<FilesystemRepairParticipantKind>
        switch sourceKind {
        case .watchedParentMembership:
            requiredKinds = [
                .scanScheduler,
                .canonicalTopologyCommit,
                .cacheAndPaneRemovalReconciliation,
                .filesystemSourceRegistrationSync,
                .currentGitBaseline,
            ]
        case .registeredWorktreeContent:
            requiredKinds = [
                .contentRepairProjector,
                .gitWorkingDirectoryProjector,
                .paneFilesystemProjection,
            ]
        }
        let existingKinds = Set(existingParticipants.map(\.kind))
        return Set(
            requiredKinds.subtracting(existingKinds).map {
                makeParticipant($0, generation: 1)
            }
        )
    }

    private func makeRegistration(
        kind: FilesystemSourceKind = .registeredWorktreeContent
    ) -> FSEventRegistrationToken {
        FSEventRegistrationToken(
            sourceID: FilesystemSourceID(
                kind: kind,
                rootID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
            ),
            registrationGeneration: 5,
            rootGeneration: 9
        )
    }

    private func makeParticipant(
        _ kind: FilesystemRepairParticipantKind,
        generation: UInt64
    ) -> FilesystemRepairParticipantToken {
        FilesystemRepairParticipantToken(
            kind: kind,
            participantID: UUID(),
            participantGeneration: generation
        )
    }

    private func makeAcknowledgement(
        _ repair: RepairGeneration,
        _ participant: FilesystemRepairParticipantToken
    ) -> FilesystemRepairAcknowledgementToken {
        FilesystemRepairAcknowledgementToken(
            repairGenerationID: repair.id,
            participant: participant
        )
    }

    private enum TestFailure: Error {
        case repairNotAdmitted
    }
}
