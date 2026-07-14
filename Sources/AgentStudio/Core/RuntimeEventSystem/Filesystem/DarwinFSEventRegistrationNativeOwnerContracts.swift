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

enum DarwinFSEventNativeOwnerFleetShutdownNativePhase: Equatable, Sendable {
    case creationAvailable(FilesystemObservationStartingNativeLifetime)
    case creating(FilesystemObservationStartingNativeLifetime)
    case created(
        FilesystemObservationStartingNativeLifetime,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
    case starting(
        FilesystemObservationStartingNativeLifetime,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
    case abandoningStart(
        FilesystemObservationStartingNativeLifetime,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
    case publishingAcceptance(
        FilesystemObservationStartingNativeLifetime,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
    case acceptingPublicationPending(
        FilesystemObservationStartingNativeLifetime,
        FilesystemObservationAcceptingPublicationResult,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
    case creationRejected(DarwinFSEventRegistrationCreateFailureCleanup)
    case creationAbandoned(DarwinFSEventRegistrationCreationAbandonment)
    case unpublished(DarwinFSEventUnpublishedNativeCompletion)
    case accepting(
        FilesystemObservationAcceptingNativeLifetime,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
    case authorityRejected(
        FilesystemObservationStartingNativeLifetime,
        DarwinFSEventNativeOwnerAuthorityRejection,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
    case lifecycleRejected(
        FilesystemObservationStartingNativeLifetime,
        DarwinFSEventNativeOwnerLifecycleRejection,
        generationPhase: DarwinFSEventRegistrationGenerationPhase
    )
}

enum DarwinNativeFleetShutdownFinalizationPhase: Equatable, Sendable {
    case awaitingMaterialization
    case retainedContext
    case retirementPermitRetained(FilesystemObservationNativeRetirementPermit)
    case finalizing(FilesystemObservationNativeRetirementPermit)
    case finalized(FilesystemObservationContextReleaseAcknowledgement)
}

enum DarwinFSEventNativeOwnerFleetShutdownAdvancePhase: Equatable, Sendable {
    case available
    case inFlight
    case completed(DarwinFSEventNativeOwnerFleetShutdownCompletion)
}

struct DarwinFSEventNativeOwnerFleetShutdownProjection: Equatable, Sendable {
    let binding: FilesystemObservationSlotBinding
    let nativePhase: DarwinFSEventNativeOwnerFleetShutdownNativePhase
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
