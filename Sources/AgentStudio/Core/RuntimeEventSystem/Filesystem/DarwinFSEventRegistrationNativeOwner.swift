import CoreServices
import Foundation
import os

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
        case created(DarwinFSEventRegistrationGeneration)
        case rejected(
            DarwinFSEventRegistrationCreateFailureCleanup,
            DarwinFSEventCallbackContextCustody
        )
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
        case .created(let generation):
            state = .created(generation)
            result = .created(generation)
        case .rejected(let cleanup, let callbackContextCustody):
            state = .creationRejected(cleanup, callbackContextCustody)
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
            return .created(
                DarwinFSEventRegistrationGeneration(
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
            )
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
