import Dispatch
import Foundation
import os

/// The callback operation owned by one dormant native generation.
///
/// Mailbox construction authority stays with the mailbox. The generation receives only
/// the already-paired adapter and retains it through its callback context.
protocol DarwinFSEventRegistrationCallbackAdapter: AnyObject, Sendable {
    var controlBlock: FSEventRegistrationControlBlock { get }

    func capture(
        input: DarwinFSEventNativeCallbackInput
    ) -> DarwinFSEventObservationCaptureResult
}

extension DarwinFSEventObservationAdapter: DarwinFSEventRegistrationCallbackAdapter {}

final class DarwinFSEventRegistrationLeaseDrainReceipt: @unchecked Sendable, Equatable {
    let binding: FilesystemObservationSlotBinding
    let nativeGenerationIdentity: FilesystemObservationNativeGenerationIdentity
    let controlBlockIdentity: FilesystemObservationControlBlockIdentity

    fileprivate init(
        binding: FilesystemObservationSlotBinding,
        nativeGenerationIdentity: FilesystemObservationNativeGenerationIdentity
    ) {
        self.binding = binding
        self.nativeGenerationIdentity = nativeGenerationIdentity
        controlBlockIdentity = binding.controlBlockIdentity
    }

    static func == (
        lhs: DarwinFSEventRegistrationLeaseDrainReceipt,
        rhs: DarwinFSEventRegistrationLeaseDrainReceipt
    ) -> Bool {
        lhs === rhs
    }

}

final class DarwinFSEventRegistrationCreateFailureCleanup: @unchecked Sendable, Equatable {
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let nativeFailure: DarwinFSEventNativeStreamCreationFailure

    init(
        startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        nativeFailure: DarwinFSEventNativeStreamCreationFailure
    ) {
        self.startingNativeLifetime = startingNativeLifetime
        self.nativeFailure = nativeFailure
    }

    static func == (
        lhs: DarwinFSEventRegistrationCreateFailureCleanup,
        rhs: DarwinFSEventRegistrationCreateFailureCleanup
    ) -> Bool {
        lhs === rhs
    }
}

final class DarwinFSEventRegistrationStartFailureCleanup: @unchecked Sendable, Equatable {
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let binding: FilesystemObservationSlotBinding
    let nativeGenerationIdentity: FilesystemObservationNativeGenerationIdentity
    let controlBlockIdentity: FilesystemObservationControlBlockIdentity
    fileprivate init(startingNativeLifetime: FilesystemObservationStartingNativeLifetime) {
        self.startingNativeLifetime = startingNativeLifetime
        binding = startingNativeLifetime.binding
        nativeGenerationIdentity = startingNativeLifetime.nativeGenerationIdentity
        controlBlockIdentity = startingNativeLifetime.binding.controlBlockIdentity
    }

    static func == (
        lhs: DarwinFSEventRegistrationStartFailureCleanup,
        rhs: DarwinFSEventRegistrationStartFailureCleanup
    ) -> Bool {
        lhs === rhs
    }
}

enum DarwinFSEventRegistrationGenerationStartResult: Sendable {
    case started(FilesystemObservationAcceptingNativeLifetime)
    case failed(DarwinFSEventRegistrationStartFailureCleanup)
    case acceptingPublicationRejected(FilesystemObservationAcceptingPublicationResult)
    case invalidPhase(DarwinFSEventRegistrationGenerationPhase)
}

enum DarwinFSEventRegistrationGenerationCloseResult: Sendable {
    case closed(DarwinFSEventRegistrationLeaseDrainReceipt)
    case startFailed(DarwinFSEventRegistrationStartFailureCleanup)
    case mailboxRejected(FilesystemObservationCallbackLeaseDrainClosingResult)
    case alreadyClosing
}

enum DarwinFSEventRegistrationGenerationPhase: Equatable, Sendable {
    case created
    case starting
    case startingCloseRequested
    case started
    case startedAwaitingAcceptingPublication
    case closingCreatedStream
    case closingStartedStream
    case closed
    case startFailureDraining
    case startFailed
}

private enum DarwinFSEventRegistrationStartCompletionOutcome: Sendable {
    case accepting(FilesystemObservationAcceptingNativeLifetime)
    case failed(DarwinFSEventRegistrationStartFailureCleanup)
    case acceptingPublicationRejected(FilesystemObservationAcceptingPublicationResult)
}

private final class DarwinFSEventRegistrationStartCompletion: @unchecked Sendable {
    private typealias Outcome = DarwinFSEventRegistrationStartCompletionOutcome
    private typealias Waiter = CheckedContinuation<Outcome, Never>

    private enum State: Sendable {
        case pending
        case waiting(Waiter)
        case completed(Outcome)
    }

    private let lock = OSAllocatedUnfairLock(initialState: State.pending)

    func wait() async -> DarwinFSEventRegistrationStartCompletionOutcome {
        await withCheckedContinuation { continuation in
            let completedOutcome = lock.withLock { state -> Outcome? in
                switch state {
                case .pending:
                    state = .waiting(continuation)
                    return nil
                case .waiting:
                    preconditionFailure("native start supports one retained close waiter")
                case .completed(let outcome):
                    return outcome
                }
            }
            if let completedOutcome {
                continuation.resume(returning: completedOutcome)
            }
        }
    }

    func resolve(_ outcome: DarwinFSEventRegistrationStartCompletionOutcome) {
        let waiter = lock.withLock { state -> Waiter? in
            switch state {
            case .pending:
                state = .completed(outcome)
                return nil
            case .waiting(let continuation):
                state = .completed(outcome)
                return continuation
            case .completed:
                preconditionFailure("native start completion resolves exactly once")
            }
        }
        waiter?.resume(returning: outcome)
    }
}

final class DarwinFSEventRegistrationGeneration: @unchecked Sendable {
    struct NativeCustody: Sendable {
        let stream: DarwinFSEventNativeStreamHandle
        let callbackQueue: DispatchQueue
        let callbackContextCustody: DarwinFSEventCallbackContextCustody
    }

    private struct ClosedCustody: Sendable {
        let receipt: DarwinFSEventRegistrationLeaseDrainReceipt
    }

    private enum State: Sendable {
        case created(NativeCustody)
        case starting(NativeCustody, DarwinFSEventRegistrationStartCompletion)
        case startingCloseRequested(
            NativeCustody,
            DarwinFSEventRegistrationStartCompletion
        )
        case started(NativeCustody, FilesystemObservationAcceptingNativeLifetime)
        case startedAwaitingAcceptingPublication(
            NativeCustody,
            FilesystemObservationAcceptingPublicationResult
        )
        case closingCreatedStream(NativeCustody)
        case closingStartedStream(NativeCustody)
        case closed(ClosedCustody)
        case startFailureDraining(NativeCustody)
        case startFailed(DarwinFSEventRegistrationStartFailureCleanup)
    }

    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let controlBlock: FSEventRegistrationControlBlock
    private let lifecyclePort: FilesystemObservationNativeLifecyclePort
    private let nativeDriver: any DarwinFSEventNativeDriver
    private let callbackQueueBarrier: any DarwinFSEventCallbackQueueBarrier
    private let stateLock: OSAllocatedUnfairLock<State>

    init(
        startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        controlBlock: FSEventRegistrationControlBlock,
        lifecyclePort: FilesystemObservationNativeLifecyclePort,
        nativeDriver: any DarwinFSEventNativeDriver,
        callbackQueueBarrier: any DarwinFSEventCallbackQueueBarrier,
        nativeCustody: NativeCustody
    ) {
        self.startingNativeLifetime = startingNativeLifetime
        self.controlBlock = controlBlock
        self.lifecyclePort = lifecyclePort
        self.nativeDriver = nativeDriver
        self.callbackQueueBarrier = callbackQueueBarrier
        stateLock = OSAllocatedUnfairLock(initialState: .created(nativeCustody))
    }

    var phase: DarwinFSEventRegistrationGenerationPhase {
        stateLock.withLock { state in
            switch state {
            case .created: .created
            case .starting: .starting
            case .startingCloseRequested: .startingCloseRequested
            case .started: .started
            case .startedAwaitingAcceptingPublication: .startedAwaitingAcceptingPublication
            case .closingCreatedStream: .closingCreatedStream
            case .closingStartedStream: .closingStartedStream
            case .closed: .closed
            case .startFailureDraining: .startFailureDraining
            case .startFailed: .startFailed
            }
        }
    }

    func start() async -> DarwinFSEventRegistrationGenerationStartResult {
        enum StartCustodySelection {
            case created(NativeCustody, DarwinFSEventRegistrationStartCompletion)
            case invalidPhase(DarwinFSEventRegistrationGenerationPhase)
        }
        let custody: NativeCustody
        let completion: DarwinFSEventRegistrationStartCompletion
        switch stateLock.withLock({ state -> StartCustodySelection in
            switch state {
            case .created(let createdCustody):
                let completion = DarwinFSEventRegistrationStartCompletion()
                state = .starting(createdCustody, completion)
                return .created(createdCustody, completion)
            case .starting: return .invalidPhase(.starting)
            case .startingCloseRequested: return .invalidPhase(.startingCloseRequested)
            case .started: return .invalidPhase(.started)
            case .startedAwaitingAcceptingPublication:
                return .invalidPhase(.startedAwaitingAcceptingPublication)
            case .closingCreatedStream: return .invalidPhase(.closingCreatedStream)
            case .closingStartedStream: return .invalidPhase(.closingStartedStream)
            case .closed: return .invalidPhase(.closed)
            case .startFailureDraining: return .invalidPhase(.startFailureDraining)
            case .startFailed: return .invalidPhase(.startFailed)
            }
        }) {
        case .created(let createdCustody, let startCompletion):
            custody = createdCustody
            completion = startCompletion
        case .invalidPhase(let phase):
            return .invalidPhase(phase)
        }

        guard nativeDriver.startStream(custody.stream) else {
            stateLock.withLock { state in
                state = .startFailureDraining(custody)
            }
            _ = controlBlock.beginClosing()
            nativeDriver.invalidateStream(custody.stream)
            _ = controlBlock.markStreamInvalidated()
            await callbackQueueBarrier.waitForBarrier(on: custody.callbackQueue)
            _ = controlBlock.markCallbackQueueDrained()
            await controlBlock.waitUntilLeasesDrained()
            nativeDriver.releaseStream(custody.stream)
            let cleanup = DarwinFSEventRegistrationStartFailureCleanup(
                startingNativeLifetime: startingNativeLifetime
            )
            stateLock.withLock { state in
                state = .startFailed(cleanup)
            }
            completion.resolve(.failed(cleanup))
            return .failed(cleanup)
        }

        let acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
        switch lifecyclePort.publishAccepting(startingNativeLifetime) {
        case .published(let publication), .alreadyPublished(let publication):
            acceptingNativeLifetime = publication.acceptingNativeLifetime
        case let rejection:
            stateLock.withLock { state in
                state = .startedAwaitingAcceptingPublication(custody, rejection)
            }
            completion.resolve(.acceptingPublicationRejected(rejection))
            return .acceptingPublicationRejected(rejection)
        }
        stateLock.withLock { state in
            switch state {
            case .starting:
                state = .started(custody, acceptingNativeLifetime)
            case .startingCloseRequested:
                break
            case .created, .started, .closingCreatedStream, .closingStartedStream,
                .startedAwaitingAcceptingPublication, .closed, .startFailureDraining,
                .startFailed:
                preconditionFailure("native start completion requires an in-flight start state")
            }
        }
        completion.resolve(.accepting(acceptingNativeLifetime))
        return .started(acceptingNativeLifetime)
    }

    func retryAcceptingPublication() -> DarwinFSEventRegistrationGenerationStartResult {
        enum RetrySelection {
            case pending(NativeCustody)
            case started(FilesystemObservationAcceptingNativeLifetime)
            case invalidPhase(DarwinFSEventRegistrationGenerationPhase)
        }
        let custody: NativeCustody
        switch stateLock.withLock({ state -> RetrySelection in
            switch state {
            case .startedAwaitingAcceptingPublication(let retainedCustody, _):
                return .pending(retainedCustody)
            case .started(_, let acceptingNativeLifetime):
                return .started(acceptingNativeLifetime)
            case .created: return .invalidPhase(.created)
            case .starting: return .invalidPhase(.starting)
            case .startingCloseRequested: return .invalidPhase(.startingCloseRequested)
            case .closingCreatedStream: return .invalidPhase(.closingCreatedStream)
            case .closingStartedStream: return .invalidPhase(.closingStartedStream)
            case .closed: return .invalidPhase(.closed)
            case .startFailureDraining: return .invalidPhase(.startFailureDraining)
            case .startFailed: return .invalidPhase(.startFailed)
            }
        }) {
        case .pending(let retainedCustody):
            custody = retainedCustody
        case .started(let acceptingNativeLifetime):
            return .started(acceptingNativeLifetime)
        case .invalidPhase(let phase):
            return .invalidPhase(phase)
        }

        switch lifecyclePort.publishAccepting(startingNativeLifetime) {
        case .published(let publication), .alreadyPublished(let publication):
            let acceptingNativeLifetime = publication.acceptingNativeLifetime
            stateLock.withLock { state in
                guard case .startedAwaitingAcceptingPublication = state else {
                    preconditionFailure("accepting publication retry requires retained custody")
                }
                state = .started(custody, acceptingNativeLifetime)
            }
            return .started(acceptingNativeLifetime)
        case let rejection:
            stateLock.withLock { state in
                guard case .startedAwaitingAcceptingPublication = state else {
                    preconditionFailure("accepting publication retry requires retained custody")
                }
                state = .startedAwaitingAcceptingPublication(custody, rejection)
            }
            return .acceptingPublicationRejected(rejection)
        }
    }

    // The close path keeps its custody claim, native fence, and receipt minting visibly ordered.
    // swiftlint:disable:next function_body_length
    func close() async -> DarwinFSEventRegistrationGenerationCloseResult {
        enum CloseClaim {
            case claimed
            case noLongerCurrent
        }
        enum NativeCloseKind {
            case created
            case accepting(FilesystemObservationAcceptingNativeLifetime)
        }
        enum CloseCustody {
            case created(NativeCustody)
            case awaitingStart(
                NativeCustody,
                DarwinFSEventRegistrationStartCompletion
            )
            case accepting(
                NativeCustody,
                FilesystemObservationAcceptingNativeLifetime
            )
            case closed(DarwinFSEventRegistrationLeaseDrainReceipt)
            case startFailed(DarwinFSEventRegistrationStartFailureCleanup)
            case alreadyClosing
        }
        var closeCustody = stateLock.withLock { state -> CloseCustody in
            switch state {
            case .created(let custody):
                state = .closingCreatedStream(custody)
                return .created(custody)
            case .starting(let custody, let completion):
                state = .startingCloseRequested(custody, completion)
                return .awaitingStart(custody, completion)
            case .startingCloseRequested, .startFailureDraining:
                return .alreadyClosing
            case .started(let custody, let acceptingNativeLifetime):
                state = .closingStartedStream(custody)
                return .accepting(custody, acceptingNativeLifetime)
            case .startedAwaitingAcceptingPublication:
                return .alreadyClosing
            case .closingCreatedStream, .closingStartedStream:
                return .alreadyClosing
            case .startFailed(let cleanup):
                return .startFailed(cleanup)
            case .closed(let closedCustody):
                return .closed(closedCustody.receipt)
            }
        }
        if case .awaitingStart(let custody, let completion) = closeCustody {
            switch await completion.wait() {
            case .accepting(let acceptingNativeLifetime):
                let closeClaim = stateLock.withLock { state -> CloseClaim in
                    guard case .startingCloseRequested = state else {
                        return .noLongerCurrent
                    }
                    state = .closingStartedStream(custody)
                    return .claimed
                }
                guard case .claimed = closeClaim else { return .alreadyClosing }
                closeCustody = .accepting(custody, acceptingNativeLifetime)
            case .failed(let cleanup):
                return .startFailed(cleanup)
            case .acceptingPublicationRejected:
                return .alreadyClosing
            }
        }
        let custody: NativeCustody
        let nativeCloseKind: NativeCloseKind
        switch closeCustody {
        case .created(let createdCustody):
            custody = createdCustody
            nativeCloseKind = .created
        case .accepting(let startedCustody, let accepting):
            custody = startedCustody
            nativeCloseKind = .accepting(accepting)
        case .closed(let receipt):
            return .closed(receipt)
        case .startFailed(let cleanup):
            return .startFailed(cleanup)
        case .alreadyClosing:
            return .alreadyClosing
        case .awaitingStart:
            preconditionFailure("awaited start custody must resolve before native close")
        }

        switch nativeCloseKind {
        case .created:
            break
        case .accepting(let acceptingNativeLifetime):
            switch lifecyclePort
                .beginClosingAwaitingCallbackLeaseDrain(acceptingNativeLifetime)
            {
            case .transitioned, .alreadyTransitioned:
                break
            case let rejection:
                return .mailboxRejected(rejection)
            }
        }
        _ = controlBlock.beginClosing()
        if case .accepting = nativeCloseKind {
            nativeDriver.stopStream(custody.stream)
        }
        nativeDriver.invalidateStream(custody.stream)
        _ = controlBlock.markStreamInvalidated()
        await callbackQueueBarrier.waitForBarrier(on: custody.callbackQueue)
        _ = controlBlock.markCallbackQueueDrained()
        await controlBlock.waitUntilLeasesDrained()
        let receipt = DarwinFSEventRegistrationLeaseDrainReceipt(
            binding: startingNativeLifetime.binding,
            nativeGenerationIdentity: startingNativeLifetime.nativeGenerationIdentity
        )
        nativeDriver.releaseStream(custody.stream)
        stateLock.withLock { state in
            state = .closed(ClosedCustody(receipt: receipt))
        }
        return .closed(receipt)
    }
}
