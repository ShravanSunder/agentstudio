extension FilesystemObservationSlotRegistry.ReadView {
    func fleetShutdownSlotDebt(
        for physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FilesystemObservationRegistrySlotShutdownDebt {
        guard let slotState = fleetShutdownProjectionSlotState(for: physicalSlotID) else {
            preconditionFailure("Fleet shutdown projected an undeclared physical slot")
        }
        let lifecycle = fleetShutdownLifecycle(slotState)
        let publication = fleetShutdownPublicationDebt(
            fleetShutdownProjectionPublicationRetention(for: physicalSlotID)
        )
        return FilesystemObservationRegistrySlotShutdownDebt(
            lifecycle: lifecycle,
            postStartPublication: publication
        )
    }

    var fleetShutdownDesiredCustody: FilesystemObservationDesiredShutdownCustody {
        let deferredRegistrations = deferredDesiredRegistrationsInFIFOOrder
        let deferredFIFO = deferredRegistrations.map(
            FilesystemObservationMailboxProjection.desiredShutdownReference
        )
        var pendingBySourceID = fleetShutdownProjectionPendingConfigurations
        var pendingInDeclaredSlotOrder: [FilesystemObservationDeclaredSlotPendingShutdownCustody] =
            []
        for physicalSlotID in fleetShutdownProjectionPhysicalSlotIDs {
            guard let slotState = fleetShutdownProjectionSlotState(for: physicalSlotID),
                let sourceID = fleetShutdownSourceID(slotState),
                let slotDesiredIdentity = fleetShutdownDesiredIdentity(slotState),
                let pending = pendingBySourceID[sourceID],
                pending.desiredRegistration.identity == slotDesiredIdentity
            else {
                continue
            }
            pendingBySourceID.removeValue(forKey: sourceID)
            pendingInDeclaredSlotOrder.append(
                FilesystemObservationDeclaredSlotPendingShutdownCustody(
                    physicalSlotID: physicalSlotID,
                    pending: FilesystemObservationMailboxProjection.pendingDesiredShutdownCustody(
                        pending
                    )
                )
            )
        }
        var pendingInDeferredFIFOOrder: [FilesystemObservationDeferredPendingShutdownCustody] = []
        for deferredRegistration in deferredRegistrations {
            guard let pending = pendingBySourceID[deferredRegistration.sourceID],
                pending.desiredRegistration.identity == deferredRegistration.identity
            else {
                continue
            }
            pendingBySourceID.removeValue(forKey: deferredRegistration.sourceID)
            pendingInDeferredFIFOOrder.append(
                FilesystemObservationDeferredPendingShutdownCustody(
                    deferred: FilesystemObservationMailboxProjection.desiredShutdownReference(
                        deferredRegistration
                    ),
                    pending: FilesystemObservationMailboxProjection.pendingDesiredShutdownCustody(
                        pending
                    )
                )
            )
        }
        let detachedPending: [FilesystemSourceID: FilesystemObservationPendingDesiredShutdownCustody] = Dictionary(
            uniqueKeysWithValues: pendingBySourceID.map { sourceID, pending in
                (
                    sourceID,
                    FilesystemObservationMailboxProjection.pendingDesiredShutdownCustody(
                        pending
                    )
                )
            }
        )
        return FilesystemObservationDesiredShutdownCustody(
            deferredFIFO: deferredFIFO,
            pendingInDeclaredSlotOrder: pendingInDeclaredSlotOrder,
            pendingInDeferredFIFOOrder: pendingInDeferredFIFOOrder,
            detachedPending: FilesystemObservationDetachedPendingShutdownInventory(
                pendingBySourceID: detachedPending
            )
        )
    }

    func fleetShutdownCompletedRelease(
        for physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FilesystemObservationCompletedReleaseShutdownReplay {
        guard let release = fleetShutdownProjectionCompletedRelease(for: physicalSlotID) else {
            preconditionFailure("Fleet shutdown projected an undeclared release shell")
        }
        return FilesystemObservationMailboxProjection.completedReleaseShutdownReplay(release)
    }

    private func fleetShutdownLifecycle(
        _ slotState: FilesystemObservationRegistrySlotState
    ) -> FilesystemObservationRegistrySlotShutdownLifecycle {
        switch slotState {
        case .vacant:
            return .vacant
        case .selected(let selection):
            return .selected(
                desired: FilesystemObservationMailboxProjection.desiredShutdownReference(
                    selection.desiredRegistration
                ),
                reservation: selection.reservation
            )
        case .starting(let startingNativeLifetime):
            return .starting(
                FilesystemObservationMailboxProjection.nativeShutdownReference(
                    startingNativeLifetime
                )
            )
        case .startingAwaitingAcceptingPublication(let awaiting):
            return .awaitingAcceptingPublication(
                FilesystemObservationMailboxProjection.nativeShutdownReference(
                    awaiting.startingNativeLifetime
                )
            )
        case .accepting(let publication):
            return .accepting(
                FilesystemObservationMailboxProjection.nativeShutdownReference(
                    publication.acceptingNativeLifetime.startingNativeLifetime
                ),
                disposition: FilesystemObservationMailboxProjection.postStartShutdownDisposition(
                    publication.disposition
                )
            )
        case .closingAwaitingCallbackLeaseDrain(let closing):
            return .closingAwaitingCallbackLeaseDrain(
                FilesystemObservationMailboxProjection.nativeShutdownReference(
                    closing.acceptingNativeLifetime.startingNativeLifetime
                )
            )
        case .closingAwaitingPredecessor(let lifetime):
            return .closingAwaitingPredecessor(
                FilesystemObservationMailboxProjection.nativeShutdownReference(
                    lifetime.startingNativeLifetime
                ),
                receipt: lifetime.leaseDrainReceipt,
                order: requiredRetirementOrder(for: lifetime.binding.physicalSlotID)
            )
        case .retirementFencePending(let lifetime):
            return .retirementFencePending(
                binding: lifetime.binding,
                receipt: lifetime.leaseDrainReceipt,
                fence: lifetime.fence,
                order: requiredRetirementOrder(for: lifetime.binding.physicalSlotID)
            )
        case .retirementFenceInstalled(let lifetime):
            return .retirementFenceInstalled(
                binding: lifetime.binding,
                receipt: lifetime.pendingLifetime.leaseDrainReceipt,
                fence: lifetime.fence,
                contributionIdentity: lifetime.contributionIdentity,
                order: requiredRetirementOrder(for: lifetime.binding.physicalSlotID)
            )
        case .retirementFenceTransferredAwaitingCleanup(let lifetime):
            return .retirementFenceTransferredAwaitingCleanup(
                binding: lifetime.binding,
                fence: lifetime.fence,
                retirementAuthority: lifetime.retirementAuthority,
                order: requiredRetirementOrder(for: lifetime.binding.physicalSlotID)
            )
        case .retiredAwaitingContextRelease(let lifetime):
            return .retiredAwaitingContextRelease(
                FilesystemObservationMailboxProjection.nativeRetirementShutdownReference(
                    lifetime
                ),
                order: requiredRetirementOrder(for: lifetime.binding.physicalSlotID)
            )
        case .retiringUnpublishedGeneration(let lifetime):
            return .retiringUnpublished(
                FilesystemObservationMailboxProjection.nativeShutdownReference(
                    lifetime.startingNativeLifetime
                ),
                cause: unpublishedShutdownCause(lifetime.cause),
                order: requiredRetirementOrder(
                    for: lifetime.startingNativeLifetime.binding.physicalSlotID
                )
            )
        }
    }

    private func fleetShutdownPublicationDebt(
        _ retention: FilesystemObservationPostStartPublicationRetention
    ) -> FilesystemObservationPostStartPublicationShutdownDebt {
        switch retention {
        case .vacant:
            return .vacant
        case .retained(let publication):
            return .retained(
                FilesystemObservationMailboxProjection.nativeShutdownReference(
                    publication.acceptingNativeLifetime.startingNativeLifetime
                ),
                disposition: FilesystemObservationMailboxProjection.postStartShutdownDisposition(
                    publication.disposition
                )
            )
        case .retainedAfterRemoval(let publication, let obligation):
            return .retainedAfterRemoval(
                FilesystemObservationMailboxProjection.nativeShutdownReference(
                    publication.acceptingNativeLifetime.startingNativeLifetime
                ),
                disposition: FilesystemObservationMailboxProjection.postStartShutdownDisposition(
                    publication.disposition
                ),
                removalAuthority: obligation.removalAuthority
            )
        }
    }

    private func requiredRetirementOrder(
        for physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FilesystemObservationRetirementOrder {
        guard let slotState = fleetShutdownProjectionSlotState(for: physicalSlotID),
            let sourceID = fleetShutdownSourceID(slotState)
        else {
            preconditionFailure("Retiring shutdown slot lost its source identity")
        }
        switch retiringGenerationChain(for: sourceID) {
        case .none:
            break
        case .oldest(let oldest):
            if oldest.startingNativeLifetime.binding.physicalSlotID == physicalSlotID {
                return .oldest
            }
        case .oldestAndSuccessor(let oldest, let successor):
            if oldest.startingNativeLifetime.binding.physicalSlotID == physicalSlotID {
                return .oldest
            }
            if successor.startingNativeLifetime.binding.physicalSlotID == physicalSlotID {
                return .successor
            }
        }
        preconditionFailure("Retiring shutdown slot is missing from its exact source chain")
    }

    private func fleetShutdownSourceID(
        _ slotState: FilesystemObservationRegistrySlotState
    ) -> FilesystemSourceID? {
        switch slotState {
        case .vacant:
            return nil
        case .selected(let selection):
            return selection.desiredRegistration.sourceID
        case .starting(let lifetime):
            return lifetime.desiredRegistration.sourceID
        case .startingAwaitingAcceptingPublication(let lifetime):
            return lifetime.startingNativeLifetime.desiredRegistration.sourceID
        case .accepting(let publication):
            return publication.acceptingNativeLifetime.binding.registration.sourceID
        case .closingAwaitingCallbackLeaseDrain(let lifetime):
            return lifetime.binding.registration.sourceID
        case .closingAwaitingPredecessor(let lifetime):
            return lifetime.binding.registration.sourceID
        case .retirementFencePending(let lifetime):
            return lifetime.binding.registration.sourceID
        case .retirementFenceInstalled(let lifetime):
            return lifetime.binding.registration.sourceID
        case .retirementFenceTransferredAwaitingCleanup(let lifetime):
            return lifetime.binding.registration.sourceID
        case .retiredAwaitingContextRelease(let lifetime):
            return lifetime.binding.registration.sourceID
        case .retiringUnpublishedGeneration(let lifetime):
            return lifetime.startingNativeLifetime.desiredRegistration.sourceID
        }
    }

    private func fleetShutdownDesiredIdentity(
        _ slotState: FilesystemObservationRegistrySlotState
    ) -> FilesystemObservationDesiredIdentity? {
        switch slotState {
        case .vacant:
            return nil
        case .selected(let selection):
            return selection.desiredRegistration.identity
        case .starting(let lifetime):
            return lifetime.desiredRegistration.identity
        case .startingAwaitingAcceptingPublication(let lifetime):
            return lifetime.startingNativeLifetime.desiredRegistration.identity
        case .accepting(let publication):
            return publication.acceptingNativeLifetime.startingNativeLifetime
                .desiredRegistration.identity
        case .closingAwaitingCallbackLeaseDrain(let lifetime):
            return lifetime.acceptingNativeLifetime.startingNativeLifetime
                .desiredRegistration.identity
        case .closingAwaitingPredecessor(let lifetime):
            return lifetime.startingNativeLifetime.desiredRegistration.identity
        case .retirementFencePending(let lifetime):
            return lifetime.startingNativeLifetime.desiredRegistration.identity
        case .retirementFenceInstalled(let lifetime):
            return lifetime.startingNativeLifetime.desiredRegistration.identity
        case .retirementFenceTransferredAwaitingCleanup(let lifetime):
            return lifetime.startingNativeLifetime.desiredRegistration.identity
        case .retiredAwaitingContextRelease(let lifetime):
            return lifetime.startingNativeLifetime.desiredRegistration.identity
        case .retiringUnpublishedGeneration(let lifetime):
            return lifetime.startingNativeLifetime.desiredRegistration.identity
        }
    }

    private func unpublishedShutdownCause(
        _ cause: FilesystemObservationUnpublishedGenerationRetirementCause
    ) -> FilesystemObservationUnpublishedShutdownCause {
        switch cause {
        case .desiredWithdrawn:
            return .desiredWithdrawn
        case .nativeCreateOrStartFailed(let desiredRegistration):
            return .nativeCreateOrStartFailed(
                FilesystemObservationMailboxProjection.desiredShutdownReference(
                    desiredRegistration
                )
            )
        }
    }
}
