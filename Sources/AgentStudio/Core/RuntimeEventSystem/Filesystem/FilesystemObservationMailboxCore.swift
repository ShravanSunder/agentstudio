import Foundation
import os

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

    fileprivate init(
        callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort,
        lifecyclePort: FilesystemObservationNativeLifecyclePort
    ) {
        self.callbackAdmissionPort = callbackAdmissionPort
        self.lifecyclePort = lifecyclePort
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

    fileprivate init(operation: FilesystemObservationNativeLifecycleOperation) {
        self.operation = operation
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
    private let callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort
    private let mailboxLifetimeOwner: FilesystemObservationMailbox
    private let core: FilesystemObservationMailboxCore

    init(
        startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort,
        mailboxLifetimeOwner: FilesystemObservationMailbox,
        core: FilesystemObservationMailboxCore
    ) {
        expectedStartingNativeLifetime = startingNativeLifetime
        self.callbackAdmissionPort = callbackAdmissionPort
        self.mailboxLifetimeOwner = mailboxLifetimeOwner
        self.core = core
    }

    func publishAccepting(
        _ startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    ) -> FilesystemObservationAcceptingPublicationResult {
        guard startingNativeLifetime == expectedStartingNativeLifetime else {
            return .startingNativeLifetimeMismatch(expectedStartingNativeLifetime)
        }
        return core.publishAcceptingNativeLifetime(
            startingNativeLifetime,
            callbackAdmissionPortIdentity: callbackAdmissionPort.identity
        )
    }

    func beginClosingAwaitingCallbackLeaseDrain(
        _ acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
    ) -> FilesystemObservationCallbackLeaseDrainClosingResult {
        guard
            acceptingNativeLifetime.startingNativeLifetime
                == expectedStartingNativeLifetime,
            acceptingNativeLifetime.callbackAdmissionPortIdentity
                == callbackAdmissionPort.identity
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

    private enum Lifecycle: Sendable {
        case open
        case sealed
        case invalidated
        case finished
    }

    private enum ActiveLeaseCustody: Sendable {
        case vacant
        case authoritative(
            token: AdmissionDrainToken,
            binding: FilesystemObservationSlotBinding
        )
        case recovery(
            token: AdmissionDrainToken,
            binding: FilesystemObservationSlotBinding,
            evidence: FixedFilesystemRecoveryEvidenceSnapshot
        )
    }

    private enum RetryEvidenceCustody: Sendable {
        case vacant
        case retained(
            binding: FilesystemObservationSlotBinding,
            evidence: FixedFilesystemRecoveryEvidenceSnapshot
        )
    }

    private enum CustodyInspection: Sendable {
        case quiescent
        case outstanding(FilesystemObservationOutstandingCustody)
    }

    private enum NativeGenerationPortCustody: Sendable {
        case vacant
        case issued(
            startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
            callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity,
            synchronization: any FilesystemObservationCallbackSynchronization
        )
    }

    private struct State: Sendable {
        var lifecycle: Lifecycle
        var activeLease: ActiveLeaseCustody
        var retryEvidenceByPhysicalSlotID: [FilesystemObservationPhysicalSlotID: RetryEvidenceCustody]
        var nativeGenerationPortsByPhysicalSlotID: [FilesystemObservationPhysicalSlotID: NativeGenerationPortCustody]
        var isFleetOrdinaryAdmissionSealed: Bool

        init(
            physicalSlotIDs: [FilesystemObservationPhysicalSlotID],
            isFleetOrdinaryAdmissionSealed: Bool
        ) {
            lifecycle = .open
            activeLease = .vacant
            retryEvidenceByPhysicalSlotID = Dictionary(
                uniqueKeysWithValues: physicalSlotIDs.map { ($0, .vacant) }
            )
            nativeGenerationPortsByPhysicalSlotID = Dictionary(
                uniqueKeysWithValues: physicalSlotIDs.map { ($0, .vacant) }
            )
            self.isFleetOrdinaryAdmissionSealed = isFleetOrdinaryAdmissionSealed
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
                isFleetOrdinaryAdmissionSealed: FilesystemObservationMailboxProjection.isFleetOrdinaryAdmissionSealed(
                    recoveryAuthoritySeed
                )
            )
        )
    }

    var fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity {
        slotRegistry.fleetMailboxIdentity
    }

    var physicalSlotIDs: [FilesystemObservationPhysicalSlotID] {
        slotRegistry.physicalSlotIDs
    }

    func recordDesiredRegistration(
        _ registration: FSEventRegistrationToken
    ) -> FilesystemObservationDesiredUpdateResult {
        lock.withLock { _ in
            slotRegistry.recordDesiredRegistration(registration)
        }
    }

    func selectNextDesiredSource() -> FilesystemObservationDesiredSelectionResult {
        lock.withLock { _ in
            slotRegistry.selectNextDesiredSource()
        }
    }

    func beginNativeLifetime(
        _ reservation: FilesystemObservationSlotReservation
    ) -> FilesystemObservationNativeLifetimeCommitResult {
        lock.withLock { _ in
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
                .staleReservation, .deferredToConfigurationCurrentness:
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
            slotRegistry.state(of: physicalSlotID)
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

    fileprivate func acceptingNativeLifetimeMismatch(
        for startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    ) -> FilesystemObservationCallbackLeaseDrainClosingResult {
        lock.withLock { _ in
            switch slotRegistry.state(of: startingNativeLifetime.binding.physicalSlotID) {
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
        case .issued(
            let issuedStartingNativeLifetime,
            let callbackAdmissionPortIdentity,
            let issuedSynchronization
        ):
            return issuedStartingNativeLifetime == startingNativeLifetime
                ? .created(
                    makeNativeGenerationPorts(
                        for: startingNativeLifetime,
                        retaining: mailboxLifetimeOwner,
                        callbackAdmissionPortIdentity: callbackAdmissionPortIdentity,
                        synchronization: issuedSynchronization
                    )
                ) : .bindingNotCurrent
        case .vacant:
            break
        }
        switch slotRegistry.state(of: binding.physicalSlotID) {
        case .starting(let currentStartingNativeLifetime)
        where currentStartingNativeLifetime == startingNativeLifetime:
            let callbackAdmissionPortIdentity =
                FilesystemObservationCallbackAdmissionPortIdentity(
                    value: UUIDv7.generate()
                )
            let ports = makeNativeGenerationPorts(
                for: startingNativeLifetime,
                retaining: mailboxLifetimeOwner,
                callbackAdmissionPortIdentity: callbackAdmissionPortIdentity,
                synchronization: synchronization
            )
            state.nativeGenerationPortsByPhysicalSlotID[binding.physicalSlotID] =
                .issued(
                    startingNativeLifetime: startingNativeLifetime,
                    callbackAdmissionPortIdentity: callbackAdmissionPortIdentity,
                    synchronization: synchronization
                )
            return .created(ports)
        case .undeclaredPhysicalSlot:
            return binding.fleetMailboxIdentity == fleetMailboxIdentity
                ? .undeclaredPhysicalSlot : .foreignFleet
        case .starting, .vacant, .selected, .accepting,
            .closingAwaitingCallbackLeaseDrain, .retiringUnpublishedGeneration:
            return binding.fleetMailboxIdentity == fleetMailboxIdentity
                ? .bindingNotCurrent : .foreignFleet
        }
    }

    private func makeNativeGenerationPorts(
        for startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        retaining mailboxLifetimeOwner: FilesystemObservationMailbox,
        callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity,
        synchronization: any FilesystemObservationCallbackSynchronization
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
        return FilesystemObservationNativeGenerationPorts(
            callbackAdmissionPort: callbackAdmissionPort,
            lifecyclePort: FilesystemObservationNativeLifecyclePort(
                operation: FilesystemObservationNativeLifecycleOperation(
                    startingNativeLifetime: startingNativeLifetime,
                    callbackAdmissionPort: callbackAdmissionPort,
                    mailboxLifetimeOwner: mailboxLifetimeOwner,
                    core: self
                )
            )
        )
    }

    var actorConsumerPort: FilesystemObservationActorConsumerPort {
        FilesystemObservationActorConsumerPort(
            bind: bindConsumer,
            take: takeDrain,
            acknowledge: acknowledge,
            cleanup: performCleanup
        )
    }

    var actorWaiterPort: FilesystemObservationActorWaiterPort {
        let waiter = doorbell.consumerPort
        return FilesystemObservationActorWaiterPort(wait: waiter.nextSignal)
    }

    var lifecyclePort: FilesystemObservationLifecyclePort {
        FilesystemObservationLifecyclePort(
            seal: seal,
            invalidate: invalidate,
            finish: finish,
            diagnostics: { self.diagnostics }
        )
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
            switch slotRegistry.storedBindingCurrentness(of: binding) {
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
            guard !state.isFleetOrdinaryAdmissionSealed else {
                return .mailboxRejected(.fleetOrdinaryAdmissionSealed)
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
                case .undeclaredSlot:
                    return .mailboxRejected(.undeclaredSlot)
                case .bindingMismatch:
                    return .mailboxRejected(.fenced)
                case .invalidFootprint:
                    return .mailboxRejected(.invalidFootprint)
                case .fleetOrdinaryAdmissionSealed:
                    return .mailboxRejected(.fleetOrdinaryAdmissionSealed)
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
        if case .admitted(.contractedToRecovery(_, let cause), _) = gatherResult {
            switch cause {
            case .recoveryAuthorityExhaustedTransition, .ordinaryAdmissionAlreadySealed:
                state.isFleetOrdinaryAdmissionSealed = true
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
            acknowledgeLocked(
                token: token,
                disposition: disposition,
                state: &state
            )
        }
        doorbell.ownerPort.apply(result.wake)
        return result
    }

    func performCleanup() -> AdmissionCleanupTurnResult {
        let result = lock.withLock { _ in
            gatherMailbox.consumerPort.performCleanup(generation: generation)
        }
        if case .performed(let turn) = result {
            doorbell.ownerPort.apply(turn.wake)
        }
        return result
    }

    func seal() -> FilesystemObservationLifecycleTransitionResult {
        lock.withLock { state in
            switch state.lifecycle {
            case .open:
                break
            case .sealed:
                return .alreadyApplied
            case .invalidated, .finished:
                return .invalidState(lifecycleSnapshot(state.lifecycle))
            }
            let result = gatherMailbox.lifecyclePort.seal(generation: generation)
            guard result == .applied else {
                preconditionFailure("Generation-bound filesystem mailbox failed to seal")
            }
            state.lifecycle = .sealed
            return .applied
        }
    }

    func invalidate() -> FilesystemObservationLifecycleTransitionResult {
        lock.withLock { state in
            switch state.lifecycle {
            case .open:
                return .invalidState(.open)
            case .sealed:
                break
            case .invalidated:
                return .alreadyApplied
            case .finished:
                return .invalidState(.finished)
            }
            switch inspectCustody(state: state) {
            case .quiescent:
                break
            case .outstanding(let custody):
                return .outstandingCustody(custody)
            }
            let result = gatherMailbox.lifecyclePort.invalidate(generation: generation)
            guard result == .applied else {
                preconditionFailure("Generation-bound filesystem mailbox failed to invalidate")
            }
            state.lifecycle = .invalidated
            return .applied
        }
    }

    func finish() -> FilesystemObservationLifecycleTransitionResult {
        let transition = lock.withLock { state -> FilesystemObservationLifecycleTransitionResult in
            switch state.lifecycle {
            case .invalidated:
                state.lifecycle = .finished
                return .applied
            case .finished:
                return .alreadyApplied
            case .open, .sealed:
                return .invalidState(lifecycleSnapshot(state.lifecycle))
            }
        }
        if transition == .applied {
            doorbell.lifecyclePort.finish()
        }
        return transition
    }

    var diagnostics: FilesystemObservationMailboxDiagnostics {
        lock.withLock { state in
            FilesystemObservationMailboxDiagnostics(
                gather: gatherMailbox.lifecyclePort.diagnostics,
                doorbellState: doorbell.lifecyclePort.stateSnapshot,
                lifecycleState: lifecycleSnapshot(state.lifecycle),
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
        case .authoritative(_, let retainedBinding):
            guard retainedBinding == binding else {
                preconditionFailure("Rebound filesystem lease changed its exact slot binding")
            }
            state.activeLease = .authoritative(token: gatherLease.token, binding: binding)
            return FilesystemObservationDrainLease(
                token: gatherLease.token,
                binding: binding,
                payload: FilesystemObservationMailboxProjection.contributionsPayload(
                    from: gatherLease.payload
                )
            )
        case .recovery(_, let retainedBinding, let evidence):
            guard retainedBinding == binding else {
                preconditionFailure("Rebound recovery lease changed its exact slot binding")
            }
            state.activeLease = .recovery(
                token: gatherLease.token,
                binding: binding,
                evidence: evidence
            )
            return FilesystemObservationDrainLease(
                token: gatherLease.token,
                binding: binding,
                payload: FilesystemObservationMailboxProjection.recoveryPayload(
                    from: gatherLease.payload,
                    evidence: evidence
                )
            )
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
            state.activeLease = .authoritative(token: gatherLease.token, binding: binding)
            payload = .contributions(
                FilesystemObservationMailboxProjection.contributionsPayloads(
                    from: contributions
                )
            )
        case .contributionsWithRecovery(let contributions, _):
            let evidence = evidenceForLease(
                binding: binding,
                retryEvidenceByPhysicalSlotID: &state.retryEvidenceByPhysicalSlotID
            )
            state.activeLease = .recovery(
                token: gatherLease.token,
                binding: binding,
                evidence: evidence
            )
            payload = .contributionsWithRecovery(
                FilesystemObservationMailboxProjection.contributionsPayloads(
                    from: contributions
                ),
                evidence
            )
        case .recovery:
            let evidence = evidenceForLease(
                binding: binding,
                retryEvidenceByPhysicalSlotID: &state.retryEvidenceByPhysicalSlotID
            )
            state.activeLease = .recovery(
                token: gatherLease.token,
                binding: binding,
                evidence: evidence
            )
            payload = .recovery(evidence)
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
        case (.authoritative(let activeToken, _), .retry) where activeToken == token:
            return completeRetry(token: token, recovery: .authoritative, state: &state)
        case (
            .recovery(let activeToken, _, let evidence),
            .retry
        ) where activeToken == token:
            return completeRetry(
                token: token,
                recovery: .retained(evidence),
                state: &state
            )
        case (
            .authoritative(let activeToken, _),
            .transferredAuthoritative
        ) where activeToken == token:
            return completeAuthoritativeTransfer(token: token, state: &state)
        case (
            .recovery(let activeToken, _, let retainedEvidence),
            .transferredRecovery(let acceptance)
        ) where activeToken == token && acceptance.matches(retainedEvidence):
            return completeRecoveryTransfer(
                token: token,
                evidence: retainedEvidence,
                state: &state
            )
        case (.vacant, _):
            return .invalidToken
        case (.authoritative(let activeToken, _), _) where activeToken == token:
            return .dispositionMismatch
        case (.recovery(let activeToken, _, _), _) where activeToken == token:
            return .dispositionMismatch
        case (.authoritative, _), (.recovery, _):
            return .invalidToken
        }
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
        state: inout State
    ) -> FilesystemObservationDrainAcknowledgement {
        let acknowledgement = gatherMailbox.consumerPort.acknowledge(
            token: token,
            disposition: .transferred
        )
        guard case .accepted(let wake) = acknowledgement else {
            return FilesystemObservationMailboxProjection.mapRejectedAcknowledgement(
                acknowledgement
            )
        }
        state.activeLease = .vacant
        return .transferredAuthoritative(wake: wake)
    }

    private func completeRecoveryTransfer(
        token: AdmissionDrainToken,
        evidence: FixedFilesystemRecoveryEvidenceSnapshot,
        state: inout State
    ) -> FilesystemObservationDrainAcknowledgement {
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
        state.activeLease = .vacant
        return .transferredRecovery(
            evidence: evidenceAcknowledgement,
            wake: wake
        )
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

    private func inspectCustody(
        state: State
    ) -> CustodyInspection {
        let gatherDiagnostics = gatherMailbox.lifecyclePort.diagnostics
        let activeLeaseCount: Int
        switch state.activeLease {
        case .vacant:
            activeLeaseCount = 0
        case .authoritative, .recovery:
            activeLeaseCount = 1
        }
        var retryEvidenceRegistrationCount = 0
        for custody in state.retryEvidenceByPhysicalSlotID.values {
            switch custody {
            case .vacant:
                break
            case .retained:
                retryEvidenceRegistrationCount += 1
            }
        }
        var recoveryEvidenceRegistrationCount = 0
        for physicalSlotID in slotRegistry.physicalSlotIDs {
            switch recoveryRegister.state(of: physicalSlotID) {
            case .boundRetained:
                recoveryEvidenceRegistrationCount += 1
            case .undeclaredPhysicalSlot, .vacant, .boundClear:
                break
            }
        }
        let cleanupEntryCount =
            gatherDiagnostics.cleanupContributionCount
            + gatherDiagnostics.cleanupMetadataEntryCount
        let custody = FilesystemObservationOutstandingCustody(
            retainedContributionCount: gatherDiagnostics.retainedContributionCount,
            activeLeaseCount: activeLeaseCount,
            retryEvidenceRegistrationCount: retryEvidenceRegistrationCount,
            recoveryEvidenceRegistrationCount: recoveryEvidenceRegistrationCount,
            cleanupEntryCount: cleanupEntryCount
        )
        guard
            custody.retainedContributionCount > 0
                || custody.activeLeaseCount > 0
                || custody.retryEvidenceRegistrationCount > 0
                || custody.recoveryEvidenceRegistrationCount > 0
                || custody.cleanupEntryCount > 0
        else {
            return .quiescent
        }
        return .outstanding(custody)
    }
}
