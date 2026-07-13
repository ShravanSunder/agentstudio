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
    private var retiringUnpublishedGenerationChainsBySourceID:
        [FilesystemSourceID: FilesystemObservationRetiringUnpublishedGenerationChain] =
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

    func retiringUnpublishedGenerationChain(
        for sourceID: FilesystemSourceID
    ) -> FilesystemObservationRetiringUnpublishedGenerationChain {
        retiringUnpublishedGenerationChainsBySourceID[sourceID] ?? .none
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
        case .retiringUnpublishedGeneration(let retiringNativeLifetime):
            return retiringNativeLifetime.startingNativeLifetime.binding == binding
                ? .storedCurrent : .storedSuperseded
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
            || retiringUnpublishedGenerationChain(for: sourceID) != .none
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
            let retirementChain = retiringUnpublishedGenerationChain(for: sourceID)
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
        let oldestRetirementChain = retiringUnpublishedGenerationChain(
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
            return .starting(startingNativeLifetime)
        }
        if let desiredRegistration = deferredDesiredRegistrationsBySourceID[sourceID] {
            return .deferred(desiredRegistration)
        }
        let retirementChain = retiringUnpublishedGenerationChain(for: sourceID)
        switch retirementChain {
        case .none:
            return .absent
        case .oldest, .oldestAndSuccessor:
            return .retiringUnpublishedGenerations(retirementChain)
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
            return .retiringUnpublishedGeneration(retiringNativeLifetime)
        }
        if let desiredRegistration = deferredDesiredRegistrationsBySourceID[sourceID] {
            guard desiredRegistration.identity == desiredIdentity else {
                return .staleDesiredIdentity(desiredRegistration.identity)
            }
            deferredDesiredRegistrationsBySourceID.removeValue(forKey: sourceID)
            deferredSourceOrder.removeAll { $0 == sourceID }
            return .withdrewDeferred(desiredRegistration)
        }
        switch retiringUnpublishedGenerationChain(for: sourceID) {
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
            return .retiringUnpublishedGeneration(oldestRetirement)
        case .oldestAndSuccessor(let oldestRetirement, let successorRetirement):
            let oldestDesiredRegistration =
                oldestRetirement.startingNativeLifetime.desiredRegistration
            if oldestDesiredRegistration.identity == desiredIdentity {
                return .retiringUnpublishedGeneration(oldestRetirement)
            }
            let successorDesiredRegistration =
                successorRetirement.startingNativeLifetime.desiredRegistration
            guard successorDesiredRegistration.identity == desiredIdentity else {
                return .staleDesiredIdentity(
                    pendingDesiredRegistration?.identity ?? successorDesiredRegistration.identity
                )
            }
            return .retiringUnpublishedGeneration(successorRetirement)
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
        case .vacant, .selected:
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
        switch retiringUnpublishedGenerationChain(for: sourceID) {
        case .none:
            retiringUnpublishedGenerationChainsBySourceID[sourceID] =
                .oldest(retiringNativeLifetime)
        case .oldest(let oldestRetirement):
            retiringUnpublishedGenerationChainsBySourceID[sourceID] =
                .oldestAndSuccessor(
                    oldest: oldestRetirement,
                    successor: retiringNativeLifetime
                )
        case .oldestAndSuccessor:
            preconditionFailure(
                "A source cannot own more than two retiring unpublished generations"
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
        activeSourceIDs.formUnion(retiringUnpublishedGenerationChainsBySourceID.keys)
        return activeSourceIDs.count
    }

    private func isActiveLogicalSource(_ sourceID: FilesystemSourceID) -> Bool {
        selectedDesiredSourcesBySourceID[sourceID] != nil
            || startingNativeLifetimesBySourceID[sourceID] != nil
            || retiringUnpublishedGenerationChainsBySourceID[sourceID] != nil
    }
}
