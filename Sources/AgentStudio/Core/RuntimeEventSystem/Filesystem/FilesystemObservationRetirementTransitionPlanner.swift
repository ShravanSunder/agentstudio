import Foundation

enum FilesystemRetirementFenceTransferState: Equatable, Sendable {
    case installed(
        FilesystemRetirementFenceInstalledLifetime,
        FilesystemObservationRetiringGenerationChain
    )
    case transferred(FilesystemRetirementFenceTransferredLifetime)
    case retired(FilesystemRetiredContextReleaseLifetime)
    case invalid(FilesystemObservationPhysicalSlotState)
}

struct FilesystemRetirementFenceTransferRequest: Equatable, Sendable {
    let installedLifetime: FilesystemRetirementFenceInstalledLifetime
    let transferredLifetime: FilesystemRetirementFenceTransferredLifetime
    let currentState: FilesystemRetirementFenceTransferState
}

struct FilesystemRetirementFenceTransferMutation: Equatable, Sendable {
    let transferredLifetime: FilesystemRetirementFenceTransferredLifetime
    let retiringGenerationChain: FilesystemObservationRetiringGenerationChain
}

enum FilesystemObservationRetirementFenceTransferPlan: Equatable, Sendable {
    case apply(
        FilesystemRetirementFenceTransferMutation,
        FilesystemObservationRetirementFenceTransferResult
    )
    case unchanged(FilesystemObservationRetirementFenceTransferResult)
}

enum FilesystemRetirementCompletionState: Equatable, Sendable {
    case transferred(
        FilesystemRetirementFenceTransferredLifetime,
        FilesystemObservationRetiringGenerationChain
    )
    case retired(FilesystemRetiredContextReleaseLifetime)
    case invalid(FilesystemObservationPhysicalSlotState)
}

struct FilesystemObservationRetirementCompletionRequest: Equatable, Sendable {
    let transferredLifetime: FilesystemRetirementFenceTransferredLifetime
    let retiredLifetime: FilesystemRetiredContextReleaseLifetime
    let currentState: FilesystemRetirementCompletionState
}

struct FilesystemRetirementCompletionMutation: Equatable, Sendable {
    let retiredLifetime: FilesystemRetiredContextReleaseLifetime
    let retiringGenerationChain: FilesystemObservationRetiringGenerationChain
}

enum FilesystemObservationRetirementCompletionPlan: Equatable, Sendable {
    case apply(
        FilesystemRetirementCompletionMutation,
        FilesystemObservationRetirementCompletionResult
    )
    case unchanged(FilesystemObservationRetirementCompletionResult)
}

enum FilesystemUnpublishedFailureSlotState: Equatable {
    case undeclared
    case declared(FilesystemObservationRegistrySlotState)
}

enum FilesystemPendingConfigurationRecordSnapshot: Equatable {
    case absent
    case retained(FilesystemObservationPendingConfigurationRecord)
}

struct FilesystemUnpublishedFailureRequest: Equatable {
    let expectedFleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity
    let failedStartingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let currentSlotState: FilesystemUnpublishedFailureSlotState
    let pendingConfigurationRecord: FilesystemPendingConfigurationRecordSnapshot
    let retiringGenerationChain: FilesystemObservationRetiringGenerationChain
    let continuityRepairDisposition: FilesystemFailureContinuityRepairDisposition
}

enum FilesystemFailureContinuityRepairDisposition: Equatable {
    case preserve(FilesystemContinuityRepairCustodyState)
    case install(FilesystemPendingContinuityRepairAuthority)
}

enum FilesystemUnpublishedRetirementMutation: Equatable {
    case withdrawn(
        retiringLifetime: FilesystemObservationRetiringUnpublishedNativeLifetime,
        retiringGenerationChain: FilesystemObservationRetiringGenerationChain
    )
    case failed(
        retiringLifetime: FilesystemObservationRetiringUnpublishedNativeLifetime,
        retiringGenerationChain: FilesystemObservationRetiringGenerationChain,
        desiredRegistration: FilesystemObservationDesiredRegistration,
        pendingConfigurationRecord: FilesystemObservationPendingConfigurationRecord
    )
}

enum FilesystemUnpublishedFailurePlan: Equatable {
    case apply(
        FilesystemUnpublishedRetirementMutation,
        FilesystemObservationNativeLifetimeFailureResult
    )
    case unchanged(FilesystemObservationNativeLifetimeFailureResult)
}

struct FilesystemRetirementFencePreparationRequest: Equatable {
    let receipt: DarwinFSEventRegistrationLeaseDrainReceipt
    let currentSlotState: FilesystemObservationRegistrySlotState
    let retiringGenerationChain: FilesystemObservationRetiringGenerationChain
    let candidateFenceIdentity: FilesystemObservationRetirementFenceIdentity
}

enum FilesystemPreparedRetirementMutation: Equatable {
    case pending(
        lifetime: FilesystemRetirementFencePendingLifetime,
        retiringGenerationChain: FilesystemObservationRetiringGenerationChain
    )
    case awaitingPredecessor(
        lifetime: FilesystemClosingAwaitingPredecessorLifetime,
        retiringGenerationChain: FilesystemObservationRetiringGenerationChain
    )
}

enum FilesystemRetirementFencePreparationPlan: Equatable {
    case apply(
        FilesystemPreparedRetirementMutation,
        FilesystemRetirementFencePreparationResult
    )
    case unchanged(FilesystemRetirementFencePreparationResult)
}

struct FilesystemRetirementFenceInstallationRequest: Equatable {
    let pendingLifetime: FilesystemRetirementFencePendingLifetime
    let contributionIdentity: FilesystemObservationContributionIdentity
    let currentSlotState: FilesystemUnpublishedFailureSlotState
    let retiringGenerationChain: FilesystemObservationRetiringGenerationChain
}

struct FilesystemRetirementFenceInstallationMutation: Equatable {
    let installedLifetime: FilesystemRetirementFenceInstalledLifetime
    let retiringGenerationChain: FilesystemObservationRetiringGenerationChain
}

enum FilesystemRetirementFenceInstallationPlan: Equatable {
    case apply(
        FilesystemRetirementFenceInstallationMutation,
        FilesystemRetirementFenceInstallationResult
    )
    case unchanged(FilesystemRetirementFenceInstallationResult)
}

/// Stateless transition validation for the registry-owned retirement lifecycle.
///
/// The registry captures immutable exact state, constructs authority-bearing
/// lifetime candidates, and applies accepted plans. This planner stores no
/// custody and cannot mint retirement authority.
enum FilesystemObservationRetirementTransitionPlanner {
    static func makeRetiredLifetime(
        transferredLifetime: FilesystemRetirementFenceTransferredLifetime,
        disposition: FilesystemObservationSlotRetirementDisposition
    ) -> FilesystemRetiredContextReleaseLifetime {
        .fenceBacked(
            FilesystemFenceBackedRetiredContextReleaseLifetime(
                transferredLifetime: transferredLifetime,
                receipt: FilesystemObservationSlotRetirementReceipt(
                    binding: transferredLifetime.binding,
                    fenceIdentity: transferredLifetime.fence.identity,
                    disposition: disposition,
                    retirementAuthority: transferredLifetime.retirementAuthority
                )
            )
        )
    }

    static func planUnpublishedFailure(
        _ request: FilesystemUnpublishedFailureRequest
    ) -> FilesystemUnpublishedFailurePlan {
        let failedLifetime = request.failedStartingNativeLifetime
        guard
            failedLifetime.binding.fleetMailboxIdentity
                == request.expectedFleetMailboxIdentity
        else {
            return .unchanged(.foreignFleet)
        }
        guard case .declared(let currentSlotState) = request.currentSlotState else {
            return .unchanged(.undeclaredPhysicalSlot)
        }

        switch currentSlotState {
        case .startingAwaitingAcceptingPublication(let awaitingLifetime):
            guard awaitingLifetime.startingNativeLifetime == failedLifetime else {
                return .unchanged(
                    .staleStartingNativeLifetime(
                        awaitingLifetime.startingNativeLifetime
                    )
                )
            }
            let retiringLifetime =
                FilesystemObservationRetiringUnpublishedNativeLifetime(
                    startingNativeLifetime: failedLifetime,
                    cause: .desiredWithdrawn
                )
            return .apply(
                .withdrawn(
                    retiringLifetime: retiringLifetime,
                    retiringGenerationChain: appendingRetiringGeneration(
                        .unpublished(retiringLifetime),
                        to: request.retiringGenerationChain
                    )
                ),
                .retirementRequired(retiringLifetime)
            )
        case .starting(let currentStartingLifetime):
            guard currentStartingLifetime == failedLifetime else {
                return .unchanged(
                    .staleStartingNativeLifetime(currentStartingLifetime)
                )
            }
            let desiredRegistration: FilesystemObservationDesiredRegistration
            switch request.pendingConfigurationRecord {
            case .absent:
                desiredRegistration = currentStartingLifetime.desiredRegistration
            case .retained(let pendingRecord):
                desiredRegistration = pendingRecord.desiredRegistration
            }
            let retiringLifetime =
                FilesystemObservationRetiringUnpublishedNativeLifetime(
                    startingNativeLifetime: currentStartingLifetime,
                    cause: .nativeCreateOrStartFailed(desiredRegistration)
                )
            let continuityRepairCustody = continuityRepairCustody(
                disposition: request.continuityRepairDisposition,
                desiredRegistration: desiredRegistration,
                admission: currentStartingLifetime.desiredRegistration.admission
            )
            return .apply(
                .failed(
                    retiringLifetime: retiringLifetime,
                    retiringGenerationChain: appendingRetiringGeneration(
                        .unpublished(retiringLifetime),
                        to: request.retiringGenerationChain
                    ),
                    desiredRegistration: desiredRegistration,
                    pendingConfigurationRecord:
                        FilesystemObservationPendingConfigurationRecord(
                            desiredRegistration: desiredRegistration,
                            continuityRepairCustody: continuityRepairCustody
                        )
                ),
                .retirementRequired(retiringLifetime)
            )
        case .retiringUnpublishedGeneration(let retiringLifetime):
            guard retiringLifetime.startingNativeLifetime == failedLifetime else {
                return .unchanged(
                    .staleStartingNativeLifetime(
                        retiringLifetime.startingNativeLifetime
                    )
                )
            }
            return .unchanged(.alreadyRetirementRequired(retiringLifetime))
        case .vacant, .selected, .accepting, .closingAwaitingCallbackLeaseDrain,
            .closingAwaitingPredecessor, .retirementFencePending,
            .retirementFenceInstalled, .retirementFenceTransferredAwaitingCleanup,
            .retiredAwaitingContextRelease:
            return .unchanged(.nativeLifetimeNoLongerCurrent)
        }
    }

    private static func continuityRepairCustody(
        disposition: FilesystemFailureContinuityRepairDisposition,
        desiredRegistration: FilesystemObservationDesiredRegistration,
        admission: FilesystemObservationDesiredAdmission
    ) -> FilesystemContinuityRepairCustodyState {
        switch admission {
        case .replacementRetainingPredecessor:
            guard case .preserve(let custody) = disposition else {
                preconditionFailure(
                    "Retained-predecessor failure must preserve continuity-repair custody"
                )
            }
            return custody
        case .installation, .replacementAfterPredecessorClose:
            guard case .install(let authority) = disposition,
                authority.desiredIdentity == desiredRegistration.identity,
                authority.desiredConfiguration == desiredRegistration.configuration,
                authority.acceptedTopologyRevision
                    == desiredRegistration.acceptedTopologyRevision,
                authority.cause == .nativeCreateOrStartFailure,
                authority.recoveryRevision.value
                    == desiredRegistration.acceptedTopologyRevision.value
            else {
                preconditionFailure(
                    "Create/start failure requires exact pre-minted continuity-repair authority"
                )
            }
            return .pending(authority)
        }
    }

    private static func appendingRetiringGeneration(
        _ retiringLifetime: FilesystemObservationRetiringNativeLifetime,
        to currentChain: FilesystemObservationRetiringGenerationChain
    ) -> FilesystemObservationRetiringGenerationChain {
        switch currentChain {
        case .none:
            return .oldest(retiringLifetime)
        case .oldest(let oldestRetirement):
            return .oldestAndSuccessor(
                oldest: oldestRetirement,
                successor: retiringLifetime
            )
        case .oldestAndSuccessor:
            preconditionFailure("A source cannot own more than two retiring generations")
        }
    }

    static func planFencePreparation(
        _ request: FilesystemRetirementFencePreparationRequest
    ) -> FilesystemRetirementFencePreparationPlan {
        switch request.currentSlotState {
        case .closingAwaitingCallbackLeaseDrain(let closingLifetime):
            guard closingLifetime.matches(request.receipt) else {
                return .unchanged(.receiptMismatch)
            }
            switch request.retiringGenerationChain {
            case .none:
                let candidate = FilesystemRetirementFencePendingLifetime(
                    closingNativeLifetime: closingLifetime,
                    leaseDrainReceipt: request.receipt,
                    fence: FilesystemObservationSlotRetirementFence(
                        binding: closingLifetime.binding,
                        identity: request.candidateFenceIdentity
                    )
                )
                guard candidate.closingNativeLifetime == closingLifetime,
                    candidate.leaseDrainReceipt == request.receipt,
                    candidate.fence.binding == closingLifetime.binding
                else {
                    return .unchanged(.receiptMismatch)
                }
                return .apply(
                    .pending(
                        lifetime: candidate,
                        retiringGenerationChain: .oldest(
                            .retirementFencePending(candidate)
                        )
                    ),
                    .pending(candidate)
                )
            case .oldest(let oldest):
                let awaitingLifetime =
                    FilesystemClosingAwaitingPredecessorLifetime(
                        closingNativeLifetime: closingLifetime,
                        leaseDrainReceipt: request.receipt
                    )
                return .apply(
                    .awaitingPredecessor(
                        lifetime: awaitingLifetime,
                        retiringGenerationChain: .oldestAndSuccessor(
                            oldest: oldest,
                            successor: .closingAwaitingPredecessor(awaitingLifetime)
                        )
                    ),
                    .awaitingPredecessor(awaitingLifetime)
                )
            case .oldestAndSuccessor:
                return .unchanged(.retiringGenerationLimitReached)
            }
        case .closingAwaitingPredecessor(let awaitingLifetime):
            guard awaitingLifetime.leaseDrainReceipt == request.receipt else {
                return .unchanged(.receiptMismatch)
            }
            return .unchanged(.alreadyAwaitingPredecessor(awaitingLifetime))
        case .retirementFencePending(let pendingLifetime):
            guard pendingLifetime.leaseDrainReceipt == request.receipt else {
                return .unchanged(.receiptMismatch)
            }
            return .unchanged(.alreadyPending(pendingLifetime))
        case .retirementFenceInstalled(let installedLifetime):
            guard installedLifetime.pendingLifetime.leaseDrainReceipt == request.receipt else {
                return .unchanged(.receiptMismatch)
            }
            return .unchanged(.alreadyInstalled(installedLifetime))
        case .retirementFenceTransferredAwaitingCleanup(let transferredLifetime):
            let installedLifetime = transferredLifetime.installedLifetime
            guard installedLifetime.pendingLifetime.leaseDrainReceipt == request.receipt else {
                return .unchanged(.receiptMismatch)
            }
            return .unchanged(.alreadyInstalled(installedLifetime))
        case .retiredAwaitingContextRelease(let retiredLifetime):
            guard case .fenceBacked(let fenceBackedLifetime) = retiredLifetime else {
                return .unchanged(
                    .invalidSlotState(
                        projectFilesystemObservationSlotState(request.currentSlotState)
                    )
                )
            }
            let installedLifetime = fenceBackedLifetime.transferredLifetime.installedLifetime
            guard installedLifetime.pendingLifetime.leaseDrainReceipt == request.receipt else {
                return .unchanged(.receiptMismatch)
            }
            return .unchanged(.alreadyRetired(fenceBackedLifetime.receipt))
        case .vacant, .selected, .starting, .startingAwaitingAcceptingPublication,
            .accepting, .retiringUnpublishedGeneration:
            return .unchanged(
                .invalidSlotState(
                    projectFilesystemObservationSlotState(request.currentSlotState)
                )
            )
        }
    }

    static func planFenceInstallation(
        _ request: FilesystemRetirementFenceInstallationRequest
    ) -> FilesystemRetirementFenceInstallationPlan {
        let pendingLifetime = request.pendingLifetime
        guard request.contributionIdentity.binding == pendingLifetime.binding,
            case .declared(let currentSlotState) = request.currentSlotState
        else {
            return .unchanged(.stalePendingLifetime)
        }

        switch currentSlotState {
        case .retirementFencePending(let currentPendingLifetime):
            guard currentPendingLifetime == pendingLifetime else {
                return .unchanged(.stalePendingLifetime)
            }
            let installedLifetime = FilesystemRetirementFenceInstalledLifetime(
                pendingLifetime: pendingLifetime,
                contributionIdentity: request.contributionIdentity
            )
            guard
                case .replaced(let replacementChain) =
                    request.retiringGenerationChain.replacing(
                        .retirementFencePending(pendingLifetime),
                        with: .retirementFenceInstalled(installedLifetime)
                    )
            else {
                return .unchanged(.stalePendingLifetime)
            }
            return .apply(
                FilesystemRetirementFenceInstallationMutation(
                    installedLifetime: installedLifetime,
                    retiringGenerationChain: replacementChain
                ),
                .installed(installedLifetime)
            )
        case .retirementFenceInstalled(let installedLifetime):
            guard installedLifetime.pendingLifetime == pendingLifetime,
                installedLifetime.contributionIdentity == request.contributionIdentity
            else {
                return .unchanged(.stalePendingLifetime)
            }
            return .unchanged(.alreadyInstalled(installedLifetime))
        case .vacant, .selected, .starting, .startingAwaitingAcceptingPublication,
            .accepting, .closingAwaitingCallbackLeaseDrain,
            .closingAwaitingPredecessor, .retirementFenceTransferredAwaitingCleanup,
            .retiredAwaitingContextRelease, .retiringUnpublishedGeneration:
            return .unchanged(
                .invalidSlotState(
                    projectFilesystemObservationSlotState(currentSlotState)
                )
            )
        }
    }

    static func transferState(
        physicalSlotState: FilesystemObservationPhysicalSlotState,
        retiringGenerationChain: FilesystemObservationRetiringGenerationChain
    ) -> FilesystemRetirementFenceTransferState {
        switch physicalSlotState {
        case .retirementFenceInstalled(let lifetime):
            return .installed(lifetime, retiringGenerationChain)
        case .retirementFenceTransferredAwaitingCleanup(let lifetime):
            return .transferred(lifetime)
        case .retiredAwaitingContextRelease(let lifetime):
            return .retired(lifetime)
        case .undeclaredPhysicalSlot, .vacant, .selected, .starting, .accepting,
            .closingAwaitingCallbackLeaseDrain, .closingAwaitingPredecessor,
            .retirementFencePending, .retiringUnpublishedGeneration:
            return .invalid(physicalSlotState)
        }
    }

    static func completionState(
        physicalSlotState: FilesystemObservationPhysicalSlotState,
        retiringGenerationChain: FilesystemObservationRetiringGenerationChain
    ) -> FilesystemRetirementCompletionState {
        switch physicalSlotState {
        case .retirementFenceTransferredAwaitingCleanup(let lifetime):
            return .transferred(lifetime, retiringGenerationChain)
        case .retiredAwaitingContextRelease(let lifetime):
            return .retired(lifetime)
        case .undeclaredPhysicalSlot, .vacant, .selected, .starting, .accepting,
            .closingAwaitingCallbackLeaseDrain, .closingAwaitingPredecessor,
            .retirementFencePending, .retirementFenceInstalled,
            .retiringUnpublishedGeneration:
            return .invalid(physicalSlotState)
        }
    }

    static func planFenceTransfer(
        installedLifetime: FilesystemRetirementFenceInstalledLifetime,
        retirementAuthority: FilesystemObservationSlotRetirementAuthority,
        currentState: FilesystemRetirementFenceTransferState
    ) -> FilesystemObservationRetirementFenceTransferPlan {
        let transferredLifetime = FilesystemRetirementFenceTransferredLifetime(
            installedLifetime: installedLifetime,
            retirementAuthority: retirementAuthority
        )
        return planFenceTransfer(
            FilesystemRetirementFenceTransferRequest(
                installedLifetime: installedLifetime,
                transferredLifetime: transferredLifetime,
                currentState: currentState
            )
        )
    }

    private static func planFenceTransfer(
        _ request: FilesystemRetirementFenceTransferRequest
    ) -> FilesystemObservationRetirementFenceTransferPlan {
        switch request.currentState {
        case .installed(let currentInstalledLifetime, let currentChain):
            guard currentInstalledLifetime == request.installedLifetime else {
                return .unchanged(.authorityMismatch)
            }
            guard
                case .replaced(let replacementChain) = currentChain.replacing(
                    .retirementFenceInstalled(request.installedLifetime),
                    with: .retirementFenceTransferredAwaitingCleanup(
                        request.transferredLifetime
                    )
                )
            else {
                return .unchanged(.authorityMismatch)
            }
            return .apply(
                FilesystemRetirementFenceTransferMutation(
                    transferredLifetime: request.transferredLifetime,
                    retiringGenerationChain: replacementChain
                ),
                .transferred(request.transferredLifetime)
            )
        case .transferred(let currentTransferredLifetime):
            guard
                currentTransferredLifetime.installedLifetime
                    == request.installedLifetime
            else {
                return .unchanged(.authorityMismatch)
            }
            return .unchanged(.alreadyTransferred(currentTransferredLifetime))
        case .retired(let retiredLifetime):
            guard case .fenceBacked(let fenceBackedLifetime) = retiredLifetime else {
                return .unchanged(.authorityMismatch)
            }
            guard
                fenceBackedLifetime.transferredLifetime.installedLifetime
                    == request.installedLifetime
            else {
                return .unchanged(.authorityMismatch)
            }
            return .unchanged(.alreadyRetired(retiredLifetime))
        case .invalid(let physicalSlotState):
            return .unchanged(.invalidSlotState(physicalSlotState))
        }
    }

    static func planRetirementCompletion(
        _ request: FilesystemObservationRetirementCompletionRequest
    ) -> FilesystemObservationRetirementCompletionPlan {
        switch request.currentState {
        case .transferred(let currentTransferredLifetime, let currentChain):
            guard currentTransferredLifetime == request.transferredLifetime else {
                return .unchanged(.authorityMismatch)
            }
            guard case .fenceBacked(let fenceBackedLifetime) = request.retiredLifetime else {
                return .unchanged(.authorityMismatch)
            }
            guard
                case .replaced(let replacementChain) = currentChain.replacing(
                    .retirementFenceTransferredAwaitingCleanup(
                        request.transferredLifetime
                    ),
                    with: .retiredAwaitingContextRelease(request.retiredLifetime)
                )
            else {
                return .unchanged(.authorityMismatch)
            }
            return .apply(
                FilesystemRetirementCompletionMutation(
                    retiredLifetime: request.retiredLifetime,
                    retiringGenerationChain: replacementChain
                ),
                .retired(fenceBackedLifetime.receipt)
            )
        case .retired(let retiredLifetime):
            guard case .fenceBacked(let fenceBackedLifetime) = retiredLifetime else {
                return .unchanged(.authorityMismatch)
            }
            guard
                fenceBackedLifetime.transferredLifetime == request.transferredLifetime
            else {
                return .unchanged(.authorityMismatch)
            }
            return .unchanged(.alreadyRetired(fenceBackedLifetime.receipt))
        case .invalid(let physicalSlotState):
            return .unchanged(.invalidSlotState(physicalSlotState))
        }
    }
}
