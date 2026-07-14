import Foundation
import os

struct FilesystemObservationWholeLeasePreflightReceipt: Equatable, Sendable {
    fileprivate let identity: UUID
    let binding: FilesystemObservationSlotBinding
    fileprivate let token: AdmissionDrainToken

    var isUUIDv7: Bool { UUIDv7.isV7(identity) }

    fileprivate init(
        binding: FilesystemObservationSlotBinding,
        token: AdmissionDrainToken
    ) {
        identity = UUIDv7.generate()
        self.binding = binding
        self.token = token
    }

    fileprivate func matches(
        token expectedToken: AdmissionDrainToken,
        binding expectedBinding: FilesystemObservationSlotBinding
    ) -> Bool {
        token == expectedToken && binding == expectedBinding
    }
}

struct FilesystemLeaseAcknowledgementReceipt: Equatable, Sendable {
    fileprivate let authorityIdentity: UUID
    let binding: FilesystemObservationSlotBinding

    fileprivate init(authority: FilesystemObservationWholeLeaseTransferAuthority) {
        authorityIdentity = authority.preflight.identity
        binding = authority.binding
    }

    func matches(
        _ authority: FilesystemObservationWholeLeaseTransferAuthority
    ) -> Bool {
        authorityIdentity == authority.preflight.identity && binding == authority.binding
    }
}

// This fixed-capacity mailbox keeps all custody transitions together under one lock.
// swiftlint:disable file_length type_body_length

// swiftlint:disable:next type_name
enum FilesystemObservationNativeGenerationPortCreationResult: Sendable {
    case created(FilesystemObservationNativeGenerationPorts)
    case foreignFleet
    case undeclaredPhysicalSlot
    case bindingNotCurrent
}

struct FilesystemObservationContributionIdentity: Equatable, Hashable, Sendable {
    let binding: FilesystemObservationSlotBinding
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    fileprivate init(binding: FilesystemObservationSlotBinding, value: UUID) {
        self.binding = binding
        self.value = value
    }
}

struct FilesystemObservationNativeGenerationPorts: Sendable {
    let callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort
    let lifecyclePort: FilesystemObservationNativeLifecyclePort
    let nativeOwner: DarwinFSEventRegistrationNativeOwner

    fileprivate init(
        callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort,
        lifecyclePort: FilesystemObservationNativeLifecyclePort,
        nativeOwner: DarwinFSEventRegistrationNativeOwner
    ) {
        self.callbackAdmissionPort = callbackAdmissionPort
        self.lifecyclePort = lifecyclePort
        self.nativeOwner = nativeOwner
    }
}

private enum FilesystemObservationCallbackMailboxCaptureResult: Sendable {
    case admitted(FilesystemObservationOffer, FilesystemObservationOfferReceipt)
    case ignoredEmptyCallback
    case captureRejected(DarwinFSEventObservationCaptureRejection)
    case mailboxRejected(FilesystemObservationCallbackMailboxRejection)
}

struct FilesystemObservationCallbackAdmissionPort: Equatable, Sendable {
    let identity: FilesystemObservationCallbackAdmissionPortIdentity
    private let operation: FilesystemObservationCallbackAdmissionOperation

    fileprivate init(
        identity: FilesystemObservationCallbackAdmissionPortIdentity,
        operation: FilesystemObservationCallbackAdmissionOperation
    ) {
        self.identity = identity
        self.operation = operation
    }

    func admit(
        using lease: FSEventCallbackLease,
        preflight: FilesystemObservationCallbackPreflight,
        capture: () -> DarwinFSEventObservationCapture.OfferResult
    ) -> DarwinFSEventObservationCaptureResult {
        operation.admit(using: lease, preflight: preflight, capture: capture)
    }

    static func == (
        lhs: Self,
        rhs: Self
    ) -> Bool {
        lhs.identity == rhs.identity
    }
}

struct FilesystemObservationNativeLifecyclePort: Sendable {
    private let operation: FilesystemObservationNativeLifecycleOperation
    private let mailboxLifetimeOwner: FilesystemObservationMailbox?

    fileprivate init(
        operation: FilesystemObservationNativeLifecycleOperation,
        mailboxLifetimeOwner: FilesystemObservationMailbox? = nil
    ) {
        self.operation = operation
        self.mailboxLifetimeOwner = mailboxLifetimeOwner
    }

    func publishAccepting(
        _ startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    ) -> FilesystemObservationAcceptingPublicationResult {
        operation.publishAccepting(startingNativeLifetime)
    }

    func beginClosingAwaitingCallbackLeaseDrain(
        _ acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
    ) -> FilesystemObservationCallbackLeaseDrainClosingResult {
        operation.beginClosingAwaitingCallbackLeaseDrain(acceptingNativeLifetime)
    }
}

private final class FilesystemObservationNativeLifecycleOperation: @unchecked Sendable {
    private let expectedStartingNativeLifetime: FilesystemObservationStartingNativeLifetime
    private let callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity
    private weak var core: FilesystemObservationMailboxCore?

    init(
        startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity,
        core: FilesystemObservationMailboxCore
    ) {
        expectedStartingNativeLifetime = startingNativeLifetime
        self.callbackAdmissionPortIdentity = callbackAdmissionPortIdentity
        self.core = core
    }

    func publishAccepting(
        _ startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    ) -> FilesystemObservationAcceptingPublicationResult {
        guard startingNativeLifetime == expectedStartingNativeLifetime else {
            return .startingNativeLifetimeMismatch(expectedStartingNativeLifetime)
        }
        guard let core else { return .mailboxReleased }
        return core.publishAcceptingNativeLifetime(
            startingNativeLifetime,
            callbackAdmissionPortIdentity: callbackAdmissionPortIdentity
        )
    }

    func beginClosingAwaitingCallbackLeaseDrain(
        _ acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
    ) -> FilesystemObservationCallbackLeaseDrainClosingResult {
        guard let core else { return .mailboxReleased }
        guard
            acceptingNativeLifetime.startingNativeLifetime
                == expectedStartingNativeLifetime,
            acceptingNativeLifetime.callbackAdmissionPortIdentity
                == callbackAdmissionPortIdentity
        else {
            return core.acceptingNativeLifetimeMismatch(
                for: expectedStartingNativeLifetime
            )
        }
        return core.beginClosingAwaitingCallbackLeaseDrain(
            acceptingNativeLifetime
        )
    }
}

private final class FilesystemObservationCallbackAdmissionOperation: @unchecked Sendable {
    private let leaseAdmissionAuthority: FilesystemObservationMailboxCore.CallbackLeaseAdmissionAuthority
    private let mailboxLifetimeOwner: FilesystemObservationMailbox
    private let core: FilesystemObservationMailboxCore
    private let synchronization: any FilesystemObservationCallbackSynchronization

    init(
        leaseAdmissionAuthority: FilesystemObservationMailboxCore.CallbackLeaseAdmissionAuthority,
        mailboxLifetimeOwner: FilesystemObservationMailbox,
        core: FilesystemObservationMailboxCore,
        synchronization: any FilesystemObservationCallbackSynchronization
    ) {
        self.leaseAdmissionAuthority = leaseAdmissionAuthority
        self.mailboxLifetimeOwner = mailboxLifetimeOwner
        self.core = core
        self.synchronization = synchronization
    }

    func admit(
        using lease: FSEventCallbackLease,
        preflight: FilesystemObservationCallbackPreflight,
        capture: () -> DarwinFSEventObservationCapture.OfferResult
    ) -> DarwinFSEventObservationCaptureResult {
        let leaseResult = lease.withOneShotCallbackAdmission(
            authority: leaseAdmissionAuthority,
            expectedCaptureLimits: preflight.captureLimits
        ) {
            synchronization.afterAuthorityConsumedBeforeMailboxOffer()
            let mailboxResult = core.captureAndOffer(
                for: leaseAdmissionAuthority.binding,
                preflight: preflight,
                capture: capture
            )
            synchronization.afterMailboxOfferBeforeWakeApplication()
            return applyWakeAndMap(mailboxResult)
        }
        switch leaseResult {
        case .admitted(let result):
            return result
        case .authorityRejected(let rejection):
            return .rejected(.callbackAuthority(Self.mapAuthorityRejection(rejection)))
        }
    }

    private func applyWakeAndMap(
        _ mailboxResult: FilesystemObservationCallbackMailboxCaptureResult
    ) -> DarwinFSEventObservationCaptureResult {
        switch mailboxResult {
        case .admitted(let offer, let receipt):
            let wakeApplication = core.applyCallbackWake(receipt.wake)
            return .admitted(
                offer: offer,
                admission: .admitted(receipt.disposition, wakeApplication)
            )
        case .ignoredEmptyCallback:
            return .ignoredEmptyCallback
        case .captureRejected(let rejection):
            return .rejected(rejection)
        case .mailboxRejected(let rejection):
            return .rejected(.mailbox(rejection))
        }
    }

    private static func mapAuthorityRejection(
        _ rejection: FSEventCallbackLeaseAuthorityRejection
    ) -> FilesystemObservationCallbackAuthorityRejection {
        switch rejection {
        case .released: .released
        case .foreignControlBlock: .foreignControlBlock
        case .registrationMismatch: .registrationMismatch
        case .slotBindingMismatch: .slotBindingMismatch
        case .captureConfigurationMismatch: .captureConfigurationMismatch
        case .alreadyConsumed: .alreadyConsumed
        }
    }
}

/// Bounded callback custody for opaque FSEvent observations.
///
/// The coordination lock couples the generic gather recovery revision to exact
/// filesystem recovery evidence. It intentionally performs no path or flag
/// reduction; semantic filesystem work belongs to the actor after a lease is
/// acquired.
final class FilesystemObservationMailboxCore: @unchecked Sendable {
    struct CallbackLeaseAdmissionAuthority: Sendable {
        let controlBlockIdentity: FilesystemObservationControlBlockIdentity
        let registration: FSEventRegistrationToken
        let binding: FilesystemObservationSlotBinding

        fileprivate init(binding: FilesystemObservationSlotBinding) {
            controlBlockIdentity = binding.controlBlockIdentity
            registration = binding.registration
            self.binding = binding
        }
    }

    private enum Lifecycle: Equatable, Sendable {
        case open
        case sealed
        case invalidated
        case finished(FilesystemObservationFleetShutdownIdentity)
    }

    private enum ActiveLeaseCustody: Sendable {
        case vacant
        case authoritative(
            token: AdmissionDrainToken,
            binding: FilesystemObservationSlotBinding,
            fingerprint: WholeLeaseFingerprint
        )
        case recovery(
            token: AdmissionDrainToken,
            binding: FilesystemObservationSlotBinding,
            evidence: FixedFilesystemRecoveryEvidenceSnapshot,
            fingerprint: WholeLeaseFingerprint
        )
    }

    private enum ContributionFingerprint: Equatable, Sendable {
        case observation(FilesystemObservationContributionIdentity)
        case retirementFence(
            FilesystemObservationContributionIdentity,
            FilesystemObservationSlotRetirementFence
        )

        var identity: FilesystemObservationContributionIdentity {
            switch self {
            case .observation(let identity), .retirementFence(let identity, _): identity
            }
        }
    }

    private enum WholeLeaseFingerprint: Equatable, Sendable {
        case contributions([ContributionFingerprint])
        case contributionsWithRecovery(
            [ContributionFingerprint],
            FixedFilesystemRecoveryEvidenceSnapshot
        )
        case recovery(FixedFilesystemRecoveryEvidenceSnapshot)

        var contributionFingerprints: [ContributionFingerprint] {
            switch self {
            case .contributions(let contributions),
                .contributionsWithRecovery(let contributions, _):
                contributions
            case .recovery:
                []
            }
        }
    }

    private enum PendingWholeLeaseCompletionCustody: Sendable {
        case vacant
        case ordinary(
            FilesystemObservationWholeLeaseTransferAuthority,
            FilesystemLeaseAcknowledgementReceipt
        )
        case retirement(
            FilesystemObservationWholeLeaseTransferAuthority,
            FilesystemLeaseAcknowledgementReceipt,
            FilesystemRetirementFenceInstalledLifetime,
            FilesystemObservationSlotRetirementDisposition
        )
    }

    private enum RetryEvidenceCustody: Sendable {
        case vacant
        case retained(
            binding: FilesystemObservationSlotBinding,
            evidence: FixedFilesystemRecoveryEvidenceSnapshot
        )
    }

    private enum PendingRetirementFenceAttempt: Sendable {
        case noEligibleFence
        case awaitingCleanup(FilesystemRetirementFencePendingLifetime)
        case installed(
            FilesystemRetirementFenceInstalledLifetime,
            AdmissionWakeDirective
        )
        case contracted(
            FilesystemRetirementFencePendingLifetime,
            FixedFilesystemRecoveryEvidenceSnapshot,
            AdmissionWakeDirective
        )
    }

    private enum RetirementFencePreparation: Sendable {
        case completed(FilesystemObservationRetirementFenceRequestResult)
        case prepared(FilesystemRetirementFencePendingLifetime)
    }

    private struct IssuedNativeGenerationPortCustody: Sendable {
        let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
        let callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity
        let synchronization: any FilesystemObservationCallbackSynchronization
        let lifecycleOperation: FilesystemObservationNativeLifecycleOperation
        let nativeOwner: DarwinFSEventRegistrationNativeOwner
    }

    private enum NativeGenerationPortCustody: Sendable {
        case vacant
        case issued(IssuedNativeGenerationPortCustody)
    }

    private enum FleetShutdownProgressTurnState: Sendable {
        case idle
        case inFlight
    }

    private enum FleetShutdownProgressPlan: Sendable {
        case completed(
            FilesystemObservationFleetShutdownProgressResult,
            AdmissionWakeDirective
        )
        case advanceNativeOwner(DarwinFSEventRegistrationNativeOwner)
        case applyNativeCompletion(DarwinFSEventRegistrationNativeOwner)
        case performGenericCleanup
        case retainFenceRetirementPermit(FilesystemObservationSlotRetirementReceipt)
        case finalizeNativeContext(
            DarwinFSEventRegistrationNativeOwner,
            FilesystemObservationNativeRetirementPermit
        )
        case applyContextReleaseAcknowledgement(
            FilesystemObservationContextReleaseAcknowledgement
        )

        var isCompleted: Bool {
            guard case .completed = self else { return false }
            return true
        }
    }

    private struct PendingRetirementFenceReadyQueue: Sendable {
        private enum Endpoint: Sendable {
            case boundary
            case slot(Int)
        }

        private enum Link: Sendable {
            case detached
            case linked(previous: Endpoint, next: Endpoint)
        }

        enum AppendResult: Sendable {
            case appended
            case alreadyPresent
            case undeclaredPhysicalSlot
        }

        enum PopResult: Sendable {
            case physicalSlot(FilesystemObservationPhysicalSlotID)
            case empty
        }

        private let physicalSlotIDs: [FilesystemObservationPhysicalSlotID]
        private let slotIndexByPhysicalSlotID: [FilesystemObservationPhysicalSlotID: Int]
        private var links: [Link]
        private var head = Endpoint.boundary
        private var tail = Endpoint.boundary
        private(set) var count = 0

        init(physicalSlotIDs: [FilesystemObservationPhysicalSlotID]) {
            self.physicalSlotIDs = physicalSlotIDs
            slotIndexByPhysicalSlotID = Dictionary(
                uniqueKeysWithValues: physicalSlotIDs.enumerated().map { ($0.element, $0.offset) }
            )
            links = Array(repeating: .detached, count: physicalSlotIDs.count)
        }

        mutating func append(
            _ physicalSlotID: FilesystemObservationPhysicalSlotID
        ) -> AppendResult {
            guard let slotIndex = slotIndexByPhysicalSlotID[physicalSlotID] else {
                return .undeclaredPhysicalSlot
            }
            guard case .detached = links[slotIndex] else {
                return .alreadyPresent
            }
            switch tail {
            case .boundary:
                head = .slot(slotIndex)
                tail = .slot(slotIndex)
                links[slotIndex] = .linked(previous: .boundary, next: .boundary)
            case .slot(let previousTailIndex):
                guard
                    case .linked(let previous, .boundary) = links[previousTailIndex]
                else {
                    preconditionFailure("Pending fence queue tail must terminate at boundary")
                }
                links[previousTailIndex] = .linked(
                    previous: previous,
                    next: .slot(slotIndex)
                )
                links[slotIndex] = .linked(
                    previous: .slot(previousTailIndex),
                    next: .boundary
                )
                tail = .slot(slotIndex)
            }
            count += 1
            return .appended
        }

        func first() -> PopResult {
            guard case .slot(let firstIndex) = head else { return .empty }
            return .physicalSlot(physicalSlotIDs[firstIndex])
        }

        var elementsInFIFOOrder: [FilesystemObservationPhysicalSlotID] {
            var elements: [FilesystemObservationPhysicalSlotID] = []
            elements.reserveCapacity(count)
            var cursor = head
            while case .slot(let slotIndex) = cursor {
                elements.append(physicalSlotIDs[slotIndex])
                guard case .linked(_, let next) = links[slotIndex] else {
                    preconditionFailure("Pending fence queue traversal reached a detached slot")
                }
                cursor = next
            }
            precondition(elements.count == count, "Pending fence queue count drifted")
            return elements
        }

        mutating func popFirst() -> PopResult {
            guard case .slot(let firstIndex) = head else { return .empty }
            guard case .linked(.boundary, let next) = links[firstIndex] else {
                preconditionFailure("Pending fence queue head must begin at boundary")
            }
            links[firstIndex] = .detached
            switch next {
            case .boundary:
                head = .boundary
                tail = .boundary
            case .slot(let nextIndex):
                guard case .linked(_, let nextAfterHead) = links[nextIndex] else {
                    preconditionFailure("Pending fence queue successor must remain linked")
                }
                links[nextIndex] = .linked(previous: .boundary, next: nextAfterHead)
                head = .slot(nextIndex)
            }
            count -= 1
            return .physicalSlot(physicalSlotIDs[firstIndex])
        }
    }

    private struct State: Sendable {
        enum ConfigurationIntentReplayCustody: Sendable {
            case vacant
            case retained(
                batch: FilesystemSourceConfigurationIntentBatch,
                result: FilesystemConfigurationIntentBatchAdmissionResult
            )
        }

        var lifecycle: Lifecycle
        var fleetIngressLifecycle: FilesystemObservationFleetIngressLifecycle
        var fleetOrdinaryAdmissionDisposition: FilesystemFleetOrdinaryAdmissionDisposition
        var activeLease: ActiveLeaseCustody
        var pendingWholeLeaseCompletion: PendingWholeLeaseCompletionCustody
        var retryEvidenceByPhysicalSlotID: [FilesystemObservationPhysicalSlotID: RetryEvidenceCustody]
        var nativeGenerationPortsByPhysicalSlotID: [FilesystemObservationPhysicalSlotID: NativeGenerationPortCustody]
        var pendingRetirementFenceReadyQueue: PendingRetirementFenceReadyQueue
        var configurationIntentReplayCustody: ConfigurationIntentReplayCustody
        var fleetShutdownProgressTurn: FleetShutdownProgressTurnState

        init(
            physicalSlotIDs: [FilesystemObservationPhysicalSlotID],
            fleetOrdinaryAdmissionDisposition:
                FilesystemFleetOrdinaryAdmissionDisposition
        ) {
            lifecycle = .open
            fleetIngressLifecycle = .accepting
            self.fleetOrdinaryAdmissionDisposition = fleetOrdinaryAdmissionDisposition
            activeLease = .vacant
            pendingWholeLeaseCompletion = .vacant
            retryEvidenceByPhysicalSlotID = Dictionary(
                uniqueKeysWithValues: physicalSlotIDs.map { ($0, .vacant) }
            )
            nativeGenerationPortsByPhysicalSlotID = Dictionary(
                uniqueKeysWithValues: physicalSlotIDs.map { ($0, .vacant) }
            )
            pendingRetirementFenceReadyQueue = PendingRetirementFenceReadyQueue(
                physicalSlotIDs: physicalSlotIDs
            )
            configurationIntentReplayCustody = .vacant
            fleetShutdownProgressTurn = .idle
        }
    }

    private let generation: AdmissionGeneration
    private let slotRegistry: FilesystemObservationSlotRegistry
    private let gatherMailbox:
        BoundedGatherMailbox<
            FilesystemObservationPhysicalSlotID,
            FilesystemObservationMailboxContribution
        >
    private let recoveryRegister: FixedFilesystemRecoveryEvidenceRegister
    private let doorbell = AdmissionDoorbell()
    private let lock: OSAllocatedUnfairLock<State>

    init(
        generation: AdmissionGeneration,
        maximumSimultaneousSourceCount: Int,
        replacementReserveSlotCount: Int,
        limits: GatherMailboxLimits,
        recoveryAuthoritySeed: FilesystemObservationRecoveryAuthoritySeed = .initial
    ) throws {
        let slotRegistry = try FilesystemObservationSlotRegistry(
            maximumSimultaneousSourceCount: maximumSimultaneousSourceCount,
            replacementReserveSlotCount: replacementReserveSlotCount
        )
        guard
            BoundedGatherMailbox<
                FilesystemObservationPhysicalSlotID,
                FilesystemObservationMailboxContribution
            >
            .isConfigurationValid(
                declaredKeyCount: slotRegistry.physicalSlotCount,
                limits: limits
            )
        else {
            throw FilesystemObservationMailboxConfigurationError.invalidGatherLimits
        }

        recoveryRegister = FixedFilesystemRecoveryEvidenceRegister(slotRegistry: slotRegistry)
        gatherMailbox = BoundedGatherMailbox(
            generation: generation,
            declaredKeys: Set(slotRegistry.physicalSlotIDs),
            limits: limits,
            clock: ContinuousClock(),
            authoritySeed: GatherMailboxAuthoritySeed(
                recoveryStampsByKey: FilesystemObservationMailboxProjection.recoveryStampsByPhysicalSlotID(
                    recoveryAuthoritySeed,
                    physicalSlotIDs: slotRegistry.physicalSlotIDs
                )
            )
        )
        self.generation = generation
        self.slotRegistry = slotRegistry
        lock = OSAllocatedUnfairLock(
            initialState: State(
                physicalSlotIDs: slotRegistry.physicalSlotIDs,
                fleetOrdinaryAdmissionDisposition: .ordinary
            )
        )
    }

    var fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity {
        slotRegistry.fleetMailboxIdentity
    }

    var physicalSlotIDs: [FilesystemObservationPhysicalSlotID] {
        slotRegistry.physicalSlotIDs
    }

    func freezeFleetIngress(
        for shutdownIdentity: FilesystemObservationFleetShutdownIdentity
    ) -> FilesystemObservationFleetIngressFreezeResult {
        lock.withLock { state in
            guard state.lifecycle == .open else {
                return .terminationAlreadyAdvanced(lifecycleSnapshot(state.lifecycle))
            }
            switch state.fleetIngressLifecycle {
            case .accepting:
                state.fleetIngressLifecycle = .shutdownFrozen(shutdownIdentity)
                return .applied(shutdownIdentity)
            case .shutdownFrozen(let retainedIdentity):
                guard retainedIdentity == shutdownIdentity else {
                    return .shutdownIdentityMismatch(
                        expected: retainedIdentity,
                        presented: shutdownIdentity
                    )
                }
                return .alreadyApplied(retainedIdentity)
            }
        }
    }

    func freezeFleetIngressAndSnapshot(
        for shutdownIdentity: FilesystemObservationFleetShutdownIdentity
    ) -> FilesystemObservationFleetIngressFreezeAndSnapshotResult {
        lock.withLock { state in
            guard state.lifecycle == .open else {
                return .terminationAlreadyAdvanced(lifecycleSnapshot(state.lifecycle))
            }
            switch state.fleetIngressLifecycle {
            case .accepting:
                state.fleetIngressLifecycle = .shutdownFrozen(shutdownIdentity)
                return .applied(
                    makeFleetShutdownDebtSnapshotLocked(
                        shutdownIdentity: shutdownIdentity,
                        state: state
                    )
                )
            case .shutdownFrozen(let retainedIdentity):
                guard retainedIdentity == shutdownIdentity else {
                    return .shutdownIdentityMismatch(
                        expected: retainedIdentity,
                        presented: shutdownIdentity
                    )
                }
                return .alreadyApplied(
                    makeFleetShutdownDebtSnapshotLocked(
                        shutdownIdentity: retainedIdentity,
                        state: state
                    )
                )
            }
        }
    }

    func fleetShutdownDebtSnapshot(
        for shutdownIdentity: FilesystemObservationFleetShutdownIdentity
    ) -> FilesystemObservationFleetIngressFreezeAndSnapshotResult {
        lock.withLock { state in
            guard state.lifecycle == .open else {
                return .terminationAlreadyAdvanced(lifecycleSnapshot(state.lifecycle))
            }
            guard case .shutdownFrozen(let retainedIdentity) = state.fleetIngressLifecycle else {
                preconditionFailure("Fleet shutdown debt requires an atomic ingress freeze")
            }
            guard retainedIdentity == shutdownIdentity else {
                return .shutdownIdentityMismatch(
                    expected: retainedIdentity,
                    presented: shutdownIdentity
                )
            }
            return .alreadyApplied(
                makeFleetShutdownDebtSnapshotLocked(
                    shutdownIdentity: retainedIdentity,
                    state: state
                )
            )
        }
    }

    func advanceFleetShutdownOneTurn(
        for shutdownIdentity: FilesystemObservationFleetShutdownIdentity,
        contextFinalizer: any DarwinFSEventCallbackContextFinalizer
    ) async -> FilesystemObservationFleetShutdownProgressResult {
        let plan = lock.withLock { state in
            claimFleetShutdownProgressPlanLocked(
                shutdownIdentity: shutdownIdentity,
                state: &state
            )
        }
        guard !plan.isCompleted else {
            return applyCompletedFleetShutdownProgressPlan(plan)
        }
        defer {
            lock.withLock { state in
                state.fleetShutdownProgressTurn = .idle
            }
        }

        switch plan {
        case .completed:
            preconditionFailure("completed fleet progress plan was handled before execution")
        case .advanceNativeOwner(let nativeOwner):
            let result = await nativeOwner.advanceFleetShutdown()
            return fleetShutdownProgressResult(
                .nativeOwnerAdvanced(result),
                shutdownIdentity: shutdownIdentity
            )
        case .applyNativeCompletion(let nativeOwner):
            let result = await nativeOwner.advanceFleetShutdown()
            return applyRetainedNativeShutdownCompletion(
                result,
                shutdownIdentity: shutdownIdentity
            )
        case .performGenericCleanup:
            guard case .performed = performFleetShutdownGenericCleanupTurn() else {
                return fleetShutdownNoProgressResult(for: shutdownIdentity)
            }
            return fleetShutdownProgressResult(
                .genericCleanupPerformed,
                shutdownIdentity: shutdownIdentity
            )
        case .retainFenceRetirementPermit(let receipt):
            guard case .issued = fenceBackedRetirementPermit(for: receipt) else {
                return fleetShutdownNoProgressResult(for: shutdownIdentity)
            }
            return fleetShutdownProgressResult(
                .finalRetirementPermitRetained(receipt.binding),
                shutdownIdentity: shutdownIdentity
            )
        case .finalizeNativeContext(let nativeOwner, let permit):
            let result = nativeOwner.finalizeNativeLifetime(
                using: permit,
                contextFinalizer: contextFinalizer
            )
            guard case .finalized(let acknowledgement) = result else {
                return fleetShutdownNoProgressResult(for: shutdownIdentity)
            }
            return fleetShutdownProgressResult(
                .nativeContextFinalized(
                    binding: acknowledgement.binding,
                    releaseAuthority: acknowledgement.releaseAuthority
                ),
                shutdownIdentity: shutdownIdentity
            )
        case .applyContextReleaseAcknowledgement(let acknowledgement):
            guard
                case .applied = applyContextReleaseAcknowledgement(
                    acknowledgement,
                    attemptsPromotedFence: false
                )
            else {
                return fleetShutdownNoProgressResult(for: shutdownIdentity)
            }
            return fleetShutdownProgressResult(
                .contextReleaseAcknowledgementApplied(
                    binding: acknowledgement.binding,
                    releaseAuthority: acknowledgement.releaseAuthority
                ),
                shutdownIdentity: shutdownIdentity
            )
        }
    }

    private func claimFleetShutdownProgressPlanLocked(
        shutdownIdentity: FilesystemObservationFleetShutdownIdentity,
        state: inout State
    ) -> FleetShutdownProgressPlan {
        guard state.lifecycle == .open else {
            return .completed(
                .terminationAlreadyAdvanced(lifecycleSnapshot(state.lifecycle)),
                .noWake
            )
        }
        guard case .shutdownFrozen(let retainedIdentity) = state.fleetIngressLifecycle else {
            return .completed(.shutdownNotFrozen, .noWake)
        }
        guard retainedIdentity == shutdownIdentity else {
            return .completed(
                .shutdownIdentityMismatch(
                    expected: retainedIdentity,
                    presented: shutdownIdentity
                ),
                .noWake
            )
        }
        guard case .idle = state.fleetShutdownProgressTurn else {
            return .completed(
                .noProgress(
                    makeFleetShutdownDebtSnapshotLocked(
                        shutdownIdentity: retainedIdentity,
                        state: state
                    )
                ),
                .noWake
            )
        }
        state.fleetShutdownProgressTurn = .inFlight

        if let progress = withdrawOneDesiredCustodyLocked(
            shutdownIdentity: shutdownIdentity,
            state: &state
        ) {
            return .completed(progress, .noWake)
        }

        if let nativeProgressPlan = claimNativeFleetShutdownProgressPlanLocked(state: state) {
            return nativeProgressPlan
        }

        let genericDebt = gatherMailbox.lifecyclePort.shutdownDebtSnapshot
        if FilesystemObservationFleetShutdownProgressPlanner.hasQueuedGenericCleanup(
            genericDebt
        ) {
            return .performGenericCleanup
        }

        switch attemptOnePendingRetirementFenceLocked(state: &state) {
        case .installed(let installed, let wake):
            return .completed(
                makeFleetShutdownProgressResultLocked(
                    .retirementFenceAdvanced(installed.binding.physicalSlotID),
                    shutdownIdentity: shutdownIdentity,
                    state: state
                ),
                wake
            )
        case .contracted(let pending, _, let wake):
            return .completed(
                makeFleetShutdownProgressResultLocked(
                    .retirementFenceAdvanced(pending.binding.physicalSlotID),
                    shutdownIdentity: shutdownIdentity,
                    state: state
                ),
                wake
            )
        case .noEligibleFence, .awaitingCleanup:
            break
        }

        if let finalizationPlan = claimNativeFleetShutdownFinalizationPlanLocked(state: state) {
            return finalizationPlan
        }

        state.fleetShutdownProgressTurn = .idle
        return .completed(
            .noProgress(
                makeFleetShutdownDebtSnapshotLocked(
                    shutdownIdentity: shutdownIdentity,
                    state: state
                )
            ),
            .noWake
        )
    }

    private func claimNativeFleetShutdownProgressPlanLocked(
        state: State
    ) -> FleetShutdownProgressPlan? {
        for physicalSlotID in slotRegistry.physicalSlotIDs {
            guard
                case .issued(let custody) =
                    state.nativeGenerationPortsByPhysicalSlotID[physicalSlotID]
            else {
                continue
            }
            switch custody.nativeOwner.fleetShutdownProjection.advancePhase {
            case .available, .inFlight:
                return .advanceNativeOwner(custody.nativeOwner)
            case .completed:
                switch slotRegistry.read.state(of: physicalSlotID) {
                case .starting, .closingAwaitingCallbackLeaseDrain,
                    .retiringUnpublishedGeneration:
                    return .applyNativeCompletion(custody.nativeOwner)
                case .undeclaredPhysicalSlot, .vacant, .selected, .accepting,
                    .closingAwaitingPredecessor, .retirementFencePending,
                    .retirementFenceInstalled, .retirementFenceTransferredAwaitingCleanup,
                    .retiredAwaitingContextRelease:
                    break
                }
            }
        }
        return nil
    }

    private func claimNativeFleetShutdownFinalizationPlanLocked(
        state: State
    ) -> FleetShutdownProgressPlan? {
        for physicalSlotID in slotRegistry.physicalSlotIDs {
            guard
                case .issued(let custody) =
                    state.nativeGenerationPortsByPhysicalSlotID[physicalSlotID],
                case .retiredAwaitingContextRelease(let retiredLifetime) =
                    slotRegistry.read.state(of: physicalSlotID)
            else {
                continue
            }
            switch custody.nativeOwner.fleetShutdownProjection.finalizationPhase {
            case .awaitingMaterialization, .retainedContext:
                guard case .fenceBacked(let fenceLifetime) = retiredLifetime else {
                    continue
                }
                return .retainFenceRetirementPermit(fenceLifetime.receipt)
            case .retirementPermitRetained, .finalizing:
                return .finalizeNativeContext(custody.nativeOwner, retiredLifetime.permit)
            case .finalized:
                guard
                    case .finalized(let acknowledgement) =
                        custody.nativeOwner.nativeFinalizationSnapshot
                else {
                    continue
                }
                return .applyContextReleaseAcknowledgement(acknowledgement)
            }
        }
        return nil
    }

    private func withdrawOneDesiredCustodyLocked(
        shutdownIdentity: FilesystemObservationFleetShutdownIdentity,
        state: inout State
    ) -> FilesystemObservationFleetShutdownProgressResult? {
        let candidates =
            FilesystemObservationFleetShutdownProgressPlanner
            .desiredWithdrawalCandidates(
                from: makeFleetShutdownDebtSnapshotLocked(
                    shutdownIdentity: shutdownIdentity,
                    state: state
                )
            )

        for candidate in candidates {
            switch slotRegistry.withdrawDesiredSource(
                sourceID: candidate.sourceID,
                desiredIdentity: candidate.desiredIdentity
            ) {
            case .withdrewDeferred, .withdrewPendingConfiguration,
                .releasedSelectedReservation, .awaitingAcceptingPublication:
                return makeFleetShutdownProgressResultLocked(
                    .desiredCustodyWithdrawn(candidate),
                    shutdownIdentity: shutdownIdentity,
                    state: state
                )
            case .closeAccepting, .retiringGeneration, .alreadyAbsent,
                .staleDesiredIdentity:
                continue
            }
        }
        return nil
    }

    private func applyRetainedNativeShutdownCompletion(
        _ result: DarwinFSEventNativeOwnerFleetShutdownResult,
        shutdownIdentity: FilesystemObservationFleetShutdownIdentity
    ) -> FilesystemObservationFleetShutdownProgressResult {
        guard case .completed(let completion) = result else {
            return fleetShutdownNoProgressResult(for: shutdownIdentity)
        }
        switch completion {
        case .unpublished(let unpublishedCompletion):
            switch physicalSlotState(
                of: unpublishedCompletion.startingNativeLifetime.binding.physicalSlotID
            ) {
            case .starting:
                guard
                    case .retirementRequired =
                        retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                            unpublishedCompletion.startingNativeLifetime
                        )
                else {
                    return fleetShutdownNoProgressResult(for: shutdownIdentity)
                }
                return fleetShutdownProgressResult(
                    .nativeCompletionApplied(completion.shutdownReference),
                    shutdownIdentity: shutdownIdentity
                )
            case .retiringUnpublishedGeneration(let retiringLifetime):
                guard
                    case .finalized(let finalReceipt) = finalizeUnpublishedNativeGeneration(
                        retiringLifetime,
                        completion: unpublishedCompletion
                    )
                else {
                    return fleetShutdownNoProgressResult(for: shutdownIdentity)
                }
                return fleetShutdownProgressResult(
                    .finalRetirementPermitRetained(finalReceipt.binding),
                    shutdownIdentity: shutdownIdentity
                )
            case .undeclaredPhysicalSlot, .vacant, .selected, .accepting,
                .closingAwaitingCallbackLeaseDrain, .closingAwaitingPredecessor,
                .retirementFencePending, .retirementFenceInstalled,
                .retirementFenceTransferredAwaitingCleanup,
                .retiredAwaitingContextRelease:
                return fleetShutdownNoProgressResult(for: shutdownIdentity)
            }
        case .acceptingGenerationClosed(let receipt):
            switch prepareRetirementFenceForFleetShutdown(receipt) {
            case .awaitingPredecessor, .pending:
                return fleetShutdownProgressResult(
                    .nativeCompletionApplied(completion.shutdownReference),
                    shutdownIdentity: shutdownIdentity
                )
            case .pendingAwaitingCleanup, .pendingAfterContraction, .installed,
                .alreadyAwaitingPredecessor, .alreadyPending, .alreadyInstalled, .retired,
                .foreignFleet, .undeclaredPhysicalSlot, .receiptMismatch,
                .retiringGenerationLimitReached, .invalidSlotState, .closed:
                return fleetShutdownNoProgressResult(for: shutdownIdentity)
            }
        }
    }

    private func fleetShutdownProgressResult(
        _ progress: FilesystemObservationFleetShutdownProgress,
        shutdownIdentity: FilesystemObservationFleetShutdownIdentity
    ) -> FilesystemObservationFleetShutdownProgressResult {
        lock.withLock { state in
            makeFleetShutdownProgressResultLocked(
                progress,
                shutdownIdentity: shutdownIdentity,
                state: state
            )
        }
    }

    private func makeFleetShutdownProgressResultLocked(
        _ progress: FilesystemObservationFleetShutdownProgress,
        shutdownIdentity: FilesystemObservationFleetShutdownIdentity,
        state: State
    ) -> FilesystemObservationFleetShutdownProgressResult {
        .progressed(
            FilesystemObservationFleetShutdownProgressReceipt(
                progress: progress,
                debt: makeFleetShutdownDebtSnapshotLocked(
                    shutdownIdentity: shutdownIdentity,
                    state: state
                )
            )
        )
    }

    private func fleetShutdownNoProgressResult(
        for shutdownIdentity: FilesystemObservationFleetShutdownIdentity
    ) -> FilesystemObservationFleetShutdownProgressResult {
        lock.withLock { state in
            .noProgress(
                makeFleetShutdownDebtSnapshotLocked(
                    shutdownIdentity: shutdownIdentity,
                    state: state
                )
            )
        }
    }

    private func applyCompletedFleetShutdownProgressPlan(
        _ plan: FleetShutdownProgressPlan
    ) -> FilesystemObservationFleetShutdownProgressResult {
        guard case .completed(let result, let wake) = plan else {
            preconditionFailure("only completed fleet progress plans can apply directly")
        }
        doorbell.ownerPort.apply(wake)
        if case .progressed = result {
            lock.withLock { state in
                state.fleetShutdownProgressTurn = .idle
            }
        }
        return result
    }

    func installDesiredConfiguration(
        _ configuration: FilesystemObservationSourceConfiguration,
        acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision
    ) -> FilesystemObservationDesiredUpdateResult {
        lock.withLock { state in
            if case .shutdownFrozen(let shutdownIdentity) = state.fleetIngressLifecycle {
                return .fleetShutdownInProgress(shutdownIdentity)
            }
            return slotRegistry.installDesiredConfiguration(
                configuration,
                acceptedTopologyRevision: acceptedTopologyRevision
            )
        }
    }

    func admitConfigurationIntents(
        _ batch: FilesystemSourceConfigurationIntentBatch
    ) -> FilesystemConfigurationIntentBatchAdmissionResult {
        let plan: FilesystemConfigurationIntentAdmissionPlanner.Plan
        switch FilesystemConfigurationIntentAdmissionPlanner.prepare(batch) {
        case .planned(let preparedPlan):
            plan = preparedPlan
        case .rejected(let rejection):
            return .rejected(rejection)
        }

        return lock.withLock { state in
            if case .shutdownFrozen(let shutdownIdentity) = state.fleetIngressLifecycle {
                return .rejected(.fleetShutdownInProgress(shutdownIdentity))
            }
            switch state.configurationIntentReplayCustody {
            case .vacant:
                break
            case .retained(let retainedBatch, let retainedResult):
                if batch.acceptedTopologyRevision.value
                    < retainedBatch.acceptedTopologyRevision.value
                {
                    return .rejected(
                        .staleAcceptedTopologyRevision(
                            submitted: batch.acceptedTopologyRevision,
                            retained: retainedBatch.acceptedTopologyRevision
                        )
                    )
                }
                if batch.acceptedTopologyRevision == retainedBatch.acceptedTopologyRevision {
                    guard batch == retainedBatch else {
                        return .rejected(
                            .conflictingBatchForAcceptedTopologyRevision(
                                batch.acceptedTopologyRevision
                            )
                        )
                    }
                    return retainedResult
                }
            }

            var admissionsBySourceID: [FilesystemSourceID: FilesystemConfigurationIntentAdmission] = [:]
            admissionsBySourceID.reserveCapacity(plan.orderedIntents.count)

            for orderedIntent in plan.orderedIntents {
                let sourceID = orderedIntent.sourceID
                let admission: FilesystemConfigurationIntentAdmission
                switch orderedIntent.intent {
                case .install(let installationIntent):
                    admission = .installation(
                        slotRegistry.installDesiredConfiguration(
                            installationIntent.desiredConfiguration,
                            acceptedTopologyRevision: batch.acceptedTopologyRevision
                        )
                    )
                case .replace(let replacementIntent):
                    let replacementResult: FilesystemObservationReplacementAdmissionResult
                    switch recoveryRegister.issuePriorContinuityAuthority(
                        for: replacementIntent.exactPriorBinding
                    ) {
                    case .issued(let priorContinuityAuthority):
                        replacementResult =
                            slotRegistry.admitReplacementDesiredConfiguration(
                                replacementIntent.desiredConfiguration,
                                acceptedTopologyRevision: batch.acceptedTopologyRevision,
                                exactPriorBinding: replacementIntent.exactPriorBinding,
                                priorContinuityAuthority: priorContinuityAuthority
                            )
                    case .foreignFleet:
                        replacementResult = .rejected(.priorContinuityForeignFleet)
                    case .undeclaredPhysicalSlot:
                        replacementResult = .rejected(
                            .priorContinuityUndeclaredPhysicalSlot
                        )
                    case .unboundPhysicalSlot:
                        replacementResult = .rejected(.priorContinuityUnboundPhysicalSlot)
                    case .currentBindingMismatch(let currentBinding):
                        replacementResult = .rejected(
                            .priorContinuityCurrentBindingMismatch(currentBinding)
                        )
                    }
                    admission = .replacement(replacementResult)
                case .remove(let removalIntent):
                    admission = .removal(
                        slotRegistry.admitRemoval(
                            of: removalIntent.exactPriorBinding,
                            acceptedTopologyRevision: batch.acceptedTopologyRevision
                        )
                    )
                }
                admissionsBySourceID[sourceID] = admission
            }

            let result: FilesystemConfigurationIntentBatchAdmissionResult = .admitted(
                FilesystemConfigurationIntentBatchAdmission(
                    acceptedTopologyRevision: batch.acceptedTopologyRevision,
                    admissionsBySourceID: admissionsBySourceID
                )
            )
            state.configurationIntentReplayCustody = .retained(
                batch: batch,
                result: result
            )
            return result
        }
    }

    func selectNextDesiredSource() -> FilesystemObservationDesiredSelectionResult {
        lock.withLock { state in
            if case .shutdownFrozen(let shutdownIdentity) = state.fleetIngressLifecycle {
                return .fleetShutdownInProgress(shutdownIdentity)
            }
            return slotRegistry.selectNextDesiredSource()
        }
    }

    func beginNativeLifetime(
        _ reservation: FilesystemObservationSlotReservation
    ) -> FilesystemObservationNativeLifetimeCommitResult {
        lock.withLock { state in
            if case .shutdownFrozen(let shutdownIdentity) = state.fleetIngressLifecycle {
                if case .starting(let startingNativeLifetime) =
                    slotRegistry.read.state(of: reservation.physicalSlotID),
                    startingNativeLifetime.consumedReservation == reservation
                {
                    return .alreadyCommitted(startingNativeLifetime)
                }
                return .fleetShutdownInProgress(shutdownIdentity)
            }
            let result = slotRegistry.beginNativeLifetime(reservation)
            switch result {
            case .committed(let startingNativeLifetime),
                .alreadyCommitted(let startingNativeLifetime):
                let bindResult = recoveryRegister.bind(startingNativeLifetime.binding)
                switch bindResult {
                case .boundClear, .alreadyBoundClear, .alreadyBoundRetained:
                    break
                case .foreignFleet, .undeclaredPhysicalSlot, .currentBindingMismatch:
                    preconditionFailure(
                        "Registry committed a binding rejected by its fixed recovery shell"
                    )
                }
            case .foreignFleet, .undeclaredPhysicalSlot, .reservationNoLongerCurrent,
                .staleReservation, .deferredToConfigurationCurrentness,
                .fleetShutdownInProgress:
                break
            }
            return result
        }
    }

    func retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
        _ failedStartingNativeLifetime: FilesystemObservationStartingNativeLifetime
    ) -> FilesystemObservationNativeLifetimeFailureResult {
        lock.withLock { _ in
            slotRegistry.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                failedStartingNativeLifetime
            )
        }
    }

    func finalizeUnpublishedNativeGeneration(
        _ retiringLifetime: FilesystemObservationRetiringUnpublishedNativeLifetime,
        completion: DarwinFSEventUnpublishedNativeCompletion
    ) -> FilesystemObservationUnpublishedFinalReceiptResult {
        lock.withLock { state in
            let startingNativeLifetime = retiringLifetime.startingNativeLifetime
            let binding = startingNativeLifetime.binding
            guard bindingLocalTransferDebtIsClear(for: binding, state: state) else {
                return .bindingLocalDebtRetained
            }
            guard
                let portCustody = state.nativeGenerationPortsByPhysicalSlotID[
                    binding.physicalSlotID
                ],
                case .issued(let issuedCustody) = portCustody,
                issuedCustody.startingNativeLifetime == startingNativeLifetime,
                issuedCustody.nativeOwner.matchesUnpublishedCompletion(completion)
            else {
                return .completionMismatch
            }
            let result = slotRegistry.finalizeUnpublishedNativeGeneration(
                retiringLifetime,
                completion: completion
            )
            let finalReceipt: FilesystemObservationUnpublishedFinalReceipt
            switch result {
            case .finalized(let receipt), .alreadyFinalized(let receipt):
                finalReceipt = receipt
            case .foreignFleet, .undeclaredPhysicalSlot, .bindingMismatch,
                .completionMismatch, .bindingLocalDebtRetained, .awaitingPredecessor,
                .invalidSlotState:
                return result
            }
            switch issuedCustody.nativeOwner.retainRetirementPermit(
                .unpublished(finalReceipt)
            ) {
            case .retained, .alreadyRetained:
                return result
            case .bindingMismatch, .permitLineageMismatch, .nativeLifetimeNotFinal:
                preconditionFailure(
                    "Exact unpublished final receipt must bind to its persistent native owner"
                )
            }
        }
    }

    func fenceBackedRetirementPermit(
        for receipt: FilesystemObservationSlotRetirementReceipt
    ) -> FilesystemFenceRetirementPermitResult {
        lock.withLock { state in
            let result = slotRegistry.fenceBackedRetirementPermit(for: receipt)
            let permit: FilesystemObservationNativeRetirementPermit
            switch result {
            case .issued(let issuedPermit), .alreadyIssued(let issuedPermit):
                permit = issuedPermit
            case .foreignFleet, .undeclaredPhysicalSlot, .receiptMismatch,
                .invalidSlotState:
                return result
            }
            let binding = permit.binding
            guard
                let portCustody = state.nativeGenerationPortsByPhysicalSlotID[
                    binding.physicalSlotID
                ],
                case .issued(let issuedCustody) = portCustody,
                issuedCustody.startingNativeLifetime.binding == binding
            else {
                return .receiptMismatch
            }
            switch issuedCustody.nativeOwner.retainRetirementPermit(permit) {
            case .retained, .alreadyRetained:
                return result
            case .bindingMismatch, .permitLineageMismatch, .nativeLifetimeNotFinal:
                preconditionFailure(
                    "Exact fence-backed permit must bind to its persistent native owner"
                )
            }
        }
    }

    func applyContextReleaseAcknowledgement(
        _ acknowledgement: FilesystemObservationContextReleaseAcknowledgement
    ) -> FilesystemObservationContextReleaseApplyResult {
        applyContextReleaseAcknowledgement(
            acknowledgement,
            attemptsPromotedFence: true
        )
    }

    private func applyContextReleaseAcknowledgement(
        _ acknowledgement: FilesystemObservationContextReleaseAcknowledgement,
        attemptsPromotedFence: Bool
    ) -> FilesystemObservationContextReleaseApplyResult {
        let lockedResult:
            (
                FilesystemObservationContextReleaseApplyResult,
                AdmissionWakeDirective
            ) = lock.withLock { state in
                let binding = acknowledgement.binding
                switch slotRegistry.read.state(of: binding.physicalSlotID) {
                case .vacant, .selected, .starting, .accepting,
                    .closingAwaitingCallbackLeaseDrain, .closingAwaitingPredecessor,
                    .retirementFencePending, .retirementFenceInstalled,
                    .retirementFenceTransferredAwaitingCleanup,
                    .retiringUnpublishedGeneration, .undeclaredPhysicalSlot:
                    return (
                        slotRegistry.applyContextReleaseAcknowledgement(acknowledgement),
                        .noWake
                    )
                case .retiredAwaitingContextRelease:
                    break
                }
                guard
                    let portCustody = state.nativeGenerationPortsByPhysicalSlotID[
                        binding.physicalSlotID
                    ]
                else {
                    return (.undeclaredPhysicalSlot, .noWake)
                }
                guard case .issued(let issuedCustody) = portCustody else {
                    return (.staleBinding, .noWake)
                }
                guard issuedCustody.startingNativeLifetime.binding == binding else {
                    return (.bindingMismatch, .noWake)
                }
                guard
                    case .finalized(let retainedAcknowledgement) =
                        issuedCustody.nativeOwner.nativeFinalizationSnapshot
                else {
                    return (.releaseAuthorityMismatch, .noWake)
                }
                guard retainedAcknowledgement.permit == acknowledgement.permit else {
                    return (
                        filesystemObservationContextReleasePermitMismatch(
                            expected: retainedAcknowledgement.permit,
                            presented: acknowledgement.permit
                        ),
                        .noWake
                    )
                }
                guard retainedAcknowledgement.releaseAuthority == acknowledgement.releaseAuthority,
                    retainedAcknowledgement == acknowledgement
                else {
                    return (.releaseAuthorityMismatch, .noWake)
                }
                guard
                    case .boundClear(let recoveryBinding) = recoveryRegister.state(
                        of: binding.physicalSlotID
                    ),
                    recoveryBinding == binding
                else {
                    return (.bindingLocalDebtRetained, .noWake)
                }
                let result = slotRegistry.applyContextReleaseAcknowledgement(
                    acknowledgement
                )
                guard case .applied(let application) = result else {
                    return (result, .noWake)
                }
                guard case .retired(let retiredBinding) = recoveryRegister.retire(binding),
                    retiredBinding == binding
                else {
                    preconditionFailure(
                        "Context release preflight must make exact recovery retirement infallible"
                    )
                }
                state.nativeGenerationPortsByPhysicalSlotID[binding.physicalSlotID] = .vacant
                switch application.successorDisposition {
                case .none:
                    return (result, .noWake)
                case .promoted(let pendingLifetime):
                    switch state.pendingRetirementFenceReadyQueue.append(
                        pendingLifetime.binding.physicalSlotID
                    ) {
                    case .appended, .alreadyPresent:
                        break
                    case .undeclaredPhysicalSlot:
                        preconditionFailure("Promoted successor must own a declared physical slot")
                    }
                    guard attemptsPromotedFence else {
                        return (result, .noWake)
                    }
                    switch attemptOnePendingRetirementFenceLocked(state: &state) {
                    case .installed(_, let wake), .contracted(_, _, let wake):
                        return (result, wake)
                    case .noEligibleFence, .awaitingCleanup:
                        return (result, .noWake)
                    }
                }
            }
        doorbell.ownerPort.apply(lockedResult.1)
        return lockedResult.0
    }

    func nativeGenerationPorts(
        for startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        retaining mailboxLifetimeOwner: FilesystemObservationMailbox,
        synchronization: any FilesystemObservationCallbackSynchronization =
            ImmediateFilesystemObservationCallbackSynchronization()
    ) -> FilesystemObservationNativeGenerationPortCreationResult {
        lock.withLock { state in
            makeNativeGenerationPortsLocked(
                for: startingNativeLifetime,
                retaining: mailboxLifetimeOwner,
                synchronization: synchronization,
                state: &state
            )
        }
    }

    func physicalSlotState(
        of physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FilesystemObservationPhysicalSlotState {
        lock.withLock { _ in
            slotRegistry.read.state(of: physicalSlotID)
        }
    }

    fileprivate func publishAcceptingNativeLifetime(
        _ startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity
    ) -> FilesystemObservationAcceptingPublicationResult {
        lock.withLock { _ in
            slotRegistry.publishAcceptingNativeLifetime(
                startingNativeLifetime,
                callbackAdmissionPortIdentity: callbackAdmissionPortIdentity
            )
        }
    }

    fileprivate func beginClosingAwaitingCallbackLeaseDrain(
        _ acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
    ) -> FilesystemObservationCallbackLeaseDrainClosingResult {
        lock.withLock { _ in
            slotRegistry.beginClosingAwaitingCallbackLeaseDrain(
                acceptingNativeLifetime
            )
        }
    }

    func requestRetirementFence(
        _ receipt: DarwinFSEventRegistrationLeaseDrainReceipt
    ) -> FilesystemObservationRetirementFenceRequestResult {
        let lockedResult:
            (
                FilesystemObservationRetirementFenceRequestResult,
                AdmissionWakeDirective
            ) = lock.withLock { state in
                switch prepareRetirementFenceLocked(receipt, state: &state) {
                case .completed(let result):
                    return (result, .noWake)
                case .prepared(let lifetime):
                    switch attemptOnePendingRetirementFenceLocked(state: &state) {
                    case .noEligibleFence:
                        return (.pending(lifetime), .noWake)
                    case .awaitingCleanup:
                        return (.pendingAwaitingCleanup(lifetime), .noWake)
                    case .installed(let installed, let wake):
                        guard installed.fence == lifetime.fence else {
                            return (.pending(lifetime), wake)
                        }
                        return (.installed(installed), wake)
                    case .contracted(let contracted, let evidence, let wake):
                        guard contracted.fence == lifetime.fence else {
                            return (.pending(lifetime), wake)
                        }
                        return (.pendingAfterContraction(contracted, evidence), wake)
                    }
                }
            }
        doorbell.ownerPort.apply(lockedResult.1)
        return lockedResult.0
    }

    private func prepareRetirementFenceForFleetShutdown(
        _ receipt: DarwinFSEventRegistrationLeaseDrainReceipt
    ) -> FilesystemObservationRetirementFenceRequestResult {
        lock.withLock { state in
            switch prepareRetirementFenceLocked(receipt, state: &state) {
            case .completed(let result):
                return result
            case .prepared(let lifetime):
                return .pending(lifetime)
            }
        }
    }

    private func prepareRetirementFenceLocked(
        _ receipt: DarwinFSEventRegistrationLeaseDrainReceipt,
        state: inout State
    ) -> RetirementFencePreparation {
        guard state.lifecycle == .open else {
            return .completed(.closed)
        }
        switch slotRegistry.prepareRetirementFence(receipt) {
        case .awaitingPredecessor(let lifetime):
            return .completed(.awaitingPredecessor(lifetime))
        case .alreadyAwaitingPredecessor(let lifetime):
            return .completed(.alreadyAwaitingPredecessor(lifetime))
        case .alreadyInstalled(let lifetime):
            return .completed(.alreadyInstalled(lifetime))
        case .alreadyRetired(let receipt):
            return .completed(.retired(receipt))
        case .foreignFleet:
            return .completed(.foreignFleet)
        case .undeclaredPhysicalSlot:
            return .completed(.undeclaredPhysicalSlot)
        case .receiptMismatch:
            return .completed(.receiptMismatch)
        case .retiringGenerationLimitReached:
            return .completed(.retiringGenerationLimitReached)
        case .invalidSlotState(let slotState):
            return .completed(.invalidSlotState(slotState))
        case .alreadyPending(let lifetime):
            return .completed(.alreadyPending(lifetime))
        case .pending(let lifetime):
            switch state.pendingRetirementFenceReadyQueue.append(
                lifetime.binding.physicalSlotID
            ) {
            case .appended, .alreadyPresent:
                return .prepared(lifetime)
            case .undeclaredPhysicalSlot:
                preconditionFailure("Registry returned an undeclared pending fence slot")
            }
        }
    }

    fileprivate func acceptingNativeLifetimeMismatch(
        for startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    ) -> FilesystemObservationCallbackLeaseDrainClosingResult {
        lock.withLock { _ in
            switch slotRegistry.read.state(of: startingNativeLifetime.binding.physicalSlotID) {
            case .accepting(let acceptingNativeLifetime):
                return .acceptingNativeLifetimeMismatch(acceptingNativeLifetime)
            case .closingAwaitingCallbackLeaseDrain(let closingNativeLifetime):
                return .acceptingNativeLifetimeMismatch(
                    closingNativeLifetime.acceptingNativeLifetime
                )
            case let state:
                return .invalidSlotState(state)
            }
        }
    }

    private func makeNativeGenerationPortsLocked(
        for startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        retaining mailboxLifetimeOwner: FilesystemObservationMailbox,
        synchronization: any FilesystemObservationCallbackSynchronization,
        state: inout State
    ) -> FilesystemObservationNativeGenerationPortCreationResult {
        let binding = startingNativeLifetime.binding
        guard
            let existingCustody =
                state.nativeGenerationPortsByPhysicalSlotID[binding.physicalSlotID]
        else {
            return binding.fleetMailboxIdentity == fleetMailboxIdentity
                ? .undeclaredPhysicalSlot : .foreignFleet
        }
        switch existingCustody {
        case .issued(let issuedCustody):
            return issuedCustody.startingNativeLifetime == startingNativeLifetime
                ? .created(
                    makeNativeGenerationPorts(
                        for: startingNativeLifetime,
                        retaining: mailboxLifetimeOwner,
                        callbackAdmissionPortIdentity: issuedCustody
                            .callbackAdmissionPortIdentity,
                        synchronization: issuedCustody.synchronization,
                        lifecycleOperation: issuedCustody.lifecycleOperation,
                        nativeOwner: issuedCustody.nativeOwner
                    )
                ) : .bindingNotCurrent
        case .vacant:
            break
        }
        switch slotRegistry.read.state(of: binding.physicalSlotID) {
        case .starting(let currentStartingNativeLifetime)
        where currentStartingNativeLifetime == startingNativeLifetime:
            let callbackAdmissionPortIdentity =
                FilesystemObservationCallbackAdmissionPortIdentity(
                    value: UUIDv7.generate()
                )
            let lifecycleOperation = FilesystemObservationNativeLifecycleOperation(
                startingNativeLifetime: startingNativeLifetime,
                callbackAdmissionPortIdentity: callbackAdmissionPortIdentity,
                core: self
            )
            let nativeOwner = DarwinFSEventRegistrationNativeOwner(
                startingNativeLifetime: startingNativeLifetime,
                lifecyclePort: FilesystemObservationNativeLifecyclePort(
                    operation: lifecycleOperation
                )
            )
            let ports = makeNativeGenerationPorts(
                for: startingNativeLifetime,
                retaining: mailboxLifetimeOwner,
                callbackAdmissionPortIdentity: callbackAdmissionPortIdentity,
                synchronization: synchronization,
                lifecycleOperation: lifecycleOperation,
                nativeOwner: nativeOwner
            )
            state.nativeGenerationPortsByPhysicalSlotID[binding.physicalSlotID] =
                .issued(
                    IssuedNativeGenerationPortCustody(
                        startingNativeLifetime: startingNativeLifetime,
                        callbackAdmissionPortIdentity: callbackAdmissionPortIdentity,
                        synchronization: synchronization,
                        lifecycleOperation: lifecycleOperation,
                        nativeOwner: nativeOwner
                    )
                )
            return .created(ports)
        case .undeclaredPhysicalSlot:
            return binding.fleetMailboxIdentity == fleetMailboxIdentity
                ? .undeclaredPhysicalSlot : .foreignFleet
        case .starting, .vacant, .selected, .accepting,
            .closingAwaitingCallbackLeaseDrain, .closingAwaitingPredecessor,
            .retirementFencePending, .retirementFenceInstalled,
            .retirementFenceTransferredAwaitingCleanup, .retiredAwaitingContextRelease,
            .retiringUnpublishedGeneration:
            return binding.fleetMailboxIdentity == fleetMailboxIdentity
                ? .bindingNotCurrent : .foreignFleet
        }
    }

    private func makeNativeGenerationPorts(
        for startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        retaining mailboxLifetimeOwner: FilesystemObservationMailbox,
        callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity,
        synchronization: any FilesystemObservationCallbackSynchronization,
        lifecycleOperation: FilesystemObservationNativeLifecycleOperation,
        nativeOwner: DarwinFSEventRegistrationNativeOwner
    ) -> FilesystemObservationNativeGenerationPorts {
        let leaseAdmissionAuthority = CallbackLeaseAdmissionAuthority(
            binding: startingNativeLifetime.binding
        )
        let callbackAdmissionPort = FilesystemObservationCallbackAdmissionPort(
            identity: callbackAdmissionPortIdentity,
            operation: FilesystemObservationCallbackAdmissionOperation(
                leaseAdmissionAuthority: leaseAdmissionAuthority,
                mailboxLifetimeOwner: mailboxLifetimeOwner,
                core: self,
                synchronization: synchronization
            )
        )
        let lifecyclePort = FilesystemObservationNativeLifecyclePort(
            operation: lifecycleOperation,
            mailboxLifetimeOwner: mailboxLifetimeOwner
        )
        return FilesystemObservationNativeGenerationPorts(
            callbackAdmissionPort: callbackAdmissionPort,
            lifecyclePort: lifecyclePort,
            nativeOwner: nativeOwner
        )
    }

    var actorConsumerPort: FilesystemObservationActorConsumerPort {
        FilesystemObservationActorConsumerPort(
            bind: bindConsumer,
            take: takeDrain,
            acknowledge: acknowledge,
            cleanup: performCleanup,
            preflightWholeLeaseTransfer: preflightWholeLeaseTransfer,
            completeWholeLeaseTransfer: completeWholeLeaseTransfer
        )
    }

    var actorWaiterPort: FilesystemObservationActorWaiterPort {
        let waiter = doorbell.consumerPort
        return FilesystemObservationActorWaiterPort(wait: waiter.nextSignal)
    }

    var lifecyclePort: FilesystemObservationLifecyclePort {
        FilesystemObservationLifecyclePort(
            requestRetirementFence: requestRetirementFence,
            finalizeUnpublishedNativeGeneration: finalizeUnpublishedNativeGeneration,
            fenceBackedRetirementPermit: fenceBackedRetirementPermit,
            applyContextReleaseAcknowledgement: applyContextReleaseAcknowledgement,
            diagnostics: { self.diagnostics }
        )
    }

    private func attemptOnePendingRetirementFenceLocked(
        state: inout State
    ) -> PendingRetirementFenceAttempt {
        guard case .physicalSlot = state.pendingRetirementFenceReadyQueue.first() else {
            return .noEligibleFence
        }
        let diagnostics = gatherMailbox.lifecyclePort.diagnostics
        guard diagnostics.cleanupContributionCount == 0,
            diagnostics.cleanupMetadataEntryCount == 0,
            diagnostics.outstandingCleanupTurnCount == 0
        else {
            return .awaitingCleanup(
                firstPendingRetirementFenceLocked(state: &state)
            )
        }
        guard
            case .physicalSlot(let physicalSlotID) =
                state.pendingRetirementFenceReadyQueue.popFirst()
        else {
            return .noEligibleFence
        }
        guard
            case .pending(let pendingLifetime) =
                slotRegistry.read.pendingRetirementFence(for: physicalSlotID)
        else {
            preconditionFailure("Pending fence ready queue lost registry custody")
        }

        let contributionIdentity = FilesystemObservationContributionIdentity(
            binding: pendingLifetime.binding,
            value: UUIDv7.generate()
        )
        let contribution = FilesystemObservationMailboxContribution.retirementFence(
            identity: contributionIdentity,
            fence: pendingLifetime.fence
        )
        let gatherResult = gatherMailbox.producerPort.offer(
            generation: generation,
            contribution: GatherContribution(
                key: physicalSlotID,
                payload: contribution,
                footprint: GatherFootprint(itemCount: 0, byteCount: 0),
                recoverySignal: .ordinary
            )
        )
        switch gatherResult {
        case .admitted(.retained, let wake),
            .admitted(.retainedWithRecovery, let wake):
            switch slotRegistry.installRetirementFence(
                pendingLifetime,
                contributionIdentity: contributionIdentity
            ) {
            case .installed(let installed), .alreadyInstalled(let installed):
                return .installed(installed, wake)
            case .stalePendingLifetime, .invalidSlotState:
                preconditionFailure("Retained fence contribution lost registry authority")
            }
        case .admitted(.contractedToRecovery(let genericRevision, let cause), let wake):
            if case .recoveryAuthorityExhaustedTransition = cause {
                state.fleetOrdinaryAdmissionDisposition = .fleetAdmissionExhausted(
                    FilesystemObservationFleetAdmissionExhaustionDebt(
                        triggeringBinding: pendingLifetime.binding,
                        terminalGenericRecoveryRevision: genericRevision
                    )
                )
            }
            _ = recoveryRegister.record(
                .retirementFenceAdmissionContraction,
                genericRecoveryRevision: genericRevision,
                for: pendingLifetime.binding
            )
            switch state.pendingRetirementFenceReadyQueue.append(physicalSlotID) {
            case .appended:
                break
            case .alreadyPresent, .undeclaredPhysicalSlot:
                preconditionFailure("Contracted fence must requeue exactly once")
            }
            return .contracted(
                pendingLifetime,
                requiredRecoverySnapshot(for: pendingLifetime.binding),
                wake
            )
        case .undeclaredKey, .invalidFootprint, .closed, .staleGeneration:
            preconditionFailure("Validated pending fence offer violated mailbox configuration")
        }
    }

    private func firstPendingRetirementFenceLocked(
        state: inout State
    ) -> FilesystemRetirementFencePendingLifetime {
        guard
            case .physicalSlot(let physicalSlotID) =
                state.pendingRetirementFenceReadyQueue.first(),
            case .pending(let pendingLifetime) =
                slotRegistry.read.pendingRetirementFence(for: physicalSlotID)
        else {
            preconditionFailure("Cleanup-blocked fence queue must contain pending custody")
        }
        return pendingLifetime
    }

    fileprivate func captureAndOffer(
        for binding: FilesystemObservationSlotBinding,
        preflight: FilesystemObservationCallbackPreflight,
        capture: () -> DarwinFSEventObservationCapture.OfferResult
    ) -> FilesystemObservationCallbackMailboxCaptureResult {
        // Native capture executes synchronously while the lock is held and cannot escape.
        // It may inspect callback-duration native pointers, so it must not be `Sendable`.
        lock.withLockUnchecked { state in
            guard state.lifecycle == .open else {
                return .mailboxRejected(.closed)
            }
            if case .shutdownFrozen(let shutdownIdentity) = state.fleetIngressLifecycle {
                return .mailboxRejected(.fleetShutdownInProgress(shutdownIdentity))
            }
            switch slotRegistry.read.storedBindingCurrentness(of: binding) {
            case .storedCurrent:
                break
            case .undeclaredPhysicalSlot:
                return .mailboxRejected(.undeclaredSlot)
            case .foreignFleet, .vacant, .reservedWithoutBinding, .storedSuperseded:
                return .mailboxRejected(.fenced)
            }
            guard preflight.maximumFootprint.itemCount >= 0,
                preflight.maximumFootprint.byteCount >= 0
            else {
                return .mailboxRejected(.invalidFootprint)
            }
            guard preflight.matchesCaptureConfiguration else {
                return .mailboxRejected(.captureConfigurationMismatch)
            }
            if case .fleetAdmissionExhausted(let exactDebt) =
                state.fleetOrdinaryAdmissionDisposition
            {
                return .mailboxRejected(.fleetAdmissionExhausted(exactDebt))
            }
            switch capture() {
            case .ignoredEmptyCallback:
                return .ignoredEmptyCallback
            case .rejected(let rejection):
                return .captureRejected(rejection)
            case .offer(let offer):
                switch offerValidatedBindingLocked(offer, for: binding, state: &state) {
                case .admitted(let receipt):
                    return .admitted(offer, receipt)
                case .fleetShutdownInProgress(let shutdownIdentity):
                    return .mailboxRejected(.fleetShutdownInProgress(shutdownIdentity))
                case .undeclaredSlot:
                    return .mailboxRejected(.undeclaredSlot)
                case .bindingMismatch:
                    return .mailboxRejected(.fenced)
                case .invalidFootprint:
                    return .mailboxRejected(.invalidFootprint)
                case .fleetOrdinaryAdmissionSealed:
                    guard
                        case .fleetAdmissionExhausted(let exactDebt) =
                            state.fleetOrdinaryAdmissionDisposition
                    else {
                        preconditionFailure("Generic sealed replay lost exact fleet exhaustion debt")
                    }
                    return .mailboxRejected(.fleetAdmissionExhausted(exactDebt))
                case .closed:
                    return .mailboxRejected(.closed)
                }
            }
        }
    }

    fileprivate func applyCallbackWake(
        _ wake: AdmissionWakeDirective
    ) -> FilesystemObservationCallbackWakeApplication {
        guard wake == .scheduleDrain else { return .notRequested }
        doorbell.ownerPort.apply(wake)
        return .applied
    }

    private func offerValidatedBindingLocked(
        _ offer: FilesystemObservationOffer,
        for binding: FilesystemObservationSlotBinding,
        state: inout State
    ) -> FilesystemObservationOfferResult {
        let observation = offer.observation
        guard observation.registration == binding.registration else {
            return .bindingMismatch
        }

        let contribution = FilesystemObservationMailboxContribution.observation(
            identity: FilesystemObservationContributionIdentity(
                binding: binding,
                value: UUIDv7.generate()
            ),
            observation: observation
        )
        let gatherResult = gatherMailbox.producerPort.offer(
            generation: generation,
            contribution: GatherContribution(
                key: binding.physicalSlotID,
                payload: contribution,
                footprint: GatherFootprint(
                    itemCount: observation.records.count,
                    byteCount: observation.copiedUTF8ByteCount
                ),
                recoverySignal: offer.recoverySignal
            )
        )
        if case .admitted(.contractedToRecovery(let genericRevision, let cause), _) = gatherResult {
            switch cause {
            case .recoveryAuthorityExhaustedTransition:
                state.fleetOrdinaryAdmissionDisposition = .fleetAdmissionExhausted(
                    FilesystemObservationFleetAdmissionExhaustionDebt(
                        triggeringBinding: binding,
                        terminalGenericRecoveryRevision: genericRevision
                    )
                )
            case .ordinaryAdmissionAlreadySealed:
                guard
                    case .fleetAdmissionExhausted =
                        state.fleetOrdinaryAdmissionDisposition
                else {
                    preconditionFailure("Generic sealed replay lost exact fleet exhaustion debt")
                }
            case .capacityPressure:
                break
            }
        }
        return mapOfferResult(
            gatherResult,
            binding: binding,
            explicitRecoveryEvidence: offer.explicitRecoveryEvidence
        )
    }

    func bindConsumer() -> AdmissionConsumerBindResult {
        let result = lock.withLock { _ in
            gatherMailbox.consumerPort.bindConsumer()
        }
        doorbell.ownerPort.apply(result.wake)
        return result
    }

    func takeDrain(
        binding: AdmissionConsumerBinding
    ) -> FilesystemObservationTakeDrainResult {
        lock.withLock { state in
            let gatherResult = gatherMailbox.consumerPort.takeDrain(
                binding: binding,
                generation: generation
            )
            return mapTakeResult(gatherResult, state: &state)
        }
    }

    func acknowledge(
        token: AdmissionDrainToken,
        disposition: FilesystemObservationDrainDisposition
    ) -> FilesystemObservationDrainAcknowledgement {
        let result = lock.withLock { state in
            let acknowledgement = acknowledgeLocked(
                token: token,
                disposition: disposition,
                state: &state
            )
            guard acknowledgement.didAdvanceCustody else {
                return acknowledgement
            }
            let fenceWake = retryOnePendingRetirementFenceAfterProgressLocked(
                state: &state
            )
            return acknowledgement.mergingWake(fenceWake)
        }
        doorbell.ownerPort.apply(result.wake)
        return result
    }

    func preflightWholeLeaseTransfer(
        _ lease: FilesystemObservationDrainLease
    ) -> FilesystemObservationWholeLeasePreflightResult {
        lock.withLock { state in
            guard state.lifecycle == .open || state.lifecycle == .sealed else {
                return .rejected(.closed)
            }
            let retainedFingerprint: WholeLeaseFingerprint
            switch state.activeLease {
            case .vacant:
                return .rejected(.invalidToken)
            case .authoritative(let token, let binding, let fingerprint),
                .recovery(let token, let binding, _, let fingerprint):
                guard token == lease.token else { return .rejected(.invalidToken) }
                guard binding == lease.binding else { return .rejected(.bindingMismatch) }
                retainedFingerprint = fingerprint
            }
            let presentedFingerprint = wholeLeaseFingerprint(for: lease.payload)
            guard retainedFingerprint == presentedFingerprint else {
                return .rejected(.malformedRetirementFence)
            }
            switch validateRetirementFence(
                in: presentedFingerprint,
                binding: lease.binding
            ) {
            case .valid:
                break
            case .malformed:
                return .rejected(.malformedRetirementFence)
            case .installedMismatch:
                return .rejected(.installedRetirementFenceMismatch)
            }
            return .authorized(
                FilesystemObservationWholeLeasePreflightReceipt(
                    binding: lease.binding,
                    token: lease.token
                )
            )
        }
    }

    func completeWholeLeaseTransfer(
        authority: FilesystemObservationWholeLeaseTransferAuthority,
        acknowledgement: FilesystemLeaseAcknowledgementReceipt,
        semantic: FilesystemSemanticClearCompletion,
        sourceGate: FilesystemSourceGateTransferClearCompletion,
        registry: FilesystemObservationRegistryCompletionAuthority
    ) -> FilesystemObservationWholeLeaseCompletionResult {
        lock.withLock { state in
            guard acknowledgement.matches(authority) else {
                return .rejected(.acknowledgementMismatch)
            }
            guard
                clearCompletionsMatch(
                    authority: authority,
                    acknowledgement: acknowledgement,
                    semantic: semantic,
                    sourceGate: sourceGate
                )
            else {
                return .rejected(.semanticClearMismatch)
            }
            switch (state.pendingWholeLeaseCompletion, registry) {
            case (
                .ordinary(let pendingAuthority, let pendingAcknowledgement),
                .ordinaryLease
            ):
                guard pendingAuthority == authority else {
                    return .rejected(.authorityMismatch)
                }
                guard pendingAcknowledgement == acknowledgement else {
                    return .rejected(.acknowledgementMismatch)
                }
                state.pendingWholeLeaseCompletion = .vacant
                return .completed(
                    FilesystemObservationWholeLeaseTransferReceipt(
                        binding: authority.binding,
                        outcome: .ordinaryLease
                    )
                )
            case (
                .retirement(
                    let pendingAuthority,
                    let pendingAcknowledgement,
                    let installedLifetime,
                    let disposition
                ),
                .retirement(let retirementAuthority)
            ):
                precondition(
                    bindingLocalTransferDebtIsClear(
                        for: authority.binding,
                        state: state
                    ),
                    "Credentialed final-fence ACK must make binding-local debt clear"
                )
                guard pendingAuthority == authority else {
                    return .rejected(.authorityMismatch)
                }
                guard pendingAcknowledgement == acknowledgement else {
                    return .rejected(.acknowledgementMismatch)
                }
                let transferredLifetime: FilesystemRetirementFenceTransferredLifetime
                switch slotRegistry.transferRetirementFence(
                    installedLifetime,
                    retirementAuthority: retirementAuthority
                ) {
                case .transferred(let lifetime), .alreadyTransferred(let lifetime):
                    transferredLifetime = lifetime
                case .alreadyRetired(let lifetime):
                    state.pendingWholeLeaseCompletion = .vacant
                    guard case .fenceBacked(let fenceBackedLifetime) = lifetime else {
                        return .rejected(.registryTransitionRejected)
                    }
                    return .completed(
                        FilesystemObservationWholeLeaseTransferReceipt(
                            binding: authority.binding,
                            outcome: .retired(fenceBackedLifetime.receipt)
                        )
                    )
                case .authorityMismatch, .invalidSlotState:
                    return .rejected(.registryTransitionRejected)
                }
                switch slotRegistry.completeRetirement(
                    transferredLifetime,
                    disposition: disposition
                ) {
                case .retired(let receipt), .alreadyRetired(let receipt):
                    state.pendingWholeLeaseCompletion = .vacant
                    return .completed(
                        FilesystemObservationWholeLeaseTransferReceipt(
                            binding: authority.binding,
                            outcome: .retired(receipt)
                        )
                    )
                case .authorityMismatch, .invalidSlotState:
                    return .rejected(.registryTransitionRejected)
                }
            case (.vacant, _):
                return .rejected(.noAcknowledgedTransfer)
            case (.ordinary, .retirement), (.retirement, .ordinaryLease):
                return .rejected(.authorityMismatch)
            }
        }
    }

    private func clearCompletionsMatch(
        authority: FilesystemObservationWholeLeaseTransferAuthority,
        acknowledgement: FilesystemLeaseAcknowledgementReceipt,
        semantic: FilesystemSemanticClearCompletion,
        sourceGate: FilesystemSourceGateTransferClearCompletion
    ) -> Bool {
        switch (authority.evidence, semantic, sourceGate) {
        case (
            .contributions,
            .cleared(let semanticReceipt),
            .notRequired(let sourceGateBinding)
        ):
            return semanticReceipt.matches(
                authority: authority,
                acknowledgement: acknowledgement
            )
                && sourceGateBinding == authority.binding
        case (
            .contributionsWithRecovery,
            .cleared(let semanticReceipt),
            .cleared(let sourceGateReceipt)
        ):
            return semanticReceipt.matches(
                authority: authority,
                acknowledgement: acknowledgement
            )
                && sourceGateReceipt.matches(
                    authority: authority,
                    acknowledgement: acknowledgement
                )
        case (
            .recovery,
            .notRequired(let semanticBinding),
            .cleared(let sourceGateReceipt)
        ):
            return semanticBinding == authority.binding
                && sourceGateReceipt.matches(
                    authority: authority,
                    acknowledgement: acknowledgement
                )
        case (.contributions, _, _), (.contributionsWithRecovery, _, _),
            (.recovery, _, _):
            return false
        }
    }

    private func bindingLocalTransferDebtIsClear(
        for binding: FilesystemObservationSlotBinding,
        state: State
    ) -> Bool {
        guard
            let retryCustody = state.retryEvidenceByPhysicalSlotID[binding.physicalSlotID]
        else {
            return false
        }
        guard case .vacant = retryCustody else { return false }
        guard
            case .boundClear(let recoveryBinding) = recoveryRegister.state(
                of: binding.physicalSlotID
            )
        else {
            return false
        }
        return recoveryBinding == binding
    }

    func performCleanup() -> AdmissionCleanupTurnResult {
        let result = lock.withLock { state in
            let cleanupResult = gatherMailbox.consumerPort.performCleanup(
                generation: generation
            )
            guard case .performed(let turn) = cleanupResult else {
                return cleanupResult
            }
            let fenceWake = retryOnePendingRetirementFenceAfterProgressLocked(
                state: &state
            )
            return .performed(
                AdmissionCleanupTurn(
                    release: turn.release,
                    wake: Self.mergeWake(turn.wake, fenceWake)
                )
            )
        }
        if case .performed(let turn) = result {
            doorbell.ownerPort.apply(turn.wake)
        }
        return result
    }

    private func performFleetShutdownGenericCleanupTurn() -> AdmissionCleanupTurnResult {
        let result = lock.withLock { _ in
            gatherMailbox.consumerPort.performCleanup(generation: generation)
        }
        if case .performed(let turn) = result {
            doorbell.ownerPort.apply(turn.wake)
        }
        return result
    }

    private func retryOnePendingRetirementFenceAfterProgressLocked(
        state: inout State
    ) -> AdmissionWakeDirective {
        switch attemptOnePendingRetirementFenceLocked(state: &state) {
        case .installed(_, let wake), .contracted(_, _, let wake):
            return wake
        case .noEligibleFence, .awaitingCleanup:
            return .noWake
        }
    }

    private static func mergeWake(
        _ first: AdmissionWakeDirective,
        _ second: AdmissionWakeDirective
    ) -> AdmissionWakeDirective {
        first == .scheduleDrain || second == .scheduleDrain
            ? .scheduleDrain : .noWake
    }

    func completeFleetShutdown(
        using authority: FilesystemFleetShutdownCompletionAuthority
    ) -> FilesystemFleetShutdownTerminationResult {
        let result = lock.withLock { state -> FilesystemFleetShutdownTerminationResult in
            guard authority.fleetMailboxIdentity == fleetMailboxIdentity else {
                return .fleetMailboxMismatch(
                    expected: fleetMailboxIdentity,
                    presented: authority.fleetMailboxIdentity
                )
            }
            switch state.lifecycle {
            case .open:
                break
            case .finished(let retainedShutdownIdentity):
                guard retainedShutdownIdentity == authority.shutdownIdentity else {
                    return .shutdownIdentityMismatch(
                        expected: retainedShutdownIdentity,
                        presented: authority.shutdownIdentity
                    )
                }
                return .terminationAlreadyAdvanced(.finished)
            case .sealed, .invalidated:
                return .terminationAlreadyAdvanced(lifecycleSnapshot(state.lifecycle))
            }
            guard
                case .shutdownFrozen(let retainedShutdownIdentity) =
                    state.fleetIngressLifecycle
            else {
                return .shutdownNotFrozen
            }
            guard retainedShutdownIdentity == authority.shutdownIdentity else {
                return .shutdownIdentityMismatch(
                    expected: retainedShutdownIdentity,
                    presented: authority.shutdownIdentity
                )
            }
            let freshDebt = makeFleetShutdownDebtSnapshotLocked(
                shutdownIdentity: retainedShutdownIdentity,
                state: state
            )
            guard freshDebt.isQuiescent else {
                return .mailboxDebtChanged(freshDebt)
            }
            let sealResult = gatherMailbox.lifecyclePort.seal(generation: generation)
            guard sealResult == .applied else {
                preconditionFailure("Quiescent filesystem mailbox failed to seal")
            }
            state.lifecycle = .sealed
            let invalidationResult = gatherMailbox.lifecyclePort.invalidate(
                generation: generation
            )
            guard invalidationResult == .applied else {
                preconditionFailure("Quiescent filesystem mailbox failed to invalidate")
            }
            state.lifecycle = .invalidated
            state.lifecycle = .finished(retainedShutdownIdentity)
            return .applied
        }
        if result == .applied {
            doorbell.lifecyclePort.finish()
        }
        return result
    }

    var diagnostics: FilesystemObservationMailboxDiagnostics {
        lock.withLock { state in
            FilesystemObservationMailboxDiagnostics(
                gather: gatherMailbox.lifecyclePort.diagnostics,
                doorbellState: doorbell.lifecyclePort.stateSnapshot,
                lifecycleState: lifecycleSnapshot(state.lifecycle),
                fleetIngressLifecycle: state.fleetIngressLifecycle,
                fleetOrdinaryAdmissionDisposition:
                    state.fleetOrdinaryAdmissionDisposition,
                recoveryEvidenceByPhysicalSlotID: Dictionary(
                    uniqueKeysWithValues: slotRegistry.physicalSlotIDs.map {
                        ($0, recoverySnapshotResult(for: $0))
                    }
                )
            )
        }
    }

    func recoveryEvidence(
        for binding: FilesystemObservationSlotBinding
    ) -> FixedFilesystemRecoveryEvidenceSnapshotResult {
        lock.withLock { _ in
            recoveryRegister.snapshot(for: binding)
        }
    }

    private func mapOfferResult(
        _ result: GatherOfferResult<FilesystemObservationPhysicalSlotID>,
        binding: FilesystemObservationSlotBinding,
        explicitRecoveryEvidence: FilesystemObservationExplicitRecoveryEvidence
    ) -> FilesystemObservationOfferResult {
        switch result {
        case .admitted(.retained, let wake):
            return .admitted(
                FilesystemObservationOfferReceipt(
                    disposition: .retained,
                    wake: wake
                )
            )
        case .admitted(.retainedWithRecovery(let genericRevision), let wake):
            recordExplicitRecoveryEvidence(
                explicitRecoveryEvidence,
                genericRecoveryRevision: genericRevision,
                binding: binding
            )
            return .admitted(
                FilesystemObservationOfferReceipt(
                    disposition: .retainedWithRecovery(
                        requiredRecoverySnapshot(for: binding)
                    ),
                    wake: wake
                )
            )
        case .admitted(
            .contractedToRecovery(_, .ordinaryAdmissionAlreadySealed), _
        ):
            return .fleetOrdinaryAdmissionSealed
        case .admitted(
            .contractedToRecovery(let genericRevision, .capacityPressure), let wake
        ),
            .admitted(
                .contractedToRecovery(
                    let genericRevision,
                    .recoveryAuthorityExhaustedTransition
                ), let wake
            ):
            var recoveryEvidence = FilesystemRecoveryEvidence.callbackAdmissionOverflow
            if case .required(let explicitEvidence) = explicitRecoveryEvidence {
                recoveryEvidence = recoveryEvidence.unioning(explicitEvidence)
            }
            _ = recoveryRegister.record(
                recoveryEvidence,
                genericRecoveryRevision: genericRevision,
                for: binding
            )
            return .admitted(
                FilesystemObservationOfferReceipt(
                    disposition: .contractedToRecovery(
                        requiredRecoverySnapshot(for: binding)
                    ),
                    wake: wake
                )
            )
        case .undeclaredKey:
            return .undeclaredSlot
        case .invalidFootprint:
            return .invalidFootprint
        case .closed:
            return .closed
        case .staleGeneration:
            preconditionFailure("Generation-bound filesystem producer became stale")
        }
    }

    private func recordExplicitRecoveryEvidence(
        _ explicitRecoveryEvidence: FilesystemObservationExplicitRecoveryEvidence,
        genericRecoveryRevision: GatherRecoveryRevision<FilesystemObservationPhysicalSlotID>,
        binding: FilesystemObservationSlotBinding
    ) {
        guard case .required(let evidence) = explicitRecoveryEvidence else { return }
        _ = recoveryRegister.record(
            evidence,
            genericRecoveryRevision: genericRecoveryRevision,
            for: binding
        )
    }

    private func mapTakeResult(
        _ result: GatherTakeDrainResult<
            FilesystemObservationPhysicalSlotID,
            FilesystemObservationMailboxContribution
        >,
        state: inout State
    ) -> FilesystemObservationTakeDrainResult {
        switch result {
        case .lease(let gatherLease):
            return .lease(mapLease(gatherLease, state: &state))
        case .cleanupRequired:
            return .cleanupRequired
        case .empty:
            return .empty
        case .alreadyLeased:
            return .alreadyLeased
        case .closed:
            return .closed
        case .staleGeneration:
            preconditionFailure("Generation-bound filesystem consumer became stale")
        }
    }

    private func mapLease(
        _ gatherLease: GatherDrainLease<
            FilesystemObservationPhysicalSlotID,
            FilesystemObservationMailboxContribution
        >,
        state: inout State
    ) -> FilesystemObservationDrainLease {
        let binding = requiredCurrentBinding(for: gatherLease.key)
        switch state.activeLease {
        case .authoritative(_, let retainedBinding, let fingerprint):
            guard retainedBinding == binding else {
                preconditionFailure("Rebound filesystem lease changed its exact slot binding")
            }
            let lease = FilesystemObservationDrainLease(
                token: gatherLease.token,
                binding: binding,
                payload: FilesystemObservationMailboxProjection.contributionsPayload(
                    from: gatherLease.payload
                )
            )
            guard wholeLeaseFingerprint(for: lease.payload) == fingerprint else {
                preconditionFailure("Retried filesystem lease changed exact payload custody")
            }
            state.activeLease = .authoritative(
                token: gatherLease.token,
                binding: binding,
                fingerprint: fingerprint
            )
            return lease
        case .recovery(_, let retainedBinding, let evidence, let fingerprint):
            guard retainedBinding == binding else {
                preconditionFailure("Rebound recovery lease changed its exact slot binding")
            }
            let lease = FilesystemObservationDrainLease(
                token: gatherLease.token,
                binding: binding,
                payload: FilesystemObservationMailboxProjection.recoveryPayload(
                    from: gatherLease.payload,
                    evidence: evidence
                )
            )
            guard wholeLeaseFingerprint(for: lease.payload) == fingerprint else {
                preconditionFailure("Retried recovery lease changed exact payload custody")
            }
            state.activeLease = .recovery(
                token: gatherLease.token,
                binding: binding,
                evidence: evidence,
                fingerprint: fingerprint
            )
            return lease
        case .vacant:
            return mapNewLease(gatherLease, state: &state)
        }
    }

    private func mapNewLease(
        _ gatherLease: GatherDrainLease<
            FilesystemObservationPhysicalSlotID,
            FilesystemObservationMailboxContribution
        >,
        state: inout State
    ) -> FilesystemObservationDrainLease {
        let binding = requiredCurrentBinding(for: gatherLease.key)
        let payload: FilesystemObservationDrainPayload
        switch gatherLease.payload {
        case .contributions(let contributions):
            payload = .contributions(
                FilesystemObservationMailboxProjection.contributionsPayloads(
                    from: contributions
                )
            )
            state.activeLease = .authoritative(
                token: gatherLease.token,
                binding: binding,
                fingerprint: wholeLeaseFingerprint(for: payload)
            )
        case .contributionsWithRecovery(let contributions, _):
            let evidence = evidenceForLease(
                binding: binding,
                retryEvidenceByPhysicalSlotID: &state.retryEvidenceByPhysicalSlotID
            )
            payload = .contributionsWithRecovery(
                FilesystemObservationMailboxProjection.contributionsPayloads(
                    from: contributions
                ),
                evidence
            )
            state.activeLease = .recovery(
                token: gatherLease.token,
                binding: binding,
                evidence: evidence,
                fingerprint: wholeLeaseFingerprint(for: payload)
            )
        case .recovery:
            let evidence = evidenceForLease(
                binding: binding,
                retryEvidenceByPhysicalSlotID: &state.retryEvidenceByPhysicalSlotID
            )
            payload = .recovery(evidence)
            state.activeLease = .recovery(
                token: gatherLease.token,
                binding: binding,
                evidence: evidence,
                fingerprint: wholeLeaseFingerprint(for: payload)
            )
        }
        return FilesystemObservationDrainLease(
            token: gatherLease.token,
            binding: binding,
            payload: payload
        )
    }

    private func acknowledgeLocked(
        token: AdmissionDrainToken,
        disposition: FilesystemObservationDrainDisposition,
        state: inout State
    ) -> FilesystemObservationDrainAcknowledgement {
        switch (state.activeLease, disposition) {
        case (.authoritative(let activeToken, _, _), .retry) where activeToken == token:
            return completeRetry(token: token, recovery: .authoritative, state: &state)
        case (
            .recovery(let activeToken, _, let evidence, _),
            .retry
        ) where activeToken == token:
            return completeRetry(
                token: token,
                recovery: .retained(evidence),
                state: &state
            )
        case (
            .authoritative(let activeToken, let binding, let fingerprint),
            .transferredAuthoritative(let authority)
        ) where activeToken == token:
            guard
                validateTransferAuthority(
                    authority,
                    token: token,
                    binding: binding,
                    fingerprint: fingerprint,
                    recoveryEvidence: .notRequired
                )
            else {
                return .dispositionMismatch
            }
            return completeAuthoritativeTransfer(
                token: token,
                authority: authority,
                fingerprint: fingerprint,
                state: &state
            )
        case (
            .recovery(
                let activeToken,
                let binding,
                let retainedEvidence,
                let fingerprint
            ),
            .transferredRecovery(let authority, let acceptance)
        ) where activeToken == token:
            guard acceptance.matches(retainedEvidence),
                validateTransferAuthority(
                    authority,
                    token: token,
                    binding: binding,
                    fingerprint: fingerprint,
                    recoveryEvidence: .required(retainedEvidence)
                )
            else {
                return .dispositionMismatch
            }
            return completeRecoveryTransfer(
                token: token,
                authority: authority,
                evidence: retainedEvidence,
                fingerprint: fingerprint,
                state: &state
            )
        case (.vacant, _):
            return .invalidToken
        case (.authoritative(let activeToken, _, _), _) where activeToken == token:
            return .dispositionMismatch
        case (.recovery(let activeToken, _, _, _), _) where activeToken == token:
            return .dispositionMismatch
        case (.authoritative, _), (.recovery, _):
            return .invalidToken
        }
    }

    private enum RetirementFenceValidation {
        case valid
        case malformed
        case installedMismatch
    }

    private enum TransferRecoveryEvidence {
        case notRequired
        case required(FixedFilesystemRecoveryEvidenceSnapshot)
    }

    private func validateTransferAuthority(
        _ authority: FilesystemObservationWholeLeaseTransferAuthority,
        token: AdmissionDrainToken,
        binding: FilesystemObservationSlotBinding,
        fingerprint: WholeLeaseFingerprint,
        recoveryEvidence: TransferRecoveryEvidence
    ) -> Bool {
        guard authority.preflight.matches(token: token, binding: binding) else {
            return false
        }
        let contributionIdentities = fingerprint.contributionFingerprints.map(\.identity)
        switch (authority.evidence, recoveryEvidence, fingerprint) {
        case (
            .contributions(let semanticAuthority),
            .notRequired,
            .contributions
        ):
            return semanticAuthorityMatches(
                semanticAuthority,
                binding: binding,
                fingerprint: fingerprint,
                contributionIdentities: contributionIdentities
            )
        case (
            .contributionsWithRecovery(let semanticAuthority, let acceptance),
            .required(let evidence),
            .contributionsWithRecovery
        ):
            return acceptance.matches(evidence)
                && semanticAuthorityMatches(
                    semanticAuthority,
                    binding: binding,
                    fingerprint: fingerprint,
                    contributionIdentities: contributionIdentities
                )
        case (
            .recovery(let acceptance),
            .required(let evidence),
            .recovery
        ):
            return acceptance.matches(evidence)
        case (.contributions, _, _), (.contributionsWithRecovery, _, _),
            (.recovery, _, _):
            return false
        }
    }

    private func semanticAuthorityMatches(
        _ semanticAuthority: FilesystemSemanticLeaseAcceptanceAuthority,
        binding: FilesystemObservationSlotBinding,
        fingerprint: WholeLeaseFingerprint,
        contributionIdentities: [FilesystemObservationContributionIdentity]
    ) -> Bool {
        guard
            semanticAuthority.matches(
                binding: binding,
                contributionIdentities: contributionIdentities
            )
        else {
            return false
        }
        let fenceIdentities = fingerprint.contributionFingerprints.compactMap { contribution in
            if case .retirementFence(_, let fence) = contribution {
                return fence.identity
            }
            return nil
        }
        switch (fenceIdentities.first, semanticAuthority.acceptedRetirementFenceIdentity) {
        case (.none, .none):
            return true
        case (.some(let expected), .some(let accepted)):
            return fenceIdentities.count == 1 && expected == accepted
        case (.none, .some), (.some, .none):
            return false
        }
    }

    private func retainPendingWholeLeaseCompletion(
        authority: FilesystemObservationWholeLeaseTransferAuthority,
        acknowledgement: FilesystemLeaseAcknowledgementReceipt,
        fingerprint: WholeLeaseFingerprint,
        recoveryDisposition: FilesystemObservationSlotRetirementDisposition,
        state: inout State
    ) {
        guard case .vacant = state.pendingWholeLeaseCompletion else {
            preconditionFailure("A whole-lease completion must finish before another transfer")
        }
        let fences = fingerprint.contributionFingerprints.compactMap { contribution in
            if case .retirementFence(let identity, let fence) = contribution {
                return (identity, fence)
            }
            return nil
        }
        guard let fence = fences.first else {
            state.pendingWholeLeaseCompletion = .ordinary(authority, acknowledgement)
            return
        }
        guard fences.count == 1,
            case .retirementFenceInstalled(let installedLifetime) = slotRegistry.read.state(
                of: authority.binding.physicalSlotID
            ),
            installedLifetime.contributionIdentity == fence.0,
            installedLifetime.fence == fence.1
        else {
            preconditionFailure("Acknowledged retirement fence lost exact registry custody")
        }
        state.pendingWholeLeaseCompletion = .retirement(
            authority,
            acknowledgement,
            installedLifetime,
            recoveryDisposition
        )
    }

    private func wholeLeaseFingerprint(
        for payload: FilesystemObservationDrainPayload
    ) -> WholeLeaseFingerprint {
        switch payload {
        case .contributions(let batch):
            return .contributions(
                ([batch.first] + batch.remaining).map(contributionFingerprint)
            )
        case .contributionsWithRecovery(let batch, let evidence):
            return .contributionsWithRecovery(
                ([batch.first] + batch.remaining).map(contributionFingerprint),
                evidence
            )
        case .recovery(let evidence):
            return .recovery(evidence)
        }
    }

    private func contributionFingerprint(
        _ contribution: FilesystemObservationMailboxContribution
    ) -> ContributionFingerprint {
        switch contribution {
        case .observation(let identity, _):
            return .observation(identity)
        case .retirementFence(let identity, let fence):
            return .retirementFence(identity, fence)
        }
    }

    private func validateRetirementFence(
        in fingerprint: WholeLeaseFingerprint,
        binding: FilesystemObservationSlotBinding
    ) -> RetirementFenceValidation {
        let contributions = fingerprint.contributionFingerprints
        let fences = contributions.enumerated().compactMap { index, contribution in
            if case .retirementFence(let identity, let fence) = contribution {
                return (index, identity, fence)
            }
            return nil
        }
        guard !fences.isEmpty else { return .valid }
        guard fences.count == 1,
            let exactFence = fences.first,
            exactFence.0 == contributions.count - 1,
            exactFence.1.binding == binding,
            exactFence.2.binding == binding
        else {
            return .malformed
        }
        guard
            case .retirementFenceInstalled(let installedLifetime) =
                slotRegistry.read.state(of: binding.physicalSlotID),
            installedLifetime.contributionIdentity == exactFence.1,
            installedLifetime.fence == exactFence.2
        else {
            return .installedMismatch
        }
        return .valid
    }

    private enum RetryRecovery: Sendable {
        case authoritative
        case retained(FixedFilesystemRecoveryEvidenceSnapshot)
    }

    private func completeRetry(
        token: AdmissionDrainToken,
        recovery: RetryRecovery,
        state: inout State
    ) -> FilesystemObservationDrainAcknowledgement {
        let acknowledgement = gatherMailbox.consumerPort.acknowledge(
            token: token,
            disposition: .retry
        )
        guard case .accepted(let wake) = acknowledgement else {
            return FilesystemObservationMailboxProjection.mapRejectedAcknowledgement(
                acknowledgement
            )
        }
        switch recovery {
        case .authoritative:
            break
        case .retained(let evidence):
            let binding = evidence.revision.binding
            state.retryEvidenceByPhysicalSlotID[binding.physicalSlotID] = .retained(
                binding: binding,
                evidence: evidence
            )
        }
        state.activeLease = .vacant
        return .retried(wake: wake)
    }

    private func completeAuthoritativeTransfer(
        token: AdmissionDrainToken,
        authority: FilesystemObservationWholeLeaseTransferAuthority,
        fingerprint: WholeLeaseFingerprint,
        state: inout State
    ) -> FilesystemObservationDrainAcknowledgement {
        guard
            finalFenceTransferDebtIsReadyForAcknowledgement(
                binding: authority.binding,
                fingerprint: fingerprint,
                recoveryEvidence: .notRequired,
                state: state
            )
        else {
            return .dispositionMismatch
        }
        let acknowledgement = gatherMailbox.consumerPort.acknowledge(
            token: token,
            disposition: .transferred
        )
        guard case .accepted(let wake) = acknowledgement else {
            return FilesystemObservationMailboxProjection.mapRejectedAcknowledgement(
                acknowledgement
            )
        }
        let transferReceipt = FilesystemLeaseAcknowledgementReceipt(
            authority: authority
        )
        state.activeLease = .vacant
        retainPendingWholeLeaseCompletion(
            authority: authority,
            acknowledgement: transferReceipt,
            fingerprint: fingerprint,
            recoveryDisposition: .quiescentWithoutRecovery,
            state: &state
        )
        return .transferredAuthoritative(receipt: transferReceipt, wake: wake)
    }

    private func completeRecoveryTransfer(
        token: AdmissionDrainToken,
        authority: FilesystemObservationWholeLeaseTransferAuthority,
        evidence: FixedFilesystemRecoveryEvidenceSnapshot,
        fingerprint: WholeLeaseFingerprint,
        state: inout State
    ) -> FilesystemObservationDrainAcknowledgement {
        guard
            finalFenceTransferDebtIsReadyForAcknowledgement(
                binding: authority.binding,
                fingerprint: fingerprint,
                recoveryEvidence: .required(evidence),
                state: state
            )
        else {
            return .dispositionMismatch
        }
        let acknowledgement = gatherMailbox.consumerPort.acknowledge(
            token: token,
            disposition: .transferred
        )
        guard case .accepted(let wake) = acknowledgement else {
            return FilesystemObservationMailboxProjection.mapRejectedAcknowledgement(
                acknowledgement
            )
        }
        let evidenceAcknowledgement = recoveryRegister.acknowledge(evidence)
        if wholeLeaseContainsRetirementFence(fingerprint) {
            guard case .cleared(evidence.revision) = evidenceAcknowledgement else {
                preconditionFailure(
                    "Validated final-fence recovery acknowledgement did not clear exact evidence"
                )
            }
        }
        let transferReceipt = FilesystemLeaseAcknowledgementReceipt(
            authority: authority
        )
        state.activeLease = .vacant
        retainPendingWholeLeaseCompletion(
            authority: authority,
            acknowledgement: transferReceipt,
            fingerprint: fingerprint,
            recoveryDisposition: .quiescentAfterRecovery(evidence.revision),
            state: &state
        )
        return .transferredRecovery(
            receipt: transferReceipt,
            evidence: evidenceAcknowledgement,
            wake: wake
        )
    }

    private func finalFenceTransferDebtIsReadyForAcknowledgement(
        binding: FilesystemObservationSlotBinding,
        fingerprint: WholeLeaseFingerprint,
        recoveryEvidence: TransferRecoveryEvidence,
        state: State
    ) -> Bool {
        let containsFinalFence = wholeLeaseContainsRetirementFence(fingerprint)
        guard containsFinalFence else { return true }
        guard
            let retryEvidence = state.retryEvidenceByPhysicalSlotID[binding.physicalSlotID],
            case .vacant = retryEvidence
        else {
            return false
        }
        switch (recoveryEvidence, recoveryRegister.state(of: binding.physicalSlotID)) {
        case (.notRequired, .boundClear(let retainedBinding)):
            return retainedBinding == binding
        case (.required(let evidence), .boundRetained(let retainedEvidence)):
            return retainedEvidence == evidence
                && evidence.revision.binding == binding
        case (.notRequired, _), (.required, _):
            return false
        }
    }

    private func wholeLeaseContainsRetirementFence(
        _ fingerprint: WholeLeaseFingerprint
    ) -> Bool {
        fingerprint.contributionFingerprints.contains { contribution in
            if case .retirementFence = contribution { return true }
            return false
        }
    }

    private func evidenceForLease(
        binding: FilesystemObservationSlotBinding,
        retryEvidenceByPhysicalSlotID: inout [FilesystemObservationPhysicalSlotID: RetryEvidenceCustody]
    ) -> FixedFilesystemRecoveryEvidenceSnapshot {
        let physicalSlotID = binding.physicalSlotID
        guard let retryEvidence = retryEvidenceByPhysicalSlotID[physicalSlotID] else {
            preconditionFailure("Filesystem retry evidence used an undeclared physical slot")
        }
        switch retryEvidence {
        case .retained(let retryBinding, let evidence)
        where retryBinding == binding:
            retryEvidenceByPhysicalSlotID[physicalSlotID] = RetryEvidenceCustody.vacant
            return evidence
        case .vacant:
            return requiredRecoverySnapshot(for: binding)
        case .retained:
            preconditionFailure("Filesystem retry evidence changed exact slot binding")
        }
    }

    private func requiredRecoverySnapshot(
        for binding: FilesystemObservationSlotBinding
    ) -> FixedFilesystemRecoveryEvidenceSnapshot {
        guard case .retained(let snapshot) = recoveryRegister.snapshot(for: binding) else {
            preconditionFailure("Generic recovery custody became visible without filesystem evidence")
        }
        return snapshot
    }

    private func requiredCurrentBinding(
        for physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FilesystemObservationSlotBinding {
        switch recoveryRegister.state(of: physicalSlotID) {
        case .boundClear(let binding):
            return binding
        case .boundRetained(let snapshot):
            return snapshot.revision.binding
        case .undeclaredPhysicalSlot, .vacant:
            preconditionFailure("Generic custody exists without a fixed slot binding")
        }
    }

    private func makeFleetShutdownDebtSnapshotLocked(
        shutdownIdentity: FilesystemObservationFleetShutdownIdentity,
        state: State
    ) -> FilesystemObservationFleetShutdownMailboxDebtSnapshot {
        let genericDebt = gatherMailbox.lifecyclePort.shutdownDebtSnapshot
        let genericDebtByPhysicalSlotID = Dictionary(
            uniqueKeysWithValues: genericDebt.keyDebt.map { ($0.key, $0) }
        )
        precondition(
            genericDebtByPhysicalSlotID.count == slotRegistry.physicalSlotIDs.count,
            "Generic shutdown debt must cover every declared physical slot exactly once"
        )
        let slots = slotRegistry.physicalSlotIDs.map { physicalSlotID in
            guard let genericSlotDebt = genericDebtByPhysicalSlotID[physicalSlotID] else {
                preconditionFailure("Generic shutdown debt omitted a declared physical slot")
            }
            let nativeOwner: FilesystemObservationNativeOwnerShutdownDebt
            switch state.nativeGenerationPortsByPhysicalSlotID[physicalSlotID] {
            case .vacant:
                nativeOwner = .vacant
            case .issued(let custody):
                nativeOwner = .issued(
                    callbackAdmissionPortIdentity: custody.callbackAdmissionPortIdentity,
                    projection: custody.nativeOwner.fleetShutdownProjection
                )
            case nil:
                preconditionFailure("Native shutdown custody omitted a declared physical slot")
            }
            let retryEvidence: FilesystemObservationRetryEvidenceShutdownDebt
            switch state.retryEvidenceByPhysicalSlotID[physicalSlotID] {
            case .vacant:
                retryEvidence = .vacant
            case .retained(let binding, let evidence):
                retryEvidence = .retained(binding: binding, evidence: evidence)
            case nil:
                preconditionFailure("Retry shutdown custody omitted a declared physical slot")
            }
            let recoveryEvidence: FilesystemObservationRecoveryShutdownDebt
            switch recoveryRegister.state(of: physicalSlotID) {
            case .undeclaredPhysicalSlot:
                preconditionFailure("Recovery shutdown custody rejected a declared physical slot")
            case .vacant:
                recoveryEvidence = .vacant
            case .boundClear(let binding):
                recoveryEvidence = .clear(binding)
            case .boundRetained(let evidence):
                recoveryEvidence = .retained(evidence)
            }
            return FilesystemObservationSlotShutdownDebt(
                physicalSlotID: physicalSlotID,
                registry: slotRegistry.read.fleetShutdownSlotDebt(for: physicalSlotID),
                nativeOwner: nativeOwner,
                retryEvidence: retryEvidence,
                recoveryEvidence: recoveryEvidence,
                generic: genericSlotDebt,
                completedReleaseReplay: slotRegistry.read.fleetShutdownCompletedRelease(
                    for: physicalSlotID
                )
            )
        }
        let activeLease = fleetShutdownActiveLeaseDebt(state.activeLease)
        let pendingWholeLeaseCompletion =
            fleetShutdownPendingCompletionDebt(
                state.pendingWholeLeaseCompletion
            )
        let desiredCustody = slotRegistry.read.fleetShutdownDesiredCustody
        let fenceFIFO = state.pendingRetirementFenceReadyQueue.elementsInFIFOOrder
        let isQuiescent =
            slots.allSatisfy(\.isQuiescent)
            && desiredCustody.isVacant
            && activeLease == .vacant
            && pendingWholeLeaseCompletion == .vacant
            && genericDebt.isQuiescent
            && fenceFIFO.isEmpty
        return FilesystemObservationFleetShutdownMailboxDebtSnapshot(
            fleetMailboxIdentity: fleetMailboxIdentity,
            shutdownIdentity: shutdownIdentity,
            fleetIngressLifecycle: state.fleetIngressLifecycle,
            fleetOrdinaryAdmissionDisposition: state.fleetOrdinaryAdmissionDisposition,
            mailboxLifecycle: lifecycleSnapshot(state.lifecycle),
            slots: slots,
            desiredCustody: desiredCustody,
            activeLease: activeLease,
            pendingWholeLeaseCompletion: pendingWholeLeaseCompletion,
            genericMailboxDebt: genericDebt,
            retirementFenceReadyFIFO: fenceFIFO,
            isQuiescent: isQuiescent
        )
    }

    private func fleetShutdownActiveLeaseDebt(
        _ activeLease: ActiveLeaseCustody
    ) -> FilesystemObservationActiveLeaseShutdownDebt {
        switch activeLease {
        case .vacant:
            return .vacant
        case .authoritative(let token, let binding, let fingerprint):
            return .authoritative(
                token: token,
                binding: binding,
                fingerprint: fleetShutdownFingerprint(fingerprint)
            )
        case .recovery(let token, let binding, let evidence, let fingerprint):
            return .recovery(
                token: token,
                binding: binding,
                evidence: evidence,
                fingerprint: fleetShutdownFingerprint(fingerprint)
            )
        }
    }

    private func fleetShutdownPendingCompletionDebt(
        _ custody: PendingWholeLeaseCompletionCustody
    ) -> FilesystemObservationPendingWholeLeaseCompletionShutdownDebt {
        switch custody {
        case .vacant:
            return .vacant
        case .ordinary(let authority, let acknowledgement):
            return .ordinary(
                authority: authority,
                acknowledgement: acknowledgement
            )
        case .retirement(
            let authority,
            let acknowledgement,
            let installedLifetime,
            let disposition
        ):
            return .retirement(
                authority: authority,
                acknowledgement: acknowledgement,
                binding: installedLifetime.binding,
                fenceIdentity: installedLifetime.identity,
                contributionIdentity: installedLifetime.contributionIdentity,
                disposition: disposition
            )
        }
    }

    private func fleetShutdownFingerprint(
        _ fingerprint: WholeLeaseFingerprint
    ) -> FilesystemObservationLeaseShutdownFingerprint {
        switch fingerprint {
        case .contributions(let contributions):
            return .contributions(contributions.map(fleetShutdownContributionReference))
        case .contributionsWithRecovery(let contributions, let evidence):
            return .contributionsWithRecovery(
                contributions.map(fleetShutdownContributionReference),
                evidence.revision
            )
        case .recovery(let evidence):
            return .recovery(evidence.revision)
        }
    }

    private func fleetShutdownContributionReference(
        _ fingerprint: ContributionFingerprint
    ) -> FilesystemObservationLeaseShutdownContributionReference {
        switch fingerprint {
        case .observation(let identity):
            return .observation(identity)
        case .retirementFence(let identity, let fence):
            return .retirementFence(identity, fence.identity)
        }
    }

    private func lifecycleSnapshot(
        _ lifecycle: Lifecycle
    ) -> FilesystemObservationLifecycleStateSnapshot {
        switch lifecycle {
        case .open: .open
        case .sealed: .sealed
        case .invalidated: .invalidated
        case .finished: .finished
        }
    }

    private func recoverySnapshotResult(
        for physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FixedFilesystemRecoveryEvidenceSnapshotResult {
        switch recoveryRegister.state(of: physicalSlotID) {
        case .undeclaredPhysicalSlot:
            return .undeclaredPhysicalSlot
        case .vacant:
            return .unboundPhysicalSlot
        case .boundClear(let binding):
            return .clear(binding)
        case .boundRetained(let snapshot):
            return .retained(snapshot)
        }
    }

}
