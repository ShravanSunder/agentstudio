enum FilesystemObservationRegistrySlotState: Equatable {
    case vacant
    case selected(FilesystemObservationDesiredSelection)
    case starting(FilesystemObservationStartingNativeLifetime)
    case startingAwaitingAcceptingPublication(
        FilesystemAwaitingAcceptingPublicationLifetime
    )
    case accepting(FilesystemObservationPostStartPublication)
    case closingAwaitingCallbackLeaseDrain(
        FilesystemObservationClosingAwaitingCallbackLeaseDrainLifetime
    )
    case closingAwaitingPredecessor(FilesystemClosingAwaitingPredecessorLifetime)
    case retirementFencePending(FilesystemRetirementFencePendingLifetime)
    case retirementFenceInstalled(FilesystemRetirementFenceInstalledLifetime)
    case retirementFenceTransferredAwaitingCleanup(
        FilesystemRetirementFenceTransferredLifetime
    )
    case retiredAwaitingContextRelease(FilesystemRetiredContextReleaseLifetime)
    case retiringUnpublishedGeneration(FilesystemObservationRetiringUnpublishedNativeLifetime)
}

func projectFilesystemObservationSlotState(
    _ slotState: FilesystemObservationRegistrySlotState?
) -> FilesystemObservationPhysicalSlotState {
    guard let slotState else { return .undeclaredPhysicalSlot }
    switch slotState {
    case .vacant:
        return .vacant
    case .selected(let selection):
        return .selected(selection)
    case .starting(let startingNativeLifetime):
        return .starting(startingNativeLifetime)
    case .startingAwaitingAcceptingPublication(let lifetime):
        return .starting(lifetime.startingNativeLifetime)
    case .accepting(let publication):
        return .accepting(publication.acceptingNativeLifetime)
    case .closingAwaitingCallbackLeaseDrain(let closingNativeLifetime):
        return .closingAwaitingCallbackLeaseDrain(closingNativeLifetime)
    case .closingAwaitingPredecessor(let lifetime):
        return .closingAwaitingPredecessor(lifetime)
    case .retirementFencePending(let lifetime):
        return .retirementFencePending(lifetime)
    case .retirementFenceInstalled(let lifetime):
        return .retirementFenceInstalled(lifetime)
    case .retirementFenceTransferredAwaitingCleanup(let lifetime):
        return .retirementFenceTransferredAwaitingCleanup(lifetime)
    case .retiredAwaitingContextRelease(let lifetime):
        return .retiredAwaitingContextRelease(lifetime)
    case .retiringUnpublishedGeneration(let retiringNativeLifetime):
        return .retiringUnpublishedGeneration(retiringNativeLifetime)
    }
}

enum FilesystemObservationPostStartPublicationRetention: Equatable {
    case vacant
    case retained(FilesystemObservationPostStartPublication)
    case retainedAfterRemoval(
        publication: FilesystemObservationPostStartPublication,
        closeObligation: FilesystemAcceptingRemovalCloseObligation
    )
}

struct FilesystemObservationPendingConfigurationRecord: Equatable {
    var desiredRegistration: FilesystemObservationDesiredRegistration
    var continuityRepairCustody: FilesystemContinuityRepairCustodyState
}
