enum FilesystemObservationFleetShutdownProgress: Equatable, Sendable {
    case desiredCustodyWithdrawn(FilesystemObservationDesiredShutdownReference)
    case nativeOwnerAdvanced(DarwinFSEventNativeOwnerFleetShutdownResult)
    case nativeCompletionApplied(DarwinNativeOwnerShutdownCompletionReference)
    case retirementFenceAdvanced(FilesystemObservationPhysicalSlotID)
    case genericCleanupPerformed
    case finalRetirementPermitRetained(FilesystemObservationSlotBinding)
    case nativeContextFinalized(
        binding: FilesystemObservationSlotBinding,
        releaseAuthority: FilesystemObservationContextReleaseAuthority
    )
    case contextReleaseAcknowledgementApplied(
        binding: FilesystemObservationSlotBinding,
        releaseAuthority: FilesystemObservationContextReleaseAuthority
    )
}

struct FilesystemObservationFleetShutdownProgressReceipt: Equatable, Sendable {
    let progress: FilesystemObservationFleetShutdownProgress
    let debt: FilesystemObservationFleetShutdownMailboxDebtSnapshot
}

enum FilesystemObservationFleetShutdownProgressResult: Equatable, Sendable {
    case progressed(FilesystemObservationFleetShutdownProgressReceipt)
    case noProgress(FilesystemObservationFleetShutdownMailboxDebtSnapshot)
    case shutdownNotFrozen
    case shutdownIdentityMismatch(
        expected: FilesystemObservationFleetShutdownIdentity,
        presented: FilesystemObservationFleetShutdownIdentity
    )
    case terminationAlreadyAdvanced(FilesystemObservationLifecycleStateSnapshot)
}

enum FilesystemObservationFleetShutdownProgressPlanner {
    static func desiredWithdrawalCandidates(
        from debt: FilesystemObservationFleetShutdownMailboxDebtSnapshot
    ) -> [FilesystemObservationDesiredShutdownReference] {
        let pendingByPhysicalSlotID = Dictionary(
            uniqueKeysWithValues: debt.desiredCustody.pendingInDeclaredSlotOrder.map {
                ($0.physicalSlotID, $0.pending.desired)
            }
        )
        var candidates: [FilesystemObservationDesiredShutdownReference] = []
        for slot in debt.slots {
            if case .selected(let desired, _) = slot.registry.lifecycle {
                candidates.append(desired)
            }
            if let pending = pendingByPhysicalSlotID[slot.physicalSlotID] {
                candidates.append(pending)
            }
        }
        candidates.append(contentsOf: debt.desiredCustody.deferredFIFO)
        return candidates
    }

    static func hasQueuedGenericCleanup(
        _ debt: GatherShutdownDebtSnapshot<FilesystemObservationPhysicalSlotID>
    ) -> Bool {
        guard case .retained = debt.queuedCleanup else { return false }
        return true
    }
}
