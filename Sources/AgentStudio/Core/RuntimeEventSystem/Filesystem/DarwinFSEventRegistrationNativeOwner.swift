import CoreServices
import Foundation
import os

// The fixed-slot owner intentionally keeps all native authority transitions in one lexical owner.
// swiftlint:disable file_length type_body_length

/// The persistent native custody owner for one committed fixed-slot binding.
///
/// The mailbox retains this owner for the entire binding lifetime. The owner consumes one
/// create-or-abandon right and retains the exact completion so cancellation or a lost response
/// cannot repeat native creation.
final class DarwinFSEventRegistrationNativeOwner: @unchecked Sendable {
    private enum State {
        case creationAvailable
        case creating
        case created(DarwinFSEventRegistrationGeneration)
        case creationRejected(
            DarwinFSEventRegistrationCreateFailureCleanup,
            DarwinFSEventCallbackContextCustody
        )
        case creationAbandoned(DarwinFSEventRegistrationCreationAbandonment)
        case starting(
            DarwinFSEventRegistrationGeneration,
            DarwinFSEventNativeOwnerStartCompletion
        )
        case abandoningStart(
            DarwinFSEventRegistrationGeneration,
            DarwinFSEventNativeOwnerStartCompletion
        )
        case publishingAcceptance(
            DarwinFSEventRegistrationGeneration,
            DarwinFSEventNativeOwnerStartCompletion
        )
        case acceptingPublicationPending(
            DarwinFSEventRegistrationGeneration,
            FilesystemObservationAcceptingPublicationResult
        )
        case startCompleted(
            DarwinFSEventRegistrationGeneration,
            DarwinFSEventNativeOwnerStartResult
        )
    }

    private enum CreationCompletion {
        case created(
            DarwinFSEventRegistrationGeneration,
            DarwinFSEventCallbackContextCustody
        )
        case rejected(
            DarwinFSEventRegistrationCreateFailureCleanup,
            DarwinFSEventCallbackContextCustody
        )
    }

    private enum NativeFinalizationMaterialization {
        case neverMaterialized
        case retainedContext(DarwinFSEventCallbackContextCustody)
    }

    private enum NativeFinalizationState {
        case awaitingMaterialization
        case retainedContext(DarwinFSEventCallbackContextCustody)
        case retirementPermitRetained(
            FilesystemObservationNativeRetirementPermit,
            NativeFinalizationMaterialization
        )
        case finalizing(
            FilesystemObservationNativeRetirementPermit,
            NativeFinalizationMaterialization
        )
        case finalized(FilesystemObservationContextReleaseAcknowledgement)
    }

    private enum NativeFinalizationAction {
        case recordNeverMaterialized
        case releaseRetainedContext(DarwinFSEventCallbackContextCustody)
        case replay(FilesystemObservationContextReleaseAcknowledgement)
        case rejected(FilesystemObservationNativeFinalizationRejection)
    }

    private enum StartIntent {
        case start
        case abandon
    }

    private enum StartAction {
        case performStart(
            DarwinFSEventRegistrationGeneration,
            DarwinFSEventNativeOwnerStartCompletion
        )
        case performAbandonment(
            DarwinFSEventRegistrationGeneration,
            DarwinFSEventNativeOwnerStartCompletion
        )
        case performAcceptingPublication(
            DarwinFSEventRegistrationGeneration,
            DarwinFSEventNativeOwnerStartCompletion
        )
        case wait(DarwinFSEventNativeOwnerStartCompletion)
        case completed(DarwinFSEventNativeOwnerStartResult)
        case rejected(DarwinFSEventNativeOwnerAuthorityRejection)
    }

    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime

    private let lifecyclePort: FilesystemObservationNativeLifecyclePort
    private let stateCondition = NSCondition()
    private var state = State.creationAvailable
    private var nativeFinalizationState = NativeFinalizationState.awaitingMaterialization
    private let fleetShutdownAdvanceCoordinator =
        DarwinFSEventNativeOwnerShutdownAdvanceCoordinator()

    var nativeFinalizationSnapshot: DarwinFSEventNativeFinalizationSnapshot {
        stateCondition.withLock {
            switch nativeFinalizationState {
            case .awaitingMaterialization, .retainedContext, .retirementPermitRetained,
                .finalizing:
                return .pending
            case .finalized(let acknowledgement):
                return .finalized(acknowledgement)
            }
        }
    }

    var fleetShutdownProjection: DarwinFSEventNativeOwnerFleetShutdownProjection {
        stateCondition.withLock {
            DarwinFSEventNativeOwnerFleetShutdownProjection(
                binding: startingNativeLifetime.binding,
                nativePhase: fleetShutdownNativePhase,
                finalizationPhase: fleetShutdownFinalizationPhase,
                advancePhase: fleetShutdownAdvancePhase
            )
        }
    }

    init(
        startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        lifecyclePort: FilesystemObservationNativeLifecyclePort
    ) {
        self.startingNativeLifetime = startingNativeLifetime
        self.lifecyclePort = lifecyclePort
    }

    func createOrReplay(
        controlBlock: FSEventRegistrationControlBlock,
        adapter: any DarwinFSEventRegistrationCallbackAdapter,
        nativeDriver: any DarwinFSEventNativeDriver = DarwinFSEventSystemNativeDriver(),
        callbackQueueBarrier: any DarwinFSEventCallbackQueueBarrier =
            DarwinFSEventAsyncCallbackQueueBarrier()
    ) -> DarwinFSEventNativeOwnerCreationResult {
        if let rejection = authorityRejection(controlBlock: controlBlock, adapter: adapter) {
            return .authorityRejected(rejection)
        }

        stateCondition.lock()
        while case .creating = state {
            stateCondition.wait()
        }
        switch state {
        case .creationAvailable:
            state = .creating
            stateCondition.unlock()
        case .creating:
            preconditionFailure("native creation wait must resolve before state selection")
        case .created(let generation):
            stateCondition.unlock()
            return .created(generation)
        case .starting(let generation, _), .abandoningStart(let generation, _),
            .publishingAcceptance(let generation, _),
            .acceptingPublicationPending(let generation, _),
            .startCompleted(let generation, _):
            stateCondition.unlock()
            return .created(generation)
        case .creationRejected(let cleanup, _):
            stateCondition.unlock()
            return .creationRejected(cleanup)
        case .creationAbandoned(let abandonment):
            stateCondition.unlock()
            return .creationAbandoned(abandonment)
        }

        let completion = createNativeGeneration(
            controlBlock: controlBlock,
            adapter: adapter,
            nativeDriver: nativeDriver,
            callbackQueueBarrier: callbackQueueBarrier
        )
        stateCondition.lock()
        let result: DarwinFSEventNativeOwnerCreationResult
        switch completion {
        case .created(let generation, let callbackContextCustody):
            state = .created(generation)
            nativeFinalizationState = .retainedContext(callbackContextCustody)
            result = .created(generation)
        case .rejected(let cleanup, let callbackContextCustody):
            state = .creationRejected(cleanup, callbackContextCustody)
            nativeFinalizationState = .retainedContext(callbackContextCustody)
            result = .creationRejected(cleanup)
        }
        stateCondition.broadcast()
        stateCondition.unlock()
        return result
    }

    func abandonCreation() -> DarwinFSEventNativeOwnerCreationResult {
        stateCondition.lock()
        while case .creating = state {
            stateCondition.wait()
        }
        let result: DarwinFSEventNativeOwnerCreationResult
        switch state {
        case .creationAvailable:
            let abandonment = DarwinFSEventRegistrationCreationAbandonment(
                startingNativeLifetime: startingNativeLifetime
            )
            state = .creationAbandoned(abandonment)
            result = .creationAbandoned(abandonment)
        case .creating:
            preconditionFailure("native creation wait must resolve before abandonment")
        case .created(let generation):
            result = .created(generation)
        case .starting(let generation, _), .abandoningStart(let generation, _),
            .publishingAcceptance(let generation, _),
            .acceptingPublicationPending(let generation, _),
            .startCompleted(let generation, _):
            result = .created(generation)
        case .creationRejected(let cleanup, _):
            result = .creationRejected(cleanup)
        case .creationAbandoned(let abandonment):
            result = .creationAbandoned(abandonment)
        }
        stateCondition.unlock()
        return result
    }

    func startOrReplay(
        creation: DarwinFSEventRegistrationGeneration
    ) async -> DarwinFSEventNativeOwnerStartResult {
        await consumeStartRight(creation: creation, intent: .start)
    }

    func abandonStartAfterCreate(
        creation: DarwinFSEventRegistrationGeneration
    ) async -> DarwinFSEventNativeOwnerStartResult {
        await consumeStartRight(creation: creation, intent: .abandon)
    }

    /// Advances this owner's already-held native rights toward whole-fleet shutdown.
    ///
    /// This operation deliberately stops at native quiescence. Retirement permits, context
    /// finalization, registry mutation, and shutdown identity remain with their existing owners.
    func advanceFleetShutdown() async -> DarwinFSEventNativeOwnerFleetShutdownResult {
        switch fleetShutdownAdvanceCoordinator.claim() {
        case .perform(let completion):
            let result = await performFleetShutdownAdvance()
            fleetShutdownAdvanceCoordinator.publish(result, for: completion)
            return result
        case .wait(let completion):
            return await completion.wait()
        case .completed(let completed):
            return .completed(completed)
        }
    }

    func finalizeNativeLifetime(
        using permit: FilesystemObservationNativeRetirementPermit,
        contextFinalizer: any DarwinFSEventCallbackContextFinalizer =
            DarwinFSEventUnmanagedCallbackContextFinalizer()
    ) -> FilesystemObservationNativeFinalizationResult {
        let action = claimNativeFinalizationAction(using: permit)
        switch action {
        case .recordNeverMaterialized:
            return retainNativeFinalizationAcknowledgement(
                makeNeverMaterializedAcknowledgement(for: permit),
                permit: permit
            )
        case .releaseRetainedContext(let callbackContextCustody):
            contextFinalizer.releaseRetainedContext(
                at: callbackContextCustody.retainedPointerAddress
            )
            return retainNativeFinalizationAcknowledgement(
                makeReleasedContextAcknowledgement(for: permit),
                permit: permit
            )
        case .replay(let acknowledgement):
            return .alreadyFinalized(acknowledgement)
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    func retainRetirementPermit(
        _ permit: FilesystemObservationNativeRetirementPermit
    ) -> DarwinFSEventNativeRetirementPermitRetentionResult {
        let expectedBinding = startingNativeLifetime.binding
        guard permit.binding == expectedBinding else {
            return .bindingMismatch(expected: expectedBinding, presented: permit.binding)
        }

        stateCondition.lock()
        defer { stateCondition.unlock() }
        switch nativeFinalizationState {
        case .awaitingMaterialization:
            guard nativeFinalizationMatchesTerminalState(permit) else {
                return permitRetentionRejection()
            }
            nativeFinalizationState = .retirementPermitRetained(permit, .neverMaterialized)
            return .retained
        case .retainedContext(let callbackContextCustody):
            guard nativeFinalizationMatchesTerminalState(permit) else {
                return permitRetentionRejection()
            }
            nativeFinalizationState = .retirementPermitRetained(
                permit,
                .retainedContext(callbackContextCustody)
            )
            return .retained
        case .retirementPermitRetained(let retainedPermit, _),
            .finalizing(let retainedPermit, _):
            return retainedPermit == permit ? .alreadyRetained : .permitLineageMismatch
        case .finalized(let acknowledgement):
            return acknowledgement.permit == permit ? .alreadyRetained : .permitLineageMismatch
        }
    }

    func matchesUnpublishedCompletion(
        _ completion: DarwinFSEventUnpublishedNativeCompletion
    ) -> Bool {
        stateCondition.withLock {
            guard completion.startingNativeLifetime == startingNativeLifetime else {
                return false
            }
            return retainedUnpublishedCompletionMatches(completion)
        }
    }

    private func performFleetShutdownAdvance()
        async -> DarwinFSEventNativeOwnerFleetShutdownResult
    {
        switch abandonCreation() {
        case .creationAbandoned(let abandonment):
            return .completed(.unpublished(.creationAbandoned(abandonment)))
        case .creationRejected(let cleanup):
            return .completed(.unpublished(.creationRejected(cleanup)))
        case .created(let generation):
            return await advanceCreatedGenerationTowardFleetShutdown(generation)
        case .authorityRejected:
            preconditionFailure("owner-local creation abandonment cannot reject its own authority")
        }
    }

    private func advanceCreatedGenerationTowardFleetShutdown(
        _ generation: DarwinFSEventRegistrationGeneration
    ) async -> DarwinFSEventNativeOwnerFleetShutdownResult {
        switch await consumeStartRight(creation: generation, intent: .abandon) {
        case .started:
            return await closeAcceptingGenerationForFleetShutdown(generation)
        case .unpublished(let quiescence):
            return .completed(.unpublished(projectUnpublishedCompletion(quiescence)))
        case .acceptingPublicationRejected(let rejection):
            return .incomplete(.acceptingPublicationPending(rejection))
        case .authorityRejected(let rejection):
            return .incomplete(
                .nativeAuthorityRejected(rejection, generationPhase: generation.phase)
            )
        case .lifecycleRejected(let rejection):
            return .incomplete(
                .nativeLifecycleRejected(rejection, generationPhase: generation.phase)
            )
        }
    }

    private func closeAcceptingGenerationForFleetShutdown(
        _ generation: DarwinFSEventRegistrationGeneration
    ) async -> DarwinFSEventNativeOwnerFleetShutdownResult {
        switch await generation.close() {
        case .closed(let receipt):
            return .completed(.acceptingGenerationClosed(receipt))
        case .startFailed:
            return .incomplete(
                .nativeLifecycleRejected(
                    .generationPhase(.startFailed),
                    generationPhase: generation.phase
                )
            )
        case .mailboxRejected(let rejection):
            return .incomplete(
                .nativeLifecycleRejected(
                    .mailboxClosing(rejection),
                    generationPhase: generation.phase
                )
            )
        case .alreadyClosing:
            return .incomplete(
                .nativeLifecycleRejected(
                    .closeAlreadyInProgress,
                    generationPhase: generation.phase
                )
            )
        }
    }

    private func projectUnpublishedCompletion(
        _ quiescence: DarwinFSEventUnpublishedQuiescence
    ) -> DarwinFSEventUnpublishedNativeCompletion {
        switch quiescence {
        case .createdNeverStartedClosed(let completion):
            return .createdNeverStartedClosed(completion)
        case .startRejectedAfterDrain(let completion):
            return .startRejectedAfterDrain(completion)
        }
    }

    private var fleetShutdownNativePhase: DarwinFSEventNativeOwnerFleetShutdownNativePhase {
        switch state {
        case .creationAvailable:
            return .creationAvailable(startingNativeLifetime)
        case .creating:
            return .creating(startingNativeLifetime)
        case .created(let generation):
            return .created(startingNativeLifetime, generationPhase: generation.phase)
        case .creationRejected(let cleanup, _):
            return .creationRejected(cleanup)
        case .creationAbandoned(let abandonment):
            return .creationAbandoned(abandonment)
        case .starting(let generation, _):
            return .starting(startingNativeLifetime, generationPhase: generation.phase)
        case .abandoningStart(let generation, _):
            return .abandoningStart(startingNativeLifetime, generationPhase: generation.phase)
        case .publishingAcceptance(let generation, _):
            return .publishingAcceptance(
                startingNativeLifetime,
                generationPhase: generation.phase
            )
        case .acceptingPublicationPending(let generation, let rejection):
            return .acceptingPublicationPending(
                startingNativeLifetime,
                rejection,
                generationPhase: generation.phase
            )
        case .startCompleted(let generation, let result):
            return fleetShutdownCompletedStartPhase(result, generation: generation)
        }
    }

    private func fleetShutdownCompletedStartPhase(
        _ result: DarwinFSEventNativeOwnerStartResult,
        generation: DarwinFSEventRegistrationGeneration
    ) -> DarwinFSEventNativeOwnerFleetShutdownNativePhase {
        switch result {
        case .started(let acceptingNativeLifetime):
            return .accepting(
                acceptingNativeLifetime,
                generationPhase: generation.phase
            )
        case .unpublished(let quiescence):
            return .unpublished(projectUnpublishedCompletion(quiescence))
        case .acceptingPublicationRejected(let rejection):
            return .acceptingPublicationPending(
                startingNativeLifetime,
                rejection,
                generationPhase: generation.phase
            )
        case .authorityRejected(let rejection):
            return .authorityRejected(
                startingNativeLifetime,
                rejection,
                generationPhase: generation.phase
            )
        case .lifecycleRejected(let rejection):
            return .lifecycleRejected(
                startingNativeLifetime,
                rejection,
                generationPhase: generation.phase
            )
        }
    }

    private var fleetShutdownFinalizationPhase: DarwinNativeFleetShutdownFinalizationPhase {
        switch nativeFinalizationState {
        case .awaitingMaterialization:
            return .awaitingMaterialization
        case .retainedContext:
            return .retainedContext
        case .retirementPermitRetained(let permit, _):
            return .retirementPermitRetained(permit)
        case .finalizing(let permit, _):
            return .finalizing(permit)
        case .finalized(let acknowledgement):
            return .finalized(acknowledgement)
        }
    }

    private var fleetShutdownAdvancePhase: DarwinFSEventNativeOwnerFleetShutdownAdvancePhase {
        fleetShutdownAdvanceCoordinator.phase
    }

    private func consumeStartRight(
        creation: DarwinFSEventRegistrationGeneration,
        intent: StartIntent
    ) async -> DarwinFSEventNativeOwnerStartResult {
        switch claimStartAction(creation: creation, intent: intent) {
        case .performStart(let generation, let completion):
            let result = await performStart(generation: generation)
            retainStartCompletion(generation: generation, completion: completion, result: result)
            return result
        case .performAbandonment(let generation, let completion):
            let result = await performStartAbandonment(generation: generation)
            retainStartCompletion(generation: generation, completion: completion, result: result)
            return result
        case .performAcceptingPublication(let generation, let completion):
            let result = projectStartResult(generation.retryAcceptingPublication())
            retainStartCompletion(generation: generation, completion: completion, result: result)
            return result
        case .wait(let completion):
            return await completion.wait()
        case .completed(let result):
            return result
        case .rejected(let rejection):
            return .authorityRejected(rejection)
        }
    }

    private func claimStartAction(
        creation: DarwinFSEventRegistrationGeneration,
        intent: StartIntent
    ) -> StartAction {
        let presentedStartingNativeLifetime = creation.startingNativeLifetime
        let expectedBinding = startingNativeLifetime.binding
        let presentedBinding = presentedStartingNativeLifetime.binding
        guard presentedBinding == expectedBinding else {
            return .rejected(
                .bindingMismatch(expected: expectedBinding, presented: presentedBinding)
            )
        }
        guard presentedStartingNativeLifetime == startingNativeLifetime else {
            return .rejected(
                .creationCompletionMismatch(
                    expected: startingNativeLifetime,
                    presented: presentedStartingNativeLifetime
                )
            )
        }

        stateCondition.lock()
        defer { stateCondition.unlock() }
        switch state {
        case .created(let retainedCreation):
            guard retainedCreation === creation else {
                return .rejected(
                    .creationCompletionMismatch(
                        expected: startingNativeLifetime,
                        presented: presentedStartingNativeLifetime
                    )
                )
            }
            let completion = DarwinFSEventNativeOwnerStartCompletion()
            switch intent {
            case .start:
                state = .starting(creation, completion)
                return .performStart(creation, completion)
            case .abandon:
                state = .abandoningStart(creation, completion)
                return .performAbandonment(creation, completion)
            }
        case .starting(let retainedCreation, let completion),
            .abandoningStart(let retainedCreation, let completion),
            .publishingAcceptance(let retainedCreation, let completion):
            guard retainedCreation === creation else {
                return .rejected(
                    .creationCompletionMismatch(
                        expected: startingNativeLifetime,
                        presented: presentedStartingNativeLifetime
                    )
                )
            }
            return .wait(completion)
        case .acceptingPublicationPending(let retainedCreation, _):
            guard retainedCreation === creation else {
                return .rejected(
                    .creationCompletionMismatch(
                        expected: startingNativeLifetime,
                        presented: presentedStartingNativeLifetime
                    )
                )
            }
            let completion = DarwinFSEventNativeOwnerStartCompletion()
            state = .publishingAcceptance(creation, completion)
            return .performAcceptingPublication(creation, completion)
        case .startCompleted(let retainedCreation, let result):
            guard retainedCreation === creation else {
                return .rejected(
                    .creationCompletionMismatch(
                        expected: startingNativeLifetime,
                        presented: presentedStartingNativeLifetime
                    )
                )
            }
            return .completed(result)
        case .creationAvailable, .creating, .creationRejected, .creationAbandoned:
            return .rejected(.creationRightUnavailable(startingNativeLifetime))
        }
    }

    private func performStart(
        generation: DarwinFSEventRegistrationGeneration
    ) async -> DarwinFSEventNativeOwnerStartResult {
        projectStartResult(await generation.start())
    }

    private func projectStartResult(
        _ generationResult: DarwinFSEventRegistrationGenerationStartResult
    ) -> DarwinFSEventNativeOwnerStartResult {
        switch generationResult {
        case .started(let acceptingNativeLifetime):
            return .started(acceptingNativeLifetime)
        case .failed(let cleanup):
            return .unpublished(
                .startRejectedAfterDrain(
                    DarwinFSEventStartRejectedQuiescence(
                        startingNativeLifetime: startingNativeLifetime,
                        cleanup: cleanup
                    )
                )
            )
        case .acceptingPublicationRejected(let rejection):
            return .acceptingPublicationRejected(rejection)
        case .invalidPhase(let phase):
            return .lifecycleRejected(.generationPhase(phase))
        }
    }

    private func performStartAbandonment(
        generation: DarwinFSEventRegistrationGeneration
    ) async -> DarwinFSEventNativeOwnerStartResult {
        switch await generation.close() {
        case .closed:
            return .unpublished(
                .createdNeverStartedClosed(
                    DarwinFSEventCreatedNeverStartedQuiescence(
                        startingNativeLifetime: startingNativeLifetime
                    )
                )
            )
        case .startFailed(let cleanup):
            return .unpublished(
                .startRejectedAfterDrain(
                    DarwinFSEventStartRejectedQuiescence(
                        startingNativeLifetime: startingNativeLifetime,
                        cleanup: cleanup
                    )
                )
            )
        case .mailboxRejected(let rejection):
            return .lifecycleRejected(.mailboxClosing(rejection))
        case .alreadyClosing:
            return .lifecycleRejected(.closeAlreadyInProgress)
        }
    }

    private func retainStartCompletion(
        generation: DarwinFSEventRegistrationGeneration,
        completion: DarwinFSEventNativeOwnerStartCompletion,
        result: DarwinFSEventNativeOwnerStartResult
    ) {
        stateCondition.lock()
        switch state {
        case .starting(let retainedGeneration, let retainedCompletion),
            .abandoningStart(let retainedGeneration, let retainedCompletion),
            .publishingAcceptance(let retainedGeneration, let retainedCompletion):
            precondition(
                retainedGeneration === generation && retainedCompletion === completion,
                "native owner must complete the exact claimed start right"
            )
            switch result {
            case .acceptingPublicationRejected(let rejection):
                state = .acceptingPublicationPending(generation, rejection)
            case .started, .unpublished, .authorityRejected, .lifecycleRejected:
                state = .startCompleted(generation, result)
            }
        case .creationAvailable, .creating, .created, .creationRejected, .creationAbandoned,
            .acceptingPublicationPending, .startCompleted:
            preconditionFailure("native owner start completion requires an in-flight claim")
        }
        stateCondition.unlock()
        completion.resolve(result)
    }

    private func claimNativeFinalizationAction(
        using permit: FilesystemObservationNativeRetirementPermit
    ) -> NativeFinalizationAction {
        let expectedBinding = startingNativeLifetime.binding
        guard permit.binding == expectedBinding else {
            return .rejected(
                .bindingMismatch(expected: expectedBinding, presented: permit.binding)
            )
        }

        stateCondition.lock()
        defer { stateCondition.unlock() }
        while true {
            switch nativeFinalizationState {
            case .finalizing(let claimedPermit, _):
                guard claimedPermit == permit else {
                    return .rejected(.permitLineageMismatch)
                }
                stateCondition.wait()
            case .finalized(let acknowledgement):
                guard acknowledgement.permit == permit else {
                    return .rejected(.permitLineageMismatch)
                }
                return .replay(acknowledgement)
            case .retirementPermitRetained(let retainedPermit, let materialization):
                guard retainedPermit == permit else {
                    return .rejected(.permitLineageMismatch)
                }
                nativeFinalizationState = .finalizing(permit, materialization)
                switch materialization {
                case .neverMaterialized:
                    return .recordNeverMaterialized
                case .retainedContext(let callbackContextCustody):
                    return .releaseRetainedContext(callbackContextCustody)
                }
            case .awaitingMaterialization, .retainedContext:
                return nativeFinalizationRejection(for: permit)
            }
        }
    }

    private func nativeFinalizationMatchesTerminalState(
        _ permit: FilesystemObservationNativeRetirementPermit
    ) -> Bool {
        switch permit {
        case .unpublished(let receipt):
            return receipt.startingNativeLifetime == startingNativeLifetime
                && retainedUnpublishedCompletionMatches(receipt.completion)
        case .fenceBacked(let receipt):
            guard
                case .startCompleted(
                    let retainedGeneration,
                    .started(let acceptingNativeLifetime)
                ) = state
            else {
                return false
            }
            return acceptingNativeLifetime.startingNativeLifetime == startingNativeLifetime
                && receipt.binding == acceptingNativeLifetime.binding
                && retainedGeneration.phase == .closed
        }
    }

    private func retainedUnpublishedCompletionMatches(
        _ presentedCompletion: DarwinFSEventUnpublishedNativeCompletion
    ) -> Bool {
        switch (state, presentedCompletion) {
        case (
            .creationAbandoned(let retainedAbandonment),
            .creationAbandoned(let presentedAbandonment)
        ):
            return presentedAbandonment === retainedAbandonment
        case (
            .creationRejected(let retainedCleanup, _),
            .creationRejected(let presentedCleanup)
        ):
            return presentedCleanup === retainedCleanup
        case (
            .startCompleted(_, .unpublished(.createdNeverStartedClosed(let retainedQuiescence))),
            .createdNeverStartedClosed(let presentedQuiescence)
        ):
            return presentedQuiescence === retainedQuiescence
        case (
            .startCompleted(_, .unpublished(.startRejectedAfterDrain(let retainedQuiescence))),
            .startRejectedAfterDrain(let presentedQuiescence)
        ):
            return presentedQuiescence === retainedQuiescence
        case (.creationAvailable, _), (.creating, _), (.created, _), (.starting, _),
            (.abandoningStart, _), (.publishingAcceptance, _),
            (.acceptingPublicationPending, _), (.startCompleted, _),
            (.creationRejected, _), (.creationAbandoned, _):
            return false
        }
    }

    private func nativeFinalizationRejection(
        for _: FilesystemObservationNativeRetirementPermit
    ) -> NativeFinalizationAction {
        nativeLifetimeIsFinal
            ? .rejected(.permitLineageMismatch)
            : .rejected(.nativeLifetimeNotFinal)
    }

    private func permitRetentionRejection()
        -> DarwinFSEventNativeRetirementPermitRetentionResult
    {
        nativeLifetimeIsFinal ? .permitLineageMismatch : .nativeLifetimeNotFinal
    }

    private var nativeLifetimeIsFinal: Bool {
        switch state {
        case .creationRejected, .creationAbandoned, .startCompleted(_, .unpublished):
            return true
        case .startCompleted(let retainedGeneration, .started):
            return retainedGeneration.phase == .closed
        case .creationAvailable, .creating, .created, .starting, .abandoningStart,
            .publishingAcceptance, .acceptingPublicationPending, .startCompleted:
            return false
        }
    }

    private func makeReleasedContextAcknowledgement(
        for permit: FilesystemObservationNativeRetirementPermit
    ) -> FilesystemObservationContextReleaseAcknowledgement {
        let finalization = FilesystemObservationReleasedContextFinalization(
            startingNativeLifetime: startingNativeLifetime
        )
        let releaseAuthority = FilesystemObservationContextReleaseAuthority(
            value: UUIDv7.generate()
        )
        switch permit {
        case .fenceBacked(let receipt):
            return .fenceBacked(
                FilesystemFenceContextReleaseAcknowledgement(
                    receipt: receipt,
                    finalization: finalization,
                    releaseAuthority: releaseAuthority
                )
            )
        case .unpublished(let receipt):
            return .unpublished(
                .releasedRetainedContext(
                    receipt: receipt,
                    finalization: finalization,
                    releaseAuthority: releaseAuthority
                )
            )
        }
    }

    private func makeNeverMaterializedAcknowledgement(
        for permit: FilesystemObservationNativeRetirementPermit
    ) -> FilesystemObservationContextReleaseAcknowledgement {
        guard case .unpublished(let receipt) = permit,
            receipt.completion.finalizationKind == .neverMaterialized
        else {
            preconditionFailure("never-materialized finalization requires creation abandonment")
        }
        return .unpublished(
            .neverMaterialized(
                receipt: receipt,
                finalization: FilesystemObservationNeverMaterializedFinalization(
                    startingNativeLifetime: startingNativeLifetime
                ),
                releaseAuthority: FilesystemObservationContextReleaseAuthority(
                    value: UUIDv7.generate()
                )
            )
        )
    }

    private func retainNativeFinalizationAcknowledgement(
        _ acknowledgement: FilesystemObservationContextReleaseAcknowledgement,
        permit: FilesystemObservationNativeRetirementPermit
    ) -> FilesystemObservationNativeFinalizationResult {
        stateCondition.lock()
        guard case .finalizing(let claimedPermit, _) = nativeFinalizationState,
            claimedPermit == permit
        else {
            stateCondition.unlock()
            preconditionFailure("native finalization must complete the exact claimed permit")
        }
        nativeFinalizationState = .finalized(acknowledgement)
        stateCondition.broadcast()
        stateCondition.unlock()
        return .finalized(acknowledgement)
    }

    private func authorityRejection(
        controlBlock: FSEventRegistrationControlBlock,
        adapter: any DarwinFSEventRegistrationCallbackAdapter
    ) -> DarwinFSEventNativeOwnerAuthorityRejection? {
        let expectedBinding = startingNativeLifetime.binding
        let presentedStartingNativeLifetime = controlBlock.startingNativeLifetime
        let presentedBinding = presentedStartingNativeLifetime.binding
        guard presentedBinding == expectedBinding else {
            return .bindingMismatch(expected: expectedBinding, presented: presentedBinding)
        }
        guard presentedStartingNativeLifetime == startingNativeLifetime else {
            return .startingNativeLifetimeMismatch(
                expected: startingNativeLifetime,
                presented: presentedStartingNativeLifetime
            )
        }
        guard adapter.controlBlock === controlBlock else {
            return .callbackAdapterControlBlockMismatch(
                expected: expectedBinding.controlBlockIdentity,
                presented: adapter.controlBlock.startingNativeLifetime.binding.controlBlockIdentity
            )
        }
        return nil
    }

    private func createNativeGeneration(
        controlBlock: FSEventRegistrationControlBlock,
        adapter: any DarwinFSEventRegistrationCallbackAdapter,
        nativeDriver: any DarwinFSEventNativeDriver,
        callbackQueueBarrier: any DarwinFSEventCallbackQueueBarrier
    ) -> CreationCompletion {
        let callbackContext = DarwinFSEventRegistrationCallbackContext(
            registration: startingNativeLifetime.binding.registration,
            adapter: adapter
        )
        let callbackContextPointer = Unmanaged.passRetained(callbackContext).toOpaque()
        let callbackContextCustody = DarwinFSEventCallbackContextCustody(
            pointer: callbackContextPointer
        )
        let callbackQueue = controlBlock.callbackQueue
        let request = DarwinFSEventNativeStreamCreationRequest(
            resolvedRootPath: controlBlock.watchRoot.resolvedPath,
            callbackQueue: callbackQueue,
            callback: Self.callback,
            callbackContextPointer: callbackContextPointer
        )
        switch nativeDriver.createStream(request: request) {
        case .success(let stream):
            let generation = DarwinFSEventRegistrationGeneration(
                startingNativeLifetime: startingNativeLifetime,
                controlBlock: controlBlock,
                lifecyclePort: lifecyclePort,
                nativeDriver: nativeDriver,
                callbackQueueBarrier: callbackQueueBarrier,
                nativeCustody: DarwinFSEventRegistrationGeneration.NativeCustody(
                    stream: stream,
                    callbackQueue: callbackQueue,
                    callbackContextCustody: callbackContextCustody
                )
            )
            return .created(generation, callbackContextCustody)
        case .failure(let nativeFailure):
            return .rejected(
                DarwinFSEventRegistrationCreateFailureCleanup(
                    startingNativeLifetime: startingNativeLifetime,
                    nativeFailure: nativeFailure
                ),
                callbackContextCustody
            )
        }
    }

    // The imported C callback signature cannot be wrapped without hiding its ABI shape.
    // swiftlint:disable closure_parameter_position
    private static let callback: FSEventStreamCallback = {
        _, callbackContextPointer, eventCount, eventPaths, eventFlags, eventIDs in
        guard let callbackContextPointer else { return }
        let callbackContext = Unmanaged<DarwinFSEventRegistrationCallbackContext>
            .fromOpaque(callbackContextPointer)
            .takeUnretainedValue()
        let eventFlagsBuffer = UnsafeBufferPointer(
            start: eventFlags,
            count: Int(eventCount)
        )
        let eventIDsBuffer = UnsafeBufferPointer(
            start: eventIDs,
            count: Int(eventCount)
        )
        _ = callbackContext.adapter.capture(
            input: DarwinFSEventNativeCallbackInput(
                capturedAt: ContinuousClock().now,
                reportedEventCount: Int(eventCount),
                eventPaths: eventPaths,
                eventFlags: eventFlagsBuffer,
                eventIDs: eventIDsBuffer
            )
        )
    }
    // swiftlint:enable closure_parameter_position
}

final class DarwinFSEventCallbackContextCustody: @unchecked Sendable {
    let retainedPointerAddress: UInt

    init(pointer: UnsafeMutableRawPointer) {
        retainedPointerAddress = UInt(bitPattern: pointer)
    }
}

final class DarwinFSEventRegistrationCallbackContext: @unchecked Sendable {
    let registration: FSEventRegistrationToken
    let adapter: any DarwinFSEventRegistrationCallbackAdapter

    init(
        registration: FSEventRegistrationToken,
        adapter: any DarwinFSEventRegistrationCallbackAdapter
    ) {
        self.registration = registration
        self.adapter = adapter
    }
}

private final class DarwinFSEventNativeOwnerStartCompletion: @unchecked Sendable {
    private typealias Waiter = CheckedContinuation<DarwinFSEventNativeOwnerStartResult, Never>

    private enum State: Sendable {
        case pending([Waiter])
        case completed(DarwinFSEventNativeOwnerStartResult)
    }

    private let lock = OSAllocatedUnfairLock(initialState: State.pending([]))

    func wait() async -> DarwinFSEventNativeOwnerStartResult {
        await withCheckedContinuation { continuation in
            let completedResult: DarwinFSEventNativeOwnerStartResult? = lock.withLock { state in
                switch state {
                case .pending(var waiters):
                    waiters.append(continuation)
                    state = .pending(waiters)
                    return nil
                case .completed(let result):
                    return result
                }
            }
            if let completedResult {
                continuation.resume(returning: completedResult)
            }
        }
    }

    func resolve(_ result: DarwinFSEventNativeOwnerStartResult) {
        let waiters = lock.withLock { state -> [Waiter] in
            switch state {
            case .pending(let waiters):
                state = .completed(result)
                return waiters
            case .completed:
                preconditionFailure("native owner start completion resolves exactly once")
            }
        }
        for waiter in waiters {
            waiter.resume(returning: result)
        }
    }
}
