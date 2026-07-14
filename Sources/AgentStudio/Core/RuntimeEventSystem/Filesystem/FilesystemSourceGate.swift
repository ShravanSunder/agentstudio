import Foundation

enum FilesystemRepairTriggerClass: Equatable, Sendable {
    case continuityLoss
    case callbackGateOverflow
    case captureTruncation
    case rootIdentityChanged
    case registrationReplaced
    case unsupportedFlags
}

enum FilesystemRepairWatermark: Equatable, Sendable {
    case eventIDs(FSEventIDWatermark)
    case recoveryRevision(UInt64)
    case eventIDsAndRecoveryRevision(FSEventIDWatermark, recoveryRevision: UInt64)
}

enum FilesystemRepairParticipantKind: Hashable, Sendable {
    case scanScheduler
    case canonicalTopologyCommit
    case cacheAndPaneRemovalReconciliation
    case filesystemSourceRegistrationSync
    case currentGitBaseline
    case registrationOwner
    case contentRepairProjector
    case gitWorkingDirectoryProjector
    case paneFilesystemProjection
    case contentConsumer
}

struct FilesystemRepairParticipantToken: Hashable, Sendable {
    let kind: FilesystemRepairParticipantKind
    let participantID: UUID
    let participantGeneration: UInt64
}

struct RepairGenerationID: Hashable, Sendable {
    let registration: FSEventRegistrationToken
    let sequence: UInt64
}

struct RepairGeneration: Equatable, Sendable {
    let id: RepairGenerationID
    let watermark: FilesystemRepairWatermark
    let trigger: FilesystemRepairTriggerClass
    let participants: Set<FilesystemRepairParticipantToken>
}

struct FilesystemRepairAcknowledgementToken: Hashable, Sendable {
    let repairGenerationID: RepairGenerationID
    let participant: FilesystemRepairParticipantToken
}

struct AwaitingFilesystemRepairAcknowledgements: Equatable, Sendable {
    let generation: RepairGeneration
    let pendingParticipants: Set<FilesystemRepairParticipantToken>
}

enum FilesystemReconciliationFailure: Equatable, Sendable {
    case authoritativeScanFailed
    case authoritativeResultPartial
    case authoritativeResultRejected
}

struct FailedFilesystemRepair: Equatable, Sendable {
    let failedGeneration: RepairGeneration
    let retryGeneration: RepairGeneration
    let failure: FilesystemReconciliationFailure
}

enum FilesystemRepairAcknowledgementFailure: Equatable, Sendable {
    case currentnessApplyFailed
    case staleParticipantState
    case participantRejected
}

enum FilesystemSourceGateShutdownDebt: Equatable, Sendable {
    case noOutstandingRepair
    case dirty(RepairGeneration)
    case reconciling(RepairGeneration)
    case reconcilingAndDirty(active: RepairGeneration, pending: RepairGeneration)
    case awaitingAcknowledgements(AwaitingFilesystemRepairAcknowledgements)
    case repairFailed(FailedFilesystemRepair)
}

struct FilesystemSourceGateShutdown: Equatable, Sendable {
    let registration: FSEventRegistrationToken
    let debt: FilesystemSourceGateShutdownDebt
}

enum FilesystemSourceGateState: Equatable, Sendable {
    case healthy(FSEventRegistrationToken)
    case dirty(RepairGeneration)
    case reconciling(RepairGeneration)
    case reconcilingAndDirty(active: RepairGeneration, pending: RepairGeneration)
    case awaitingAcknowledgements(AwaitingFilesystemRepairAcknowledgements)
    case repairFailed(FailedFilesystemRepair)
    case shuttingDown(FilesystemSourceGateShutdown)
}

enum FilesystemRepairAdmissionRejection: Equatable, Sendable {
    case emptyParticipantSet
    case participantsNotApplicableToSource(Set<FilesystemRepairParticipantToken>)
    case missingRequiredParticipantKinds(Set<FilesystemRepairParticipantKind>)
}

enum FilesystemRepairAdmissionResult: Equatable, Sendable {
    case admitted(RepairGeneration)
    case rejected(FilesystemRepairAdmissionRejection)
    case generationExhausted
    case shuttingDown
}

/// Proof that one exact mailbox recovery snapshot entered this source gate.
///
/// Only `FilesystemSourceGate` can construct this value. The mailbox accepts it
/// only when it matches the recovery snapshot held by the active drain lease.
struct FilesystemSourceGateRecoveryAcceptance: Equatable, Sendable {
    let repairGeneration: RepairGeneration
    let acceptedEvidence: FixedFilesystemRecoveryEvidenceSnapshot

    fileprivate init(
        acceptedEvidence: FixedFilesystemRecoveryEvidenceSnapshot,
        repairGeneration: RepairGeneration
    ) {
        self.acceptedEvidence = acceptedEvidence
        self.repairGeneration = repairGeneration
    }

    func matches(_ evidence: FixedFilesystemRecoveryEvidenceSnapshot) -> Bool {
        acceptedEvidence == evidence
    }
}

enum FilesystemSourceGateRecoveryAdmissionResult: Equatable, Sendable {
    case admitted(FilesystemSourceGateRecoveryAcceptance)
    case bindingMismatch
    case retainedRequestConflict(FilesystemSourceGateRecoveryRequestConflict)
    case rejected(FilesystemRepairAdmissionRejection)
    case generationExhausted
    case shuttingDown
}

struct FilesystemSourceGateTransferClearReceipt: Equatable, Sendable {
    fileprivate let authority: FilesystemObservationWholeLeaseTransferAuthority
    fileprivate let acknowledgement: FilesystemLeaseAcknowledgementReceipt
    let acceptedEvidenceRevision: FixedFilesystemRecoveryEvidenceRevision
    fileprivate let repairGenerationID: RepairGenerationID

    var binding: FilesystemObservationSlotBinding { authority.binding }

    func matches(
        authority expectedAuthority: FilesystemObservationWholeLeaseTransferAuthority,
        acknowledgement expectedAcknowledgement: FilesystemLeaseAcknowledgementReceipt
    ) -> Bool {
        authority == expectedAuthority
            && acknowledgement == expectedAcknowledgement
            && expectedAcknowledgement.matches(expectedAuthority)
    }
}

enum FilesystemSourceGateTransferClearCompletion: Equatable, Sendable {
    case notRequired(FilesystemObservationSlotBinding)
    case cleared(FilesystemSourceGateTransferClearReceipt)

    var binding: FilesystemObservationSlotBinding {
        switch self {
        case .notRequired(let binding): binding
        case .cleared(let receipt): receipt.binding
        }
    }
}

enum FilesystemSourceGateTransferClearResult: Equatable, Sendable {
    case cleared(FilesystemSourceGateTransferClearReceipt)
    case acknowledgementMismatch
    case authorityHasNoRecoveryCustody
    case acceptanceMismatch
    case noRetainedRecovery
}

enum FilesystemSourceGateRecoveryRequestMismatch: Hashable, Sendable {
    case evidence
    case trigger
    case watermark
    case participants
}

struct FilesystemSourceGateRecoveryRequestConflict: Equatable, Sendable {
    let mismatches: Set<FilesystemSourceGateRecoveryRequestMismatch>

    fileprivate init(mismatches: Set<FilesystemSourceGateRecoveryRequestMismatch>) {
        precondition(!mismatches.isEmpty, "a retained recovery request conflict must differ")
        self.mismatches = mismatches
    }
}

enum FilesystemSourceGateTransitionResult: Equatable, Sendable {
    case applied
    case alreadyApplied
    case staleGeneration
    case unknownParticipant(FilesystemRepairParticipantToken)
    case invalidState(FilesystemSourceGateState)
    case shuttingDown
}

struct FilesystemSourceGate: Sendable {
    private enum MailboxRecoveryRequestComparison: Equatable, Sendable {
        case identical
        case conflict(FilesystemSourceGateRecoveryRequestConflict)
    }

    private struct MailboxRecoveryRequest: Equatable, Sendable {
        let evidence: FixedFilesystemRecoveryEvidenceSnapshot
        let trigger: FilesystemRepairTriggerClass
        let watermark: FilesystemRepairWatermark
        let participants: Set<FilesystemRepairParticipantToken>

        func compare(
            with retainedRequest: Self
        ) -> MailboxRecoveryRequestComparison {
            var mismatches: Set<FilesystemSourceGateRecoveryRequestMismatch> = []
            if evidence != retainedRequest.evidence { mismatches.insert(.evidence) }
            if trigger != retainedRequest.trigger { mismatches.insert(.trigger) }
            if watermark != retainedRequest.watermark { mismatches.insert(.watermark) }
            if participants != retainedRequest.participants { mismatches.insert(.participants) }
            guard !mismatches.isEmpty else { return .identical }
            return .conflict(FilesystemSourceGateRecoveryRequestConflict(mismatches: mismatches))
        }
    }

    private struct RetainedMailboxRecovery: Equatable, Sendable {
        let request: MailboxRecoveryRequest
        let acceptance: FilesystemSourceGateRecoveryAcceptance
    }

    private enum MailboxRecoveryReplayShell: Equatable, Sendable {
        case vacant
        case retained(RetainedMailboxRecovery)
    }

    let binding: FilesystemObservationSlotBinding
    var registration: FSEventRegistrationToken { binding.registration }
    private(set) var state: FilesystemSourceGateState
    private var nextRepairSequence: UInt64
    private var mailboxRecoveryReplay: MailboxRecoveryReplayShell

    init(binding: FilesystemObservationSlotBinding) {
        self.binding = binding
        state = .healthy(binding.registration)
        nextRepairSequence = 0
        mailboxRecoveryReplay = .vacant
    }

    mutating func acceptMailboxRecovery(
        _ evidence: FixedFilesystemRecoveryEvidenceSnapshot,
        trigger: FilesystemRepairTriggerClass,
        watermark: FilesystemRepairWatermark,
        participants: Set<FilesystemRepairParticipantToken>
    ) -> FilesystemSourceGateRecoveryAdmissionResult {
        guard evidence.revision.binding == binding else {
            return .bindingMismatch
        }
        let request = MailboxRecoveryRequest(
            evidence: evidence,
            trigger: trigger,
            watermark: watermark,
            participants: participants
        )
        switch mailboxRecoveryReplay {
        case .vacant:
            break
        case .retained(let retained):
            switch request.compare(with: retained.request) {
            case .identical:
                return .admitted(retained.acceptance)
            case .conflict(let conflict):
                return .retainedRequestConflict(conflict)
            }
        }
        switch recordRepair(
            trigger: trigger,
            watermark: watermark,
            participants: participants
        ) {
        case .admitted(let repairGeneration):
            let acceptance = FilesystemSourceGateRecoveryAcceptance(
                acceptedEvidence: evidence,
                repairGeneration: repairGeneration
            )
            mailboxRecoveryReplay = .retained(
                RetainedMailboxRecovery(request: request, acceptance: acceptance)
            )
            return .admitted(acceptance)
        case .rejected(let rejection):
            return .rejected(rejection)
        case .generationExhausted:
            return .generationExhausted
        case .shuttingDown:
            return .shuttingDown
        }
    }

    mutating func clearTransferredMailboxRecovery(
        authority: FilesystemObservationWholeLeaseTransferAuthority,
        acknowledgement: FilesystemLeaseAcknowledgementReceipt
    ) -> FilesystemSourceGateTransferClearResult {
        guard acknowledgement.matches(authority) else {
            return .acknowledgementMismatch
        }
        let acceptance: FilesystemSourceGateRecoveryAcceptance
        switch authority.evidence {
        case .contributionsWithRecovery(_, let recoveryAcceptance),
            .recovery(let recoveryAcceptance):
            acceptance = recoveryAcceptance
        case .contributions:
            return .authorityHasNoRecoveryCustody
        }
        guard authority.binding == binding,
            acceptance.acceptedEvidence.revision.binding == binding
        else {
            return .acceptanceMismatch
        }
        guard case .retained(let retained) = mailboxRecoveryReplay else {
            return .noRetainedRecovery
        }
        guard retained.acceptance == acceptance else {
            return .acceptanceMismatch
        }
        mailboxRecoveryReplay = .vacant
        return .cleared(
            FilesystemSourceGateTransferClearReceipt(
                authority: authority,
                acknowledgement: acknowledgement,
                acceptedEvidenceRevision: acceptance.acceptedEvidence.revision,
                repairGenerationID: acceptance.repairGeneration.id
            )
        )
    }

    mutating func recordRepair(
        trigger: FilesystemRepairTriggerClass,
        watermark: FilesystemRepairWatermark,
        participants: Set<FilesystemRepairParticipantToken>
    ) -> FilesystemRepairAdmissionResult {
        if case .shuttingDown = state { return .shuttingDown }
        guard !participants.isEmpty else { return .rejected(.emptyParticipantSet) }
        let incompatibleParticipants = Set(
            participants.filter { !$0.kind.isApplicable(to: registration.sourceID.kind) }
        )
        if !incompatibleParticipants.isEmpty {
            return .rejected(.participantsNotApplicableToSource(incompatibleParticipants))
        }
        let presentParticipantKinds = Set(participants.map(\.kind))
        let missingParticipantKinds = FilesystemRepairParticipantKind.requiredKinds(
            for: registration.sourceID.kind,
            trigger: trigger
        ).subtracting(presentParticipantKinds)
        if !missingParticipantKinds.isEmpty {
            return .rejected(.missingRequiredParticipantKinds(missingParticipantKinds))
        }
        let sequence = nextRepairSequence
        let (followingSequence, overflow) = sequence.addingReportingOverflow(1)
        guard !overflow else { return .generationExhausted }
        let repair = RepairGeneration(
            id: RepairGenerationID(registration: registration, sequence: sequence),
            watermark: watermark,
            trigger: trigger,
            participants: participants
        )
        nextRepairSequence = followingSequence
        admit(repair)
        return .admitted(repair)
    }

    mutating func beginReconciliation(
        _ generationID: RepairGenerationID
    ) -> FilesystemSourceGateTransitionResult {
        switch state {
        case .dirty(let repair) where repair.id == generationID:
            state = .reconciling(repair)
            return .applied
        case .repairFailed(let failure) where failure.retryGeneration.id == generationID:
            state = .reconciling(failure.retryGeneration)
            return .applied
        case .dirty, .repairFailed:
            return .staleGeneration
        case .shuttingDown:
            return .shuttingDown
        case .healthy, .reconciling, .reconcilingAndDirty, .awaitingAcknowledgements:
            return .invalidState(state)
        }
    }

    mutating func completeReconciliation(
        _ generationID: RepairGenerationID
    ) -> FilesystemSourceGateTransitionResult {
        switch state {
        case .reconciling(let repair) where repair.id == generationID:
            state = .awaitingAcknowledgements(
                AwaitingFilesystemRepairAcknowledgements(
                    generation: repair,
                    pendingParticipants: repair.participants
                )
            )
            return .applied
        case .reconcilingAndDirty(let active, let pending) where active.id == generationID:
            state = .dirty(pending)
            return .applied
        case .reconciling, .reconcilingAndDirty:
            return .staleGeneration
        case .shuttingDown:
            return .shuttingDown
        case .healthy, .dirty, .awaitingAcknowledgements, .repairFailed:
            return .invalidState(state)
        }
    }

    mutating func failReconciliation(
        _ generationID: RepairGenerationID,
        failure: FilesystemReconciliationFailure
    ) -> FilesystemSourceGateTransitionResult {
        switch state {
        case .reconciling(let repair) where repair.id == generationID:
            state = .repairFailed(
                FailedFilesystemRepair(
                    failedGeneration: repair,
                    retryGeneration: repair,
                    failure: failure
                )
            )
            return .applied
        case .reconcilingAndDirty(let active, let pending) where active.id == generationID:
            state = .repairFailed(
                FailedFilesystemRepair(
                    failedGeneration: active,
                    retryGeneration: pending,
                    failure: failure
                )
            )
            return .applied
        case .reconciling, .reconcilingAndDirty:
            return .staleGeneration
        case .shuttingDown:
            return .shuttingDown
        case .healthy, .dirty, .awaitingAcknowledgements, .repairFailed:
            return .invalidState(state)
        }
    }

    mutating func acknowledge(
        _ token: FilesystemRepairAcknowledgementToken
    ) -> FilesystemSourceGateTransitionResult {
        switch state {
        case .awaitingAcknowledgements(let awaiting):
            guard awaiting.generation.id == token.repairGenerationID else {
                return .staleGeneration
            }
            guard awaiting.generation.participants.contains(token.participant) else {
                return .unknownParticipant(token.participant)
            }
            guard awaiting.pendingParticipants.contains(token.participant) else {
                return .alreadyApplied
            }
            var remaining = awaiting.pendingParticipants
            remaining.remove(token.participant)
            if remaining.isEmpty {
                state = .healthy(registration)
            } else {
                state = .awaitingAcknowledgements(
                    AwaitingFilesystemRepairAcknowledgements(
                        generation: awaiting.generation,
                        pendingParticipants: remaining
                    )
                )
            }
            return .applied
        case .shuttingDown:
            return .shuttingDown
        case .healthy, .dirty, .reconciling, .reconcilingAndDirty, .repairFailed:
            return .invalidState(state)
        }
    }

    mutating func rejectAcknowledgement(
        _ token: FilesystemRepairAcknowledgementToken,
        failure _: FilesystemRepairAcknowledgementFailure
    ) -> FilesystemSourceGateTransitionResult {
        switch state {
        case .awaitingAcknowledgements(let awaiting):
            guard awaiting.generation.id == token.repairGenerationID else {
                return .staleGeneration
            }
            guard awaiting.pendingParticipants.contains(token.participant) else {
                if awaiting.generation.participants.contains(token.participant) {
                    return .alreadyApplied
                }
                return .unknownParticipant(token.participant)
            }
            state = .dirty(awaiting.generation)
            return .applied
        case .shuttingDown:
            return .shuttingDown
        case .healthy, .dirty, .reconciling, .reconcilingAndDirty, .repairFailed:
            return .invalidState(state)
        }
    }

    mutating func beginShutdown() -> FilesystemSourceGateTransitionResult {
        switch state {
        case .shuttingDown:
            return .alreadyApplied
        case .healthy:
            state = .shuttingDown(
                FilesystemSourceGateShutdown(
                    registration: registration,
                    debt: .noOutstandingRepair
                )
            )
        case .dirty(let repair):
            state = .shuttingDown(
                FilesystemSourceGateShutdown(registration: registration, debt: .dirty(repair))
            )
        case .reconciling(let repair):
            state = .shuttingDown(
                FilesystemSourceGateShutdown(
                    registration: registration,
                    debt: .reconciling(repair)
                )
            )
        case .reconcilingAndDirty(let active, let pending):
            state = .shuttingDown(
                FilesystemSourceGateShutdown(
                    registration: registration,
                    debt: .reconcilingAndDirty(active: active, pending: pending)
                )
            )
        case .awaitingAcknowledgements(let awaiting):
            state = .shuttingDown(
                FilesystemSourceGateShutdown(
                    registration: registration,
                    debt: .awaitingAcknowledgements(awaiting)
                )
            )
        case .repairFailed(let failure):
            state = .shuttingDown(
                FilesystemSourceGateShutdown(
                    registration: registration,
                    debt: .repairFailed(failure)
                )
            )
        }
        return .applied
    }

    private mutating func admit(_ repair: RepairGeneration) {
        switch state {
        case .healthy, .dirty, .awaitingAcknowledgements, .repairFailed:
            state = .dirty(repair)
        case .reconciling(let active):
            state = .reconcilingAndDirty(active: active, pending: repair)
        case .reconcilingAndDirty(let active, _):
            state = .reconcilingAndDirty(active: active, pending: repair)
        case .shuttingDown:
            preconditionFailure("shutdown was checked before repair generation allocation")
        }
    }
}

extension FilesystemRepairParticipantKind {
    fileprivate static func requiredKinds(
        for sourceKind: FilesystemSourceKind,
        trigger: FilesystemRepairTriggerClass
    ) -> Set<Self> {
        var requiredKinds: Set<Self>
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
        switch trigger {
        case .rootIdentityChanged, .registrationReplaced:
            requiredKinds.insert(.registrationOwner)
        case .continuityLoss, .callbackGateOverflow, .captureTruncation, .unsupportedFlags:
            break
        }
        return requiredKinds
    }

    fileprivate func isApplicable(to sourceKind: FilesystemSourceKind) -> Bool {
        switch (sourceKind, self) {
        case (.watchedParentMembership, .scanScheduler),
            (.watchedParentMembership, .canonicalTopologyCommit),
            (.watchedParentMembership, .cacheAndPaneRemovalReconciliation),
            (.watchedParentMembership, .filesystemSourceRegistrationSync),
            (.watchedParentMembership, .currentGitBaseline),
            (.watchedParentMembership, .registrationOwner),
            (.registeredWorktreeContent, .registrationOwner),
            (.registeredWorktreeContent, .contentRepairProjector),
            (.registeredWorktreeContent, .gitWorkingDirectoryProjector),
            (.registeredWorktreeContent, .paneFilesystemProjection),
            (.registeredWorktreeContent, .contentConsumer):
            true
        case (.watchedParentMembership, .contentRepairProjector),
            (.watchedParentMembership, .gitWorkingDirectoryProjector),
            (.watchedParentMembership, .paneFilesystemProjection),
            (.watchedParentMembership, .contentConsumer),
            (.registeredWorktreeContent, .scanScheduler),
            (.registeredWorktreeContent, .canonicalTopologyCommit),
            (.registeredWorktreeContent, .cacheAndPaneRemovalReconciliation),
            (.registeredWorktreeContent, .filesystemSourceRegistrationSync),
            (.registeredWorktreeContent, .currentGitBaseline):
            false
        }
    }
}
