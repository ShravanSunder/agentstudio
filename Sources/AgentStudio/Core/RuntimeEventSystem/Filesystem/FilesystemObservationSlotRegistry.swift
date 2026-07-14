import Foundation

/// Fixed-cardinality owner of physical slots and their current bindings.
///
/// This owner is intentionally non-locking. Its eventual mailbox caller must hold the
/// wrapper coordination lock. UUIDv7 values provide opaque identity only: exact stored
/// equality determines currentness, and UUID order never determines lifecycle or FIFO.
final class FilesystemObservationSlotRegistry {
    struct ReadView {
        fileprivate let registry: FilesystemObservationSlotRegistry
    }

    let maximumSimultaneousSourceCount: Int
    let replacementReserveSlotCount: Int
    let physicalSlotCount: Int
    let fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity
    let physicalSlotIDs: [FilesystemObservationPhysicalSlotID]

    var statesByPhysicalSlotID: [FilesystemObservationPhysicalSlotID: FilesystemObservationRegistrySlotState]
    private var deferredSourceOrder: [FilesystemSourceID] = []
    private var deferredDesiredRegistrationsBySourceID: [FilesystemSourceID: FilesystemObservationDesiredRegistration] =
        [:]
    private var selectedDesiredSourcesBySourceID: [FilesystemSourceID: FilesystemObservationDesiredSelection] = [:]
    private var startingNativeLifetimesBySourceID: [FilesystemSourceID: FilesystemObservationStartingNativeLifetime] =
        [:]
    var retiringGenerationChainsBySourceID: [FilesystemSourceID: FilesystemObservationRetiringGenerationChain] =
        [:]
    private var pendingConfigurationDesiredBySourceID:
        [FilesystemSourceID: FilesystemObservationPendingConfigurationRecord] = [:]
    private var postStartPublicationRetentionByPhysicalSlotID:
        [FilesystemObservationPhysicalSlotID: FilesystemObservationPostStartPublicationRetention]
    var lastCompletedReleasesByPhysicalSlotID:
        [FilesystemObservationPhysicalSlotID: FilesystemObservationLastCompletedRelease]

    var read: ReadView { ReadView(registry: self) }

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
        postStartPublicationRetentionByPhysicalSlotID = Dictionary(
            uniqueKeysWithValues: physicalSlotIDs.map { ($0, .vacant) }
        )
        lastCompletedReleasesByPhysicalSlotID = Dictionary(
            uniqueKeysWithValues: physicalSlotIDs.map { ($0, .none) }
        )
    }

    func installDesiredConfiguration(
        _ configuration: FilesystemObservationSourceConfiguration,
        acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision
    ) -> FilesystemObservationDesiredUpdateResult {
        let desiredRegistration = FilesystemObservationSlotAdmissionPlanner.makeDesiredRegistration(
            identity: FilesystemObservationDesiredIdentity(value: UUIDv7.generate()),
            configuration: configuration,
            acceptedTopologyRevision: acceptedTopologyRevision,
            admission: .installation
        )
        return admitDesiredRegistration(desiredRegistration)
    }

    func admitReplacementDesiredConfiguration(
        _ desiredConfiguration: FilesystemObservationSourceConfiguration,
        acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision,
        exactPriorBinding: FilesystemObservationSlotBinding,
        priorContinuityAuthority: FixedFilesystemRecoveryEvidenceRegister.PriorContinuityAuthority
    ) -> FilesystemObservationReplacementAdmissionResult {
        let sourceID = desiredConfiguration.sourceID
        let validation = FilesystemObservationSlotAdmissionPlanner.validateReplacement(
            FilesystemObservationSlotAdmissionPlanner.ReplacementInput(
                desiredConfiguration: desiredConfiguration,
                exactPriorBinding: exactPriorBinding,
                exactPriorCurrentness: read.storedBindingCurrentness(of: exactPriorBinding),
                exactPriorSlotState: read.state(of: exactPriorBinding.physicalSlotID),
                currentStartingNativeLifetime: startingNativeLifetimesBySourceID[sourceID],
                priorContinuityProjection: priorContinuityAuthority.project(
                    against: exactPriorBinding
                )
            )
        )
        guard case .accepted(let predecessor) = validation else {
            guard case .rejected(let rejection) = validation else {
                preconditionFailure("Replacement validation must be accepted or rejected")
            }
            return .rejected(rejection)
        }

        let desiredRegistration = FilesystemObservationSlotAdmissionPlanner.makeDesiredRegistration(
            identity: FilesystemObservationDesiredIdentity(value: UUIDv7.generate()),
            configuration: desiredConfiguration,
            acceptedTopologyRevision: acceptedTopologyRevision,
            admission: .replacementRetainingPredecessor(predecessor)
        )
        return .admitted(admitDesiredRegistration(desiredRegistration))
    }

    func selectNextDesiredSource() -> FilesystemObservationDesiredSelectionResult {
        let plan = FilesystemObservationSlotAdmissionPlanner.planDesiredSelection(
            FilesystemObservationSlotAdmissionPlanner.DesiredSelectionInput(
                maximumSimultaneousSourceCount: maximumSimultaneousSourceCount,
                physicalSlotIDs: physicalSlotIDs,
                statesByPhysicalSlotID: statesByPhysicalSlotID,
                deferredSourceOrder: deferredSourceOrder,
                deferredRegistrations: deferredDesiredRegistrationsBySourceID,
                selectedSources: selectedDesiredSourcesBySourceID,
                startingSources: startingNativeLifetimesBySourceID,
                retiringChains: retiringGenerationChainsBySourceID
            )
        )
        switch plan {
        case .result(let result):
            return result
        case .requiresReservationIdentity(let candidate):
            let transition = FilesystemObservationSlotAdmissionPlanner.completeDesiredSelection(
                candidate,
                fleetMailboxIdentity: fleetMailboxIdentity,
                reservationIdentity: FilesystemObservationSlotReservationIdentity(
                    value: UUIDv7.generate()
                )
            )
            deferredSourceOrder.remove(at: transition.sourceIndex)
            deferredDesiredRegistrationsBySourceID.removeValue(forKey: transition.sourceID)
            selectedDesiredSourcesBySourceID[transition.sourceID] = transition.selection
            let physicalSlotID = transition.selection.reservation.physicalSlotID
            statesByPhysicalSlotID[physicalSlotID] = .selected(transition.selection)
            postStartPublicationRetentionByPhysicalSlotID[physicalSlotID] = .vacant
            return .selected(transition.selection)
        }
    }

    func admitRemoval(
        of exactPriorBinding: FilesystemObservationSlotBinding,
        acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision
    ) -> FilesystemObservationRemovalAdmissionResult {
        let physicalSlotID = exactPriorBinding.physicalSlotID
        let replaySnapshot: FilesystemRemovalReplaySnapshot
        switch postStartPublicationRetentionByPhysicalSlotID[physicalSlotID] {
        case .vacant, nil:
            replaySnapshot = .vacant
        case .retained(let publication):
            replaySnapshot = .retained(publication)
        case .retainedAfterRemoval(let publication, let obligation):
            replaySnapshot = .retainedAfterRemoval(
                publication: publication,
                closeObligation: obligation
            )
        }
        let requirement = FilesystemRemovalAdmissionPlanner.authorityRequirement(
            FilesystemRemovalAdmissionInput(
                expectedFleetMailboxIdentity: fleetMailboxIdentity,
                exactPriorBinding: exactPriorBinding,
                slotSnapshot: statesByPhysicalSlotID[physicalSlotID].map {
                    .declared($0)
                } ?? .undeclared,
                replaySnapshot: replaySnapshot
            )
        )
        guard case .required(let lifetime) = requirement else {
            guard case .terminal(let result) = requirement else {
                preconditionFailure("Removal requirement must be terminal or authority-backed")
            }
            return result
        }

        let sourceID = exactPriorBinding.registration.sourceID
        let plan = FilesystemRemovalAdmissionPlanner.planAuthorizedRemoval(
            FilesystemAuthorizedRemovalInput(
                lifetime: lifetime,
                removalAuthority: FilesystemRemovalAdmissionPlanner.makeRemovalAuthority(
                    identity: FilesystemSourceRemovalAuthorityIdentity(
                        value: UUIDv7.generate()
                    ),
                    exactPriorBinding: exactPriorBinding,
                    acceptedTopologyRevision: acceptedTopologyRevision
                ),
                pendingConfiguration: pendingConfigurationDesiredBySourceID[sourceID].map {
                    .retained($0)
                } ?? .absent,
                startingSuccessor: startingNativeLifetimesBySourceID[sourceID].map {
                    .retained($0)
                } ?? .absent,
                selectedSuccessor: selectedDesiredSourcesBySourceID[sourceID].map {
                    .retained($0)
                } ?? .absent,
                deferredSuccessor: deferredDesiredRegistrationsBySourceID[sourceID].map {
                    .retained($0)
                } ?? .absent
            )
        )
        switch plan.pendingConfiguration {
        case .unchangedAbsent:
            break
        case .remove:
            pendingConfigurationDesiredBySourceID.removeValue(forKey: sourceID)
        case .replace(let record):
            pendingConfigurationDesiredBySourceID[sourceID] = record
        }
        switch plan.primarySlot {
        case .awaitingAcceptingPublication(let awaitingLifetime):
            statesByPhysicalSlotID[physicalSlotID] =
                .startingAwaitingAcceptingPublication(awaitingLifetime)
        case .retainAccepting:
            break
        }
        if case .retainAfterRemoval(let publication, let obligation) =
            plan.publicationRetention
        {
            postStartPublicationRetentionByPhysicalSlotID[physicalSlotID] =
                .retainedAfterRemoval(
                    publication: publication,
                    closeObligation: obligation
                )
        }
        switch plan.successorCustody {
        case .absent:
            break
        case .awaitingAcceptingPublication(let awaitingLifetime):
            statesByPhysicalSlotID[awaitingLifetime.startingNativeLifetime.binding.physicalSlotID] =
                .startingAwaitingAcceptingPublication(awaitingLifetime)
        case .releaseSelection(let selection):
            selectedDesiredSourcesBySourceID.removeValue(forKey: sourceID)
            statesByPhysicalSlotID[selection.reservation.physicalSlotID] = .vacant
        case .withdrawDeferred:
            deferredDesiredRegistrationsBySourceID.removeValue(forKey: sourceID)
            deferredSourceOrder.removeAll { $0 == sourceID }
        }
        return plan.result
    }

    func withdrawDesiredSource(
        sourceID: FilesystemSourceID,
        desiredIdentity: FilesystemObservationDesiredIdentity
    ) -> FilesystemObservationDesiredWithdrawalResult {
        let plan = FilesystemObservationSlotAdmissionPlanner.planDesiredWithdrawal(
            FilesystemObservationSlotAdmissionPlanner.DesiredWithdrawalInput(
                desiredIdentity: desiredIdentity,
                pendingConfiguration: pendingConfigurationDesiredBySourceID[sourceID].map {
                    .retained($0)
                } ?? .absent,
                selectedDesired: selectedDesiredSourcesBySourceID[sourceID].map {
                    .retained($0)
                } ?? .absent,
                startingDesired: startingNativeLifetimesBySourceID[sourceID].map {
                    .retained(
                        lifetime: $0,
                        slotLookup: statesByPhysicalSlotID[$0.binding.physicalSlotID].map {
                            .declared($0)
                        } ?? .undeclared
                    )
                } ?? .absent,
                deferredDesired: deferredDesiredRegistrationsBySourceID[sourceID].map {
                    .retained($0)
                } ?? .absent,
                retiringGenerationChain: read.retiringGenerationChain(for: sourceID)
            )
        )
        switch plan {
        case .result(let result):
            return result
        case .withdrawPendingConfiguration(let desiredRegistration):
            pendingConfigurationDesiredBySourceID.removeValue(forKey: sourceID)
            return .withdrewPendingConfiguration(desiredRegistration)
        case .releaseSelectedReservation(let selection, let successorCustody):
            selectedDesiredSourcesBySourceID.removeValue(forKey: sourceID)
            statesByPhysicalSlotID[selection.reservation.physicalSlotID] = .vacant
            applySelectedWithdrawalSuccessor(successorCustody, sourceID: sourceID)
            return .releasedSelectedReservation(selection)
        case .transitionToAwaitingAcceptingPublication(let lifetime):
            statesByPhysicalSlotID[lifetime.startingNativeLifetime.binding.physicalSlotID] =
                .startingAwaitingAcceptingPublication(lifetime)
            return .awaitingAcceptingPublication(lifetime)
        case .withdrawDeferred(let desiredRegistration):
            deferredDesiredRegistrationsBySourceID.removeValue(forKey: sourceID)
            deferredSourceOrder.removeAll { $0 == sourceID }
            return .withdrewDeferred(desiredRegistration)
        }
    }

    func releaseSelectedReservationAfterFailure(
        _ reservation: FilesystemObservationSlotReservation
    ) -> FilesystemObservationReservationReleaseResult {
        let slotState = statesByPhysicalSlotID[reservation.physicalSlotID]
        let pendingRecord: FilesystemObservationPendingConfigurationRecord?
        if case .selected(let selection) = slotState {
            pendingRecord =
                pendingConfigurationDesiredBySourceID[
                    selection.desiredRegistration.sourceID
                ]
        } else {
            pendingRecord = nil
        }
        let plan = FilesystemObservationSlotAdmissionPlanner.planReservationRelease(
            FilesystemObservationSlotAdmissionPlanner.ReservationReleaseInput(
                reservation: reservation,
                fleetMailboxIdentity: fleetMailboxIdentity,
                slotLookup: slotState.map { .declared($0) } ?? .undeclared,
                pendingConfiguration: pendingRecord.map { .retained($0) } ?? .absent
            )
        )
        switch plan {
        case .result(let result):
            return result
        case .releaseAndRotate(
            let selection,
            let desiredRegistration,
            let pendingDisposition
        ):
            let sourceID = selection.desiredRegistration.sourceID
            selectedDesiredSourcesBySourceID.removeValue(forKey: sourceID)
            statesByPhysicalSlotID[reservation.physicalSlotID] = .vacant
            if case .removePending = pendingDisposition {
                pendingConfigurationDesiredBySourceID.removeValue(forKey: sourceID)
            }
            deferredDesiredRegistrationsBySourceID[sourceID] = desiredRegistration
            deferredSourceOrder.append(sourceID)
            return .releasedAndRotatedToDeferredTail(desiredRegistration)
        }
    }

    func beginNativeLifetime(
        _ reservation: FilesystemObservationSlotReservation
    ) -> FilesystemObservationNativeLifetimeCommitResult {
        let slotState = statesByPhysicalSlotID[reservation.physicalSlotID]
        let pendingRecord: FilesystemObservationPendingConfigurationRecord?
        if case .selected(let selection) = slotState {
            pendingRecord =
                pendingConfigurationDesiredBySourceID[
                    selection.desiredRegistration.sourceID
                ]
        } else {
            pendingRecord = nil
        }
        let plan = FilesystemObservationSlotAdmissionPlanner.planNativeCommit(
            reservation: reservation,
            fleetMailboxIdentity: fleetMailboxIdentity,
            slotState: slotState,
            pendingRecord: pendingRecord
        )
        switch plan {
        case .result(let result):
            return result
        case .requiresNativeLifetimeIdentities(let selection):
            let transition = FilesystemObservationSlotAdmissionPlanner.completeNativeCommit(
                selection: selection,
                identities: FilesystemObservationSlotAdmissionPlanner.NativeCommitIdentityBundle(
                    bindingIdentity: FilesystemObservationSlotBindingIdentity(
                        value: UUIDv7.generate()
                    ),
                    controlBlockIdentity: FilesystemObservationControlBlockIdentity(
                        value: UUIDv7.generate()
                    ),
                    nativeGenerationIdentity: FilesystemObservationNativeGenerationIdentity(
                        value: UUIDv7.generate()
                    )
                )
            )
            let startingNativeLifetime = transition.startingNativeLifetime
            let sourceID = selection.desiredRegistration.sourceID
            selectedDesiredSourcesBySourceID.removeValue(forKey: sourceID)
            startingNativeLifetimesBySourceID[sourceID] = startingNativeLifetime
            statesByPhysicalSlotID[reservation.physicalSlotID] =
                .starting(startingNativeLifetime)
            lastCompletedReleasesByPhysicalSlotID[reservation.physicalSlotID] =
                FilesystemObservationLastCompletedRelease.none
            return .committed(startingNativeLifetime)
        }
    }

    func retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
        _ failedStartingNativeLifetime: FilesystemObservationStartingNativeLifetime
    ) -> FilesystemObservationNativeLifetimeFailureResult {
        let binding = failedStartingNativeLifetime.binding
        let slotSnapshot: FilesystemUnpublishedFailureSlotState =
            statesByPhysicalSlotID[binding.physicalSlotID].map {
                .declared($0)
            } ?? .undeclared
        let sourceID = failedStartingNativeLifetime.desiredRegistration.sourceID
        let pendingSnapshot: FilesystemPendingConfigurationRecordSnapshot =
            pendingConfigurationDesiredBySourceID[sourceID].map {
                .retained($0)
            } ?? .absent
        let continuityRepairDisposition: FilesystemFailureContinuityRepairDisposition
        switch failedStartingNativeLifetime.desiredRegistration.admission {
        case .replacementRetainingPredecessor:
            continuityRepairDisposition = .preserve(
                pendingConfigurationDesiredBySourceID[sourceID]?
                    .continuityRepairCustody ?? .absent
            )
        case .installation, .replacementAfterPredecessorClose:
            let desiredRegistration =
                pendingConfigurationDesiredBySourceID[sourceID]?.desiredRegistration
                ?? failedStartingNativeLifetime.desiredRegistration
            continuityRepairDisposition = .install(
                FilesystemContinuityRepairCustodyPlanner.makePendingAuthority(
                    identity: FilesystemPendingContinuityRepairIdentity(
                        value: UUIDv7.generate()
                    ),
                    desiredRegistration: desiredRegistration,
                    cause: .nativeCreateOrStartFailure,
                    recoveryRevision: FilesystemContinuityRepairRevision(
                        value: desiredRegistration.acceptedTopologyRevision.value
                    )
                )
            )
        }
        let plan = FilesystemObservationRetirementTransitionPlanner.planUnpublishedFailure(
            FilesystemUnpublishedFailureRequest(
                expectedFleetMailboxIdentity: fleetMailboxIdentity,
                failedStartingNativeLifetime: failedStartingNativeLifetime,
                currentSlotState: slotSnapshot,
                pendingConfigurationRecord: pendingSnapshot,
                retiringGenerationChain: read.retiringGenerationChain(for: sourceID),
                continuityRepairDisposition: continuityRepairDisposition
            )
        )
        switch plan {
        case .apply(let mutation, let result):
            let retiringLifetime: FilesystemObservationRetiringUnpublishedNativeLifetime
            switch mutation {
            case .withdrawn(let lifetime, let chain):
                retiringLifetime = lifetime
                retiringGenerationChainsBySourceID[sourceID] = chain
            case .failed(let lifetime, let chain, let desiredRegistration, let pendingRecord):
                retiringLifetime = lifetime
                retiringGenerationChainsBySourceID[sourceID] = chain
                deferredDesiredRegistrationsBySourceID[sourceID] = desiredRegistration
                deferredSourceOrder.append(sourceID)
                pendingConfigurationDesiredBySourceID[sourceID] = pendingRecord
            }
            startingNativeLifetimesBySourceID.removeValue(forKey: sourceID)
            statesByPhysicalSlotID[binding.physicalSlotID] =
                .retiringUnpublishedGeneration(retiringLifetime)
            return result
        case .unchanged(let result):
            return result
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

        let sourceID = binding.registration.sourceID
        let plan = FilesystemObservationRetirementTransitionPlanner.planFencePreparation(
            FilesystemRetirementFencePreparationRequest(
                receipt: receipt,
                currentSlotState: slotState,
                retiringGenerationChain: read.retiringGenerationChain(for: sourceID),
                candidateFenceIdentity: FilesystemObservationRetirementFenceIdentity(
                    value: UUIDv7.generate()
                )
            )
        )
        switch plan {
        case .apply(let mutation, let result):
            let physicalSlotID: FilesystemObservationPhysicalSlotID
            let chain: FilesystemObservationRetiringGenerationChain
            switch mutation {
            case .pending(let lifetime, let replacementChain):
                physicalSlotID = lifetime.binding.physicalSlotID
                chain = replacementChain
                statesByPhysicalSlotID[physicalSlotID] = .retirementFencePending(lifetime)
            case .awaitingPredecessor(let lifetime, let replacementChain):
                physicalSlotID = lifetime.binding.physicalSlotID
                chain = replacementChain
                statesByPhysicalSlotID[physicalSlotID] = .closingAwaitingPredecessor(lifetime)
            }
            startingNativeLifetimesBySourceID.removeValue(forKey: sourceID)
            promotePendingConfigurationDesiredToFIFO(for: sourceID)
            retiringGenerationChainsBySourceID[sourceID] = chain
            return result
        case .unchanged(let result):
            return result
        }
    }

    func installRetirementFence(
        _ pendingLifetime: FilesystemRetirementFencePendingLifetime,
        contributionIdentity: FilesystemObservationContributionIdentity
    ) -> FilesystemRetirementFenceInstallationResult {
        let binding = pendingLifetime.binding
        let slotSnapshot: FilesystemUnpublishedFailureSlotState =
            statesByPhysicalSlotID[binding.physicalSlotID].map {
                .declared($0)
            } ?? .undeclared
        let plan = FilesystemObservationRetirementTransitionPlanner.planFenceInstallation(
            FilesystemRetirementFenceInstallationRequest(
                pendingLifetime: pendingLifetime,
                contributionIdentity: contributionIdentity,
                currentSlotState: slotSnapshot,
                retiringGenerationChain: read.retiringGenerationChain(
                    for: binding.registration.sourceID
                )
            )
        )
        switch plan {
        case .apply(let mutation, let result):
            retiringGenerationChainsBySourceID[binding.registration.sourceID] =
                mutation.retiringGenerationChain
            statesByPhysicalSlotID[binding.physicalSlotID] =
                .retirementFenceInstalled(mutation.installedLifetime)
            return result
        case .unchanged(let result):
            return result
        }
    }

    private func admitDesiredRegistration(
        _ desiredRegistration: FilesystemObservationDesiredRegistration
    ) -> FilesystemObservationDesiredUpdateResult {
        let sourceID = desiredRegistration.sourceID
        let pendingSnapshot: FilesystemDesiredCustodyPlanner.PendingConfigurationSnapshot =
            pendingConfigurationDesiredBySourceID[sourceID].map {
                .retained($0)
            } ?? .absent
        let plan = FilesystemDesiredCustodyPlanner.plan(
            FilesystemDesiredCustodyPlanner.Input(
                desiredRegistration: desiredRegistration,
                deferredCustody: deferredDesiredRegistrationsBySourceID[sourceID].map {
                    .retained($0)
                } ?? .absent,
                selectedCustody: selectedDesiredSourcesBySourceID[sourceID].map {
                    .retained($0)
                } ?? .absent,
                startingCustody: startingNativeLifetimesBySourceID[sourceID].map {
                    .retained($0)
                } ?? .absent,
                predecessorSlot: read.predecessorSlotSnapshot(for: desiredRegistration),
                retiringGenerationChain: read.retiringGenerationChain(for: sourceID),
                pendingConfiguration: pendingSnapshot
            )
        )
        switch plan {
        case .replaceDeferred(let previous, let successor, let pendingSupersession):
            deferredDesiredRegistrationsBySourceID[sourceID] = successor
            applyPendingSupersession(pendingSupersession, successor: successor)
            return .replacedDeferred(previous, successor)
        case .deferToConfigurationCurrentness(let desired, let custodyRequirement):
            pendingConfigurationDesiredBySourceID[sourceID] =
                supersededPendingRecord(custodyRequirement, desiredRegistration: desired)
            return .deferredToConfigurationCurrentness(desired)
        case .enqueueAtDeferredTail(let desired, let pendingRemoval):
            if case .remove = pendingRemoval {
                pendingConfigurationDesiredBySourceID.removeValue(forKey: sourceID)
            }
            deferredDesiredRegistrationsBySourceID[sourceID] = desired
            deferredSourceOrder.append(sourceID)
            return .enqueued(desired)
        }
    }

    private func applyPendingSupersession(
        _ supersession: FilesystemDesiredCustodyPlanner.PendingConfigurationSupersession,
        successor: FilesystemObservationDesiredRegistration
    ) {
        guard case .replaceDesiredRegistration(_, let requirement) = supersession else {
            return
        }
        pendingConfigurationDesiredBySourceID[successor.sourceID] =
            supersededPendingRecord(requirement, desiredRegistration: successor)
    }

    func prepareContinuityRepairHandoff(
        for acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
    ) -> FilesystemContinuityRepairHandoffPreparationResult {
        let sourceID = acceptingNativeLifetime.binding.registration.sourceID
        let publicationSnapshot: FilesystemContinuityRepairCustodyPlanner.AcceptingPublicationSnapshot
        if case .accepting(let publication) =
            statesByPhysicalSlotID[acceptingNativeLifetime.binding.physicalSlotID]
        {
            publicationSnapshot = .accepting(publication)
        } else {
            publicationSnapshot = .unavailable
        }
        let plan = FilesystemContinuityRepairCustodyPlanner.prepareHandoffRecord(
            FilesystemContinuityRepairCustodyPlanner.PendingRecordHandoffPreparationInput(
                repairInventory: pendingConfigurationDesiredBySourceID.isEmpty
                    ? .vacant : .retained,
                acceptingPublication: publicationSnapshot,
                pendingRecord: pendingConfigurationDesiredBySourceID[sourceID].map {
                    .retained($0)
                } ?? .absent,
                acceptingNativeLifetime: acceptingNativeLifetime,
                candidateHandoffIdentity: FilesystemContinuityRepairHandoffIdentity(
                    value: UUIDv7.generate()
                )
            )
        )
        if case .replace(let pendingRecord, _) = plan {
            pendingConfigurationDesiredBySourceID[sourceID] = pendingRecord
        }
        return plan.result
    }

    func acknowledgeContinuityRepairHandoff(
        _ acceptance: FilesystemSourceGateContinuityRepairAcceptance
    ) -> FilesystemRepairHandoffAcknowledgementResult {
        let acceptedBinding = acceptance.authority.acceptingBinding
        let sourceID = acceptedBinding.registration.sourceID
        let bindingSnapshot: FilesystemContinuityRepairCustodyPlanner.AcceptanceBindingSnapshot =
            acceptedBinding.fleetMailboxIdentity == fleetMailboxIdentity
                && statesByPhysicalSlotID[acceptedBinding.physicalSlotID] != nil
            ? .declared : .unavailable
        let plan = FilesystemContinuityRepairCustodyPlanner.acknowledgeHandoffRecord(
            FilesystemContinuityRepairCustodyPlanner.PendingRecordHandoffAcknowledgementInput(
                bindingSnapshot: bindingSnapshot,
                pendingRecord: pendingConfigurationDesiredBySourceID[sourceID].map {
                    .retained($0)
                } ?? .absent,
                acceptance: acceptance
            )
        )
        if case .replace(let pendingRecord, _) = plan {
            pendingConfigurationDesiredBySourceID[sourceID] = pendingRecord
        }
        return plan.result
    }

    private func promotePendingConfigurationDesiredToFIFO(
        for sourceID: FilesystemSourceID
    ) {
        guard
            let pendingRecord = pendingConfigurationDesiredBySourceID[sourceID]
        else {
            return
        }
        let pendingDesiredRegistration = pendingRecord.desiredRegistration
        if pendingRecord.continuityRepairCustody.projectedState == .absent {
            pendingConfigurationDesiredBySourceID.removeValue(forKey: sourceID)
        }
        deferredDesiredRegistrationsBySourceID[sourceID] = pendingDesiredRegistration
        deferredSourceOrder.append(sourceID)
    }

    private func applySelectedWithdrawalSuccessor(
        _ successor: FilesystemObservationSlotAdmissionPlanner.SelectedWithdrawalSuccessorCustody,
        sourceID: FilesystemSourceID
    ) {
        switch successor {
        case .absent:
            return
        case .promoteAndRemovePending(let desiredRegistration):
            pendingConfigurationDesiredBySourceID.removeValue(forKey: sourceID)
            deferredDesiredRegistrationsBySourceID[sourceID] = desiredRegistration
        case .promoteRetainingPending(let desiredRegistration):
            deferredDesiredRegistrationsBySourceID[sourceID] = desiredRegistration
        }
        deferredSourceOrder.append(sourceID)
    }

    func publishAcceptingNativeLifetime(
        _ startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity
    ) -> FilesystemObservationAcceptingPublicationResult {
        let binding = startingNativeLifetime.binding
        let plan = FilesystemObservationSlotAdmissionPlanner.planAcceptingPublication(
            FilesystemObservationSlotAdmissionPlanner.AcceptingPublicationInput(
                fleetMailboxIdentity: fleetMailboxIdentity,
                startingNativeLifetime: startingNativeLifetime,
                callbackAdmissionPortIdentity: callbackAdmissionPortIdentity,
                slotLookup: statesByPhysicalSlotID[binding.physicalSlotID].map {
                    .declared($0)
                } ?? .undeclared,
                publicationRetention: postStartPublicationRetentionByPhysicalSlotID[
                    binding.physicalSlotID
                ] ?? .vacant,
                pendingConfiguration: read.pendingConfigurationState(
                    for: startingNativeLifetime.desiredRegistration.sourceID
                )
            )
        )
        switch plan {
        case .result(let result):
            return result
        case .publish(let publication):
            statesByPhysicalSlotID[binding.physicalSlotID] = .accepting(publication)
            postStartPublicationRetentionByPhysicalSlotID[binding.physicalSlotID] =
                .retained(publication)
            return .published(publication)
        }
    }

    func beginClosingAwaitingCallbackLeaseDrain(
        _ acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
    ) -> FilesystemObservationCallbackLeaseDrainClosingResult {
        let binding = acceptingNativeLifetime.binding
        let plan = FilesystemObservationSlotAdmissionPlanner.planCallbackLeaseDrainClosing(
            FilesystemObservationSlotAdmissionPlanner.CallbackLeaseDrainClosingInput(
                fleetMailboxIdentity: fleetMailboxIdentity,
                acceptingNativeLifetime: acceptingNativeLifetime,
                slotLookup: statesByPhysicalSlotID[binding.physicalSlotID].map {
                    .declared($0)
                } ?? .undeclared
            )
        )
        switch plan {
        case .result(let result):
            return result
        case .transition(let lifetime):
            statesByPhysicalSlotID[binding.physicalSlotID] =
                .closingAwaitingCallbackLeaseDrain(lifetime)
            return .transitioned(lifetime)
        }
    }

    func transferRetirementFence(
        _ installedLifetime: FilesystemRetirementFenceInstalledLifetime,
        retirementAuthority: FilesystemObservationSlotRetirementAuthority
    ) -> FilesystemObservationRetirementFenceTransferResult {
        let binding = installedLifetime.binding
        let currentState = FilesystemObservationRetirementTransitionPlanner.transferState(
            physicalSlotState: read.state(of: binding.physicalSlotID),
            retiringGenerationChain: read.retiringGenerationChain(
                for: binding.registration.sourceID
            )
        )
        switch FilesystemObservationRetirementTransitionPlanner.planFenceTransfer(
            installedLifetime: installedLifetime,
            retirementAuthority: retirementAuthority,
            currentState: currentState
        ) {
        case .apply(let mutation, let result):
            retiringGenerationChainsBySourceID[binding.registration.sourceID] =
                mutation.retiringGenerationChain
            statesByPhysicalSlotID[binding.physicalSlotID] =
                .retirementFenceTransferredAwaitingCleanup(mutation.transferredLifetime)
            return result
        case .unchanged(let result):
            return result
        }
    }

    private func supersededPendingRecord(
        _ requirement: FilesystemContinuityRepairCustodyPlanner.SupersessionRequirement,
        desiredRegistration: FilesystemObservationDesiredRegistration
    ) -> FilesystemObservationPendingConfigurationRecord {
        let input: FilesystemContinuityRepairCustodyPlanner.SupersessionInput
        switch requirement {
        case .preserve(let retainedCustody):
            input = .preserve(retainedCustody)
        case .issuePendingAuthority(let cause, let revision):
            input = .replacePending(
                FilesystemContinuityRepairCustodyPlanner.makePendingAuthority(
                    identity: FilesystemPendingContinuityRepairIdentity(
                        value: UUIDv7.generate()
                    ),
                    desiredRegistration: desiredRegistration,
                    cause: cause,
                    recoveryRevision: revision
                )
            )
        case .issueHandoffSuccessorAuthority(let handoff, let cause, let revision):
            input = .replaceHandoffSuccessor(
                handoff: handoff,
                successorAuthority: FilesystemContinuityRepairCustodyPlanner.makePendingAuthority(
                    identity: FilesystemPendingContinuityRepairIdentity(
                        value: UUIDv7.generate()
                    ),
                    desiredRegistration: desiredRegistration,
                    cause: cause,
                    recoveryRevision: revision
                )
            )
        }
        return FilesystemContinuityRepairCustodyPlanner.supersededPendingRecord(
            .init(desiredRegistration: desiredRegistration, supersession: input)
        )
    }

}

extension FilesystemObservationSlotRegistry.ReadView {
    var deferredDesiredRegistrationsInFIFOOrder: [FilesystemObservationDesiredRegistration] {
        FilesystemObservationSlotReadModel.deferredRegistrations(
            sourceOrder: registry.deferredSourceOrder,
            registrationsBySourceID: registry.deferredDesiredRegistrationsBySourceID
        )
    }

    func state(
        of physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FilesystemObservationPhysicalSlotState {
        projectFilesystemObservationSlotState(registry.statesByPhysicalSlotID[physicalSlotID])
    }

    func storedBindingCurrentness(
        of binding: FilesystemObservationSlotBinding
    ) -> FilesystemObservationStoredBindingCurrentness {
        FilesystemObservationSlotReadModel.storedBindingCurrentness(
            classifiedCurrentness: FilesystemObservationSlotCurrentnessClassifier.classify(
                binding: binding,
                fleetMailboxIdentity: registry.fleetMailboxIdentity,
                physicalSlotState: state(of: binding.physicalSlotID)
            ),
            binding: binding,
            startingLifetime: registry.startingNativeLifetimesBySourceID[
                binding.registration.sourceID
            ].map { .retained($0) } ?? .absent
        )
    }

    func desiredState(
        for sourceID: FilesystemSourceID
    ) -> FilesystemObservationDesiredSlotState {
        if let selection = registry.selectedDesiredSourcesBySourceID[sourceID] {
            return FilesystemObservationSlotReadModel.desiredState(from: .selected(selection))
        }
        if let startingNativeLifetime = registry.startingNativeLifetimesBySourceID[sourceID] {
            return FilesystemObservationSlotReadModel.desiredState(
                from: .starting(
                    startingNativeLifetime,
                    state(of: startingNativeLifetime.binding.physicalSlotID)
                )
            )
        }
        if let desiredRegistration = registry.deferredDesiredRegistrationsBySourceID[sourceID] {
            return FilesystemObservationSlotReadModel.desiredState(
                from: .deferred(desiredRegistration)
            )
        }
        return FilesystemObservationSlotReadModel.desiredState(
            from: .retirement(retiringGenerationChain(for: sourceID))
        )
    }

    func pendingConfigurationState(
        for sourceID: FilesystemSourceID
    ) -> FilesystemObservationPendingConfigurationState {
        registry.pendingConfigurationDesiredBySourceID[sourceID]
            .map {
                FilesystemObservationPendingConfigurationState.retained(
                    $0.desiredRegistration
                )
            } ?? .absent
    }

    func pendingContinuityRepairState(
        for sourceID: FilesystemSourceID
    ) -> FilesystemPendingContinuityRepairState {
        registry.pendingConfigurationDesiredBySourceID[sourceID]?
            .continuityRepairCustody.projectedState ?? .absent
    }

    fileprivate func predecessorSlotSnapshot(
        for desiredRegistration: FilesystemObservationDesiredRegistration
    ) -> FilesystemDesiredCustodyPlanner.PredecessorSlotSnapshot {
        guard
            case .replacementRetainingPredecessor(let predecessor) =
                desiredRegistration.admission
        else {
            return .unavailable
        }
        return .declared(state(of: predecessor.binding.physicalSlotID))
    }

    func retiringGenerationChain(
        for sourceID: FilesystemSourceID
    ) -> FilesystemObservationRetiringGenerationChain {
        registry.retiringGenerationChainsBySourceID[sourceID] ?? .none
    }

    func pendingRetirementFence(
        for physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FilesystemObservationPendingRetirementFenceLookup {
        FilesystemObservationSlotReadModel.pendingRetirementFence(
            from: state(of: physicalSlotID)
        )
    }

    var fleetShutdownProjectionPhysicalSlotIDs: [FilesystemObservationPhysicalSlotID] {
        registry.physicalSlotIDs
    }

    var fleetShutdownProjectionPendingConfigurations:
        [FilesystemSourceID: FilesystemObservationPendingConfigurationRecord]
    {
        registry.pendingConfigurationDesiredBySourceID
    }

    func fleetShutdownProjectionSlotState(
        for physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FilesystemObservationRegistrySlotState? {
        registry.statesByPhysicalSlotID[physicalSlotID]
    }

    func fleetShutdownProjectionPublicationRetention(
        for physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FilesystemObservationPostStartPublicationRetention {
        registry.postStartPublicationRetentionByPhysicalSlotID[physicalSlotID] ?? .vacant
    }

    func fleetShutdownProjectionCompletedRelease(
        for physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FilesystemObservationLastCompletedRelease? {
        registry.lastCompletedReleasesByPhysicalSlotID[physicalSlotID]
    }
}
