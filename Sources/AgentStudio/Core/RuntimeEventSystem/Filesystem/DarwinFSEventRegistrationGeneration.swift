import CoreServices
import Dispatch
import Foundation
import os

enum DarwinFSEventNativeStreamCreationFailure: Error, Equatable, Sendable {
    case nativeCreateRejected
}

final class DarwinFSEventNativeStreamHandle: @unchecked Sendable {
    fileprivate enum Storage {
        case native(FSEventStreamRef)
        case test(UUID)
    }

    fileprivate let storage: Storage

    fileprivate init(storage: Storage) {
        self.storage = storage
    }

    static func testHandle(identity: UUID = UUID()) -> DarwinFSEventNativeStreamHandle {
        DarwinFSEventNativeStreamHandle(storage: .test(identity))
    }
}

struct DarwinFSEventNativeStreamCreationRequest: @unchecked Sendable {
    let resolvedRootPath: String
    let callbackQueue: DispatchQueue
    let callback: FSEventStreamCallback
    let callbackContextPointer: UnsafeMutableRawPointer
}

protocol DarwinFSEventNativeDriver: Sendable {
    func createStream(
        request: DarwinFSEventNativeStreamCreationRequest
    ) -> Result<DarwinFSEventNativeStreamHandle, DarwinFSEventNativeStreamCreationFailure>
    func startStream(_ stream: DarwinFSEventNativeStreamHandle) -> Bool
    func stopStream(_ stream: DarwinFSEventNativeStreamHandle)
    func invalidateStream(_ stream: DarwinFSEventNativeStreamHandle)
    func releaseStream(_ stream: DarwinFSEventNativeStreamHandle)
}

protocol DarwinFSEventCallbackQueueBarrier: Sendable {
    func waitForBarrier(on callbackQueue: DispatchQueue) async
}

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

struct DarwinFSEventAsyncCallbackQueueBarrier: DarwinFSEventCallbackQueueBarrier {
    func waitForBarrier(on callbackQueue: DispatchQueue) async {
        await withCheckedContinuation { continuation in
            callbackQueue.async {
                continuation.resume()
            }
        }
    }
}

struct DarwinFSEventSystemNativeDriver: DarwinFSEventNativeDriver {
    private static let latency: CFTimeInterval = 0.1

    func createStream(
        request: DarwinFSEventNativeStreamCreationRequest
    ) -> Result<DarwinFSEventNativeStreamHandle, DarwinFSEventNativeStreamCreationFailure> {
        var streamContext = FSEventStreamContext(
            version: 0,
            info: request.callbackContextPointer,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let watchPaths = [request.resolvedRootPath as NSString] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes
        )
        guard
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                request.callback,
                &streamContext,
                watchPaths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                Self.latency,
                flags
            )
        else {
            return .failure(.nativeCreateRejected)
        }
        FSEventStreamSetDispatchQueue(stream, request.callbackQueue)
        return .success(DarwinFSEventNativeStreamHandle(storage: .native(stream)))
    }

    func startStream(_ stream: DarwinFSEventNativeStreamHandle) -> Bool {
        FSEventStreamStart(nativeStream(from: stream))
    }

    func stopStream(_ stream: DarwinFSEventNativeStreamHandle) {
        FSEventStreamStop(nativeStream(from: stream))
    }

    func invalidateStream(_ stream: DarwinFSEventNativeStreamHandle) {
        FSEventStreamInvalidate(nativeStream(from: stream))
    }

    func releaseStream(_ stream: DarwinFSEventNativeStreamHandle) {
        FSEventStreamRelease(nativeStream(from: stream))
    }

    private func nativeStream(from stream: DarwinFSEventNativeStreamHandle) -> FSEventStreamRef {
        switch stream.storage {
        case .native(let nativeStream):
            nativeStream
        case .test:
            preconditionFailure("system native driver cannot operate on a test stream handle")
        }
    }
}

enum DarwinFSEventCallbackContextReleaseResult: Equatable, Sendable {
    case released
    case alreadyReleased
}

final class DarwinFSEventRegistrationLeaseDrainReceipt: @unchecked Sendable, Equatable {
    let binding: FilesystemObservationSlotBinding
    let nativeGenerationIdentity: FilesystemObservationNativeGenerationIdentity
    let controlBlockIdentity: FilesystemObservationControlBlockIdentity

    private let callbackContextCustody: DarwinFSEventCallbackContextCustody

    fileprivate init(
        binding: FilesystemObservationSlotBinding,
        nativeGenerationIdentity: FilesystemObservationNativeGenerationIdentity,
        callbackContextCustody: DarwinFSEventCallbackContextCustody
    ) {
        self.binding = binding
        self.nativeGenerationIdentity = nativeGenerationIdentity
        controlBlockIdentity = binding.controlBlockIdentity
        self.callbackContextCustody = callbackContextCustody
    }

    static func == (
        lhs: DarwinFSEventRegistrationLeaseDrainReceipt,
        rhs: DarwinFSEventRegistrationLeaseDrainReceipt
    ) -> Bool {
        lhs === rhs
    }

    func releaseCallbackContext() -> DarwinFSEventCallbackContextReleaseResult {
        callbackContextCustody.release()
    }
}

struct DarwinFSEventRegistrationCreateFailureCleanup: Sendable {
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let nativeFailure: DarwinFSEventNativeStreamCreationFailure
    private let callbackContextCustody: DarwinFSEventCallbackContextCustody

    fileprivate init(
        startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        nativeFailure: DarwinFSEventNativeStreamCreationFailure,
        callbackContextCustody: DarwinFSEventCallbackContextCustody
    ) {
        self.startingNativeLifetime = startingNativeLifetime
        self.nativeFailure = nativeFailure
        self.callbackContextCustody = callbackContextCustody
    }

    func releaseCallbackContext() -> DarwinFSEventCallbackContextReleaseResult {
        callbackContextCustody.release()
    }
}

struct DarwinFSEventRegistrationStartFailureCleanup: Sendable {
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let binding: FilesystemObservationSlotBinding
    let nativeGenerationIdentity: FilesystemObservationNativeGenerationIdentity
    let controlBlockIdentity: FilesystemObservationControlBlockIdentity
    private let callbackContextCustody: DarwinFSEventCallbackContextCustody

    fileprivate init(
        startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        callbackContextCustody: DarwinFSEventCallbackContextCustody
    ) {
        self.startingNativeLifetime = startingNativeLifetime
        binding = startingNativeLifetime.binding
        nativeGenerationIdentity = startingNativeLifetime.nativeGenerationIdentity
        controlBlockIdentity = startingNativeLifetime.binding.controlBlockIdentity
        self.callbackContextCustody = callbackContextCustody
    }

    func releaseCallbackContext() -> DarwinFSEventCallbackContextReleaseResult {
        callbackContextCustody.release()
    }
}

enum DarwinFSEventRegistrationGenerationCreationResult: Sendable {
    case created(DarwinFSEventRegistrationGeneration)
    case failed(DarwinFSEventRegistrationCreateFailureCleanup)
}

enum DarwinFSEventRegistrationGenerationStartResult: Sendable {
    case started(FilesystemObservationAcceptingNativeLifetime)
    case failed(DarwinFSEventRegistrationStartFailureCleanup)
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
    case closingCreatedStream
    case closingStartedStream
    case closed
    case startFailureDraining
    case startFailed
}

private enum DarwinFSEventRegistrationStartCompletionOutcome: Sendable {
    case accepting(FilesystemObservationAcceptingNativeLifetime)
    case failed(DarwinFSEventRegistrationStartFailureCleanup)
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

private final class DarwinFSEventCallbackContextCustody: @unchecked Sendable {
    private enum State: Sendable {
        case retained(UInt)
        case released
    }

    private let lock: OSAllocatedUnfairLock<State>

    init(pointer: UnsafeMutableRawPointer) {
        lock = OSAllocatedUnfairLock(initialState: .retained(UInt(bitPattern: pointer)))
    }

    func release() -> DarwinFSEventCallbackContextReleaseResult {
        let pointerAddressToRelease = lock.withLock { state -> UInt? in
            switch state {
            case .retained(let pointerAddress):
                state = .released
                return pointerAddress
            case .released:
                return nil
            }
        }
        guard let pointerAddressToRelease else { return .alreadyReleased }
        guard let pointerToRelease = UnsafeMutableRawPointer(bitPattern: pointerAddressToRelease)
        else {
            preconditionFailure("retained callback-context pointer address became invalid")
        }
        Unmanaged<DarwinFSEventRegistrationCallbackContext>
            .fromOpaque(pointerToRelease)
            .release()
        return .released
    }

    deinit {
        _ = release()
    }
}

private final class DarwinFSEventRegistrationCallbackContext: @unchecked Sendable {
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

final class DarwinFSEventRegistrationGeneration: @unchecked Sendable {
    private struct NativeCustody: Sendable {
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
        case closingCreatedStream(NativeCustody)
        case closingStartedStream(NativeCustody)
        case closed(ClosedCustody)
        case startFailureDraining(NativeCustody)
        case startFailed(DarwinFSEventRegistrationStartFailureCleanup)
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

    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let controlBlock: FSEventRegistrationControlBlock
    private let nativeGenerationPorts: FilesystemObservationNativeGenerationPorts
    private let nativeDriver: any DarwinFSEventNativeDriver
    private let callbackQueueBarrier: any DarwinFSEventCallbackQueueBarrier
    private let stateLock: OSAllocatedUnfairLock<State>

    private init(
        startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        controlBlock: FSEventRegistrationControlBlock,
        nativeGenerationPorts: FilesystemObservationNativeGenerationPorts,
        nativeDriver: any DarwinFSEventNativeDriver,
        callbackQueueBarrier: any DarwinFSEventCallbackQueueBarrier,
        nativeCustody: NativeCustody
    ) {
        self.startingNativeLifetime = startingNativeLifetime
        self.controlBlock = controlBlock
        self.nativeGenerationPorts = nativeGenerationPorts
        self.nativeDriver = nativeDriver
        self.callbackQueueBarrier = callbackQueueBarrier
        stateLock = OSAllocatedUnfairLock(initialState: .created(nativeCustody))
    }

    static func create(
        startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        controlBlock: FSEventRegistrationControlBlock,
        adapter: any DarwinFSEventRegistrationCallbackAdapter,
        nativeGenerationPorts: FilesystemObservationNativeGenerationPorts,
        nativeDriver: any DarwinFSEventNativeDriver = DarwinFSEventSystemNativeDriver(),
        callbackQueueBarrier: any DarwinFSEventCallbackQueueBarrier =
            DarwinFSEventAsyncCallbackQueueBarrier()
    ) -> DarwinFSEventRegistrationGenerationCreationResult {
        precondition(
            controlBlock.startingNativeLifetime == startingNativeLifetime,
            "native generation requires the control block's exact starting lifetime"
        )
        precondition(
            controlBlock.registration == startingNativeLifetime.binding.registration,
            "native generation requires its exact binding registration"
        )
        precondition(
            adapter.controlBlock === controlBlock,
            "native generation and callback adapter must share one control block"
        )
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
            callback: callback,
            callbackContextPointer: callbackContextPointer
        )
        switch nativeDriver.createStream(request: request) {
        case .success(let stream):
            return .created(
                DarwinFSEventRegistrationGeneration(
                    startingNativeLifetime: startingNativeLifetime,
                    controlBlock: controlBlock,
                    nativeGenerationPorts: nativeGenerationPorts,
                    nativeDriver: nativeDriver,
                    callbackQueueBarrier: callbackQueueBarrier,
                    nativeCustody: NativeCustody(
                        stream: stream,
                        callbackQueue: callbackQueue,
                        callbackContextCustody: callbackContextCustody
                    )
                )
            )
        case .failure(let nativeFailure):
            return .failed(
                DarwinFSEventRegistrationCreateFailureCleanup(
                    startingNativeLifetime: startingNativeLifetime,
                    nativeFailure: nativeFailure,
                    callbackContextCustody: callbackContextCustody
                )
            )
        }
    }

    var phase: DarwinFSEventRegistrationGenerationPhase {
        stateLock.withLock { state in
            switch state {
            case .created: .created
            case .starting: .starting
            case .startingCloseRequested: .startingCloseRequested
            case .started: .started
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
                startingNativeLifetime: startingNativeLifetime,
                callbackContextCustody: custody.callbackContextCustody
            )
            stateLock.withLock { state in
                state = .startFailed(cleanup)
            }
            completion.resolve(.failed(cleanup))
            return .failed(cleanup)
        }

        let acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
        switch nativeGenerationPorts.lifecyclePort.publishAccepting(startingNativeLifetime) {
        case .published(let accepting), .alreadyPublished(let accepting):
            acceptingNativeLifetime = accepting
        case .foreignFleet, .undeclaredPhysicalSlot, .startingNativeLifetimeMismatch,
            .invalidSlotState:
            _ = controlBlock.beginClosing()
            nativeDriver.stopStream(custody.stream)
            nativeDriver.invalidateStream(custody.stream)
            _ = controlBlock.markStreamInvalidated()
            await callbackQueueBarrier.waitForBarrier(on: custody.callbackQueue)
            _ = controlBlock.markCallbackQueueDrained()
            await controlBlock.waitUntilLeasesDrained()
            nativeDriver.releaseStream(custody.stream)
            let cleanup = DarwinFSEventRegistrationStartFailureCleanup(
                startingNativeLifetime: startingNativeLifetime,
                callbackContextCustody: custody.callbackContextCustody
            )
            stateLock.withLock { state in
                state = .startFailed(cleanup)
            }
            completion.resolve(.failed(cleanup))
            return .failed(cleanup)
        }
        stateLock.withLock { state in
            switch state {
            case .starting:
                state = .started(custody, acceptingNativeLifetime)
            case .startingCloseRequested:
                break
            case .created, .started, .closingCreatedStream, .closingStartedStream,
                .closed, .startFailureDraining, .startFailed:
                preconditionFailure("native start completion requires an in-flight start state")
            }
        }
        completion.resolve(.accepting(acceptingNativeLifetime))
        return .started(acceptingNativeLifetime)
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
            switch nativeGenerationPorts.lifecyclePort
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
            nativeGenerationIdentity: startingNativeLifetime.nativeGenerationIdentity,
            callbackContextCustody: custody.callbackContextCustody
        )
        nativeDriver.releaseStream(custody.stream)
        stateLock.withLock { state in
            state = .closed(ClosedCustody(receipt: receipt))
        }
        return .closed(receipt)
    }
}
