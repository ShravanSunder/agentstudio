import Foundation
import os

/// Bounded callback custody for opaque FSEvent observations.
///
/// The coordination lock couples the generic gather recovery revision to exact
/// filesystem recovery evidence. It intentionally performs no path or flag
/// reduction; semantic filesystem work belongs to the actor after a lease is
/// acquired.
final class FilesystemObservationMailbox: @unchecked Sendable {
    private enum Lifecycle: Sendable {
        case open
        case sealed
        case invalidated
        case finished
    }

    private enum ActiveLeaseCustody: Sendable {
        case vacant
        case authoritative(AdmissionDrainToken)
        case recovery(
            token: AdmissionDrainToken,
            evidence: FilesystemRecoveryEvidenceSnapshot
        )
    }

    private enum RetryEvidenceCustody: Sendable {
        case vacant
        case retained(
            registration: FSEventRegistrationToken,
            evidence: FilesystemRecoveryEvidenceSnapshot
        )
    }

    private enum CustodyInspection: Sendable {
        case quiescent
        case outstanding(FilesystemObservationOutstandingCustody)
    }

    private struct State: Sendable {
        var lifecycle: Lifecycle
        var activeLease: ActiveLeaseCustody
        var retryEvidenceByRegistration: [FSEventRegistrationToken: RetryEvidenceCustody]

        init(declaredRegistrations: Set<FSEventRegistrationToken>) {
            lifecycle = .open
            activeLease = .vacant
            retryEvidenceByRegistration = Dictionary(
                uniqueKeysWithValues: declaredRegistrations.map { ($0, .vacant) }
            )
        }
    }

    private let generation: AdmissionGeneration
    private let declaredRegistrations: Set<FSEventRegistrationToken>
    private let gatherMailbox:
        BoundedGatherMailbox<
            FSEventRegistrationToken,
            FSEventObservation
        >
    private let recoveryRegister: FilesystemRecoveryEvidenceRegister
    private let doorbell = AdmissionDoorbell()
    private let lock: OSAllocatedUnfairLock<State>

    init(
        generation: AdmissionGeneration,
        declaredRegistrations: [FSEventRegistrationToken],
        limits: GatherMailboxLimits
    ) throws {
        let declaredRegistrationSet = Set(declaredRegistrations)
        guard
            BoundedGatherMailbox<FSEventRegistrationToken, FSEventObservation>
                .isConfigurationValid(
                    declaredKeyCount: declaredRegistrationSet.count,
                    limits: limits
                )
        else {
            throw FilesystemObservationMailboxConfigurationError.invalidGatherLimits
        }

        recoveryRegister = try FilesystemRecoveryEvidenceRegister(
            maximumDeclaredRegistrations: limits.maximumDeclaredKeys,
            declaredRegistrations: declaredRegistrations
        )
        gatherMailbox = BoundedGatherMailbox(
            generation: generation,
            declaredKeys: declaredRegistrationSet,
            limits: limits
        )
        self.generation = generation
        self.declaredRegistrations = declaredRegistrationSet
        lock = OSAllocatedUnfairLock(
            initialState: State(declaredRegistrations: declaredRegistrationSet)
        )
    }

    var callbackProducerPort: FilesystemObservationCallbackProducerPort {
        FilesystemObservationCallbackProducerPort(offer: offer)
    }

    var callbackSignalerPort: FilesystemObservationCallbackSignalerPort {
        let signaler = doorbell.signalerPort
        return FilesystemObservationCallbackSignalerPort { wake in
            guard wake == .scheduleDrain else { return }
            signaler.signal()
        }
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

    func offer(
        _ offer: FilesystemObservationOffer
    ) -> FilesystemObservationOfferResult {
        lock.withLock { state in
            guard state.lifecycle == .open else { return .closed }
            let observation = offer.observation
            guard declaredRegistrations.contains(observation.registration) else {
                return .undeclaredRegistration
            }

            switch offer.explicitRecoveryEvidence {
            case .notRequired:
                break
            case .required(let evidence):
                _ = recoveryRegister.record(evidence, for: observation.registration)
            }

            let gatherResult = gatherMailbox.producerPort.offer(
                generation: generation,
                contribution: GatherContribution(
                    key: observation.registration,
                    payload: observation,
                    footprint: GatherFootprint(
                        itemCount: observation.records.count,
                        byteCount: observation.copiedUTF8ByteCount
                    ),
                    recoverySignal: offer.recoverySignal
                )
            )
            return mapOfferResult(
                gatherResult,
                registration: observation.registration
            )
        }
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
                recoveryEvidenceByRegistration: Dictionary(
                    uniqueKeysWithValues: declaredRegistrations.map {
                        ($0, recoveryRegister.snapshot(for: $0))
                    }
                )
            )
        }
    }

    func recoveryEvidence(
        for registration: FSEventRegistrationToken
    ) -> FilesystemRecoveryEvidenceSnapshotResult {
        lock.withLock { _ in
            recoveryRegister.snapshot(for: registration)
        }
    }

    private func mapOfferResult(
        _ result: GatherOfferResult<FSEventRegistrationToken>,
        registration: FSEventRegistrationToken
    ) -> FilesystemObservationOfferResult {
        switch result {
        case .admitted(.retained, let wake):
            return .admitted(
                FilesystemObservationOfferReceipt(
                    disposition: .retained,
                    wake: wake
                )
            )
        case .admitted(.retainedWithRecovery, let wake):
            return .admitted(
                FilesystemObservationOfferReceipt(
                    disposition: .retainedWithRecovery(
                        requiredRecoverySnapshot(for: registration)
                    ),
                    wake: wake
                )
            )
        case .admitted(.contractedToRecovery(_, .capacityPressure), let wake),
            .admitted(.contractedToRecovery(_, .recoveryAuthorityExhaustedTransition), let wake),
            .admitted(.contractedToRecovery(_, .ordinaryAdmissionAlreadySealed), let wake):
            _ = recoveryRegister.record(
                .callbackAdmissionOverflow,
                for: registration
            )
            return .admitted(
                FilesystemObservationOfferReceipt(
                    disposition: .contractedToRecovery(
                        requiredRecoverySnapshot(for: registration)
                    ),
                    wake: wake
                )
            )
        case .undeclaredKey:
            return .undeclaredRegistration
        case .invalidFootprint:
            return .invalidFootprint
        case .closed:
            return .closed
        case .staleGeneration:
            preconditionFailure("Generation-bound filesystem producer became stale")
        }
    }

    private func mapTakeResult(
        _ result: GatherTakeDrainResult<FSEventRegistrationToken, FSEventObservation>,
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
        _ gatherLease: GatherDrainLease<FSEventRegistrationToken, FSEventObservation>,
        state: inout State
    ) -> FilesystemObservationDrainLease {
        switch state.activeLease {
        case .authoritative:
            state.activeLease = .authoritative(gatherLease.token)
            return FilesystemObservationDrainLease(
                token: gatherLease.token,
                registration: gatherLease.key,
                payload: observationsPayload(from: gatherLease.payload)
            )
        case .recovery(_, let evidence):
            state.activeLease = .recovery(token: gatherLease.token, evidence: evidence)
            return FilesystemObservationDrainLease(
                token: gatherLease.token,
                registration: gatherLease.key,
                payload: recoveryPayload(from: gatherLease.payload, evidence: evidence)
            )
        case .vacant:
            return mapNewLease(gatherLease, state: &state)
        }
    }

    private func mapNewLease(
        _ gatherLease: GatherDrainLease<FSEventRegistrationToken, FSEventObservation>,
        state: inout State
    ) -> FilesystemObservationDrainLease {
        let payload: FilesystemObservationDrainPayload
        switch gatherLease.payload {
        case .contributions(let contributions):
            state.activeLease = .authoritative(gatherLease.token)
            payload = .observations(observations(from: contributions))
        case .contributionsWithRecovery(let contributions, _):
            let evidence = evidenceForLease(
                registration: gatherLease.key,
                retryEvidenceByRegistration: &state.retryEvidenceByRegistration
            )
            state.activeLease = .recovery(token: gatherLease.token, evidence: evidence)
            payload = .observationsWithRecovery(observations(from: contributions), evidence)
        case .recovery:
            let evidence = evidenceForLease(
                registration: gatherLease.key,
                retryEvidenceByRegistration: &state.retryEvidenceByRegistration
            )
            state.activeLease = .recovery(token: gatherLease.token, evidence: evidence)
            payload = .recovery(evidence)
        }
        return FilesystemObservationDrainLease(
            token: gatherLease.token,
            registration: gatherLease.key,
            payload: payload
        )
    }

    private func acknowledgeLocked(
        token: AdmissionDrainToken,
        disposition: FilesystemObservationDrainDisposition,
        state: inout State
    ) -> FilesystemObservationDrainAcknowledgement {
        switch (state.activeLease, disposition) {
        case (.authoritative(let activeToken), .retry) where activeToken == token:
            return completeRetry(token: token, recovery: .authoritative, state: &state)
        case (
            .recovery(let activeToken, let evidence),
            .retry
        ) where activeToken == token:
            return completeRetry(
                token: token,
                recovery: .retained(evidence),
                state: &state
            )
        case (
            .authoritative(let activeToken),
            .transferredAuthoritative
        ) where activeToken == token:
            return completeAuthoritativeTransfer(token: token, state: &state)
        case (
            .recovery(let activeToken, let retainedEvidence),
            .transferredRecovery(let acceptance)
        ) where activeToken == token && acceptance.matches(retainedEvidence):
            return completeRecoveryTransfer(
                token: token,
                evidence: retainedEvidence,
                state: &state
            )
        case (.vacant, _):
            return .invalidToken
        case (.authoritative(let activeToken), _) where activeToken == token:
            return .dispositionMismatch
        case (.recovery(let activeToken, _), _) where activeToken == token:
            return .dispositionMismatch
        case (.authoritative, _), (.recovery, _):
            return .invalidToken
        }
    }

    private enum RetryRecovery: Sendable {
        case authoritative
        case retained(FilesystemRecoveryEvidenceSnapshot)
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
            return mapRejectedAcknowledgement(acknowledgement)
        }
        switch recovery {
        case .authoritative:
            break
        case .retained(let evidence):
            state.retryEvidenceByRegistration[evidence.revision.registration] = .retained(
                registration: evidence.revision.registration,
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
            return mapRejectedAcknowledgement(acknowledgement)
        }
        state.activeLease = .vacant
        return .transferredAuthoritative(wake: wake)
    }

    private func completeRecoveryTransfer(
        token: AdmissionDrainToken,
        evidence: FilesystemRecoveryEvidenceSnapshot,
        state: inout State
    ) -> FilesystemObservationDrainAcknowledgement {
        let acknowledgement = gatherMailbox.consumerPort.acknowledge(
            token: token,
            disposition: .transferred
        )
        guard case .accepted(let wake) = acknowledgement else {
            return mapRejectedAcknowledgement(acknowledgement)
        }
        let evidenceAcknowledgement = recoveryRegister.acknowledge(evidence)
        state.activeLease = .vacant
        return .transferredRecovery(
            evidence: evidenceAcknowledgement,
            wake: wake
        )
    }

    private func mapRejectedAcknowledgement(
        _ acknowledgement: AdmissionDrainAcknowledgement
    ) -> FilesystemObservationDrainAcknowledgement {
        switch acknowledgement {
        case .invalidToken, .staleGeneration:
            .invalidToken
        case .closed:
            .closed
        case .accepted:
            preconditionFailure("Accepted acknowledgement must be mapped by its caller")
        }
    }

    private func evidenceForLease(
        registration: FSEventRegistrationToken,
        retryEvidenceByRegistration: inout [FSEventRegistrationToken: RetryEvidenceCustody]
    ) -> FilesystemRecoveryEvidenceSnapshot {
        guard let retryEvidence = retryEvidenceByRegistration[registration] else {
            preconditionFailure("Filesystem retry evidence used an undeclared registration")
        }
        switch retryEvidence {
        case .retained(let retryRegistration, let evidence)
        where retryRegistration == registration:
            retryEvidenceByRegistration[registration] = RetryEvidenceCustody.vacant
            return evidence
        case .vacant:
            return requiredRecoverySnapshot(for: registration)
        case .retained:
            preconditionFailure("Filesystem retry evidence changed registration identity")
        }
    }

    private func observationsPayload(
        from payload: GatherDrainPayload<FSEventRegistrationToken, FSEventObservation>
    ) -> FilesystemObservationDrainPayload {
        guard case .contributions(let contributions) = payload else {
            preconditionFailure("Authoritative filesystem lease changed payload kind during rebind")
        }
        return .observations(observations(from: contributions))
    }

    private func recoveryPayload(
        from payload: GatherDrainPayload<FSEventRegistrationToken, FSEventObservation>,
        evidence: FilesystemRecoveryEvidenceSnapshot
    ) -> FilesystemObservationDrainPayload {
        switch payload {
        case .contributionsWithRecovery(let contributions, _):
            .observationsWithRecovery(observations(from: contributions), evidence)
        case .recovery:
            .recovery(evidence)
        case .contributions:
            preconditionFailure("Recovery filesystem lease changed payload kind during rebind")
        }
    }

    private func observations(
        from contributions: NonEmptyAdmissionBatch<
            GatherContribution<FSEventRegistrationToken, FSEventObservation>
        >
    ) -> NonEmptyAdmissionBatch<FSEventObservation> {
        NonEmptyAdmissionBatch(
            first: contributions.first.payload,
            remaining: contributions.remaining.map(\.payload)
        )
    }

    private func requiredRecoverySnapshot(
        for registration: FSEventRegistrationToken
    ) -> FilesystemRecoveryEvidenceSnapshot {
        guard case .evidence(let snapshot) = recoveryRegister.snapshot(for: registration) else {
            preconditionFailure("Generic recovery custody became visible without filesystem evidence")
        }
        return snapshot
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
        for custody in state.retryEvidenceByRegistration.values {
            switch custody {
            case .vacant:
                break
            case .retained:
                retryEvidenceRegistrationCount += 1
            }
        }
        var recoveryEvidenceRegistrationCount = 0
        for registration in declaredRegistrations {
            switch recoveryRegister.snapshot(for: registration) {
            case .evidence:
                recoveryEvidenceRegistrationCount += 1
            case .noEvidence, .unknownRegistration:
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
