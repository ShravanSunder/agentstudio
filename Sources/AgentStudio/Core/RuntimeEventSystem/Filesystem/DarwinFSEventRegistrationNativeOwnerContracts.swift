import Foundation

enum DarwinFSEventNativeOwnerAuthorityRejection: Equatable, Sendable {
    case bindingMismatch(
        expected: FilesystemObservationSlotBinding,
        presented: FilesystemObservationSlotBinding
    )
    case startingNativeLifetimeMismatch(
        expected: FilesystemObservationStartingNativeLifetime,
        presented: FilesystemObservationStartingNativeLifetime
    )
    case callbackAdapterControlBlockMismatch(
        expected: FilesystemObservationControlBlockIdentity,
        presented: FilesystemObservationControlBlockIdentity
    )
    case creationCompletionMismatch(
        expected: FilesystemObservationStartingNativeLifetime,
        presented: FilesystemObservationStartingNativeLifetime
    )
    case creationRightUnavailable(FilesystemObservationStartingNativeLifetime)
}

final class DarwinFSEventRegistrationCreationAbandonment: @unchecked Sendable, Equatable {
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime

    init(startingNativeLifetime: FilesystemObservationStartingNativeLifetime) {
        self.startingNativeLifetime = startingNativeLifetime
    }

    static func == (
        lhs: DarwinFSEventRegistrationCreationAbandonment,
        rhs: DarwinFSEventRegistrationCreationAbandonment
    ) -> Bool {
        lhs === rhs
    }
}

enum DarwinFSEventNativeOwnerCreationResult: Sendable {
    case created(DarwinFSEventRegistrationGeneration)
    case creationRejected(DarwinFSEventRegistrationCreateFailureCleanup)
    case creationAbandoned(DarwinFSEventRegistrationCreationAbandonment)
    case authorityRejected(DarwinFSEventNativeOwnerAuthorityRejection)
}

enum DarwinFSEventNativeFinalizationSnapshot: Equatable, Sendable {
    case pending
    case finalized(FilesystemObservationContextReleaseAcknowledgement)
}

enum DarwinFSEventNativeRetirementPermitRetentionResult: Equatable, Sendable {
    case retained
    case alreadyRetained
    case bindingMismatch(
        expected: FilesystemObservationSlotBinding,
        presented: FilesystemObservationSlotBinding
    )
    case permitLineageMismatch
    case nativeLifetimeNotFinal
}

final class DarwinFSEventCreatedNeverStartedQuiescence: @unchecked Sendable, Equatable {
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime

    init(startingNativeLifetime: FilesystemObservationStartingNativeLifetime) {
        self.startingNativeLifetime = startingNativeLifetime
    }

    static func == (
        lhs: DarwinFSEventCreatedNeverStartedQuiescence,
        rhs: DarwinFSEventCreatedNeverStartedQuiescence
    ) -> Bool {
        lhs === rhs
    }
}

final class DarwinFSEventStartRejectedQuiescence: @unchecked Sendable, Equatable {
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let cleanup: DarwinFSEventRegistrationStartFailureCleanup

    init(
        startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        cleanup: DarwinFSEventRegistrationStartFailureCleanup
    ) {
        self.startingNativeLifetime = startingNativeLifetime
        self.cleanup = cleanup
    }

    static func == (
        lhs: DarwinFSEventStartRejectedQuiescence,
        rhs: DarwinFSEventStartRejectedQuiescence
    ) -> Bool {
        lhs === rhs
    }
}

enum DarwinFSEventUnpublishedQuiescence: Sendable {
    case createdNeverStartedClosed(DarwinFSEventCreatedNeverStartedQuiescence)
    case startRejectedAfterDrain(DarwinFSEventStartRejectedQuiescence)
}

enum DarwinFSEventNativeOwnerLifecycleRejection: Equatable, Sendable {
    case generationPhase(DarwinFSEventRegistrationGenerationPhase)
    case mailboxClosing(FilesystemObservationCallbackLeaseDrainClosingResult)
    case closeAlreadyInProgress
}

enum DarwinFSEventNativeOwnerFleetShutdownCompletion: Equatable, Sendable {
    case unpublished(DarwinFSEventUnpublishedNativeCompletion)
    case acceptingGenerationClosed(DarwinFSEventRegistrationLeaseDrainReceipt)
}

enum DarwinFSEventNativeOwnerFleetShutdownDebt: Equatable, Sendable {
    case acceptingPublicationPending(FilesystemObservationAcceptingPublicationResult)
    case nativeAuthorityRejected(
        DarwinFSEventNativeOwnerAuthorityRejection,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
    case nativeLifecycleRejected(
        DarwinFSEventNativeOwnerLifecycleRejection,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
}

enum DarwinFSEventNativeOwnerFleetShutdownResult: Equatable, Sendable {
    case completed(DarwinFSEventNativeOwnerFleetShutdownCompletion)
    case incomplete(DarwinFSEventNativeOwnerFleetShutdownDebt)
}

/// Payload-free correlation for one native generation during fleet shutdown.
///
/// The binding identifies the fixed-slot lineage without retaining desired configuration or a
/// canonical root. The native generation identity correlates owner-local phase transitions.
struct FilesystemObservationNativeShutdownReference: Equatable, Sendable {
    let binding: FilesystemObservationSlotBinding
    let nativeGenerationIdentity: FilesystemObservationNativeGenerationIdentity
}

enum DarwinNativeOwnerShutdownCompletionReference: Equatable, Sendable {
    case creationAbandoned(FilesystemObservationNativeShutdownReference)
    case creationRejected(
        FilesystemObservationNativeShutdownReference,
        DarwinFSEventNativeStreamCreationFailure
    )
    case createdNeverStartedClosed(FilesystemObservationNativeShutdownReference)
    case startRejectedAfterDrain(FilesystemObservationNativeShutdownReference)
    case acceptingGenerationClosed(FilesystemObservationNativeShutdownReference)
}

extension DarwinFSEventNativeOwnerFleetShutdownCompletion {
    var shutdownReference: DarwinNativeOwnerShutdownCompletionReference {
        switch self {
        case .unpublished(let completion):
            let reference = FilesystemObservationNativeShutdownReference(
                binding: completion.startingNativeLifetime.binding,
                nativeGenerationIdentity: completion.startingNativeLifetime
                    .nativeGenerationIdentity
            )
            switch completion {
            case .creationAbandoned:
                return .creationAbandoned(reference)
            case .creationRejected(let cleanup):
                return .creationRejected(reference, cleanup.nativeFailure)
            case .createdNeverStartedClosed:
                return .createdNeverStartedClosed(reference)
            case .startRejectedAfterDrain:
                return .startRejectedAfterDrain(reference)
            }
        case .acceptingGenerationClosed(let receipt):
            return .acceptingGenerationClosed(
                FilesystemObservationNativeShutdownReference(
                    binding: receipt.binding,
                    nativeGenerationIdentity: receipt.nativeGenerationIdentity
                )
            )
        }
    }
}

enum DarwinAcceptingPublicationShutdownRejection: Equatable, Sendable {
    case foreignFleet
    case undeclaredPhysicalSlot
    case startingNativeLifetimeMismatch(FilesystemObservationNativeShutdownReference)
    case invalidSlotState
    case mailboxReleased
}

enum DarwinFSEventNativeOwnerAuthorityShutdownRejection: Equatable, Sendable {
    case bindingMismatch(
        expected: FilesystemObservationSlotBinding,
        presented: FilesystemObservationSlotBinding
    )
    case startingNativeLifetimeMismatch(
        expected: FilesystemObservationNativeShutdownReference,
        presented: FilesystemObservationNativeShutdownReference
    )
    case callbackAdapterControlBlockMismatch(
        expected: FilesystemObservationControlBlockIdentity,
        presented: FilesystemObservationControlBlockIdentity
    )
    case creationCompletionMismatch(
        expected: FilesystemObservationNativeShutdownReference,
        presented: FilesystemObservationNativeShutdownReference
    )
    case creationRightUnavailable(FilesystemObservationNativeShutdownReference)
}

enum DarwinFSEventNativeOwnerLifecycleShutdownRejection: Equatable, Sendable {
    case generationPhase(DarwinFSEventRegistrationGenerationPhase)
    case mailboxClosing
    case closeAlreadyInProgress
}

enum DarwinFSEventNativeOwnerFleetShutdownNativePhase: Equatable, Sendable {
    case creationAvailable(FilesystemObservationNativeShutdownReference)
    case creating(FilesystemObservationNativeShutdownReference)
    case created(
        FilesystemObservationNativeShutdownReference,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
    case starting(
        FilesystemObservationNativeShutdownReference,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
    case abandoningStart(
        FilesystemObservationNativeShutdownReference,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
    case publishingAcceptance(
        FilesystemObservationNativeShutdownReference,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
    case acceptingPublicationPending(
        FilesystemObservationNativeShutdownReference,
        DarwinAcceptingPublicationShutdownRejection,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
    case creationRejected(
        FilesystemObservationNativeShutdownReference,
        DarwinFSEventNativeStreamCreationFailure
    )
    case creationAbandoned(FilesystemObservationNativeShutdownReference)
    case createdNeverStartedClosed(FilesystemObservationNativeShutdownReference)
    case startRejectedAfterDrain(FilesystemObservationNativeShutdownReference)
    case accepting(
        FilesystemObservationNativeShutdownReference,
        callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
    case authorityRejected(
        FilesystemObservationNativeShutdownReference,
        DarwinFSEventNativeOwnerAuthorityShutdownRejection,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
    case lifecycleRejected(
        FilesystemObservationNativeShutdownReference,
        DarwinFSEventNativeOwnerLifecycleShutdownRejection,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
}

enum DarwinNativeFleetShutdownRetirementReference: Equatable, Sendable {
    case fenceBacked(
        fenceIdentity: FilesystemObservationRetirementFenceIdentity,
        disposition: FilesystemObservationSlotRetirementDisposition,
        retirementAuthority: FilesystemObservationSlotRetirementAuthority
    )
    case unpublished(
        retirementAuthority: FilesystemUnpublishedRetirementAuthority,
        finalizationKind: FilesystemObservationUnpublishedFinalizationKind
    )
}

enum DarwinNativeFleetShutdownFinalizationPhase: Equatable, Sendable {
    case awaitingMaterialization(FilesystemObservationNativeShutdownReference)
    case retainedContext(FilesystemObservationNativeShutdownReference)
    case retirementPermitRetained(
        FilesystemObservationNativeShutdownReference,
        DarwinNativeFleetShutdownRetirementReference
    )
    case finalizing(
        FilesystemObservationNativeShutdownReference,
        DarwinNativeFleetShutdownRetirementReference
    )
    case finalized(
        FilesystemObservationNativeShutdownReference,
        DarwinNativeFleetShutdownRetirementReference,
        releaseAuthority: FilesystemObservationContextReleaseAuthority
    )
}

enum DarwinNativeOwnerCallbackDrainProjection: Equatable, Sendable {
    case notMaterialized
    case materialized(
        lifecycle: FSEventRegistrationLifecycleSnapshot,
        leaseDrainCompletion: FSEventCallbackLeaseDrainCompletionSnapshot
    )
}

enum DarwinFSEventNativeOwnerFleetShutdownAdvancePhase: Equatable, Sendable {
    case available
    case inFlight
    case completed(DarwinNativeOwnerShutdownCompletionReference)
}

struct DarwinFSEventNativeOwnerFleetShutdownProjection: Equatable, Sendable {
    let binding: FilesystemObservationSlotBinding
    let nativePhase: DarwinFSEventNativeOwnerFleetShutdownNativePhase
    let callbackDrain: DarwinNativeOwnerCallbackDrainProjection
    let finalizationPhase: DarwinNativeFleetShutdownFinalizationPhase
    let advancePhase: DarwinFSEventNativeOwnerFleetShutdownAdvancePhase
}

enum DarwinFSEventNativeOwnerStartResult: Sendable {
    case started(FilesystemObservationAcceptingNativeLifetime)
    case unpublished(DarwinFSEventUnpublishedQuiescence)
    case acceptingPublicationRejected(FilesystemObservationAcceptingPublicationResult)
    case authorityRejected(DarwinFSEventNativeOwnerAuthorityRejection)
    case lifecycleRejected(DarwinFSEventNativeOwnerLifecycleRejection)
}
