import Foundation

struct FilesystemPendingContinuityRepairIdentity: Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    init(value: UUID) {
        self.value = value
    }
}

struct FilesystemContinuityRepairRevision: Hashable, Sendable {
    let value: UInt64
}

enum FilesystemPendingContinuityRepairCause: Hashable, Sendable {
    case nativeCreateOrStartFailure
}

struct FilesystemPendingContinuityRepairAuthority: Hashable, Sendable {
    let identity: FilesystemPendingContinuityRepairIdentity
    let desiredIdentity: FilesystemObservationDesiredIdentity
    let desiredConfiguration: FilesystemObservationSourceConfiguration
    let acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision
    let cause: FilesystemPendingContinuityRepairCause
    let recoveryRevision: FilesystemContinuityRepairRevision
    let requiredParticipantKinds: Set<FilesystemRepairParticipantKind>

    var sourceID: FilesystemSourceID { desiredConfiguration.sourceID }
}

struct FilesystemSourceRemovalAuthorityIdentity: Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    init(value: UUID) {
        self.value = value
    }
}

struct FilesystemSourceRemovalAuthority: Hashable, Sendable {
    let identity: FilesystemSourceRemovalAuthorityIdentity
    let exactPriorBinding: FilesystemObservationSlotBinding
    let acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision

    var sourceID: FilesystemSourceID {
        exactPriorBinding.registration.sourceID
    }
}

enum FilesystemContinuityRepairSuccessorDisposition: Hashable, Sendable {
    case sameDesired
    case superseded(FilesystemPendingContinuityRepairAuthority)
    case removed(FilesystemSourceRemovalAuthority)
}

struct FilesystemContinuityRepairHandoff: Hashable, Sendable {
    let pendingAuthority: FilesystemPendingContinuityRepairAuthority
    let authority: FilesystemContinuityRepairHandoffAuthority
    let successorDisposition: FilesystemContinuityRepairSuccessorDisposition
}

enum FilesystemPendingContinuityRepairState: Equatable, Sendable {
    case absent
    case pending(FilesystemPendingContinuityRepairAuthority)
    case handoffInFlight(FilesystemContinuityRepairHandoff)
}

enum FilesystemContinuityRepairHandoffPreparationResult: Equatable, Sendable {
    case prepared(FilesystemContinuityRepairHandoff)
    case replayed(FilesystemContinuityRepairHandoff)
    case absent
    case bindingMismatch
    case desiredIdentityMismatch
}

enum FilesystemContinuityRepairHandoffAcknowledgement: Equatable, Sendable {
    case sameDesired(
        handoff: FilesystemContinuityRepairHandoff,
        acceptance: FilesystemSourceGateContinuityRepairAcceptance
    )
    case superseded(
        handoff: FilesystemContinuityRepairHandoff,
        acceptance: FilesystemSourceGateContinuityRepairAcceptance,
        successorAuthority: FilesystemPendingContinuityRepairAuthority
    )
    case removed(
        handoff: FilesystemContinuityRepairHandoff,
        acceptance: FilesystemSourceGateContinuityRepairAcceptance,
        removalAuthority: FilesystemSourceRemovalAuthority
    )
}

enum FilesystemRepairHandoffAcknowledgementResult: Equatable, Sendable {
    case acknowledged(FilesystemContinuityRepairHandoffAcknowledgement)
    case alreadyAcknowledged(FilesystemContinuityRepairHandoffAcknowledgement)
    case bindingMismatch
    case staleAcceptance
    case absent
}

enum FilesystemContinuityRepairCustodyState: Equatable, Sendable {
    case absent
    case pending(FilesystemPendingContinuityRepairAuthority)
    case handoffInFlight(FilesystemContinuityRepairHandoff)
    case acknowledged(
        FilesystemContinuityRepairHandoffAcknowledgement,
        successor: FilesystemContinuityRepairAcknowledgedSuccessor
    )

    var projectedState: FilesystemPendingContinuityRepairState {
        switch self {
        case .absent, .acknowledged(_, .noSuccessor):
            .absent
        case .pending(let authority), .acknowledged(_, .pending(let authority)):
            .pending(authority)
        case .handoffInFlight(let handoff):
            .handoffInFlight(handoff)
        }
    }
}

enum FilesystemContinuityRepairAcknowledgedSuccessor: Equatable, Sendable {
    case noSuccessor
    case pending(FilesystemPendingContinuityRepairAuthority)
}
