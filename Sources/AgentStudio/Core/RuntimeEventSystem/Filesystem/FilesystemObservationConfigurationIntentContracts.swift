import Foundation

struct FilesystemObservationAcceptedTopologyRevision: Hashable, Sendable {
    let value: UInt64
}

struct FilesystemSourceInstallationIntent: Hashable, Sendable {
    let desiredConfiguration: FilesystemObservationSourceConfiguration
}

struct FilesystemSourceReplacementIntent: Hashable, Sendable {
    let exactPriorBinding: FilesystemObservationSlotBinding
    let desiredConfiguration: FilesystemObservationSourceConfiguration
}

struct FilesystemSourceRemovalIntent: Hashable, Sendable {
    let exactPriorBinding: FilesystemObservationSlotBinding
}

enum FilesystemSourceConfigurationIntent: Hashable, Sendable {
    case install(FilesystemSourceInstallationIntent)
    case replace(FilesystemSourceReplacementIntent)
    case remove(FilesystemSourceRemovalIntent)
}

struct FilesystemSourceConfigurationIntentBatch: Hashable, Sendable {
    let acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision
    let intentsBySourceID: [FilesystemSourceID: FilesystemSourceConfigurationIntent]
}

struct FilesystemConfigurationIntentSourceMismatch: Equatable, Hashable, Sendable {
    let keyedSourceID: FilesystemSourceID
    let representedSourceIDs: Set<FilesystemSourceID>
}

enum FilesystemConfigurationIntentBatchRejection: Equatable, Sendable {
    case sourceMismatches(Set<FilesystemConfigurationIntentSourceMismatch>)
    case staleAcceptedTopologyRevision(
        submitted: FilesystemObservationAcceptedTopologyRevision,
        retained: FilesystemObservationAcceptedTopologyRevision
    )
    case conflictingBatchForAcceptedTopologyRevision(
        FilesystemObservationAcceptedTopologyRevision
    )
}

enum FilesystemObservationRemovalAdmissionRejection: Equatable, Sendable {
    case foreignFleet
    case undeclaredPhysicalSlot
    case vacant
    case reservedWithoutBinding
    case storedSuperseded
    case priorBindingNotCurrent(FilesystemObservationPhysicalSlotState)
}

enum FilesystemRemovedPendingConfiguration: Equatable, Sendable {
    case absent
    case withdrawn(FilesystemObservationDesiredRegistration)
}

enum FilesystemRemovedSuccessorCustody: Equatable, Sendable {
    case absent
    case deferred(FilesystemObservationDesiredRegistration)
    case selected(FilesystemObservationDesiredSelection)
    case awaitingAcceptingPublication(FilesystemAwaitingAcceptingPublicationLifetime)
}

struct FilesystemObservationRemovedDesiredDisposition: Equatable, Sendable {
    let pendingConfiguration: FilesystemRemovedPendingConfiguration
    let successorCustody: FilesystemRemovedSuccessorCustody
}

struct FilesystemAcceptingRemovalCloseObligation: Equatable, Sendable {
    let acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
    let removalAuthority: FilesystemSourceRemovalAuthority
    let withdrawnDesiredDisposition: FilesystemObservationRemovedDesiredDisposition
}

enum FilesystemObservationRemovalAdmissionResult: Equatable, Sendable {
    case awaitingAcceptingPublication(FilesystemAwaitingAcceptingPublicationLifetime)
    case closeAccepting(FilesystemAcceptingRemovalCloseObligation)
    case alreadyClosing(FilesystemObservationPhysicalSlotState)
    case rejected(FilesystemObservationRemovalAdmissionRejection)
}

enum FilesystemConfigurationIntentAdmission: Equatable, Sendable {
    case installation(FilesystemObservationDesiredUpdateResult)
    case replacement(FilesystemObservationReplacementAdmissionResult)
    case removal(FilesystemObservationRemovalAdmissionResult)
}

struct FilesystemConfigurationIntentBatchAdmission: Equatable, Sendable {
    let acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision
    let admissionsBySourceID: [FilesystemSourceID: FilesystemConfigurationIntentAdmission]
}

enum FilesystemConfigurationIntentBatchAdmissionResult: Equatable, Sendable {
    case admitted(FilesystemConfigurationIntentBatchAdmission)
    case rejected(FilesystemConfigurationIntentBatchRejection)
}
