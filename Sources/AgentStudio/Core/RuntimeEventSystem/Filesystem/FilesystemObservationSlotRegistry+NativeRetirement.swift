import Foundation

extension FilesystemObservationSlotRegistry {
    func completeRetirement(
        _ transferredLifetime: FilesystemRetirementFenceTransferredLifetime,
        disposition: FilesystemObservationSlotRetirementDisposition
    ) -> FilesystemObservationRetirementCompletionResult {
        let binding = transferredLifetime.binding
        let currentState = FilesystemObservationRetirementTransitionPlanner.completionState(
            physicalSlotState: read.state(of: binding.physicalSlotID),
            retiringGenerationChain: read.retiringGenerationChain(
                for: binding.registration.sourceID
            )
        )
        let retiredLifetime = FilesystemObservationRetirementTransitionPlanner.makeRetiredLifetime(
            transferredLifetime: transferredLifetime,
            disposition: disposition
        )
        switch FilesystemObservationRetirementTransitionPlanner.planRetirementCompletion(
            FilesystemObservationRetirementCompletionRequest(
                transferredLifetime: transferredLifetime,
                retiredLifetime: retiredLifetime,
                currentState: currentState
            )
        ) {
        case .apply(let mutation, let result):
            retiringGenerationChainsBySourceID[binding.registration.sourceID] =
                mutation.retiringGenerationChain
            statesByPhysicalSlotID[binding.physicalSlotID] =
                .retiredAwaitingContextRelease(mutation.retiredLifetime)
            return result
        case .unchanged(let result):
            return result
        }
    }

    func finalizeUnpublishedNativeGeneration(
        _ retiringLifetime: FilesystemObservationRetiringUnpublishedNativeLifetime,
        completion: DarwinFSEventUnpublishedNativeCompletion
    ) -> FilesystemObservationUnpublishedFinalReceiptResult {
        let startingNativeLifetime = retiringLifetime.startingNativeLifetime
        let binding = startingNativeLifetime.binding
        guard binding.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        guard statesByPhysicalSlotID[binding.physicalSlotID] != nil else {
            return .undeclaredPhysicalSlot
        }
        guard completion.startingNativeLifetime == startingNativeLifetime else {
            return .completionMismatch
        }
        let currentState = statesByPhysicalSlotID[binding.physicalSlotID]
        switch currentState {
        case .retiringUnpublishedGeneration(let currentRetiringLifetime):
            guard currentRetiringLifetime.startingNativeLifetime.binding == binding else {
                return .bindingMismatch
            }
            guard currentRetiringLifetime == retiringLifetime else {
                return .completionMismatch
            }
            let sourceID = retiringLifetime.startingNativeLifetime.desiredRegistration.sourceID
            let currentChain = read.retiringGenerationChain(for: sourceID)
            let currentChainLifetime = FilesystemObservationRetiringNativeLifetime.unpublished(
                retiringLifetime
            )
            switch currentChain {
            case .oldest(let oldest) where oldest == currentChainLifetime:
                break
            case .oldestAndSuccessor(let oldest, _) where oldest == currentChainLifetime:
                break
            case .oldestAndSuccessor(_, let successor) where successor == currentChainLifetime:
                return .awaitingPredecessor
            case .none, .oldest, .oldestAndSuccessor:
                return .bindingMismatch
            }
            let receipt = FilesystemObservationUnpublishedFinalReceipt(
                retiringLifetime: retiringLifetime,
                completion: completion,
                retirementAuthority: FilesystemUnpublishedRetirementAuthority(
                    value: UUIDv7.generate()
                )
            )
            let retiredLifetime = FilesystemRetiredContextReleaseLifetime.unpublished(
                FilesystemUnpublishedRetiredContextReleaseLifetime(receipt: receipt)
            )
            guard
                case .replaced(let replacementChain) = currentChain.replacing(
                    currentChainLifetime,
                    with: .retiredAwaitingContextRelease(retiredLifetime)
                )
            else {
                return .bindingMismatch
            }
            retiringGenerationChainsBySourceID[sourceID] = replacementChain
            statesByPhysicalSlotID[binding.physicalSlotID] =
                .retiredAwaitingContextRelease(retiredLifetime)
            return .finalized(receipt)
        case .retiredAwaitingContextRelease(let currentRetiredLifetime):
            guard case .unpublished(let unpublishedLifetime) = currentRetiredLifetime else {
                return .invalidSlotState(
                    projectFilesystemObservationSlotState(currentState)
                )
            }
            let receipt = unpublishedLifetime.receipt
            guard receipt.binding == binding else { return .bindingMismatch }
            guard receipt.retiringLifetime == retiringLifetime,
                receipt.completion == completion
            else {
                return .completionMismatch
            }
            return .alreadyFinalized(receipt)
        case .none:
            return .undeclaredPhysicalSlot
        case .vacant, .selected, .starting, .startingAwaitingAcceptingPublication,
            .accepting, .closingAwaitingCallbackLeaseDrain,
            .closingAwaitingPredecessor, .retirementFencePending,
            .retirementFenceInstalled, .retirementFenceTransferredAwaitingCleanup:
            return .invalidSlotState(
                projectFilesystemObservationSlotState(currentState)
            )
        }
    }

    func fenceBackedRetirementPermit(
        for receipt: FilesystemObservationSlotRetirementReceipt
    ) -> FilesystemFenceRetirementPermitResult {
        let binding = receipt.binding
        guard binding.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        guard let currentState = statesByPhysicalSlotID[binding.physicalSlotID] else {
            return .undeclaredPhysicalSlot
        }
        guard case .retiredAwaitingContextRelease(let retiredLifetime) = currentState,
            case .fenceBacked(let fenceBackedLifetime) = retiredLifetime
        else {
            return .invalidSlotState(projectFilesystemObservationSlotState(currentState))
        }
        guard fenceBackedLifetime.receipt == receipt else {
            return .receiptMismatch
        }
        return .issued(.fenceBacked(receipt))
    }

    func applyContextReleaseAcknowledgement(
        _ acknowledgement: FilesystemObservationContextReleaseAcknowledgement
    ) -> FilesystemObservationContextReleaseApplyResult {
        let binding = acknowledgement.binding
        guard binding.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        guard let currentState = statesByPhysicalSlotID[binding.physicalSlotID] else {
            return .undeclaredPhysicalSlot
        }
        switch currentState {
        case .retiredAwaitingContextRelease(let retiredLifetime):
            guard retiredLifetime.binding == binding else {
                return .bindingMismatch
            }
            guard retiredLifetime.permit == acknowledgement.permit else {
                return filesystemObservationContextReleasePermitMismatch(
                    expected: retiredLifetime.permit,
                    presented: acknowledgement.permit
                )
            }
            guard
                acknowledgementFinalizationMatchesRetiredLifetime(
                    acknowledgement,
                    retiredLifetime: retiredLifetime
                )
            else {
                return .permitLineageMismatch
            }
            let release = removeCompletedRetirement(
                retiredLifetime,
                acknowledgement: acknowledgement
            )
            guard case .applied = release else { return release }
            return release
        case .vacant, .selected:
            return completedReleaseReplayResult(
                acknowledgement,
                currentState: currentState
            )
        case .starting(let currentStartingNativeLifetime):
            return currentStartingNativeLifetime.binding == binding
                ? .invalidSlotState(projectFilesystemObservationSlotState(currentState))
                : .staleBinding
        case .startingAwaitingAcceptingPublication(let lifetime):
            return lifetime.startingNativeLifetime.binding == binding
                ? .invalidSlotState(projectFilesystemObservationSlotState(currentState))
                : .staleBinding
        case .accepting(let publication):
            return publication.acceptingNativeLifetime.binding == binding
                ? .invalidSlotState(projectFilesystemObservationSlotState(currentState))
                : .staleBinding
        case .closingAwaitingCallbackLeaseDrain(let lifetime):
            return lifetime.binding == binding
                ? .invalidSlotState(projectFilesystemObservationSlotState(currentState))
                : .staleBinding
        case .closingAwaitingPredecessor(let lifetime):
            return lifetime.binding == binding
                ? .invalidSlotState(projectFilesystemObservationSlotState(currentState))
                : .staleBinding
        case .retirementFencePending(let lifetime):
            return lifetime.binding == binding
                ? .invalidSlotState(projectFilesystemObservationSlotState(currentState))
                : .staleBinding
        case .retirementFenceInstalled(let lifetime):
            return lifetime.binding == binding
                ? .invalidSlotState(projectFilesystemObservationSlotState(currentState))
                : .staleBinding
        case .retirementFenceTransferredAwaitingCleanup(let lifetime):
            return lifetime.binding == binding
                ? .invalidSlotState(projectFilesystemObservationSlotState(currentState))
                : .staleBinding
        case .retiringUnpublishedGeneration(let lifetime):
            return lifetime.startingNativeLifetime.binding == binding
                ? .invalidSlotState(projectFilesystemObservationSlotState(currentState))
                : .staleBinding
        }
    }

    private func acknowledgementFinalizationMatchesRetiredLifetime(
        _ acknowledgement: FilesystemObservationContextReleaseAcknowledgement,
        retiredLifetime: FilesystemRetiredContextReleaseLifetime
    ) -> Bool {
        switch (acknowledgement, retiredLifetime) {
        case (.fenceBacked(let release), .fenceBacked(let retired)):
            return release.receipt == retired.receipt
                && release.finalization.startingNativeLifetime
                    == retired.startingNativeLifetime
                && release.releaseAuthority.isUUIDv7
        case (.unpublished(let release), .unpublished(let retired)):
            guard release.receipt == retired.receipt,
                release.releaseAuthority.isUUIDv7
            else {
                return false
            }
            switch release {
            case .releasedRetainedContext(_, let finalization, _):
                return retired.receipt.completion.finalizationKind == .retainedContext
                    && finalization.startingNativeLifetime
                        == retired.startingNativeLifetime
            case .neverMaterialized(_, let finalization, _):
                return retired.receipt.completion.finalizationKind == .neverMaterialized
                    && finalization.startingNativeLifetime
                        == retired.startingNativeLifetime
            }
        case (.fenceBacked, .unpublished), (.unpublished, .fenceBacked):
            return false
        }
    }

    private func completedReleaseReplayResult(
        _ acknowledgement: FilesystemObservationContextReleaseAcknowledgement,
        currentState: FilesystemObservationRegistrySlotState
    ) -> FilesystemObservationContextReleaseApplyResult {
        switch lastCompletedReleasesByPhysicalSlotID[acknowledgement.binding.physicalSlotID] {
        case .completed(let completedAcknowledgement):
            guard completedAcknowledgement.binding == acknowledgement.binding else {
                return .staleBinding
            }
            guard completedAcknowledgement.permit == acknowledgement.permit else {
                return filesystemObservationContextReleasePermitMismatch(
                    expected: completedAcknowledgement.permit,
                    presented: acknowledgement.permit
                )
            }
            guard
                completedAcknowledgement.releaseAuthority
                    == acknowledgement.releaseAuthority
            else {
                return .releaseAuthorityMismatch
            }
            return completedAcknowledgement == acknowledgement
                ? .alreadyApplied(acknowledgement)
                : .permitLineageMismatch
        case .some(.none), nil:
            return .invalidSlotState(projectFilesystemObservationSlotState(currentState))
        }
    }

    private func removeCompletedRetirement(
        _ retiredLifetime: FilesystemRetiredContextReleaseLifetime,
        acknowledgement: FilesystemObservationContextReleaseAcknowledgement
    ) -> FilesystemObservationContextReleaseApplyResult {
        let binding = retiredLifetime.binding
        let sourceID = binding.registration.sourceID
        let currentRetiringLifetime =
            FilesystemObservationRetiringNativeLifetime.retiredAwaitingContextRelease(
                retiredLifetime
            )
        let successorDisposition: FilesystemObservationSuccessorReleaseDisposition
        switch read.retiringGenerationChain(for: sourceID) {
        case .oldest(let oldest):
            guard oldest == currentRetiringLifetime else { return .bindingMismatch }
            retiringGenerationChainsBySourceID[sourceID] =
                FilesystemObservationRetiringGenerationChain.none
            successorDisposition = .none
        case .oldestAndSuccessor(let oldest, let successor):
            guard oldest == currentRetiringLifetime else { return .bindingMismatch }
            switch successor {
            case .closingAwaitingPredecessor(let awaitingLifetime):
                let pendingLifetime = FilesystemRetirementFencePendingLifetime(
                    closingNativeLifetime: awaitingLifetime.closingNativeLifetime,
                    leaseDrainReceipt: awaitingLifetime.leaseDrainReceipt,
                    fence: FilesystemObservationSlotRetirementFence(
                        binding: awaitingLifetime.binding,
                        identity: FilesystemObservationRetirementFenceIdentity(
                            value: UUIDv7.generate()
                        )
                    )
                )
                statesByPhysicalSlotID[awaitingLifetime.binding.physicalSlotID] =
                    .retirementFencePending(pendingLifetime)
                retiringGenerationChainsBySourceID[sourceID] =
                    .oldest(.retirementFencePending(pendingLifetime))
                successorDisposition = .promoted(pendingLifetime)
            case .unpublished:
                retiringGenerationChainsBySourceID[sourceID] = .oldest(successor)
                successorDisposition = .none
            case .retirementFencePending, .retirementFenceInstalled,
                .retirementFenceTransferredAwaitingCleanup,
                .retiredAwaitingContextRelease:
                preconditionFailure(
                    "Only an unpublished or predecessor-blocked successor may follow the oldest retirement"
                )
            }
        case .none:
            return .bindingMismatch
        }
        statesByPhysicalSlotID[binding.physicalSlotID] = .vacant
        lastCompletedReleasesByPhysicalSlotID[binding.physicalSlotID] =
            .completed(acknowledgement)
        return .applied(
            FilesystemObservationContextReleaseApplication(
                acknowledgement: acknowledgement,
                successorDisposition: successorDisposition
            )
        )
    }
}
