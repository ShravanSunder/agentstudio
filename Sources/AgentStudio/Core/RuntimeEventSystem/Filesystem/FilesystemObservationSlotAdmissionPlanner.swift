import Foundation

enum FilesystemObservationSlotAdmissionPlanner {
    enum SlotLookup {
        case undeclared
        case declared(FilesystemObservationRegistrySlotState)
    }

    enum WithdrawalPendingConfiguration {
        case absent
        case retained(FilesystemObservationPendingConfigurationRecord)
    }

    enum WithdrawalSelectedDesired {
        case absent
        case retained(FilesystemObservationDesiredSelection)
    }

    enum WithdrawalStartingDesired {
        case absent
        case retained(
            lifetime: FilesystemObservationStartingNativeLifetime,
            slotLookup: SlotLookup
        )
    }

    enum WithdrawalDeferredDesired {
        case absent
        case retained(FilesystemObservationDesiredRegistration)
    }

    enum SelectedWithdrawalSuccessorCustody {
        case absent
        case promoteAndRemovePending(FilesystemObservationDesiredRegistration)
        case promoteRetainingPending(FilesystemObservationDesiredRegistration)
    }

    enum DesiredWithdrawalPlan {
        case result(FilesystemObservationDesiredWithdrawalResult)
        case withdrawPendingConfiguration(FilesystemObservationDesiredRegistration)
        case releaseSelectedReservation(
            selection: FilesystemObservationDesiredSelection,
            successorCustody: SelectedWithdrawalSuccessorCustody
        )
        case transitionToAwaitingAcceptingPublication(
            FilesystemAwaitingAcceptingPublicationLifetime
        )
        case withdrawDeferred(FilesystemObservationDesiredRegistration)
    }

    struct DesiredWithdrawalInput {
        let desiredIdentity: FilesystemObservationDesiredIdentity
        let pendingConfiguration: WithdrawalPendingConfiguration
        let selectedDesired: WithdrawalSelectedDesired
        let startingDesired: WithdrawalStartingDesired
        let deferredDesired: WithdrawalDeferredDesired
        let retiringGenerationChain: FilesystemObservationRetiringGenerationChain
    }

    enum AcceptingPublicationPlan {
        case result(FilesystemObservationAcceptingPublicationResult)
        case publish(FilesystemObservationPostStartPublication)
    }

    struct AcceptingPublicationInput {
        let fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity
        let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
        let callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity
        let slotLookup: SlotLookup
        let publicationRetention: FilesystemObservationPostStartPublicationRetention
        let pendingConfiguration: FilesystemObservationPendingConfigurationState
    }

    enum CallbackLeaseDrainClosingPlan {
        case result(FilesystemObservationCallbackLeaseDrainClosingResult)
        case transition(FilesystemObservationClosingAwaitingCallbackLeaseDrainLifetime)
    }

    struct CallbackLeaseDrainClosingInput {
        let fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity
        let acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
        let slotLookup: SlotLookup
    }

    enum ReservationReleasePendingConfiguration {
        case absent
        case retained(FilesystemObservationPendingConfigurationRecord)
    }

    enum ReleasedSelectionPendingDisposition {
        case absent
        case removePending
        case retainPending
    }

    struct ReservationReleaseInput {
        let reservation: FilesystemObservationSlotReservation
        let fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity
        let slotLookup: SlotLookup
        let pendingConfiguration: ReservationReleasePendingConfiguration
    }

    enum ReservationReleasePlan {
        case result(FilesystemObservationReservationReleaseResult)
        case releaseAndRotate(
            selection: FilesystemObservationDesiredSelection,
            desiredRegistration: FilesystemObservationDesiredRegistration,
            pendingDisposition: ReleasedSelectionPendingDisposition
        )
    }

    enum NativeCommitPlan {
        case result(FilesystemObservationNativeLifetimeCommitResult)
        case requiresNativeLifetimeIdentities(FilesystemObservationDesiredSelection)
    }

    struct NativeCommitIdentityBundle {
        let bindingIdentity: FilesystemObservationSlotBindingIdentity
        let controlBlockIdentity: FilesystemObservationControlBlockIdentity
        let nativeGenerationIdentity: FilesystemObservationNativeGenerationIdentity
    }

    struct NativeCommitTransition {
        let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    }

    enum DesiredSelectionPlan {
        case result(FilesystemObservationDesiredSelectionResult)
        case requiresReservationIdentity(DesiredSelectionCandidate)
    }

    struct DesiredSelectionCandidate {
        let sourceIndex: Int
        let sourceID: FilesystemSourceID
        let physicalSlotID: FilesystemObservationPhysicalSlotID
        let desiredRegistration: FilesystemObservationDesiredRegistration
    }

    struct DesiredSelectionTransition {
        let sourceIndex: Int
        let sourceID: FilesystemSourceID
        let selection: FilesystemObservationDesiredSelection
    }

    struct DesiredOverlapInput {
        let admission: FilesystemObservationDesiredAdmission
        let hasSelectedDesired: Bool
        let currentStartingNativeLifetime: FilesystemObservationStartingNativeLifetime?
        let predecessorSlotState: FilesystemObservationPhysicalSlotState?
        let retiringGenerationChain: FilesystemObservationRetiringGenerationChain
    }

    struct ReplacementInput {
        let desiredConfiguration: FilesystemObservationSourceConfiguration
        let exactPriorBinding: FilesystemObservationSlotBinding
        let exactPriorCurrentness: FilesystemObservationStoredBindingCurrentness
        let exactPriorSlotState: FilesystemObservationPhysicalSlotState
        let currentStartingNativeLifetime: FilesystemObservationStartingNativeLifetime?
        let priorContinuityProjection: FixedFilesystemRecoveryEvidenceRegister.PriorContinuityAuthority.Projection
    }

    struct DesiredSelectionInput {
        let maximumSimultaneousSourceCount: Int
        let physicalSlotIDs: [FilesystemObservationPhysicalSlotID]
        let statesByPhysicalSlotID: [FilesystemObservationPhysicalSlotID: FilesystemObservationRegistrySlotState]
        let deferredSourceOrder: [FilesystemSourceID]
        let deferredRegistrations: [FilesystemSourceID: FilesystemObservationDesiredRegistration]
        let selectedSources: [FilesystemSourceID: FilesystemObservationDesiredSelection]
        let startingSources: [FilesystemSourceID: FilesystemObservationStartingNativeLifetime]
        let retiringChains: [FilesystemSourceID: FilesystemObservationRetiringGenerationChain]
    }

    enum ReplacementValidation {
        case accepted(FilesystemObservationAcceptingNativeLifetime)
        case rejected(FilesystemObservationReplacementAdmissionRejection)
    }

    static func validateReplacement(
        _ input: ReplacementInput
    ) -> ReplacementValidation {
        let exactPriorSourceID = input.exactPriorBinding.registration.sourceID
        guard exactPriorSourceID == input.desiredConfiguration.sourceID else {
            return .rejected(
                .sourceMismatch(
                    exactPriorSourceID: exactPriorSourceID,
                    desiredSourceID: input.desiredConfiguration.sourceID
                )
            )
        }
        guard input.exactPriorCurrentness == .storedCurrent else {
            return .rejected(.priorBindingNotCurrent(input.exactPriorCurrentness))
        }
        guard case .accepting(let acceptingNativeLifetime) = input.exactPriorSlotState,
            acceptingNativeLifetime.binding == input.exactPriorBinding,
            input.currentStartingNativeLifetime == acceptingNativeLifetime.startingNativeLifetime
        else {
            return .rejected(.priorBindingNotAccepting(input.exactPriorSlotState))
        }

        let priorConfiguration = acceptingNativeLifetime.startingNativeLifetime
            .desiredRegistration.configuration
        guard
            priorConfiguration.canonicalResolvedRootIdentity
                == input.desiredConfiguration.canonicalResolvedRootIdentity
        else {
            return .rejected(.canonicalResolvedRootMismatch)
        }
        guard
            priorConfiguration.authorizationScopeIdentity
                == input.desiredConfiguration.authorizationScopeIdentity
        else {
            return .rejected(.authorizationScopeMismatch)
        }
        guard priorConfiguration.eventCoverage == input.desiredConfiguration.eventCoverage else {
            return .rejected(.eventCoverageMismatch)
        }
        switch input.priorContinuityProjection {
        case .exactContinuous:
            return .accepted(acceptingNativeLifetime)
        case .exactDiscontinuous(let retainedSnapshot):
            return .rejected(.priorContinuityDiscontinuous(retainedSnapshot))
        case .bindingMismatch:
            return .rejected(.authorityBindingMismatch)
        }
    }

    static func canEnqueueAlongsideCurrentPredecessor(
        _ input: DesiredOverlapInput
    ) -> Bool {
        guard
            case .replacementRetainingPredecessor(let predecessor) = input.admission,
            !input.hasSelectedDesired,
            input.currentStartingNativeLifetime == predecessor.startingNativeLifetime,
            input.predecessorSlotState == .accepting(predecessor),
            input.retiringGenerationChain == .none
        else {
            return false
        }
        return true
    }

    static func planReservationRelease(
        _ input: ReservationReleaseInput
    ) -> ReservationReleasePlan {
        let reservation = input.reservation
        guard reservation.fleetMailboxIdentity == input.fleetMailboxIdentity else {
            return .result(.foreignFleet)
        }
        guard case .declared(let slotState) = input.slotLookup else {
            return .result(.reservationNoLongerCurrent)
        }
        switch slotState {
        case .vacant:
            return .result(.reservationNoLongerCurrent)
        case .selected(let selection):
            guard selection.reservation == reservation else {
                return .result(.staleReservation(selection.reservation))
            }
            let rotation = reservationReleaseRotation(
                selection: selection,
                pendingConfiguration: input.pendingConfiguration
            )
            return .releaseAndRotate(
                selection: selection,
                desiredRegistration: rotation.desiredRegistration,
                pendingDisposition: rotation.pendingDisposition
            )
        case .starting(let startingNativeLifetime):
            guard startingNativeLifetime.consumedReservation == reservation else {
                return .result(.reservationNoLongerCurrent)
            }
            return .result(.nativeLifetimeAlreadyCommitted(startingNativeLifetime))
        case .startingAwaitingAcceptingPublication(let lifetime):
            return .result(.nativeLifetimeAlreadyCommitted(lifetime.startingNativeLifetime))
        case .accepting(let publication):
            return .result(
                .nativeLifetimeAlreadyCommitted(
                    publication.acceptingNativeLifetime.startingNativeLifetime
                )
            )
        case .closingAwaitingCallbackLeaseDrain(let lifetime):
            return .result(
                .nativeLifetimeAlreadyCommitted(
                    lifetime.acceptingNativeLifetime.startingNativeLifetime
                )
            )
        case .closingAwaitingPredecessor(let lifetime):
            return .result(.nativeLifetimeAlreadyCommitted(lifetime.startingNativeLifetime))
        case .retirementFencePending(let lifetime):
            return .result(.nativeLifetimeAlreadyCommitted(lifetime.startingNativeLifetime))
        case .retirementFenceInstalled(let lifetime):
            return .result(.nativeLifetimeAlreadyCommitted(lifetime.startingNativeLifetime))
        case .retirementFenceTransferredAwaitingCleanup(let lifetime):
            return .result(.nativeLifetimeAlreadyCommitted(lifetime.startingNativeLifetime))
        case .retiredAwaitingContextRelease(let lifetime):
            return .result(.nativeLifetimeAlreadyCommitted(lifetime.startingNativeLifetime))
        case .retiringUnpublishedGeneration(let lifetime):
            guard lifetime.startingNativeLifetime.consumedReservation == reservation else {
                return .result(.reservationNoLongerCurrent)
            }
            return .result(
                .nativeLifetimeAlreadyCommitted(lifetime.startingNativeLifetime)
            )
        }
    }

    private static func reservationReleaseRotation(
        selection: FilesystemObservationDesiredSelection,
        pendingConfiguration: ReservationReleasePendingConfiguration
    ) -> (
        desiredRegistration: FilesystemObservationDesiredRegistration,
        pendingDisposition: ReleasedSelectionPendingDisposition
    ) {
        switch pendingConfiguration {
        case .absent:
            return (selection.desiredRegistration, .absent)
        case .retained(let pendingRecord):
            let pendingDisposition: ReleasedSelectionPendingDisposition =
                pendingRecord.continuityRepairCustody.projectedState == .absent
                ? .removePending : .retainPending
            return (pendingRecord.desiredRegistration, pendingDisposition)
        }
    }

    static func planDesiredSelection(
        _ input: DesiredSelectionInput
    ) -> DesiredSelectionPlan {
        guard let oldestDeferredSourceID = input.deferredSourceOrder.first else {
            return .result(.noDeferredDesiredSource)
        }
        let activeSourceIDs = FilesystemObservationSlotReadModel.activeSourceIDs(
            selected: input.selectedSources,
            starting: input.startingSources,
            retiring: input.retiringChains
        )
        var encounteredActiveSourceCapacityLimit = false
        for (sourceIndex, sourceID) in input.deferredSourceOrder.enumerated() {
            let retirementChain = input.retiringChains[sourceID] ?? .none
            if case .oldestAndSuccessor = retirementChain {
                continue
            }
            if !activeSourceIDs.contains(sourceID)
                && activeSourceIDs.count >= input.maximumSimultaneousSourceCount
            {
                encounteredActiveSourceCapacityLimit = true
                continue
            }
            guard
                let physicalSlotID = input.physicalSlotIDs.first(where: {
                    input.statesByPhysicalSlotID[$0] == .vacant
                })
            else {
                return .result(.deferredBehindSlotCapacity)
            }
            guard let desiredRegistration = input.deferredRegistrations[sourceID] else {
                preconditionFailure("FIFO source must retain one exact desired registration")
            }
            return .requiresReservationIdentity(
                DesiredSelectionCandidate(
                    sourceIndex: sourceIndex,
                    sourceID: sourceID,
                    physicalSlotID: physicalSlotID,
                    desiredRegistration: desiredRegistration
                )
            )
        }
        if encounteredActiveSourceCapacityLimit {
            return .result(.deferredBehindActiveSourceCapacity)
        }
        guard
            case .oldestAndSuccessor(let oldest, let successor) =
                input.retiringChains[oldestDeferredSourceID] ?? .none
        else {
            preconditionFailure("Deferred source scan must find an eligible or chain-blocked source")
        }
        return .result(
            .deferredBehindRetiringGenerationLimit(
                oldest: oldest,
                successor: successor
            )
        )
    }

    static func completeDesiredSelection(
        _ candidate: DesiredSelectionCandidate,
        fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity,
        reservationIdentity: FilesystemObservationSlotReservationIdentity
    ) -> DesiredSelectionTransition {
        let reservation = FilesystemObservationSlotReservation(
            fleetMailboxIdentity: fleetMailboxIdentity,
            physicalSlotID: candidate.physicalSlotID,
            desiredIdentity: candidate.desiredRegistration.identity,
            identity: reservationIdentity
        )
        return DesiredSelectionTransition(
            sourceIndex: candidate.sourceIndex,
            sourceID: candidate.sourceID,
            selection: FilesystemObservationDesiredSelection(
                desiredRegistration: candidate.desiredRegistration,
                reservation: reservation
            )
        )
    }

    static func planNativeCommit(
        reservation: FilesystemObservationSlotReservation,
        fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity,
        slotState: FilesystemObservationRegistrySlotState?,
        pendingRecord: FilesystemObservationPendingConfigurationRecord?
    ) -> NativeCommitPlan {
        guard reservation.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .result(.foreignFleet)
        }
        guard let slotState else {
            return .result(.undeclaredPhysicalSlot)
        }
        switch slotState {
        case .vacant:
            return .result(.reservationNoLongerCurrent)
        case .selected(let selection):
            guard selection.reservation == reservation else {
                return .result(.staleReservation(selection.reservation))
            }
            if let pendingRecord,
                pendingRecord.desiredRegistration.identity
                    != selection.desiredRegistration.identity
            {
                return .result(
                    .deferredToConfigurationCurrentness(
                        pendingRecord.desiredRegistration
                    )
                )
            }
            return .requiresNativeLifetimeIdentities(selection)
        case .starting(let lifetime):
            guard lifetime.consumedReservation == reservation else {
                return .result(.reservationNoLongerCurrent)
            }
            return .result(.alreadyCommitted(lifetime))
        case .startingAwaitingAcceptingPublication(let lifetime):
            return .result(.alreadyCommitted(lifetime.startingNativeLifetime))
        case .accepting(let publication):
            return .result(
                .alreadyCommitted(publication.acceptingNativeLifetime.startingNativeLifetime)
            )
        case .closingAwaitingCallbackLeaseDrain(let lifetime):
            return .result(
                .alreadyCommitted(lifetime.acceptingNativeLifetime.startingNativeLifetime)
            )
        case .closingAwaitingPredecessor(let lifetime):
            return .result(.alreadyCommitted(lifetime.startingNativeLifetime))
        case .retirementFencePending(let lifetime):
            return .result(.alreadyCommitted(lifetime.startingNativeLifetime))
        case .retirementFenceInstalled(let lifetime):
            return .result(.alreadyCommitted(lifetime.startingNativeLifetime))
        case .retirementFenceTransferredAwaitingCleanup(let lifetime):
            return .result(.alreadyCommitted(lifetime.startingNativeLifetime))
        case .retiredAwaitingContextRelease(let lifetime):
            return .result(.alreadyCommitted(lifetime.startingNativeLifetime))
        case .retiringUnpublishedGeneration(let lifetime):
            guard lifetime.startingNativeLifetime.consumedReservation == reservation else {
                return .result(.reservationNoLongerCurrent)
            }
            return .result(.alreadyCommitted(lifetime.startingNativeLifetime))
        }
    }

    static func completeNativeCommit(
        selection: FilesystemObservationDesiredSelection,
        identities: NativeCommitIdentityBundle
    ) -> NativeCommitTransition {
        let reservation = selection.reservation
        let binding = FilesystemObservationSlotBinding(
            fleetMailboxIdentity: reservation.fleetMailboxIdentity,
            physicalSlotID: reservation.physicalSlotID,
            identity: identities.bindingIdentity,
            registration: selection.desiredRegistration.registration,
            controlBlockIdentity: identities.controlBlockIdentity
        )
        return NativeCommitTransition(
            startingNativeLifetime: FilesystemObservationStartingNativeLifetime(
                desiredRegistration: selection.desiredRegistration,
                consumedReservation: reservation,
                binding: binding,
                nativeGenerationIdentity: identities.nativeGenerationIdentity
            )
        )
    }

    static func planDesiredWithdrawal(
        _ input: DesiredWithdrawalInput
    ) -> DesiredWithdrawalPlan {
        if case .retained(let pendingRecord) = input.pendingConfiguration,
            pendingRecord.desiredRegistration.identity == input.desiredIdentity
        {
            return .withdrawPendingConfiguration(pendingRecord.desiredRegistration)
        }

        if case .retained(let selection) = input.selectedDesired {
            guard selection.desiredRegistration.identity == input.desiredIdentity else {
                return .result(.staleDesiredIdentity(currentDesiredIdentity(input)))
            }
            return .releaseSelectedReservation(
                selection: selection,
                successorCustody: selectedWithdrawalSuccessorCustody(
                    input.pendingConfiguration
                )
            )
        }

        if case .retained(let startingNativeLifetime, let slotLookup) = input.startingDesired {
            guard startingNativeLifetime.desiredRegistration.identity == input.desiredIdentity else {
                return .result(.staleDesiredIdentity(currentDesiredIdentity(input)))
            }
            let awaitingLifetime = FilesystemAwaitingAcceptingPublicationLifetime(
                startingNativeLifetime: startingNativeLifetime
            )
            switch slotLookup {
            case .declared(.starting):
                return .transitionToAwaitingAcceptingPublication(awaitingLifetime)
            case .declared(.startingAwaitingAcceptingPublication(let retainedLifetime)):
                return .result(.awaitingAcceptingPublication(retainedLifetime))
            case .undeclared, .declared:
                return .result(
                    .staleDesiredIdentity(startingNativeLifetime.desiredRegistration.identity)
                )
            }
        }

        if case .retained(let desiredRegistration) = input.deferredDesired {
            guard desiredRegistration.identity == input.desiredIdentity else {
                return .result(.staleDesiredIdentity(desiredRegistration.identity))
            }
            return .withdrawDeferred(desiredRegistration)
        }

        return retiringDesiredWithdrawalPlan(input)
    }

    static func planAcceptingPublication(
        _ input: AcceptingPublicationInput
    ) -> AcceptingPublicationPlan {
        let startingNativeLifetime = input.startingNativeLifetime
        let binding = startingNativeLifetime.binding
        guard binding.fleetMailboxIdentity == input.fleetMailboxIdentity else {
            return .result(.foreignFleet)
        }
        guard case .declared(let slotState) = input.slotLookup else {
            return .result(.undeclaredPhysicalSlot)
        }

        switch input.publicationRetention {
        case .retained(let publication), .retainedAfterRemoval(let publication, _):
            guard
                publication.acceptingNativeLifetime.startingNativeLifetime
                    == startingNativeLifetime
            else {
                return .result(
                    .startingNativeLifetimeMismatch(
                        publication.acceptingNativeLifetime.startingNativeLifetime
                    )
                )
            }
            return .result(.alreadyPublished(publication))
        case .vacant:
            break
        }

        switch slotState {
        case .starting(let currentStartingNativeLifetime):
            guard currentStartingNativeLifetime == startingNativeLifetime else {
                return .result(.startingNativeLifetimeMismatch(currentStartingNativeLifetime))
            }
            switch input.pendingConfiguration {
            case .absent:
                return .publish(makeAcceptingPublication(input, disposition: .current))
            case .retained(let desiredRegistration):
                let disposition: AcceptingPublicationDisposition =
                    desiredRegistration.identity == startingNativeLifetime.desiredRegistration.identity
                    ? .current : .closePublished
                return .publish(makeAcceptingPublication(input, disposition: disposition))
            }
        case .startingAwaitingAcceptingPublication(let awaitingLifetime):
            guard awaitingLifetime.startingNativeLifetime == startingNativeLifetime else {
                return .result(
                    .startingNativeLifetimeMismatch(awaitingLifetime.startingNativeLifetime)
                )
            }
            return .publish(makeAcceptingPublication(input, disposition: .closePublished))
        case .accepting(let publication):
            guard
                publication.acceptingNativeLifetime.startingNativeLifetime
                    == startingNativeLifetime
            else {
                return .result(
                    .startingNativeLifetimeMismatch(
                        publication.acceptingNativeLifetime.startingNativeLifetime
                    )
                )
            }
            return .result(.alreadyPublished(publication))
        case .vacant, .selected, .closingAwaitingCallbackLeaseDrain,
            .closingAwaitingPredecessor, .retirementFencePending,
            .retirementFenceInstalled, .retirementFenceTransferredAwaitingCleanup,
            .retiredAwaitingContextRelease, .retiringUnpublishedGeneration:
            return .result(.invalidSlotState(projectFilesystemObservationSlotState(slotState)))
        }
    }

    private enum AcceptingPublicationDisposition {
        case current
        case closePublished
    }

    private static func makeAcceptingPublication(
        _ input: AcceptingPublicationInput,
        disposition: AcceptingPublicationDisposition
    ) -> FilesystemObservationPostStartPublication {
        let acceptingNativeLifetime = FilesystemObservationAcceptingNativeLifetime(
            startingNativeLifetime: input.startingNativeLifetime,
            callbackAdmissionPortIdentity: input.callbackAdmissionPortIdentity
        )
        return FilesystemObservationPostStartPublication(
            acceptingNativeLifetime: acceptingNativeLifetime,
            disposition: makePostStartDisposition(
                admission: input.startingNativeLifetime.desiredRegistration.admission,
                acceptingNativeLifetime: acceptingNativeLifetime,
                publishedLifetimeDisposition: disposition
            )
        )
    }

    static func planCallbackLeaseDrainClosing(
        _ input: CallbackLeaseDrainClosingInput
    ) -> CallbackLeaseDrainClosingPlan {
        let acceptingNativeLifetime = input.acceptingNativeLifetime
        let binding = acceptingNativeLifetime.binding
        guard binding.fleetMailboxIdentity == input.fleetMailboxIdentity else {
            return .result(.foreignFleet)
        }
        guard case .declared(let slotState) = input.slotLookup else {
            return .result(.undeclaredPhysicalSlot)
        }
        switch slotState {
        case .accepting(let publication):
            guard publication.acceptingNativeLifetime == acceptingNativeLifetime else {
                return .result(
                    .acceptingNativeLifetimeMismatch(publication.acceptingNativeLifetime)
                )
            }
            return .transition(
                FilesystemObservationClosingAwaitingCallbackLeaseDrainLifetime(
                    acceptingNativeLifetime: acceptingNativeLifetime
                )
            )
        case .closingAwaitingCallbackLeaseDrain(let closingNativeLifetime):
            guard closingNativeLifetime.acceptingNativeLifetime == acceptingNativeLifetime else {
                return .result(
                    .acceptingNativeLifetimeMismatch(
                        closingNativeLifetime.acceptingNativeLifetime
                    )
                )
            }
            return .result(.alreadyTransitioned(closingNativeLifetime))
        case .vacant, .selected, .starting, .startingAwaitingAcceptingPublication,
            .closingAwaitingPredecessor, .retirementFencePending, .retirementFenceInstalled,
            .retirementFenceTransferredAwaitingCleanup, .retiredAwaitingContextRelease,
            .retiringUnpublishedGeneration:
            return .result(.invalidSlotState(projectFilesystemObservationSlotState(slotState)))
        }
    }

    private static func currentDesiredIdentity(
        _ input: DesiredWithdrawalInput
    ) -> FilesystemObservationDesiredIdentity {
        if case .retained(let pendingRecord) = input.pendingConfiguration {
            return pendingRecord.desiredRegistration.identity
        }
        if case .retained(let selection) = input.selectedDesired {
            return selection.desiredRegistration.identity
        }
        if case .retained(let startingNativeLifetime, _) = input.startingDesired {
            return startingNativeLifetime.desiredRegistration.identity
        }
        preconditionFailure("Withdrawal currentness requires one retained desired identity")
    }

    private static func selectedWithdrawalSuccessorCustody(
        _ pendingConfiguration: WithdrawalPendingConfiguration
    ) -> SelectedWithdrawalSuccessorCustody {
        guard case .retained(let pendingRecord) = pendingConfiguration else {
            return .absent
        }
        if pendingRecord.continuityRepairCustody.projectedState == .absent {
            return .promoteAndRemovePending(pendingRecord.desiredRegistration)
        }
        return .promoteRetainingPending(pendingRecord.desiredRegistration)
    }

    private static func retiringDesiredWithdrawalPlan(
        _ input: DesiredWithdrawalInput
    ) -> DesiredWithdrawalPlan {
        switch input.retiringGenerationChain {
        case .none:
            return .result(.alreadyAbsent)
        case .oldest(let oldestRetirement):
            let oldestIdentity = oldestRetirement.startingNativeLifetime.desiredRegistration.identity
            guard oldestIdentity == input.desiredIdentity else {
                return .result(
                    .staleDesiredIdentity(
                        pendingIdentity(input, fallback: oldestIdentity)
                    )
                )
            }
            return .result(.retiringGeneration(oldestRetirement))
        case .oldestAndSuccessor(let oldestRetirement, let successorRetirement):
            let oldestIdentity = oldestRetirement.startingNativeLifetime.desiredRegistration.identity
            if oldestIdentity == input.desiredIdentity {
                return .result(.retiringGeneration(oldestRetirement))
            }
            let successorIdentity = successorRetirement.startingNativeLifetime
                .desiredRegistration.identity
            guard successorIdentity == input.desiredIdentity else {
                return .result(
                    .staleDesiredIdentity(
                        pendingIdentity(input, fallback: successorIdentity)
                    )
                )
            }
            return .result(.retiringGeneration(successorRetirement))
        }
    }

    private static func pendingIdentity(
        _ input: DesiredWithdrawalInput,
        fallback: FilesystemObservationDesiredIdentity
    ) -> FilesystemObservationDesiredIdentity {
        switch input.pendingConfiguration {
        case .absent:
            return fallback
        case .retained(let pendingRecord):
            return pendingRecord.desiredRegistration.identity
        }
    }

    private static func makePostStartDisposition(
        admission: FilesystemObservationDesiredAdmission,
        acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime,
        publishedLifetimeDisposition: AcceptingPublicationDisposition
    ) -> FilesystemObservationPostStartDisposition {
        switch (admission, publishedLifetimeDisposition) {
        case (.replacementRetainingPredecessor(let predecessor), .closePublished):
            return .closePredecessorAndPublished(
                predecessor: predecessor,
                published: acceptingNativeLifetime
            )
        case (.replacementRetainingPredecessor(let predecessor), .current):
            return .closePredecessor(predecessor)
        case (.installation, .closePublished),
            (.replacementAfterPredecessorClose, .closePublished):
            return .closePublished(acceptingNativeLifetime)
        case (.installation, .current), (.replacementAfterPredecessorClose, .current):
            return .current
        }
    }

    static func makeDesiredRegistration(
        identity: FilesystemObservationDesiredIdentity,
        configuration: FilesystemObservationSourceConfiguration,
        acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision,
        admission: FilesystemObservationDesiredAdmission
    ) -> FilesystemObservationDesiredRegistration {
        FilesystemObservationDesiredRegistration(
            identity: identity,
            acceptedTopologyRevision: acceptedTopologyRevision,
            configuration: configuration,
            admission: admission
        )
    }
}
