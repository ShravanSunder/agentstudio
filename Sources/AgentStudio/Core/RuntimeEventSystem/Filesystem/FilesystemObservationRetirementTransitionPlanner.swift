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

enum FilesystemObservationRetirementFenceTransferPlan: Equatable, Sendable {
    case apply(
        FilesystemRetirementFenceTransferredLifetime,
        FilesystemObservationRetiringGenerationChain
    )
    case alreadyTransferred(FilesystemRetirementFenceTransferredLifetime)
    case alreadyRetired(FilesystemRetiredContextReleaseLifetime)
    case authorityMismatch
    case invalidSlotState(FilesystemObservationPhysicalSlotState)
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

enum FilesystemObservationRetirementCompletionPlan: Equatable, Sendable {
    case apply(
        FilesystemRetiredContextReleaseLifetime,
        FilesystemObservationRetiringGenerationChain
    )
    case alreadyRetired(FilesystemObservationSlotRetirementReceipt)
    case authorityMismatch
    case invalidSlotState(FilesystemObservationPhysicalSlotState)
}

/// Stateless transition validation for the registry-owned retirement lifecycle.
///
/// The registry captures immutable exact state, constructs authority-bearing
/// lifetime candidates, and applies accepted plans. This planner stores no
/// custody and cannot mint retirement authority.
enum FilesystemObservationRetirementTransitionPlanner {
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
        _ request: FilesystemRetirementFenceTransferRequest
    ) -> FilesystemObservationRetirementFenceTransferPlan {
        switch request.currentState {
        case .installed(let currentInstalledLifetime, let currentChain):
            guard currentInstalledLifetime == request.installedLifetime else {
                return .authorityMismatch
            }
            guard
                case .replaced(let replacementChain) = currentChain.replacing(
                    .retirementFenceInstalled(request.installedLifetime),
                    with: .retirementFenceTransferredAwaitingCleanup(
                        request.transferredLifetime
                    )
                )
            else {
                return .authorityMismatch
            }
            return .apply(request.transferredLifetime, replacementChain)
        case .transferred(let currentTransferredLifetime):
            guard
                currentTransferredLifetime.installedLifetime
                    == request.installedLifetime
            else {
                return .authorityMismatch
            }
            return .alreadyTransferred(currentTransferredLifetime)
        case .retired(let retiredLifetime):
            guard
                retiredLifetime.transferredLifetime.installedLifetime
                    == request.installedLifetime
            else {
                return .authorityMismatch
            }
            return .alreadyRetired(retiredLifetime)
        case .invalid(let physicalSlotState):
            return .invalidSlotState(physicalSlotState)
        }
    }

    static func planRetirementCompletion(
        _ request: FilesystemObservationRetirementCompletionRequest
    ) -> FilesystemObservationRetirementCompletionPlan {
        switch request.currentState {
        case .transferred(let currentTransferredLifetime, let currentChain):
            guard currentTransferredLifetime == request.transferredLifetime else {
                return .authorityMismatch
            }
            guard
                case .replaced(let replacementChain) = currentChain.replacing(
                    .retirementFenceTransferredAwaitingCleanup(
                        request.transferredLifetime
                    ),
                    with: .retiredAwaitingContextRelease(request.retiredLifetime)
                )
            else {
                return .authorityMismatch
            }
            return .apply(request.retiredLifetime, replacementChain)
        case .retired(let retiredLifetime):
            guard
                retiredLifetime.transferredLifetime == request.transferredLifetime
            else {
                return .authorityMismatch
            }
            return .alreadyRetired(retiredLifetime.receipt)
        case .invalid(let physicalSlotState):
            return .invalidSlotState(physicalSlotState)
        }
    }
}
