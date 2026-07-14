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

enum DarwinFSEventNativeOwnerLifecycleRejection: Sendable {
    case generationPhase(DarwinFSEventRegistrationGenerationPhase)
    case mailboxClosing(FilesystemObservationCallbackLeaseDrainClosingResult)
    case closeAlreadyInProgress
}

enum DarwinFSEventNativeOwnerStartResult: Sendable {
    case started(FilesystemObservationAcceptingNativeLifetime)
    case unpublished(DarwinFSEventUnpublishedQuiescence)
    case acceptingPublicationRejected(FilesystemObservationAcceptingPublicationResult)
    case authorityRejected(DarwinFSEventNativeOwnerAuthorityRejection)
    case lifecycleRejected(DarwinFSEventNativeOwnerLifecycleRejection)
}
