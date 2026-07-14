enum FilesystemDesiredCustodyPlanner {
    enum DeferredCustodySnapshot: Equatable, Sendable {
        case absent
        case retained(FilesystemObservationDesiredRegistration)
    }

    enum SelectedCustodySnapshot: Equatable, Sendable {
        case absent
        case retained(FilesystemObservationDesiredSelection)
    }

    enum StartingCustodySnapshot: Equatable, Sendable {
        case absent
        case retained(FilesystemObservationStartingNativeLifetime)
    }

    enum PredecessorSlotSnapshot: Equatable, Sendable {
        case unavailable
        case declared(FilesystemObservationPhysicalSlotState)
    }

    enum PendingConfigurationSnapshot: Equatable {
        case absent
        case retained(FilesystemObservationPendingConfigurationRecord)
    }

    struct Input: Equatable {
        let desiredRegistration: FilesystemObservationDesiredRegistration
        let deferredCustody: DeferredCustodySnapshot
        let selectedCustody: SelectedCustodySnapshot
        let startingCustody: StartingCustodySnapshot
        let predecessorSlot: PredecessorSlotSnapshot
        let retiringGenerationChain: FilesystemObservationRetiringGenerationChain
        let pendingConfiguration: PendingConfigurationSnapshot
    }

    enum PendingConfigurationSupersession: Equatable {
        case absent
        case replaceDesiredRegistration(
            retainedRecord: FilesystemObservationPendingConfigurationRecord,
            custodyRequirement: FilesystemContinuityRepairCustodyPlanner.SupersessionRequirement
        )
    }

    enum PendingConfigurationRemoval: Equatable {
        case alreadyAbsent
        case remove(FilesystemObservationPendingConfigurationRecord)
    }

    enum Plan: Equatable {
        case replaceDeferred(
            previous: FilesystemObservationDesiredRegistration,
            successor: FilesystemObservationDesiredRegistration,
            pendingConfiguration: PendingConfigurationSupersession
        )
        case deferToConfigurationCurrentness(
            desiredRegistration: FilesystemObservationDesiredRegistration,
            custodyRequirement: FilesystemContinuityRepairCustodyPlanner.SupersessionRequirement
        )
        case enqueueAtDeferredTail(
            desiredRegistration: FilesystemObservationDesiredRegistration,
            pendingConfiguration: PendingConfigurationRemoval
        )
    }

    static func plan(_ input: Input) -> Plan {
        if case .retained(let previousDesiredRegistration) = input.deferredCustody {
            return .replaceDeferred(
                previous: previousDesiredRegistration,
                successor: input.desiredRegistration,
                pendingConfiguration: pendingConfigurationSupersession(
                    input.pendingConfiguration
                )
            )
        }

        if !mayEnqueueAlongsideCurrentPredecessor(input), input.hasActiveCustody {
            return .deferToConfigurationCurrentness(
                desiredRegistration: input.desiredRegistration,
                custodyRequirement: continuitySupersessionRequirement(
                    input.pendingConfiguration
                )
            )
        }

        return .enqueueAtDeferredTail(
            desiredRegistration: input.desiredRegistration,
            pendingConfiguration: pendingConfigurationRemoval(
                input.pendingConfiguration
            )
        )
    }

    private static func mayEnqueueAlongsideCurrentPredecessor(
        _ input: Input
    ) -> Bool {
        guard
            case .replacementRetainingPredecessor(let predecessor) =
                input.desiredRegistration.admission,
            case .absent = input.selectedCustody,
            case .retained(let startingNativeLifetime) = input.startingCustody,
            startingNativeLifetime == predecessor.startingNativeLifetime,
            case .declared(.accepting(let acceptingNativeLifetime)) = input.predecessorSlot,
            acceptingNativeLifetime == predecessor,
            input.retiringGenerationChain == .none
        else {
            return false
        }
        return true
    }

    private static func pendingConfigurationSupersession(
        _ snapshot: PendingConfigurationSnapshot
    ) -> PendingConfigurationSupersession {
        switch snapshot {
        case .absent:
            return .absent
        case .retained(let record):
            return .replaceDesiredRegistration(
                retainedRecord: record,
                custodyRequirement:
                    FilesystemContinuityRepairCustodyPlanner
                    .supersessionRequirement(for: record.continuityRepairCustody)
            )
        }
    }

    private static func continuitySupersessionRequirement(
        _ snapshot: PendingConfigurationSnapshot
    ) -> FilesystemContinuityRepairCustodyPlanner.SupersessionRequirement {
        switch snapshot {
        case .absent:
            return .preserve(.absent)
        case .retained(let record):
            return FilesystemContinuityRepairCustodyPlanner.supersessionRequirement(
                for: record.continuityRepairCustody
            )
        }
    }

    private static func pendingConfigurationRemoval(
        _ snapshot: PendingConfigurationSnapshot
    ) -> PendingConfigurationRemoval {
        switch snapshot {
        case .absent:
            return .alreadyAbsent
        case .retained(let record):
            return .remove(record)
        }
    }
}

extension FilesystemDesiredCustodyPlanner.Input {
    fileprivate var hasActiveCustody: Bool {
        switch selectedCustody {
        case .retained:
            return true
        case .absent:
            break
        }
        switch startingCustody {
        case .retained:
            return true
        case .absent:
            return retiringGenerationChain != .none
        }
    }
}
