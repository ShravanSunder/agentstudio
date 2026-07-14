import Foundation

// Shutdown debt names remain explicit because these types cross several lifecycle owners.
// Strict associated values encode correlated state that must not be representable independently.
// swiftlint:disable type_name enum_case_associated_values_count

struct FilesystemObservationDesiredShutdownReference: Equatable, Sendable {
    let sourceID: FilesystemSourceID
    let registration: FSEventRegistrationToken
    let desiredIdentity: FilesystemObservationDesiredIdentity
    let acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision
}

enum FilesystemObservationPostStartShutdownDisposition: Equatable, Sendable {
    case current
    case closePredecessor(FilesystemObservationSlotBinding)
    case closePublished(FilesystemObservationSlotBinding)
    case closePredecessorAndPublished(
        predecessor: FilesystemObservationSlotBinding,
        published: FilesystemObservationSlotBinding
    )
}

enum FilesystemObservationUnpublishedShutdownCause: Equatable, Sendable {
    case desiredWithdrawn
    case nativeCreateOrStartFailed(FilesystemObservationDesiredShutdownReference)
}

enum FilesystemObservationRetirementOrder: Equatable, Sendable {
    case oldest
    case successor
}

enum FilesystemObservationNativeRetirementShutdownDisposition: Equatable, Sendable {
    case fenceBacked(
        fenceIdentity: FilesystemObservationRetirementFenceIdentity,
        disposition: FilesystemObservationSlotRetirementDisposition,
        retirementAuthority: FilesystemObservationSlotRetirementAuthority
    )
    case unpublished(
        retirementAuthority: FilesystemUnpublishedRetirementAuthority,
        finalizationKind: FilesystemObservationUnpublishedFinalizationKind
    )
}

struct FilesystemObservationNativeRetirementShutdownReference: Equatable, Sendable {
    let native: FilesystemObservationNativeShutdownReference
    let disposition: FilesystemObservationNativeRetirementShutdownDisposition
}

enum FilesystemObservationCompletedReleaseShutdownReplay: Equatable, Sendable {
    case vacant
    case completed(
        retirement: FilesystemObservationNativeRetirementShutdownReference,
        releaseAuthority: FilesystemObservationContextReleaseAuthority
    )
}

enum FilesystemObservationRegistrySlotShutdownLifecycle: Equatable, Sendable {
    case vacant
    case selected(
        desired: FilesystemObservationDesiredShutdownReference,
        reservation: FilesystemObservationSlotReservation
    )
    case starting(FilesystemObservationNativeShutdownReference)
    case awaitingAcceptingPublication(FilesystemObservationNativeShutdownReference)
    case accepting(
        FilesystemObservationNativeShutdownReference,
        disposition: FilesystemObservationPostStartShutdownDisposition
    )
    case closingAwaitingCallbackLeaseDrain(FilesystemObservationNativeShutdownReference)
    case closingAwaitingPredecessor(
        FilesystemObservationNativeShutdownReference,
        receipt: DarwinFSEventRegistrationLeaseDrainReceipt,
        order: FilesystemObservationRetirementOrder
    )
    case retirementFencePending(
        binding: FilesystemObservationSlotBinding,
        receipt: DarwinFSEventRegistrationLeaseDrainReceipt,
        fence: FilesystemObservationSlotRetirementFence,
        order: FilesystemObservationRetirementOrder
    )
    case retirementFenceInstalled(
        binding: FilesystemObservationSlotBinding,
        receipt: DarwinFSEventRegistrationLeaseDrainReceipt,
        fence: FilesystemObservationSlotRetirementFence,
        contributionIdentity: FilesystemObservationContributionIdentity,
        order: FilesystemObservationRetirementOrder
    )
    case retirementFenceTransferredAwaitingCleanup(
        binding: FilesystemObservationSlotBinding,
        fence: FilesystemObservationSlotRetirementFence,
        retirementAuthority: FilesystemObservationSlotRetirementAuthority,
        order: FilesystemObservationRetirementOrder
    )
    case retiredAwaitingContextRelease(
        FilesystemObservationNativeRetirementShutdownReference,
        order: FilesystemObservationRetirementOrder
    )
    case retiringUnpublished(
        FilesystemObservationNativeShutdownReference,
        cause: FilesystemObservationUnpublishedShutdownCause,
        order: FilesystemObservationRetirementOrder
    )
}

enum FilesystemObservationPostStartPublicationShutdownDebt: Equatable, Sendable {
    case vacant
    case retained(
        FilesystemObservationNativeShutdownReference,
        disposition: FilesystemObservationPostStartShutdownDisposition
    )
    case retainedAfterRemoval(
        FilesystemObservationNativeShutdownReference,
        disposition: FilesystemObservationPostStartShutdownDisposition,
        removalAuthority: FilesystemSourceRemovalAuthority
    )
}

struct FilesystemObservationRegistrySlotShutdownDebt: Equatable, Sendable {
    let lifecycle: FilesystemObservationRegistrySlotShutdownLifecycle
    let postStartPublication: FilesystemObservationPostStartPublicationShutdownDebt
}

enum FilesystemObservationNativeOwnerShutdownDebt: Equatable, Sendable {
    case vacant
    case issued(
        callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity,
        projection: DarwinFSEventNativeOwnerFleetShutdownProjection
    )
}

enum FilesystemObservationRetryEvidenceShutdownDebt: Equatable, Sendable {
    case vacant
    case retained(
        binding: FilesystemObservationSlotBinding,
        evidence: FixedFilesystemRecoveryEvidenceSnapshot
    )
}

enum FilesystemObservationRecoveryShutdownDebt: Equatable, Sendable {
    case vacant
    case clear(FilesystemObservationSlotBinding)
    case retained(FixedFilesystemRecoveryEvidenceSnapshot)
}

enum FilesystemObservationLeaseShutdownContributionReference: Equatable, Sendable {
    case observation(FilesystemObservationContributionIdentity)
    case retirementFence(
        FilesystemObservationContributionIdentity,
        FilesystemObservationRetirementFenceIdentity
    )
}

enum FilesystemObservationLeaseShutdownFingerprint: Equatable, Sendable {
    case contributions([FilesystemObservationLeaseShutdownContributionReference])
    case contributionsWithRecovery(
        [FilesystemObservationLeaseShutdownContributionReference],
        FixedFilesystemRecoveryEvidenceRevision
    )
    case recovery(FixedFilesystemRecoveryEvidenceRevision)
}

enum FilesystemObservationActiveLeaseShutdownDebt: Equatable, Sendable {
    case vacant
    case authoritative(
        token: AdmissionDrainToken,
        binding: FilesystemObservationSlotBinding,
        fingerprint: FilesystemObservationLeaseShutdownFingerprint
    )
    case recovery(
        token: AdmissionDrainToken,
        binding: FilesystemObservationSlotBinding,
        evidence: FixedFilesystemRecoveryEvidenceSnapshot,
        fingerprint: FilesystemObservationLeaseShutdownFingerprint
    )
}

enum FilesystemObservationPendingWholeLeaseCompletionShutdownDebt: Equatable, Sendable {
    case vacant
    case ordinary(
        authority: FilesystemObservationWholeLeaseTransferAuthority,
        acknowledgement: FilesystemLeaseAcknowledgementReceipt
    )
    case retirement(
        authority: FilesystemObservationWholeLeaseTransferAuthority,
        acknowledgement: FilesystemLeaseAcknowledgementReceipt,
        binding: FilesystemObservationSlotBinding,
        fenceIdentity: FilesystemObservationRetirementFenceIdentity,
        contributionIdentity: FilesystemObservationContributionIdentity,
        disposition: FilesystemObservationSlotRetirementDisposition
    )
}

struct FilesystemObservationPendingContinuityRepairShutdownReference: Equatable, Sendable {
    let identity: FilesystemPendingContinuityRepairIdentity
    let registration: FSEventRegistrationToken
    let desiredIdentity: FilesystemObservationDesiredIdentity
    let acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision
    let cause: FilesystemPendingContinuityRepairCause
    let recoveryRevision: FilesystemContinuityRepairRevision
    let requiredParticipantKinds: Set<FilesystemRepairParticipantKind>
}

struct FilesystemObservationContinuityRepairHandoffShutdownReference: Equatable, Sendable {
    let acceptingBinding: FilesystemObservationSlotBinding
    let handoffIdentity: FilesystemContinuityRepairHandoffIdentity
    let desiredIdentity: FilesystemObservationDesiredIdentity
    let acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision
}

struct FilesystemObservationSourceRemovalShutdownReference: Equatable, Sendable {
    let identity: FilesystemSourceRemovalAuthorityIdentity
    let exactPriorBinding: FilesystemObservationSlotBinding
    let acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision
}

enum FilesystemObservationContinuityRepairSuccessorShutdownReference: Equatable, Sendable {
    case sameDesired
    case superseded(FilesystemObservationPendingContinuityRepairShutdownReference)
    case removed(FilesystemObservationSourceRemovalShutdownReference)
}

struct FilesystemObservationContinuityRepairHandoffStateShutdownReference: Equatable, Sendable {
    let pending: FilesystemObservationPendingContinuityRepairShutdownReference
    let authority: FilesystemObservationContinuityRepairHandoffShutdownReference
    let successor: FilesystemObservationContinuityRepairSuccessorShutdownReference
}

struct FilesystemObservationContinuityRepairAcceptanceShutdownReference: Equatable, Sendable {
    let authority: FilesystemObservationContinuityRepairHandoffShutdownReference
    let repairGenerationID: RepairGenerationID
}

enum FilesystemObservationContinuityRepairAcknowledgementShutdownReference: Equatable, Sendable {
    case sameDesired(
        handoff: FilesystemObservationContinuityRepairHandoffStateShutdownReference,
        acceptance: FilesystemObservationContinuityRepairAcceptanceShutdownReference
    )
    case superseded(
        handoff: FilesystemObservationContinuityRepairHandoffStateShutdownReference,
        acceptance: FilesystemObservationContinuityRepairAcceptanceShutdownReference,
        successor: FilesystemObservationPendingContinuityRepairShutdownReference
    )
    case removed(
        handoff: FilesystemObservationContinuityRepairHandoffStateShutdownReference,
        acceptance: FilesystemObservationContinuityRepairAcceptanceShutdownReference,
        removal: FilesystemObservationSourceRemovalShutdownReference
    )
}

enum FilesystemObservationContinuityRepairAcknowledgedSuccessorShutdownReference:
    Equatable, Sendable
{
    case noSuccessor
    case pending(FilesystemObservationPendingContinuityRepairShutdownReference)
}

enum FilesystemObservationContinuityRepairShutdownCustody: Equatable, Sendable {
    case absent
    case pending(FilesystemObservationPendingContinuityRepairShutdownReference)
    case handoffInFlight(FilesystemObservationContinuityRepairHandoffStateShutdownReference)
    case acknowledged(
        FilesystemObservationContinuityRepairAcknowledgementShutdownReference,
        successor: FilesystemObservationContinuityRepairAcknowledgedSuccessorShutdownReference
    )
}

struct FilesystemObservationPendingDesiredShutdownCustody: Equatable, Sendable {
    let desired: FilesystemObservationDesiredShutdownReference
    let continuityRepair: FilesystemObservationContinuityRepairShutdownCustody
}

struct FilesystemObservationDeclaredSlotPendingShutdownCustody: Equatable, Sendable {
    let physicalSlotID: FilesystemObservationPhysicalSlotID
    let pending: FilesystemObservationPendingDesiredShutdownCustody
}

struct FilesystemObservationDeferredPendingShutdownCustody: Equatable, Sendable {
    let deferred: FilesystemObservationDesiredShutdownReference
    let pending: FilesystemObservationPendingDesiredShutdownCustody
}

struct FilesystemObservationDetachedPendingShutdownInventory: Equatable, Sendable {
    let pendingBySourceID: [FilesystemSourceID: FilesystemObservationPendingDesiredShutdownCustody]
}

struct FilesystemObservationDesiredShutdownCustody: Equatable, Sendable {
    let deferredFIFO: [FilesystemObservationDesiredShutdownReference]
    let pendingInDeclaredSlotOrder: [FilesystemObservationDeclaredSlotPendingShutdownCustody]
    let pendingInDeferredFIFOOrder: [FilesystemObservationDeferredPendingShutdownCustody]
    let detachedPending: FilesystemObservationDetachedPendingShutdownInventory

    var isVacant: Bool {
        deferredFIFO.isEmpty
            && pendingInDeclaredSlotOrder.isEmpty
            && pendingInDeferredFIFOOrder.isEmpty
            && detachedPending.pendingBySourceID.isEmpty
    }
}

struct FilesystemObservationSlotShutdownDebt: Equatable, Sendable {
    let physicalSlotID: FilesystemObservationPhysicalSlotID
    let registry: FilesystemObservationRegistrySlotShutdownDebt
    let nativeOwner: FilesystemObservationNativeOwnerShutdownDebt
    let retryEvidence: FilesystemObservationRetryEvidenceShutdownDebt
    let recoveryEvidence: FilesystemObservationRecoveryShutdownDebt
    let generic: GatherShutdownKeyDebt<FilesystemObservationPhysicalSlotID>
    let completedReleaseReplay: FilesystemObservationCompletedReleaseShutdownReplay

    var isQuiescent: Bool {
        guard case .vacant = registry.lifecycle,
            case .vacant = registry.postStartPublication,
            case .vacant = nativeOwner,
            case .vacant = retryEvidence,
            case .vacant = recoveryEvidence
        else {
            return false
        }
        return generic.queuedContributionCount == 0
            && generic.queuedItemCount == 0
            && generic.queuedByteCount == 0
            && generic.retryDisposition == .vacant
            && generic.recoveryDisposition == .vacant
            && generic.queuedCleanupContributionCount == 0
            && generic.queuedCleanupItemCount == 0
            && generic.queuedCleanupByteCount == 0
    }
}

struct FilesystemObservationFleetShutdownMailboxDebtSnapshot: Equatable, Sendable {
    let fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity
    let shutdownIdentity: FilesystemObservationFleetShutdownIdentity
    let fleetIngressLifecycle: FilesystemObservationFleetIngressLifecycle
    let fleetOrdinaryAdmissionDisposition: FilesystemFleetOrdinaryAdmissionDisposition
    let mailboxLifecycle: FilesystemObservationLifecycleStateSnapshot
    let slots: [FilesystemObservationSlotShutdownDebt]
    let desiredCustody: FilesystemObservationDesiredShutdownCustody
    let activeLease: FilesystemObservationActiveLeaseShutdownDebt
    let pendingWholeLeaseCompletion: FilesystemObservationPendingWholeLeaseCompletionShutdownDebt
    let genericMailboxDebt: GatherShutdownDebtSnapshot<FilesystemObservationPhysicalSlotID>
    let retirementFenceReadyFIFO: [FilesystemObservationPhysicalSlotID]
    let isQuiescent: Bool
}

enum FilesystemObservationFleetIngressFreezeAndSnapshotResult: Equatable, Sendable {
    case applied(FilesystemObservationFleetShutdownMailboxDebtSnapshot)
    case alreadyApplied(FilesystemObservationFleetShutdownMailboxDebtSnapshot)
    case fleetMailboxMismatch(
        expected: FilesystemObservationFleetMailboxIdentity,
        presented: FilesystemObservationFleetMailboxIdentity
    )
    case shutdownIdentityMismatch(
        expected: FilesystemObservationFleetShutdownIdentity,
        presented: FilesystemObservationFleetShutdownIdentity
    )
    case terminationAlreadyAdvanced(FilesystemObservationLifecycleStateSnapshot)
}

// swiftlint:enable type_name enum_case_associated_values_count
