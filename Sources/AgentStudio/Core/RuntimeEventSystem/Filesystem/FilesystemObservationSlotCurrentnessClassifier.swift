import Foundation

enum FilesystemObservationSlotCurrentnessClassifier {
    static func classify(
        binding: FilesystemObservationSlotBinding,
        fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity,
        physicalSlotState: FilesystemObservationPhysicalSlotState
    ) -> FilesystemObservationStoredBindingCurrentness {
        guard binding.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        switch physicalSlotState {
        case .undeclaredPhysicalSlot:
            return .undeclaredPhysicalSlot
        case .vacant:
            return .vacant
        case .selected:
            return .reservedWithoutBinding
        case .starting(let lifetime):
            return lifetime.binding == binding ? .storedCurrent : .storedSuperseded
        case .accepting(let lifetime):
            return lifetime.binding == binding ? .storedCurrent : .storedSuperseded
        case .closingAwaitingCallbackLeaseDrain(let lifetime):
            return lifetime.binding == binding ? .storedCurrent : .storedSuperseded
        case .closingAwaitingPredecessor, .retirementFencePending,
            .retirementFenceInstalled, .retirementFenceTransferredAwaitingCleanup,
            .retiredAwaitingContextRelease, .retiringUnpublishedGeneration:
            return .storedSuperseded
        }
    }
}
