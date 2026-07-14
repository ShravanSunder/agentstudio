import Foundation

enum FilesystemObservationDesiredStateInput: Equatable, Sendable {
    case selected(FilesystemObservationDesiredSelection)
    case starting(
        FilesystemObservationStartingNativeLifetime,
        FilesystemObservationPhysicalSlotState
    )
    case deferred(FilesystemObservationDesiredRegistration)
    case retirement(FilesystemObservationRetiringGenerationChain)
}

enum FilesystemObservationStartingCurrentnessSnapshot {
    case absent
    case retained(FilesystemObservationStartingNativeLifetime)
}

enum FilesystemObservationSlotReadModel {
    static func storedBindingCurrentness(
        classifiedCurrentness: FilesystemObservationStoredBindingCurrentness,
        binding: FilesystemObservationSlotBinding,
        startingLifetime: FilesystemObservationStartingCurrentnessSnapshot
    ) -> FilesystemObservationStoredBindingCurrentness {
        guard classifiedCurrentness == .storedCurrent,
            case .retained(let currentStartingLifetime) = startingLifetime
        else {
            return classifiedCurrentness
        }
        return currentStartingLifetime.binding == binding ? .storedCurrent : .storedSuperseded
    }

    static func activeSourceIDs(
        selected: [FilesystemSourceID: FilesystemObservationDesiredSelection],
        starting: [FilesystemSourceID: FilesystemObservationStartingNativeLifetime],
        retiring: [FilesystemSourceID: FilesystemObservationRetiringGenerationChain]
    ) -> Set<FilesystemSourceID> {
        var activeSourceIDs = Set(selected.keys)
        activeSourceIDs.formUnion(starting.keys)
        activeSourceIDs.formUnion(retiring.keys)
        return activeSourceIDs
    }

    static func deferredRegistrations(
        sourceOrder: [FilesystemSourceID],
        registrationsBySourceID: [FilesystemSourceID: FilesystemObservationDesiredRegistration]
    ) -> [FilesystemObservationDesiredRegistration] {
        sourceOrder.map { sourceID in
            guard let registration = registrationsBySourceID[sourceID] else {
                preconditionFailure("FIFO source must retain one exact desired registration")
            }
            return registration
        }
    }

    static func desiredState(
        from input: FilesystemObservationDesiredStateInput
    ) -> FilesystemObservationDesiredSlotState {
        switch input {
        case .selected(let selection):
            return .selected(selection)
        case .starting(let startingLifetime, let physicalSlotState):
            switch physicalSlotState {
            case .accepting(let acceptingLifetime):
                return .accepting(acceptingLifetime)
            case .closingAwaitingCallbackLeaseDrain(let closingLifetime):
                return .closingAwaitingCallbackLeaseDrain(closingLifetime)
            case .undeclaredPhysicalSlot, .vacant, .selected, .starting,
                .closingAwaitingPredecessor, .retirementFencePending,
                .retirementFenceInstalled, .retirementFenceTransferredAwaitingCleanup,
                .retiredAwaitingContextRelease, .retiringUnpublishedGeneration:
                return .starting(startingLifetime)
            }
        case .deferred(let registration):
            return .deferred(registration)
        case .retirement(let chain):
            switch chain {
            case .none:
                return .absent
            case .oldest, .oldestAndSuccessor:
                return .retiringGenerations(chain)
            }
        }
    }

    static func pendingRetirementFence(
        from physicalSlotState: FilesystemObservationPhysicalSlotState
    ) -> FilesystemObservationPendingRetirementFenceLookup {
        guard case .retirementFencePending(let lifetime) = physicalSlotState else {
            return .notPending(physicalSlotState)
        }
        return .pending(lifetime)
    }
}
