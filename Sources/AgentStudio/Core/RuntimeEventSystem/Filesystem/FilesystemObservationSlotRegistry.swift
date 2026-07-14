import Foundation

/// Fixed-cardinality owner of physical slots and their current bindings.
///
/// This owner is intentionally non-locking. Its eventual mailbox caller must hold the
/// wrapper coordination lock. UUIDv7 values provide opaque identity only: exact stored
/// equality determines currentness, and UUID order never determines lifecycle or FIFO.
final class FilesystemObservationSlotRegistry {
    private enum SlotState: Equatable {
        case vacant
        case selected(FilesystemObservationDesiredSelection)
        case starting(FilesystemObservationStartingNativeLifetime)
        case accepting(FilesystemObservationAcceptingNativeLifetime)
        case closingAwaitingCallbackLeaseDrain(
            FilesystemObservationClosingAwaitingCallbackLeaseDrainLifetime
        )
        case closingAwaitingPredecessor(
            FilesystemClosingAwaitingPredecessorLifetime
        )
        case retirementFencePending(FilesystemRetirementFencePendingLifetime)
        case retirementFenceInstalled(FilesystemRetirementFenceInstalledLifetime)
        case retiringUnpublishedGeneration(
            FilesystemObservationRetiringUnpublishedNativeLifetime
        )
    }

    let maximumSimultaneousSourceCount: Int
    let replacementReserveSlotCount: Int
    let physicalSlotCount: Int
    let fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity
    let physicalSlotIDs: [FilesystemObservationPhysicalSlotID]

    private var statesByPhysicalSlotID: [FilesystemObservationPhysicalSlotID: SlotState]
    private var deferredSourceOrder: [FilesystemSourceID] = []
    private var deferredDesiredRegistrationsBySourceID: [FilesystemSourceID: FilesystemObservationDesiredRegistration] =
        [:]
    private var selectedDesiredSourcesBySourceID: [FilesystemSourceID: FilesystemObservationDesiredSelection] = [:]
    private var startingNativeLifetimesBySourceID: [FilesystemSourceID: FilesystemObservationStartingNativeLifetime] =
        [:]
    private var retiringGenerationChainsBySourceID: [FilesystemSourceID: FilesystemObservationRetiringGenerationChain] =
        [:]
    private var pendingConfigurationDesiredBySourceID: [FilesystemSourceID: FilesystemObservationDesiredRegistration] =
        [:]

    var deferredDesiredRegistrationsInFIFOOrder: [FilesystemObservationDesiredRegistration] {
        deferredSourceOrder.map { sourceID in
            guard
                let desiredRegistration =
                    deferredDesiredRegistrationsBySourceID[sourceID]
            else {
                preconditionFailure("FIFO source must retain one exact desired registration")
            }
            return desiredRegistration
        }
    }

    func retiringGenerationChain(
        for sourceID: FilesystemSourceID
    ) -> FilesystemObservationRetiringGenerationChain {
        retiringGenerationChainsBySourceID[sourceID] ?? .none
    }

    init(
        maximumSimultaneousSourceCount: Int,
        replacementReserveSlotCount: Int
    ) throws {
        guard maximumSimultaneousSourceCount > 0 else {
            throw
                FilesystemObservationSlotConfigurationError
                .nonPositiveMaximumSimultaneousSourceCount(maximumSimultaneousSourceCount)
        }
        guard replacementReserveSlotCount >= 0 else {
            throw
                FilesystemObservationSlotConfigurationError
                .negativeReplacementReserveSlotCount(replacementReserveSlotCount)
        }
        let (physicalSlotCount, physicalSlotCountOverflow) =
            maximumSimultaneousSourceCount.addingReportingOverflow(
                replacementReserveSlotCount
            )
        guard !physicalSlotCountOverflow else {
            throw FilesystemObservationSlotConfigurationError.physicalSlotCountOverflow
        }

        self.maximumSimultaneousSourceCount = maximumSimultaneousSourceCount
        self.replacementReserveSlotCount = replacementReserveSlotCount
        self.physicalSlotCount = physicalSlotCount
        fleetMailboxIdentity = FilesystemObservationFleetMailboxIdentity(
            value: UUIDv7.generate()
        )
        physicalSlotIDs = (0..<physicalSlotCount).map { _ in
            FilesystemObservationPhysicalSlotID(
                value: UUIDv7.generate()
            )
        }
        statesByPhysicalSlotID = Dictionary(
            uniqueKeysWithValues: physicalSlotIDs.map { ($0, .vacant) }
        )
    }

    func state(
        of physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FilesystemObservationPhysicalSlotState {
        guard let slotState = statesByPhysicalSlotID[physicalSlotID] else {
            return .undeclaredPhysicalSlot
        }
        switch slotState {
        case .vacant:
            return .vacant
        case .selected(let selection):
            return .selected(selection)
        case .starting(let startingNativeLifetime):
            return .starting(startingNativeLifetime)
        case .accepting(let acceptingNativeLifetime):
            return .accepting(acceptingNativeLifetime)
        case .closingAwaitingCallbackLeaseDrain(let closingNativeLifetime):
            return .closingAwaitingCallbackLeaseDrain(closingNativeLifetime)
        case .closingAwaitingPredecessor(let lifetime):
            return .closingAwaitingPredecessor(lifetime)
        case .retirementFencePending(let lifetime):
            return .retirementFencePending(lifetime)
        case .retirementFenceInstalled(let lifetime):
            return .retirementFenceInstalled(lifetime)
        case .retiringUnpublishedGeneration(let retiringNativeLifetime):
            return .retiringUnpublishedGeneration(retiringNativeLifetime)
        }
    }

    func storedBindingCurrentness(
        of binding: FilesystemObservationSlotBinding
    ) -> FilesystemObservationStoredBindingCurrentness {
        guard binding.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        guard let slotState = statesByPhysicalSlotID[binding.physicalSlotID] else {
            return .undeclaredPhysicalSlot
        }
        switch slotState {
        case .vacant:
            return .vacant
        case .selected:
            return .reservedWithoutBinding
        case .starting(let startingNativeLifetime):
            return startingNativeLifetime.binding == binding
                ? .storedCurrent : .storedSuperseded
        case .accepting(let acceptingNativeLifetime):
            return acceptingNativeLifetime.binding == binding
                ? .storedCurrent : .storedSuperseded
        case .closingAwaitingCallbackLeaseDrain(let closingNativeLifetime):
            return closingNativeLifetime.binding == binding
                ? .storedCurrent : .storedSuperseded
        case .closingAwaitingPredecessor, .retirementFencePending,
            .retirementFenceInstalled, .retiringUnpublishedGeneration:
            return .storedSuperseded
        }
    }

    func recordDesiredRegistration(
        _ registration: FSEventRegistrationToken
    ) -> FilesystemObservationDesiredUpdateResult {
        let sourceID = registration.sourceID
        let desiredRegistration = makeDesiredRegistration(registration)
        if let previousDesiredRegistration =
            deferredDesiredRegistrationsBySourceID[sourceID]
        {
            deferredDesiredRegistrationsBySourceID[sourceID] = desiredRegistration
            return .replacedDeferred(previousDesiredRegistration, desiredRegistration)
        }

        if selectedDesiredSourcesBySourceID[sourceID] != nil
            || startingNativeLifetimesBySourceID[sourceID] != nil
            || retiringGenerationChain(for: sourceID) != .none
        {
            pendingConfigurationDesiredBySourceID[sourceID] = desiredRegistration
            return .deferredToConfigurationCurrentness(desiredRegistration)
        }

        deferredDesiredRegistrationsBySourceID[sourceID] = desiredRegistration
        deferredSourceOrder.append(sourceID)
        return .enqueued(desiredRegistration)
    }

    func selectNextDesiredSource() -> FilesystemObservationDesiredSelectionResult {
        guard let oldestDeferredSourceID = deferredSourceOrder.first else {
            return .noDeferredDesiredSource
        }
        let currentActiveLogicalSourceCount = activeLogicalSourceCount
        var encounteredActiveSourceCapacityLimit = false
        for (sourceIndex, sourceID) in deferredSourceOrder.enumerated() {
            let retirementChain = retiringGenerationChain(for: sourceID)
            if case .oldestAndSuccessor = retirementChain {
                continue
            }
            if !isActiveLogicalSource(sourceID)
                && currentActiveLogicalSourceCount >= maximumSimultaneousSourceCount
            {
                encounteredActiveSourceCapacityLimit = true
                continue
            }
            guard let physicalSlotID = firstVacantPhysicalSlotID() else {
                return .deferredBehindSlotCapacity
            }
            guard let desiredRegistration = deferredDesiredRegistrationsBySourceID[sourceID] else {
                preconditionFailure("FIFO source must retain one exact desired registration")
            }

            let reservation = FilesystemObservationSlotReservation(
                fleetMailboxIdentity: fleetMailboxIdentity,
                physicalSlotID: physicalSlotID,
                desiredIdentity: desiredRegistration.identity,
                identity: FilesystemObservationSlotReservationIdentity(
                    value: UUIDv7.generate()
                )
            )
            let selection = FilesystemObservationDesiredSelection(
                desiredRegistration: desiredRegistration,
                reservation: reservation
            )
            deferredSourceOrder.remove(at: sourceIndex)
            deferredDesiredRegistrationsBySourceID.removeValue(forKey: sourceID)
            selectedDesiredSourcesBySourceID[sourceID] = selection
            statesByPhysicalSlotID[physicalSlotID] = .selected(selection)
            return .selected(selection)
        }

        if encounteredActiveSourceCapacityLimit {
            return .deferredBehindActiveSourceCapacity
        }
        let oldestRetirementChain = retiringGenerationChain(
            for: oldestDeferredSourceID
        )
        guard case .oldestAndSuccessor(let oldest, let successor) = oldestRetirementChain else {
            preconditionFailure("Deferred source scan must find an eligible or chain-blocked source")
        }
        return .deferredBehindRetiringGenerationLimit(
            oldest: oldest,
            successor: successor
        )
    }

    func desiredState(
        for sourceID: FilesystemSourceID
    ) -> FilesystemObservationDesiredSlotState {
        if let selection = selectedDesiredSourcesBySourceID[sourceID] {
            return .selected(selection)
        }
        if let startingNativeLifetime = startingNativeLifetimesBySourceID[sourceID] {
            switch statesByPhysicalSlotID[startingNativeLifetime.binding.physicalSlotID] {
            case .accepting(let acceptingNativeLifetime):
                return .accepting(acceptingNativeLifetime)
            case .closingAwaitingCallbackLeaseDrain(let closingNativeLifetime):
                return .closingAwaitingCallbackLeaseDrain(closingNativeLifetime)
            case .starting, .vacant, .selected, .closingAwaitingPredecessor,
                .retirementFencePending, .retirementFenceInstalled,
                .retiringUnpublishedGeneration, .none:
                return .starting(startingNativeLifetime)
            }
        }
        if let desiredRegistration = deferredDesiredRegistrationsBySourceID[sourceID] {
            return .deferred(desiredRegistration)
        }
        let retirementChain = retiringGenerationChain(for: sourceID)
        switch retirementChain {
        case .none:
            return .absent
        case .oldest, .oldestAndSuccessor:
            return .retiringGenerations(retirementChain)
        }
    }

    func pendingConfigurationState(
        for sourceID: FilesystemSourceID
    ) -> FilesystemObservationPendingConfigurationState {
        guard let desiredRegistration = pendingConfigurationDesiredBySourceID[sourceID] else {
            return .absent
        }
        return .retained(desiredRegistration)
    }

    func withdrawDesiredSource(
        sourceID: FilesystemSourceID,
        desiredIdentity: FilesystemObservationDesiredIdentity
    ) -> FilesystemObservationDesiredWithdrawalResult {
        let pendingDesiredRegistration = pendingConfigurationDesiredBySourceID[sourceID]
        if let pendingDesiredRegistration,
            pendingDesiredRegistration.identity == desiredIdentity
        {
            pendingConfigurationDesiredBySourceID.removeValue(forKey: sourceID)
            return .withdrewPendingConfiguration(pendingDesiredRegistration)
        }
        if let selection = selectedDesiredSourcesBySourceID[sourceID] {
            guard selection.desiredRegistration.identity == desiredIdentity else {
                return .staleDesiredIdentity(
                    pendingDesiredRegistration?.identity ?? selection.desiredRegistration.identity
                )
            }
            selectedDesiredSourcesBySourceID.removeValue(forKey: sourceID)
            statesByPhysicalSlotID[selection.reservation.physicalSlotID] = .vacant
            promotePendingConfigurationDesiredToFIFO(for: sourceID)
            return .releasedSelectedReservation(selection)
        }
        if let startingNativeLifetime = startingNativeLifetimesBySourceID[sourceID] {
            guard startingNativeLifetime.desiredRegistration.identity == desiredIdentity else {
                return .staleDesiredIdentity(
                    pendingDesiredRegistration?.identity
                        ?? startingNativeLifetime.desiredRegistration.identity
                )
            }
            startingNativeLifetimesBySourceID.removeValue(forKey: sourceID)
            let retiringNativeLifetime = FilesystemObservationRetiringUnpublishedNativeLifetime(
                startingNativeLifetime: startingNativeLifetime,
                cause: .desiredWithdrawn
            )
            appendRetiringUnpublishedNativeLifetime(
                retiringNativeLifetime,
                for: sourceID
            )
            statesByPhysicalSlotID[startingNativeLifetime.binding.physicalSlotID] =
                .retiringUnpublishedGeneration(retiringNativeLifetime)
            return .retiringGeneration(.unpublished(retiringNativeLifetime))
        }
        if let desiredRegistration = deferredDesiredRegistrationsBySourceID[sourceID] {
            guard desiredRegistration.identity == desiredIdentity else {
                return .staleDesiredIdentity(desiredRegistration.identity)
            }
            deferredDesiredRegistrationsBySourceID.removeValue(forKey: sourceID)
            deferredSourceOrder.removeAll { $0 == sourceID }
            return .withdrewDeferred(desiredRegistration)
        }
        switch retiringGenerationChain(for: sourceID) {
        case .none:
            return .alreadyAbsent
        case .oldest(let oldestRetirement):
            let oldestDesiredRegistration =
                oldestRetirement.startingNativeLifetime.desiredRegistration
            guard oldestDesiredRegistration.identity == desiredIdentity else {
                return .staleDesiredIdentity(
                    pendingDesiredRegistration?.identity ?? oldestDesiredRegistration.identity
                )
            }
            return .retiringGeneration(oldestRetirement)
        case .oldestAndSuccessor(let oldestRetirement, let successorRetirement):
            let oldestDesiredRegistration =
                oldestRetirement.startingNativeLifetime.desiredRegistration
            if oldestDesiredRegistration.identity == desiredIdentity {
                return .retiringGeneration(oldestRetirement)
            }
            let successorDesiredRegistration =
                successorRetirement.startingNativeLifetime.desiredRegistration
            guard successorDesiredRegistration.identity == desiredIdentity else {
                return .staleDesiredIdentity(
                    pendingDesiredRegistration?.identity ?? successorDesiredRegistration.identity
                )
            }
            return .retiringGeneration(successorRetirement)
        }
    }

    func releaseSelectedReservationAfterFailure(
        _ reservation: FilesystemObservationSlotReservation
    ) -> FilesystemObservationReservationReleaseResult {
        guard reservation.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        guard let slotState = statesByPhysicalSlotID[reservation.physicalSlotID] else {
            return .reservationNoLongerCurrent
        }
        switch slotState {
        case .vacant:
            return .reservationNoLongerCurrent
        case .selected(let selection):
            guard selection.reservation == reservation else {
                return .staleReservation(selection.reservation)
            }
            let sourceID = selection.desiredRegistration.sourceID
            selectedDesiredSourcesBySourceID.removeValue(forKey: sourceID)
            statesByPhysicalSlotID[reservation.physicalSlotID] = .vacant
            let desiredRegistration =
                pendingConfigurationDesiredBySourceID.removeValue(forKey: sourceID)
                ?? selection.desiredRegistration
            deferredDesiredRegistrationsBySourceID[sourceID] = desiredRegistration
            deferredSourceOrder.append(sourceID)
            return .releasedAndRotatedToDeferredTail(desiredRegistration)
        case .starting(let startingNativeLifetime):
            guard startingNativeLifetime.consumedReservation == reservation else {
                return .reservationNoLongerCurrent
            }
            return .nativeLifetimeAlreadyCommitted(startingNativeLifetime)
        case .accepting(let acceptingNativeLifetime):
            return .nativeLifetimeAlreadyCommitted(
                acceptingNativeLifetime.startingNativeLifetime
            )
        case .closingAwaitingCallbackLeaseDrain(let closingNativeLifetime):
            return .nativeLifetimeAlreadyCommitted(
                closingNativeLifetime.acceptingNativeLifetime.startingNativeLifetime
            )
        case .closingAwaitingPredecessor(let lifetime):
            return .nativeLifetimeAlreadyCommitted(lifetime.startingNativeLifetime)
        case .retirementFencePending(let lifetime):
            return .nativeLifetimeAlreadyCommitted(lifetime.startingNativeLifetime)
        case .retirementFenceInstalled(let lifetime):
            return .nativeLifetimeAlreadyCommitted(lifetime.startingNativeLifetime)
        case .retiringUnpublishedGeneration(let retiringNativeLifetime):
            guard
                retiringNativeLifetime.startingNativeLifetime.consumedReservation
                    == reservation
            else {
                return .reservationNoLongerCurrent
            }
            return .nativeLifetimeAlreadyCommitted(
                retiringNativeLifetime.startingNativeLifetime
            )
        }
    }

    func beginNativeLifetime(
        _ reservation: FilesystemObservationSlotReservation
    ) -> FilesystemObservationNativeLifetimeCommitResult {
        guard reservation.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        guard let slotState = statesByPhysicalSlotID[reservation.physicalSlotID] else {
            return .undeclaredPhysicalSlot
        }
        switch slotState {
        case .vacant:
            return .reservationNoLongerCurrent
        case .selected(let selection):
            guard selection.reservation == reservation else {
                return .staleReservation(selection.reservation)
            }
            if let pendingDesiredRegistration =
                pendingConfigurationDesiredBySourceID[selection.desiredRegistration.sourceID]
            {
                return .deferredToConfigurationCurrentness(pendingDesiredRegistration)
            }
            let binding = FilesystemObservationSlotBinding(
                fleetMailboxIdentity: fleetMailboxIdentity,
                physicalSlotID: reservation.physicalSlotID,
                identity: FilesystemObservationSlotBindingIdentity(
                    value: UUIDv7.generate()
                ),
                registration: selection.desiredRegistration.registration,
                controlBlockIdentity: FilesystemObservationControlBlockIdentity(
                    value: UUIDv7.generate()
                )
            )
            let startingNativeLifetime = FilesystemObservationStartingNativeLifetime(
                desiredRegistration: selection.desiredRegistration,
                consumedReservation: reservation,
                binding: binding,
                nativeGenerationIdentity: FilesystemObservationNativeGenerationIdentity(
                    value: UUIDv7.generate()
                )
            )
            let sourceID = selection.desiredRegistration.sourceID
            selectedDesiredSourcesBySourceID.removeValue(forKey: sourceID)
            startingNativeLifetimesBySourceID[sourceID] = startingNativeLifetime
            statesByPhysicalSlotID[reservation.physicalSlotID] =
                .starting(startingNativeLifetime)
            return .committed(startingNativeLifetime)
        case .starting(let startingNativeLifetime):
            guard startingNativeLifetime.consumedReservation == reservation else {
                return .reservationNoLongerCurrent
            }
            return .alreadyCommitted(startingNativeLifetime)
        case .accepting(let acceptingNativeLifetime):
            return .alreadyCommitted(acceptingNativeLifetime.startingNativeLifetime)
        case .closingAwaitingCallbackLeaseDrain(let closingNativeLifetime):
            return .alreadyCommitted(
                closingNativeLifetime.acceptingNativeLifetime.startingNativeLifetime
            )
        case .closingAwaitingPredecessor(let lifetime):
            return .alreadyCommitted(lifetime.startingNativeLifetime)
        case .retirementFencePending(let lifetime):
            return .alreadyCommitted(lifetime.startingNativeLifetime)
        case .retirementFenceInstalled(let lifetime):
            return .alreadyCommitted(lifetime.startingNativeLifetime)
        case .retiringUnpublishedGeneration(let retiringNativeLifetime):
            guard
                retiringNativeLifetime.startingNativeLifetime.consumedReservation
                    == reservation
            else {
                return .reservationNoLongerCurrent
            }
            return .alreadyCommitted(retiringNativeLifetime.startingNativeLifetime)
        }
    }

    func retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
        _ failedStartingNativeLifetime: FilesystemObservationStartingNativeLifetime
    ) -> FilesystemObservationNativeLifetimeFailureResult {
        let binding = failedStartingNativeLifetime.binding
        guard binding.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        guard let slotState = statesByPhysicalSlotID[binding.physicalSlotID] else {
            return .undeclaredPhysicalSlot
        }

        switch slotState {
        case .vacant, .selected, .accepting, .closingAwaitingCallbackLeaseDrain,
            .closingAwaitingPredecessor, .retirementFencePending,
            .retirementFenceInstalled:
            return .nativeLifetimeNoLongerCurrent
        case .starting(let currentStartingNativeLifetime):
            guard currentStartingNativeLifetime == failedStartingNativeLifetime else {
                return .staleStartingNativeLifetime(currentStartingNativeLifetime)
            }

            let sourceID = currentStartingNativeLifetime.desiredRegistration.sourceID
            let desiredRegistration =
                pendingConfigurationDesiredBySourceID.removeValue(forKey: sourceID)
                ?? currentStartingNativeLifetime.desiredRegistration
            let retiringNativeLifetime = FilesystemObservationRetiringUnpublishedNativeLifetime(
                startingNativeLifetime: currentStartingNativeLifetime,
                cause: .nativeCreateOrStartFailed(desiredRegistration)
            )

            startingNativeLifetimesBySourceID.removeValue(forKey: sourceID)
            appendRetiringUnpublishedNativeLifetime(
                retiringNativeLifetime,
                for: sourceID
            )
            deferredDesiredRegistrationsBySourceID[sourceID] = desiredRegistration
            deferredSourceOrder.append(sourceID)
            statesByPhysicalSlotID[binding.physicalSlotID] =
                .retiringUnpublishedGeneration(retiringNativeLifetime)
            return .retirementRequired(retiringNativeLifetime)
        case .retiringUnpublishedGeneration(let retiringNativeLifetime):
            guard
                retiringNativeLifetime.startingNativeLifetime
                    == failedStartingNativeLifetime
            else {
                return .staleStartingNativeLifetime(
                    retiringNativeLifetime.startingNativeLifetime
                )
            }
            return .alreadyRetirementRequired(retiringNativeLifetime)
        }
    }

    func publishAcceptingNativeLifetime(
        _ startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity
    ) -> FilesystemObservationAcceptingPublicationResult {
        let binding = startingNativeLifetime.binding
        guard binding.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        guard let slotState = statesByPhysicalSlotID[binding.physicalSlotID] else {
            return .undeclaredPhysicalSlot
        }
        switch slotState {
        case .starting(let currentStartingNativeLifetime):
            guard currentStartingNativeLifetime == startingNativeLifetime else {
                return .startingNativeLifetimeMismatch(currentStartingNativeLifetime)
            }
            let acceptingNativeLifetime = FilesystemObservationAcceptingNativeLifetime(
                startingNativeLifetime: startingNativeLifetime,
                callbackAdmissionPortIdentity: callbackAdmissionPortIdentity
            )
            statesByPhysicalSlotID[binding.physicalSlotID] =
                .accepting(acceptingNativeLifetime)
            return .published(acceptingNativeLifetime)
        case .accepting(let acceptingNativeLifetime):
            guard acceptingNativeLifetime.startingNativeLifetime == startingNativeLifetime else {
                return .startingNativeLifetimeMismatch(
                    acceptingNativeLifetime.startingNativeLifetime
                )
            }
            return .alreadyPublished(acceptingNativeLifetime)
        case .vacant, .selected, .closingAwaitingCallbackLeaseDrain,
            .closingAwaitingPredecessor, .retirementFencePending,
            .retirementFenceInstalled, .retiringUnpublishedGeneration:
            return .invalidSlotState(state(of: binding.physicalSlotID))
        }
    }

    func beginClosingAwaitingCallbackLeaseDrain(
        _ acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
    ) -> FilesystemObservationCallbackLeaseDrainClosingResult {
        let binding = acceptingNativeLifetime.binding
        guard binding.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        guard let slotState = statesByPhysicalSlotID[binding.physicalSlotID] else {
            return .undeclaredPhysicalSlot
        }
        switch slotState {
        case .accepting(let currentAcceptingNativeLifetime):
            guard currentAcceptingNativeLifetime == acceptingNativeLifetime else {
                return .acceptingNativeLifetimeMismatch(currentAcceptingNativeLifetime)
            }
            let closingNativeLifetime =
                FilesystemObservationClosingAwaitingCallbackLeaseDrainLifetime(
                    acceptingNativeLifetime: acceptingNativeLifetime
                )
            statesByPhysicalSlotID[binding.physicalSlotID] =
                .closingAwaitingCallbackLeaseDrain(closingNativeLifetime)
            return .transitioned(closingNativeLifetime)
        case .closingAwaitingCallbackLeaseDrain(let closingNativeLifetime):
            guard closingNativeLifetime.acceptingNativeLifetime == acceptingNativeLifetime else {
                return .acceptingNativeLifetimeMismatch(
                    closingNativeLifetime.acceptingNativeLifetime
                )
            }
            return .alreadyTransitioned(closingNativeLifetime)
        case .vacant, .selected, .starting, .closingAwaitingPredecessor,
            .retirementFencePending, .retirementFenceInstalled,
            .retiringUnpublishedGeneration:
            return .invalidSlotState(state(of: binding.physicalSlotID))
        }
    }

    func prepareRetirementFence(
        _ receipt: DarwinFSEventRegistrationLeaseDrainReceipt
    ) -> FilesystemRetirementFencePreparationResult {
        let binding = receipt.binding
        guard binding.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        guard let slotState = statesByPhysicalSlotID[binding.physicalSlotID] else {
            return .undeclaredPhysicalSlot
        }

        switch slotState {
        case .closingAwaitingCallbackLeaseDrain(let closingNativeLifetime):
            guard closingNativeLifetime.matches(receipt) else {
                return .receiptMismatch
            }

            let sourceID = binding.registration.sourceID
            let retirementChain = retiringGenerationChain(for: sourceID)
            switch retirementChain {
            case .none:
                let fence = FilesystemObservationSlotRetirementFence(
                    binding: binding,
                    identity: FilesystemObservationRetirementFenceIdentity(
                        value: UUIDv7.generate()
                    )
                )
                let pendingLifetime = FilesystemRetirementFencePendingLifetime(
                    closingNativeLifetime: closingNativeLifetime,
                    leaseDrainReceipt: receipt,
                    fence: fence
                )
                startingNativeLifetimesBySourceID.removeValue(forKey: sourceID)
                promotePendingConfigurationDesiredToFIFO(for: sourceID)
                retiringGenerationChainsBySourceID[sourceID] =
                    .oldest(.retirementFencePending(pendingLifetime))
                statesByPhysicalSlotID[binding.physicalSlotID] =
                    .retirementFencePending(pendingLifetime)
                return .pending(pendingLifetime)
            case .oldest(let oldest):
                let awaitingLifetime =
                    FilesystemClosingAwaitingPredecessorLifetime(
                        closingNativeLifetime: closingNativeLifetime,
                        leaseDrainReceipt: receipt
                    )
                startingNativeLifetimesBySourceID.removeValue(forKey: sourceID)
                promotePendingConfigurationDesiredToFIFO(for: sourceID)
                retiringGenerationChainsBySourceID[sourceID] =
                    .oldestAndSuccessor(
                        oldest: oldest,
                        successor: .closingAwaitingPredecessor(awaitingLifetime)
                    )
                statesByPhysicalSlotID[binding.physicalSlotID] =
                    .closingAwaitingPredecessor(awaitingLifetime)
                return .awaitingPredecessor(awaitingLifetime)
            case .oldestAndSuccessor:
                return .retiringGenerationLimitReached
            }
        case .closingAwaitingPredecessor(let awaitingLifetime):
            guard awaitingLifetime.leaseDrainReceipt == receipt else {
                return .receiptMismatch
            }
            return .alreadyAwaitingPredecessor(awaitingLifetime)
        case .retirementFencePending(let pendingLifetime):
            guard pendingLifetime.leaseDrainReceipt == receipt else {
                return .receiptMismatch
            }
            return .alreadyPending(pendingLifetime)
        case .retirementFenceInstalled(let installedLifetime):
            guard installedLifetime.pendingLifetime.leaseDrainReceipt == receipt else {
                return .receiptMismatch
            }
            return .alreadyInstalled(installedLifetime)
        case .vacant, .selected, .starting, .accepting,
            .retiringUnpublishedGeneration:
            return .invalidSlotState(state(of: binding.physicalSlotID))
        }
    }

    func installRetirementFence(
        _ pendingLifetime: FilesystemRetirementFencePendingLifetime,
        contributionIdentity: FilesystemObservationContributionIdentity
    ) -> FilesystemRetirementFenceInstallationResult {
        let binding = pendingLifetime.binding
        guard contributionIdentity.binding == binding,
            let slotState = statesByPhysicalSlotID[binding.physicalSlotID]
        else {
            return .stalePendingLifetime
        }

        switch slotState {
        case .retirementFencePending(let currentPendingLifetime):
            guard currentPendingLifetime == pendingLifetime else {
                return .stalePendingLifetime
            }
            let installedLifetime = FilesystemRetirementFenceInstalledLifetime(
                pendingLifetime: pendingLifetime,
                contributionIdentity: contributionIdentity
            )
            let replacement = retiringGenerationChain(
                for: binding.registration.sourceID
            ).replacing(
                .retirementFencePending(pendingLifetime),
                with: .retirementFenceInstalled(installedLifetime)
            )
            guard case .replaced(let replacementChain) = replacement else {
                return .stalePendingLifetime
            }
            retiringGenerationChainsBySourceID[binding.registration.sourceID] = replacementChain
            statesByPhysicalSlotID[binding.physicalSlotID] =
                .retirementFenceInstalled(installedLifetime)
            return .installed(installedLifetime)
        case .retirementFenceInstalled(let installedLifetime):
            guard installedLifetime.pendingLifetime == pendingLifetime,
                installedLifetime.contributionIdentity == contributionIdentity
            else {
                return .stalePendingLifetime
            }
            return .alreadyInstalled(installedLifetime)
        case .vacant, .selected, .starting, .accepting,
            .closingAwaitingCallbackLeaseDrain, .closingAwaitingPredecessor,
            .retiringUnpublishedGeneration:
            return .invalidSlotState(state(of: binding.physicalSlotID))
        }
    }

    func pendingRetirementFence(
        for physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FilesystemObservationPendingRetirementFenceLookup {
        guard
            case .retirementFencePending(let pendingLifetime) =
                statesByPhysicalSlotID[physicalSlotID]
        else {
            return .notPending(state(of: physicalSlotID))
        }
        return .pending(pendingLifetime)
    }

    private func makeDesiredRegistration(
        _ registration: FSEventRegistrationToken
    ) -> FilesystemObservationDesiredRegistration {
        FilesystemObservationDesiredRegistration(
            identity: FilesystemObservationDesiredIdentity(
                value: UUIDv7.generate()
            ),
            registration: registration
        )
    }

    private func appendRetiringUnpublishedNativeLifetime(
        _ retiringNativeLifetime: FilesystemObservationRetiringUnpublishedNativeLifetime,
        for sourceID: FilesystemSourceID
    ) {
        let retiringLifetime = FilesystemObservationRetiringNativeLifetime.unpublished(
            retiringNativeLifetime
        )
        switch retiringGenerationChain(for: sourceID) {
        case .none:
            retiringGenerationChainsBySourceID[sourceID] =
                .oldest(retiringLifetime)
        case .oldest(let oldestRetirement):
            retiringGenerationChainsBySourceID[sourceID] =
                .oldestAndSuccessor(
                    oldest: oldestRetirement,
                    successor: retiringLifetime
                )
        case .oldestAndSuccessor:
            preconditionFailure(
                "A source cannot own more than two retiring generations"
            )
        }
    }

    private func promotePendingConfigurationDesiredToFIFO(
        for sourceID: FilesystemSourceID
    ) {
        guard
            let pendingDesiredRegistration =
                pendingConfigurationDesiredBySourceID.removeValue(forKey: sourceID)
        else {
            return
        }
        deferredDesiredRegistrationsBySourceID[sourceID] = pendingDesiredRegistration
        deferredSourceOrder.append(sourceID)
    }

    private func firstVacantPhysicalSlotID() -> FilesystemObservationPhysicalSlotID? {
        physicalSlotIDs.first { physicalSlotID in
            statesByPhysicalSlotID[physicalSlotID] == .vacant
        }
    }

    private var activeLogicalSourceCount: Int {
        var activeSourceIDs = Set(selectedDesiredSourcesBySourceID.keys)
        activeSourceIDs.formUnion(startingNativeLifetimesBySourceID.keys)
        activeSourceIDs.formUnion(retiringGenerationChainsBySourceID.keys)
        return activeSourceIDs.count
    }

    private func isActiveLogicalSource(_ sourceID: FilesystemSourceID) -> Bool {
        selectedDesiredSourcesBySourceID[sourceID] != nil
            || startingNativeLifetimesBySourceID[sourceID] != nil
            || retiringGenerationChainsBySourceID[sourceID] != nil
    }
}
