// swiftlint:disable:next type_name
enum FilesystemObservationFleetShutdownDebtJoinRejection: Equatable, Sendable {
    case sourceGateFleetMailboxMismatch(
        expected: FilesystemObservationFleetMailboxIdentity,
        presentedBindings: [FilesystemObservationSlotBinding]
    )
    case semanticSlotCoverageMismatch(
        mailboxPhysicalSlotIDsInDeclarationOrder: [FilesystemObservationPhysicalSlotID],
        semanticPhysicalSlotIDsInPresentedOrder: [FilesystemObservationPhysicalSlotID]
    )
    case sourceGateCoverageMismatch(
        mailboxPhysicalSlotIDsInDeclarationOrder: [FilesystemObservationPhysicalSlotID],
        sourceGateBindingsInPresentedOrder: [FilesystemObservationSlotBinding]
    )
}

struct FilesystemObservationFleetShutdownDebtSnapshot: Equatable, Sendable {
    let mailbox: FilesystemObservationFleetShutdownMailboxDebtSnapshot
    let actor: FilesystemObservationFleetShutdownActorDebtSnapshot

    var shutdownIdentity: FilesystemObservationFleetShutdownIdentity {
        mailbox.shutdownIdentity
    }

    var isQuiescent: Bool {
        mailbox.isQuiescent && actor.isQuiescent
    }
}

enum FilesystemObservationFleetShutdownDebtJoinResult: Equatable, Sendable {
    case joined(FilesystemObservationFleetShutdownDebtSnapshot)
    case rejected(FilesystemObservationFleetShutdownDebtJoinRejection)
}

enum FilesystemObservationFleetShutdownAwaitedProgress: Equatable, Sendable {
    case genericLeaseCompletion(FilesystemObservationActiveLeaseShutdownDebt)
    case wholeLeaseCompletion(FilesystemObservationPendingWholeLeaseCompletionShutdownDebt)
    case genericCleanupCompletion(
        GatherShutdownInFlightCleanupDisposition<FilesystemObservationPhysicalSlotID>
    )
    case mailboxLifecycle([FilesystemObservationSlotShutdownDebt])
    case sourceGateRepairLifecycle([FilesystemSourceGateShutdownDebtSnapshot])
}

enum FilesystemObservationFleetShutdownTurnPlan: Equatable, Sendable {
    case advanceMailbox
    case advanceActorDrain
    case beginSourceGateShutdown
    case awaitOwnedProgress(FilesystemObservationFleetShutdownAwaitedProgress)
    case readyForCompletion
}

enum FilesystemObservationFleetShutdownRetainedDebt: Equatable, Sendable {
    case awaitingInitialCapture
    case incomplete(
        snapshot: FilesystemObservationFleetShutdownDebtSnapshot,
        turnPlan: FilesystemObservationFleetShutdownTurnPlan
    )
}

enum FilesystemObservationFleetShutdownResumeFailure: Equatable, Sendable {
    case shutdownNotBegun
    case shutdownFreezeInProgress
    case fleetMailboxMismatch(
        expected: FilesystemObservationFleetMailboxIdentity,
        presented: FilesystemObservationFleetMailboxIdentity
    )
    case shutdownIdentityMismatch(
        expected: FilesystemObservationFleetShutdownIdentity,
        presented: FilesystemObservationFleetShutdownIdentity
    )
    case shutdownRejected
    case mailboxShutdownNotFrozen
    case actorDrainConfigurationRejected(
        FilesystemObservationFleetShutdownDrainConfigurationRejection
    )
    case actorDrainUndeclaredBinding(FilesystemObservationSlotBinding)
    case actorDrainMailboxClosed
    case terminationAlreadyAdvanced(FilesystemObservationLifecycleStateSnapshot)
    case debtJoinRejected(FilesystemObservationFleetShutdownDebtJoinRejection)
}

enum FilesystemFleetShutdownAwaitedActorProgress: Equatable, Sendable {
    case recoveryContextUnavailable(
        binding: FilesystemObservationSlotBinding,
        evidence: FixedFilesystemRecoveryEvidenceRevision
    )
}

enum FilesystemObservationFleetShutdownResumeResult: Equatable, Sendable {
    case incomplete(
        snapshot: FilesystemObservationFleetShutdownDebtSnapshot,
        turnPlan: FilesystemObservationFleetShutdownTurnPlan
    )
    case awaitingActorProgress(
        FilesystemFleetShutdownAwaitedActorProgress,
        snapshot: FilesystemObservationFleetShutdownDebtSnapshot,
        turnPlan: FilesystemObservationFleetShutdownTurnPlan
    )
    case completed(FilesystemObservationFleetShutdownReceipt)
    case resumeAlreadyInProgress(FilesystemObservationFleetShutdownRetainedDebt)
    case unavailable(FilesystemObservationFleetShutdownResumeFailure)
}

enum FilesystemObservationFleetShutdownDebtJoiner {
    static func join(
        mailbox: FilesystemObservationFleetShutdownMailboxDebtSnapshot,
        actor: FilesystemObservationFleetShutdownActorDebtSnapshot
    ) -> FilesystemObservationFleetShutdownDebtJoinResult {
        let mailboxPhysicalSlotIDs = mailbox.slots.map(\.physicalSlotID)
        let semanticSlotsByPhysicalSlotID = uniqueSemanticSlotsByPhysicalSlotID(
            actor.semanticReplay.slots
        )
        guard
            semanticSlotsByPhysicalSlotID.count == mailboxPhysicalSlotIDs.count,
            mailboxPhysicalSlotIDs.allSatisfy({ semanticSlotsByPhysicalSlotID[$0] != nil })
        else {
            return .rejected(
                .semanticSlotCoverageMismatch(
                    mailboxPhysicalSlotIDsInDeclarationOrder: mailboxPhysicalSlotIDs,
                    semanticPhysicalSlotIDsInPresentedOrder: actor.semanticReplay.slots.map(
                        \.physicalSlotID
                    )
                )
            )
        }

        let sourceGatesByPhysicalSlotID = uniqueSourceGatesByPhysicalSlotID(
            actor.sourceGatesInBindingDeclarationOrder
        )
        let foreignSourceGateBindings = actor.sourceGatesInBindingDeclarationOrder
            .map(\.binding)
            .filter { $0.fleetMailboxIdentity != mailbox.fleetMailboxIdentity }
        guard foreignSourceGateBindings.isEmpty else {
            return .rejected(
                .sourceGateFleetMailboxMismatch(
                    expected: mailbox.fleetMailboxIdentity,
                    presentedBindings: foreignSourceGateBindings
                )
            )
        }
        guard
            sourceGatesByPhysicalSlotID.count == mailboxPhysicalSlotIDs.count,
            mailboxPhysicalSlotIDs.allSatisfy({ sourceGatesByPhysicalSlotID[$0] != nil })
        else {
            return .rejected(
                .sourceGateCoverageMismatch(
                    mailboxPhysicalSlotIDsInDeclarationOrder: mailboxPhysicalSlotIDs,
                    sourceGateBindingsInPresentedOrder: actor.sourceGatesInBindingDeclarationOrder
                        .map(\.binding)
                )
            )
        }

        let normalizedActor = FilesystemObservationFleetShutdownActorDebtSnapshot(
            semanticReplay: FilesystemObservationSemanticShutdownDebtSnapshot(
                slots: mailboxPhysicalSlotIDs.map { physicalSlotID in
                    guard let slot = semanticSlotsByPhysicalSlotID[physicalSlotID] else {
                        preconditionFailure("Validated semantic shutdown slot disappeared")
                    }
                    return slot
                }
            ),
            sourceGatesInBindingDeclarationOrder: mailboxPhysicalSlotIDs.map { physicalSlotID in
                guard let sourceGate = sourceGatesByPhysicalSlotID[physicalSlotID] else {
                    preconditionFailure("Validated SourceGate shutdown debt disappeared")
                }
                return sourceGate
            }
        )
        return .joined(
            FilesystemObservationFleetShutdownDebtSnapshot(
                mailbox: mailbox,
                actor: normalizedActor
            )
        )
    }

    private static func uniqueSemanticSlotsByPhysicalSlotID(
        _ slots: [FilesystemObservationSemanticShutdownSlotDebt]
    ) -> [FilesystemObservationPhysicalSlotID: FilesystemObservationSemanticShutdownSlotDebt] {
        var slotsByPhysicalSlotID:
            [FilesystemObservationPhysicalSlotID: FilesystemObservationSemanticShutdownSlotDebt] = [:]
        for slot in slots {
            guard slotsByPhysicalSlotID[slot.physicalSlotID] == nil else { return [:] }
            slotsByPhysicalSlotID[slot.physicalSlotID] = slot
        }
        return slotsByPhysicalSlotID
    }

    private static func uniqueSourceGatesByPhysicalSlotID(
        _ sourceGates: [FilesystemSourceGateShutdownDebtSnapshot]
    ) -> [FilesystemObservationPhysicalSlotID: FilesystemSourceGateShutdownDebtSnapshot] {
        var sourceGatesByPhysicalSlotID:
            [FilesystemObservationPhysicalSlotID: FilesystemSourceGateShutdownDebtSnapshot] = [:]
        for sourceGate in sourceGates {
            let physicalSlotID = sourceGate.binding.physicalSlotID
            guard sourceGatesByPhysicalSlotID[physicalSlotID] == nil else { return [:] }
            sourceGatesByPhysicalSlotID[physicalSlotID] = sourceGate
        }
        return sourceGatesByPhysicalSlotID
    }
}

enum FilesystemObservationFleetShutdownTurnPlanner {
    static func plan(
        _ snapshot: FilesystemObservationFleetShutdownDebtSnapshot
    ) -> FilesystemObservationFleetShutdownTurnPlan {
        if hasMailboxPreDrainProgress(snapshot.mailbox) {
            return .advanceMailbox
        }
        if case .vacant = snapshot.mailbox.activeLease {
            // Continue to the next exact custody class.
        } else {
            return .awaitOwnedProgress(.genericLeaseCompletion(snapshot.mailbox.activeLease))
        }
        if case .vacant = snapshot.mailbox.pendingWholeLeaseCompletion {
            // Continue to the next exact custody class.
        } else {
            return .awaitOwnedProgress(
                .wholeLeaseCompletion(snapshot.mailbox.pendingWholeLeaseCompletion)
            )
        }
        if case .vacant = snapshot.mailbox.genericMailboxDebt.inFlightCleanup {
            // Continue to actor-owned progress.
        } else {
            return .awaitOwnedProgress(
                .genericCleanupCompletion(snapshot.mailbox.genericMailboxDebt.inFlightCleanup)
            )
        }
        if hasActorDrainProgress(snapshot) {
            return .advanceActorDrain
        }
        if snapshot.actor.hasReadySourceGate {
            return .beginSourceGateShutdown
        }
        if snapshot.actor.haveAllSourceGatesBegunShutdown,
            hasMailboxFinalizationProgress(snapshot.mailbox)
        {
            return .advanceMailbox
        }
        if snapshot.isQuiescent {
            return .readyForCompletion
        }
        if !snapshot.mailbox.isQuiescent {
            return .awaitOwnedProgress(.mailboxLifecycle(snapshot.mailbox.slots))
        }
        return .awaitOwnedProgress(
            .sourceGateRepairLifecycle(snapshot.actor.sourceGatesInBindingDeclarationOrder)
        )
    }

    private static func hasMailboxPreDrainProgress(
        _ mailbox: FilesystemObservationFleetShutdownMailboxDebtSnapshot
    ) -> Bool {
        if !FilesystemObservationFleetShutdownProgressPlanner
            .desiredWithdrawalCandidates(from: mailbox).isEmpty
            || !mailbox.retirementFenceReadyFIFO.isEmpty
        {
            return true
        }
        if case .retained = mailbox.genericMailboxDebt.queuedCleanup {
            return true
        }
        return mailbox.slots.contains(where: hasMailboxPreDrainProgress)
    }

    private static func hasMailboxPreDrainProgress(
        _ slot: FilesystemObservationSlotShutdownDebt
    ) -> Bool {
        guard case .issued(_, let nativeProjection) = slot.nativeOwner else { return false }
        switch nativeProjection.advancePhase {
        case .available, .inFlight:
            return true
        case .completed:
            switch slot.registry.lifecycle {
            case .starting, .closingAwaitingCallbackLeaseDrain:
                return true
            case .retiringUnpublished:
                return slot.generic.recoveryDisposition == .vacant
            case .retiredAwaitingContextRelease:
                return false
            case .vacant, .selected, .awaitingAcceptingPublication, .accepting,
                .closingAwaitingPredecessor, .retirementFencePending,
                .retirementFenceInstalled, .retirementFenceTransferredAwaitingCleanup:
                return false
            }
        }
    }

    private static func hasMailboxFinalizationProgress(
        _ mailbox: FilesystemObservationFleetShutdownMailboxDebtSnapshot
    ) -> Bool {
        mailbox.slots.contains { slot in
            guard case .issued(_, let nativeProjection) = slot.nativeOwner,
                case .completed = nativeProjection.advancePhase,
                case .retiredAwaitingContextRelease = slot.registry.lifecycle
            else {
                return false
            }
            switch nativeProjection.finalizationPhase {
            case .awaitingMaterialization, .retainedContext, .retirementPermitRetained,
                .finalizing, .finalized:
                return true
            }
        }
    }

    private static func hasActorDrainProgress(
        _ snapshot: FilesystemObservationFleetShutdownDebtSnapshot
    ) -> Bool {
        if !snapshot.actor.isSemanticTransferQuiescent {
            return true
        }
        return snapshot.mailbox.genericMailboxDebt.keyDebt.contains(
            where: hasActorDrainCustody
        )
    }

    private static func hasActorDrainCustody(
        _ debt: GatherShutdownKeyDebt<FilesystemObservationPhysicalSlotID>
    ) -> Bool {
        debt.queuedContributionCount > 0
            || debt.queuedItemCount > 0
            || debt.queuedByteCount > 0
            || debt.retryDisposition == .retained
            || debt.recoveryDisposition != .vacant
    }
}
