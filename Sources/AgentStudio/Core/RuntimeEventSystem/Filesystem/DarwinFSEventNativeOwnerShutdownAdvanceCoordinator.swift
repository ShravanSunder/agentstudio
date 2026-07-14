import os

protocol DarwinFSEventNativeOwnerShutdownResultPublisher: AnyObject, Sendable {
    func wait() async -> DarwinFSEventNativeOwnerFleetShutdownResult
    func publish(_ result: DarwinFSEventNativeOwnerFleetShutdownResult)
}

enum DarwinFSEventNativeOwnerShutdownAdvanceClaim: Sendable {
    case perform(any DarwinFSEventNativeOwnerShutdownResultPublisher)
    case wait(any DarwinFSEventNativeOwnerShutdownResultPublisher)
    case completed(DarwinFSEventNativeOwnerFleetShutdownCompletion)
}

final class DarwinFSEventNativeOwnerShutdownAdvanceCoordinator: @unchecked Sendable {
    private enum State: Sendable {
        case available
        case advancing(any DarwinFSEventNativeOwnerShutdownResultPublisher)
        case publishing(any DarwinFSEventNativeOwnerShutdownResultPublisher)
        case completed(DarwinFSEventNativeOwnerFleetShutdownCompletion)
    }

    private let publisherFactory: @Sendable () -> any DarwinFSEventNativeOwnerShutdownResultPublisher
    private let lock = OSAllocatedUnfairLock(initialState: State.available)

    init(
        publisherFactory:
            @escaping @Sendable () ->
            any DarwinFSEventNativeOwnerShutdownResultPublisher = {
                DarwinFSEventNativeOwnerShutdownResultWaiter()
            }
    ) {
        self.publisherFactory = publisherFactory
    }

    func claim() -> DarwinFSEventNativeOwnerShutdownAdvanceClaim {
        lock.withLock { state in
            switch state {
            case .available:
                let publisher = publisherFactory()
                state = .advancing(publisher)
                return .perform(publisher)
            case .advancing(let publisher), .publishing(let publisher):
                return .wait(publisher)
            case .completed(let completion):
                return .completed(completion)
            }
        }
    }

    func publish(
        _ result: DarwinFSEventNativeOwnerFleetShutdownResult,
        for publisher: any DarwinFSEventNativeOwnerShutdownResultPublisher
    ) {
        lock.withLock { state in
            guard case .advancing(let retainedPublisher) = state,
                retainedPublisher === publisher
            else {
                preconditionFailure("fleet shutdown must publish the exact claimed advance")
            }
            state = .publishing(retainedPublisher)
        }

        publisher.publish(result)

        lock.withLock { state in
            guard case .publishing(let retainedPublisher) = state,
                retainedPublisher === publisher
            else {
                preconditionFailure("fleet shutdown publication lost its exact claim")
            }
            switch result {
            case .completed(let completion):
                state = .completed(completion)
            case .incomplete:
                state = .available
            }
        }
    }

    var phase: DarwinFSEventNativeOwnerFleetShutdownAdvancePhase {
        lock.withLock { state in
            switch state {
            case .available:
                return .available
            case .advancing, .publishing:
                return .inFlight
            case .completed(let completion):
                return .completed(completion)
            }
        }
    }
}

private final class DarwinFSEventNativeOwnerShutdownResultWaiter:
    DarwinFSEventNativeOwnerShutdownResultPublisher,
    @unchecked Sendable
{
    private typealias Waiter = CheckedContinuation<
        DarwinFSEventNativeOwnerFleetShutdownResult,
        Never
    >

    private enum State: Sendable {
        case pending([Waiter])
        case completed(DarwinFSEventNativeOwnerFleetShutdownResult)
    }

    private let lock = OSAllocatedUnfairLock(initialState: State.pending([]))

    func wait() async -> DarwinFSEventNativeOwnerFleetShutdownResult {
        await withCheckedContinuation { continuation in
            // swiftlint:disable closure_parameter_position
            let completedResult = lock.withLock {
                (state: inout State) -> DarwinFSEventNativeOwnerFleetShutdownResult? in
                switch state {
                case .pending(var waiters):
                    waiters.append(continuation)
                    state = .pending(waiters)
                    return nil
                case .completed(let result):
                    return result
                }
            }
            // swiftlint:enable closure_parameter_position
            if let completedResult {
                continuation.resume(returning: completedResult)
            }
        }
    }

    func publish(_ result: DarwinFSEventNativeOwnerFleetShutdownResult) {
        let waiters = lock.withLock { state -> [Waiter] in
            switch state {
            case .pending(let waiters):
                state = .completed(result)
                return waiters
            case .completed:
                preconditionFailure("native owner fleet shutdown result publishes once")
            }
        }
        for waiter in waiters {
            waiter.resume(returning: result)
        }
    }
}
