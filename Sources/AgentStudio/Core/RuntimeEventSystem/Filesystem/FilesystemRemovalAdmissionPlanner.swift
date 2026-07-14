enum FilesystemRemovalSlotSnapshot: Equatable {
    case undeclared
    case declared(FilesystemObservationRegistrySlotState)
}

enum FilesystemRemovalReplaySnapshot: Equatable {
    case vacant
    case retained(FilesystemObservationPostStartPublication)
    case retainedAfterRemoval(
        publication: FilesystemObservationPostStartPublication,
        closeObligation: FilesystemAcceptingRemovalCloseObligation
    )
}

struct FilesystemRemovalAdmissionInput: Equatable {
    let expectedFleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity
    let exactPriorBinding: FilesystemObservationSlotBinding
    let slotSnapshot: FilesystemRemovalSlotSnapshot
    let replaySnapshot: FilesystemRemovalReplaySnapshot
}

enum FilesystemRemovalAdmissionPlan: Equatable {
    case rejected(FilesystemObservationRemovalAdmissionRejection)
    case replayClose(FilesystemAcceptingRemovalCloseObligation)
    case markStartingAwaiting(FilesystemObservationStartingNativeLifetime)
    case replayAwaiting(FilesystemAwaitingAcceptingPublicationLifetime)
    case closeAccepting(FilesystemObservationPostStartPublication)
    case alreadyClosing(FilesystemObservationPhysicalSlotState)
}

enum FilesystemRemovalAuthorityRequirement: Equatable {
    case terminal(FilesystemObservationRemovalAdmissionResult)
    case required(FilesystemAuthorizedRemovalLifetime)
}

enum FilesystemStartingSuccessorSnapshot: Equatable {
    case absent
    case retained(FilesystemObservationStartingNativeLifetime)
}

enum FilesystemSelectedSuccessorSnapshot: Equatable {
    case absent
    case retained(FilesystemObservationDesiredSelection)
}

enum FilesystemDeferredSuccessorSnapshot: Equatable {
    case absent
    case retained(FilesystemObservationDesiredRegistration)
}

struct FilesystemRemovalSuccessorInput: Equatable {
    let exactPriorBinding: FilesystemObservationSlotBinding
    let startingSuccessor: FilesystemStartingSuccessorSnapshot
    let selectedSuccessor: FilesystemSelectedSuccessorSnapshot
    let deferredSuccessor: FilesystemDeferredSuccessorSnapshot
}

enum FilesystemRemovalSuccessorPlan: Equatable {
    case markStartingAwaiting(FilesystemObservationStartingNativeLifetime)
    case releaseSelection(FilesystemObservationDesiredSelection)
    case withdrawDeferred(FilesystemObservationDesiredRegistration)
    case absent
}

enum FilesystemAuthorizedRemovalLifetime: Equatable {
    case starting(FilesystemObservationStartingNativeLifetime)
    case accepting(FilesystemObservationPostStartPublication)
}

enum FilesystemRemovalPendingConfigurationProduct: Equatable {
    case unchangedAbsent
    case remove(FilesystemObservationPendingConfigurationRecord)
    case replace(FilesystemObservationPendingConfigurationRecord)
}

enum FilesystemRemovalPrimarySlotProduct: Equatable {
    case awaitingAcceptingPublication(FilesystemAwaitingAcceptingPublicationLifetime)
    case retainAccepting(FilesystemObservationPostStartPublication)
}

enum FilesystemRemovalPublicationRetentionProduct: Equatable {
    case unchanged
    case retainAfterRemoval(
        publication: FilesystemObservationPostStartPublication,
        closeObligation: FilesystemAcceptingRemovalCloseObligation
    )
}

enum FilesystemRemovalSuccessorCustodyProduct: Equatable {
    case absent
    case awaitingAcceptingPublication(FilesystemAwaitingAcceptingPublicationLifetime)
    case releaseSelection(FilesystemObservationDesiredSelection)
    case withdrawDeferred(FilesystemObservationDesiredRegistration)

    var publicDisposition: FilesystemRemovedSuccessorCustody {
        switch self {
        case .absent:
            .absent
        case .awaitingAcceptingPublication(let lifetime):
            .awaitingAcceptingPublication(lifetime)
        case .releaseSelection(let selection):
            .selected(selection)
        case .withdrawDeferred(let desiredRegistration):
            .deferred(desiredRegistration)
        }
    }
}

struct FilesystemAuthorizedRemovalInput {
    let lifetime: FilesystemAuthorizedRemovalLifetime
    let removalAuthority: FilesystemSourceRemovalAuthority
    let pendingConfiguration: FilesystemContinuityRepairCustodyPlanner.PendingRemovalSnapshot
    let startingSuccessor: FilesystemStartingSuccessorSnapshot
    let selectedSuccessor: FilesystemSelectedSuccessorSnapshot
    let deferredSuccessor: FilesystemDeferredSuccessorSnapshot
}

struct FilesystemAuthorizedRemovalPlan: Equatable {
    let result: FilesystemObservationRemovalAdmissionResult
    let pendingConfiguration: FilesystemRemovalPendingConfigurationProduct
    let primarySlot: FilesystemRemovalPrimarySlotProduct
    let publicationRetention: FilesystemRemovalPublicationRetentionProduct
    let successorCustody: FilesystemRemovalSuccessorCustodyProduct
}

/// Stateless removal validation and successor-custody classification.
///
/// The registry captures immutable state, mints removal authority only after
/// validation, and applies the returned plan. This planner stores no custody,
/// generates no identity, and performs no mutation.
enum FilesystemRemovalAdmissionPlanner {
    static func makeRemovalAuthority(
        identity: FilesystemSourceRemovalAuthorityIdentity,
        exactPriorBinding: FilesystemObservationSlotBinding,
        acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision
    ) -> FilesystemSourceRemovalAuthority {
        FilesystemSourceRemovalAuthority(
            identity: identity,
            exactPriorBinding: exactPriorBinding,
            acceptedTopologyRevision: acceptedTopologyRevision
        )
    }

    static func authorityRequirement(
        _ input: FilesystemRemovalAdmissionInput
    ) -> FilesystemRemovalAuthorityRequirement {
        switch planAdmission(input) {
        case .rejected(let rejection):
            return .terminal(.rejected(rejection))
        case .replayClose(let closeObligation):
            return .terminal(.closeAccepting(closeObligation))
        case .markStartingAwaiting(let startingNativeLifetime):
            return .required(.starting(startingNativeLifetime))
        case .replayAwaiting(let awaitingLifetime):
            return .terminal(.awaitingAcceptingPublication(awaitingLifetime))
        case .closeAccepting(let publication):
            return .required(.accepting(publication))
        case .alreadyClosing(let physicalSlotState):
            return .terminal(.alreadyClosing(physicalSlotState))
        }
    }

    static func planAdmission(
        _ input: FilesystemRemovalAdmissionInput
    ) -> FilesystemRemovalAdmissionPlan {
        let exactPriorBinding = input.exactPriorBinding
        guard
            exactPriorBinding.fleetMailboxIdentity
                == input.expectedFleetMailboxIdentity
        else {
            return .rejected(.foreignFleet)
        }
        guard case .declared(let slotState) = input.slotSnapshot else {
            return .rejected(.undeclaredPhysicalSlot)
        }
        if case .retainedAfterRemoval(let publication, let closeObligation) =
            input.replaySnapshot,
            publication.acceptingNativeLifetime.binding == exactPriorBinding
        {
            return .replayClose(closeObligation)
        }

        switch slotState {
        case .vacant:
            return .rejected(.vacant)
        case .selected:
            return .rejected(.reservedWithoutBinding)
        case .starting(let startingNativeLifetime):
            guard startingNativeLifetime.binding == exactPriorBinding else {
                return .rejected(.storedSuperseded)
            }
            return .markStartingAwaiting(startingNativeLifetime)
        case .startingAwaitingAcceptingPublication(let awaitingLifetime):
            guard awaitingLifetime.startingNativeLifetime.binding == exactPriorBinding else {
                return .rejected(.storedSuperseded)
            }
            return .replayAwaiting(awaitingLifetime)
        case .accepting(let publication):
            let acceptingNativeLifetime = publication.acceptingNativeLifetime
            guard acceptingNativeLifetime.binding == exactPriorBinding else {
                return .rejected(.storedSuperseded)
            }
            return .closeAccepting(publication)
        case .closingAwaitingCallbackLeaseDrain(let lifetime):
            return planAlreadyClosing(
                exactPriorBinding: exactPriorBinding,
                currentBinding: lifetime.binding,
                slotState: slotState
            )
        case .closingAwaitingPredecessor(let lifetime):
            return planAlreadyClosing(
                exactPriorBinding: exactPriorBinding,
                currentBinding: lifetime.binding,
                slotState: slotState
            )
        case .retirementFencePending(let lifetime):
            return planAlreadyClosing(
                exactPriorBinding: exactPriorBinding,
                currentBinding: lifetime.binding,
                slotState: slotState
            )
        case .retirementFenceInstalled(let lifetime):
            return planAlreadyClosing(
                exactPriorBinding: exactPriorBinding,
                currentBinding: lifetime.binding,
                slotState: slotState
            )
        case .retirementFenceTransferredAwaitingCleanup(let lifetime):
            return planAlreadyClosing(
                exactPriorBinding: exactPriorBinding,
                currentBinding: lifetime.binding,
                slotState: slotState
            )
        case .retiredAwaitingContextRelease(let lifetime):
            return planAlreadyClosing(
                exactPriorBinding: exactPriorBinding,
                currentBinding: lifetime.binding,
                slotState: slotState
            )
        case .retiringUnpublishedGeneration(let lifetime):
            return planAlreadyClosing(
                exactPriorBinding: exactPriorBinding,
                currentBinding: lifetime.startingNativeLifetime.binding,
                slotState: slotState
            )
        }
    }

    static func planSuccessor(
        _ input: FilesystemRemovalSuccessorInput
    ) -> FilesystemRemovalSuccessorPlan {
        if case .retained(let startingNativeLifetime) = input.startingSuccessor,
            startingNativeLifetime.binding != input.exactPriorBinding
        {
            return .markStartingAwaiting(startingNativeLifetime)
        }
        if case .retained(let selectedDesiredSource) = input.selectedSuccessor {
            return .releaseSelection(selectedDesiredSource)
        }
        if case .retained(let deferredDesiredRegistration) = input.deferredSuccessor {
            return .withdrawDeferred(deferredDesiredRegistration)
        }
        return .absent
    }

    static func planAuthorizedRemoval(
        _ input: FilesystemAuthorizedRemovalInput
    ) -> FilesystemAuthorizedRemovalPlan {
        let pendingPlan =
            FilesystemContinuityRepairCustodyPlanner.withdrawPendingRecordForRemoval(
                snapshot: input.pendingConfiguration,
                removalAuthority: input.removalAuthority
            )
        let successorPlan = planSuccessor(
            FilesystemRemovalSuccessorInput(
                exactPriorBinding: input.removalAuthority.exactPriorBinding,
                startingSuccessor: input.startingSuccessor,
                selectedSuccessor: input.selectedSuccessor,
                deferredSuccessor: input.deferredSuccessor
            )
        )
        let successorProduct = successorProduct(successorPlan)
        let withdrawnDesiredDisposition = FilesystemObservationRemovedDesiredDisposition(
            pendingConfiguration: pendingPlan.disposition,
            successorCustody: successorProduct.publicDisposition
        )

        switch input.lifetime {
        case .starting(let startingNativeLifetime):
            let awaitingLifetime = FilesystemAwaitingAcceptingPublicationLifetime(
                startingNativeLifetime: startingNativeLifetime
            )
            return FilesystemAuthorizedRemovalPlan(
                result: .awaitingAcceptingPublication(awaitingLifetime),
                pendingConfiguration: pendingConfigurationProduct(pendingPlan),
                primarySlot: .awaitingAcceptingPublication(awaitingLifetime),
                publicationRetention: .unchanged,
                successorCustody: successorProduct
            )
        case .accepting(let publication):
            let closeObligation = FilesystemAcceptingRemovalCloseObligation(
                acceptingNativeLifetime: publication.acceptingNativeLifetime,
                removalAuthority: input.removalAuthority,
                withdrawnDesiredDisposition: withdrawnDesiredDisposition
            )
            return FilesystemAuthorizedRemovalPlan(
                result: .closeAccepting(closeObligation),
                pendingConfiguration: pendingConfigurationProduct(pendingPlan),
                primarySlot: .retainAccepting(publication),
                publicationRetention: .retainAfterRemoval(
                    publication: publication,
                    closeObligation: closeObligation
                ),
                successorCustody: successorProduct
            )
        }
    }

    private static func pendingConfigurationProduct(
        _ plan: FilesystemContinuityRepairCustodyPlanner.PendingRemovalPlan
    ) -> FilesystemRemovalPendingConfigurationProduct {
        switch plan {
        case .unchanged:
            return .unchangedAbsent
        case .removeRecord(let record, _):
            return .remove(record)
        case .retainRecord(let record, _):
            return .replace(record)
        }
    }

    private static func successorProduct(
        _ plan: FilesystemRemovalSuccessorPlan
    ) -> FilesystemRemovalSuccessorCustodyProduct {
        switch plan {
        case .markStartingAwaiting(let startingNativeLifetime):
            return .awaitingAcceptingPublication(
                FilesystemAwaitingAcceptingPublicationLifetime(
                    startingNativeLifetime: startingNativeLifetime
                )
            )
        case .releaseSelection(let selection):
            return .releaseSelection(selection)
        case .withdrawDeferred(let desiredRegistration):
            return .withdrawDeferred(desiredRegistration)
        case .absent:
            return .absent
        }
    }

    private static func planAlreadyClosing(
        exactPriorBinding: FilesystemObservationSlotBinding,
        currentBinding: FilesystemObservationSlotBinding,
        slotState: FilesystemObservationRegistrySlotState
    ) -> FilesystemRemovalAdmissionPlan {
        guard currentBinding == exactPriorBinding else {
            return .rejected(.storedSuperseded)
        }
        return .alreadyClosing(projectFilesystemObservationSlotState(slotState))
    }
}
