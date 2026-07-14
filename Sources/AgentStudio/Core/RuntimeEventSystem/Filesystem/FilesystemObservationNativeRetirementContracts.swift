import Foundation

struct FilesystemUnpublishedRetirementAuthority: Equatable, Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    init(value: UUID) {
        self.value = value
    }
}

struct FilesystemObservationContextReleaseAuthority: Equatable, Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    init(value: UUID) {
        self.value = value
    }
}

enum DarwinFSEventUnpublishedNativeCompletion: Equatable, Sendable {
    case creationAbandoned(DarwinFSEventRegistrationCreationAbandonment)
    case creationRejected(DarwinFSEventRegistrationCreateFailureCleanup)
    case createdNeverStartedClosed(DarwinFSEventCreatedNeverStartedQuiescence)
    case startRejectedAfterDrain(DarwinFSEventStartRejectedQuiescence)

    var startingNativeLifetime: FilesystemObservationStartingNativeLifetime {
        switch self {
        case .creationAbandoned(let abandonment):
            abandonment.startingNativeLifetime
        case .creationRejected(let cleanup):
            cleanup.startingNativeLifetime
        case .createdNeverStartedClosed(let quiescence):
            quiescence.startingNativeLifetime
        case .startRejectedAfterDrain(let quiescence):
            quiescence.startingNativeLifetime
        }
    }

    var finalizationKind: FilesystemObservationUnpublishedFinalizationKind {
        switch self {
        case .creationAbandoned:
            .neverMaterialized
        case .creationRejected, .createdNeverStartedClosed, .startRejectedAfterDrain:
            .retainedContext
        }
    }
}

enum FilesystemObservationUnpublishedFinalizationKind: Equatable, Sendable {
    case neverMaterialized
    case retainedContext
}

struct FilesystemObservationUnpublishedFinalReceipt: Equatable, Sendable {
    let retiringLifetime: FilesystemObservationRetiringUnpublishedNativeLifetime
    let completion: DarwinFSEventUnpublishedNativeCompletion
    let retirementAuthority: FilesystemUnpublishedRetirementAuthority

    var startingNativeLifetime: FilesystemObservationStartingNativeLifetime {
        retiringLifetime.startingNativeLifetime
    }

    var binding: FilesystemObservationSlotBinding {
        startingNativeLifetime.binding
    }
}

enum FilesystemObservationNativeRetirementPermit: Equatable, Sendable {
    case fenceBacked(FilesystemObservationSlotRetirementReceipt)
    case unpublished(FilesystemObservationUnpublishedFinalReceipt)

    var binding: FilesystemObservationSlotBinding {
        switch self {
        case .fenceBacked(let receipt):
            receipt.binding
        case .unpublished(let receipt):
            receipt.binding
        }
    }
}

struct FilesystemObservationReleasedContextFinalization: Equatable, Sendable {
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
}

struct FilesystemObservationNeverMaterializedFinalization: Equatable, Sendable {
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
}

struct FilesystemFenceContextReleaseAcknowledgement: Equatable, Sendable {
    let receipt: FilesystemObservationSlotRetirementReceipt
    let finalization: FilesystemObservationReleasedContextFinalization
    let releaseAuthority: FilesystemObservationContextReleaseAuthority

    var permit: FilesystemObservationNativeRetirementPermit { .fenceBacked(receipt) }
    var binding: FilesystemObservationSlotBinding { receipt.binding }
}

enum FilesystemUnpublishedReleaseAcknowledgement: Equatable, Sendable {
    case releasedRetainedContext(
        receipt: FilesystemObservationUnpublishedFinalReceipt,
        finalization: FilesystemObservationReleasedContextFinalization,
        releaseAuthority: FilesystemObservationContextReleaseAuthority
    )
    case neverMaterialized(
        receipt: FilesystemObservationUnpublishedFinalReceipt,
        finalization: FilesystemObservationNeverMaterializedFinalization,
        releaseAuthority: FilesystemObservationContextReleaseAuthority
    )

    var receipt: FilesystemObservationUnpublishedFinalReceipt {
        switch self {
        case .releasedRetainedContext(let receipt, _, _),
            .neverMaterialized(let receipt, _, _):
            receipt
        }
    }

    var releaseAuthority: FilesystemObservationContextReleaseAuthority {
        switch self {
        case .releasedRetainedContext(_, _, let authority),
            .neverMaterialized(_, _, let authority):
            authority
        }
    }

    var permit: FilesystemObservationNativeRetirementPermit { .unpublished(receipt) }
    var binding: FilesystemObservationSlotBinding { receipt.binding }
}

enum FilesystemObservationContextReleaseAcknowledgement: Equatable, Sendable {
    case fenceBacked(FilesystemFenceContextReleaseAcknowledgement)
    case unpublished(FilesystemUnpublishedReleaseAcknowledgement)

    var permit: FilesystemObservationNativeRetirementPermit {
        switch self {
        case .fenceBacked(let acknowledgement):
            acknowledgement.permit
        case .unpublished(let acknowledgement):
            acknowledgement.permit
        }
    }

    var binding: FilesystemObservationSlotBinding {
        switch self {
        case .fenceBacked(let acknowledgement):
            acknowledgement.binding
        case .unpublished(let acknowledgement):
            acknowledgement.binding
        }
    }

    var releaseAuthority: FilesystemObservationContextReleaseAuthority {
        switch self {
        case .fenceBacked(let acknowledgement):
            acknowledgement.releaseAuthority
        case .unpublished(let acknowledgement):
            acknowledgement.releaseAuthority
        }
    }
}

enum FilesystemObservationLastCompletedRelease: Equatable, Sendable {
    // swiftlint:disable:next discouraged_none_name
    case none
    case completed(FilesystemObservationContextReleaseAcknowledgement)
}

enum FilesystemObservationNativeFinalizationRejection: Equatable, Sendable {
    case bindingMismatch(
        expected: FilesystemObservationSlotBinding,
        presented: FilesystemObservationSlotBinding
    )
    case permitLineageMismatch
    case nativeLifetimeNotFinal
}

enum FilesystemObservationNativeFinalizationResult: Equatable, Sendable {
    case finalized(FilesystemObservationContextReleaseAcknowledgement)
    case alreadyFinalized(FilesystemObservationContextReleaseAcknowledgement)
    case rejected(FilesystemObservationNativeFinalizationRejection)
}

enum FilesystemObservationUnpublishedFinalReceiptResult: Equatable, Sendable {
    case finalized(FilesystemObservationUnpublishedFinalReceipt)
    case alreadyFinalized(FilesystemObservationUnpublishedFinalReceipt)
    case foreignFleet
    case undeclaredPhysicalSlot
    case bindingMismatch
    case completionMismatch
    case bindingLocalDebtRetained
    case awaitingPredecessor
    case invalidSlotState(FilesystemObservationPhysicalSlotState)
}

enum FilesystemFenceRetirementPermitResult: Equatable, Sendable {
    case issued(FilesystemObservationNativeRetirementPermit)
    case alreadyIssued(FilesystemObservationNativeRetirementPermit)
    case foreignFleet
    case undeclaredPhysicalSlot
    case receiptMismatch
    case invalidSlotState(FilesystemObservationPhysicalSlotState)
}

enum FilesystemObservationSuccessorReleaseDisposition: Equatable, Sendable {
    // swiftlint:disable:next discouraged_none_name
    case none
    case promoted(FilesystemRetirementFencePendingLifetime)
}

struct FilesystemObservationContextReleaseApplication: Equatable, Sendable {
    let acknowledgement: FilesystemObservationContextReleaseAcknowledgement
    let successorDisposition: FilesystemObservationSuccessorReleaseDisposition
}

enum FilesystemObservationContextReleaseApplyResult: Equatable, Sendable {
    case applied(FilesystemObservationContextReleaseApplication)
    case alreadyApplied(FilesystemObservationContextReleaseAcknowledgement)
    case foreignFleet
    case undeclaredPhysicalSlot
    case bindingMismatch
    case permitLineageMismatch
    case fenceMismatch
    case retirementAuthorityMismatch
    case releaseAuthorityMismatch
    case bindingLocalDebtRetained
    case staleBinding
    case invalidSlotState(FilesystemObservationPhysicalSlotState)
}

func filesystemObservationContextReleasePermitMismatch(
    expected: FilesystemObservationNativeRetirementPermit,
    presented: FilesystemObservationNativeRetirementPermit
) -> FilesystemObservationContextReleaseApplyResult {
    switch (expected, presented) {
    case (.fenceBacked(let expectedReceipt), .fenceBacked(let presentedReceipt)):
        guard expectedReceipt.binding == presentedReceipt.binding else {
            return .bindingMismatch
        }
        guard expectedReceipt.fenceIdentity == presentedReceipt.fenceIdentity else {
            return .fenceMismatch
        }
        guard expectedReceipt.retirementAuthority == presentedReceipt.retirementAuthority else {
            return .retirementAuthorityMismatch
        }
        return .permitLineageMismatch
    case (.unpublished(let expectedReceipt), .unpublished(let presentedReceipt)):
        guard expectedReceipt.binding == presentedReceipt.binding else {
            return .bindingMismatch
        }
        return .permitLineageMismatch
    case (.fenceBacked, .unpublished), (.unpublished, .fenceBacked):
        return .permitLineageMismatch
    }
}

protocol DarwinFSEventCallbackContextFinalizer: Sendable {
    func releaseRetainedContext(at pointerAddress: UInt)
}

struct DarwinFSEventUnmanagedCallbackContextFinalizer: DarwinFSEventCallbackContextFinalizer {
    func releaseRetainedContext(at pointerAddress: UInt) {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: pointerAddress) else {
            preconditionFailure("Retained callback context must have a nonzero pointer")
        }
        Unmanaged<DarwinFSEventRegistrationCallbackContext>
            .fromOpaque(pointer)
            .release()
    }
}
