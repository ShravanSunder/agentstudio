import Dispatch
import Foundation

enum BridgeGitDataPlaneTimeoutError: Error {
    case timedOut
}

enum BridgeGitDataPlaneTimeoutFailure {
    static let message = "Bridge Git data-plane read timed out"
}

enum BridgeGitDataPlaneTimeout {
    nonisolated static func readWithHardTimeout<ReturnValue: Sendable>(
        _ timeout: Duration,
        timeoutScheduler: any BridgeGitDataPlaneTimeoutScheduler,
        operation: @Sendable @escaping () async throws -> ReturnValue
    ) async throws -> ReturnValue {
        let raceBox = BridgeGitDataPlaneTimeoutRaceBox<ReturnValue>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ReturnValue, Error>) in
                let race = BridgeGitDataPlaneTimeoutRace(continuation: continuation)
                guard raceBox.install(race) else { return }
                // Detached by design: the Git SDK read may ignore cooperative cancellation.
                // swiftlint:disable:next no_task_detached
                let readTask = Task.detached(priority: .utility) {
                    do {
                        race.succeed(try await operation())
                    } catch {
                        race.fail(error)
                    }
                }
                let scheduledTimeout = timeoutScheduler.scheduleTimeout(after: timeout) {
                    race.fail(BridgeGitDataPlaneTimeoutError.timedOut)
                }
                _ = race.install(readTask: readTask, scheduledTimeout: scheduledTimeout)
            }
        } onCancel: {
            raceBox.cancel()
        }
    }

    nonisolated static func dispatchInterval(for duration: Duration) -> DispatchTimeInterval {
        let components = duration.components
        let (secondsNanoseconds, multiplicationOverflow) =
            components.seconds.multipliedReportingOverflow(by: 1_000_000_000)
        let attosecondNanoseconds = components.attoseconds / 1_000_000_000
        let (totalNanoseconds, additionOverflow) =
            secondsNanoseconds.addingReportingOverflow(attosecondNanoseconds)

        guard !multiplicationOverflow, !additionOverflow else {
            return .seconds(Int.max)
        }
        guard totalNanoseconds > 0 else {
            return .nanoseconds(0)
        }
        guard totalNanoseconds <= Int64(Int.max) else {
            return .seconds(Int.max)
        }
        return .nanoseconds(Int(totalNanoseconds))
    }
}

protocol BridgeGitDataPlaneTimeoutScheduler: Sendable {
    func scheduleTimeout(
        after timeout: Duration,
        _ handler: @escaping @Sendable () -> Void
    ) -> BridgeGitDataPlaneScheduledTimeout
}

struct BridgeGitDataPlaneScheduledTimeout: Sendable {
    private let box: BridgeGitDataPlaneScheduledTimeoutBox

    init(cancel: @escaping () -> Void) {
        box = BridgeGitDataPlaneScheduledTimeoutBox(cancel: cancel)
    }

    func cancel() {
        box.cancel()
    }
}

struct DispatchBridgeGitDataPlaneTimeoutScheduler: BridgeGitDataPlaneTimeoutScheduler {
    private static let timeoutQueue = DispatchQueue(
        label: "com.agentstudio.bridge.git-data-plane-timeout",
        qos: .userInitiated
    )

    func scheduleTimeout(
        after timeout: Duration,
        _ handler: @escaping @Sendable () -> Void
    ) -> BridgeGitDataPlaneScheduledTimeout {
        let workItem = DispatchWorkItem(block: handler)
        Self.timeoutQueue.asyncAfter(
            deadline: .now() + BridgeGitDataPlaneTimeout.dispatchInterval(for: timeout),
            execute: workItem
        )
        return BridgeGitDataPlaneScheduledTimeout {
            workItem.cancel()
        }
    }
}

private final class BridgeGitDataPlaneScheduledTimeoutBox: @unchecked Sendable {
    private let cancelHandler: () -> Void

    init(cancel: @escaping () -> Void) {
        cancelHandler = cancel
    }

    func cancel() {
        cancelHandler()
    }
}

private final class BridgeGitDataPlaneTimeoutRaceBox<ReturnValue: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var race: BridgeGitDataPlaneTimeoutRace<ReturnValue>?
    private var didCancel = false

    func install(_ race: BridgeGitDataPlaneTimeoutRace<ReturnValue>) -> Bool {
        lock.lock()
        if didCancel {
            lock.unlock()
            race.fail(CancellationError())
            return false
        }
        self.race = race
        lock.unlock()
        return true
    }

    func cancel() {
        let raceToCancel: BridgeGitDataPlaneTimeoutRace<ReturnValue>?
        lock.lock()
        didCancel = true
        raceToCancel = race
        race = nil
        lock.unlock()

        raceToCancel?.fail(CancellationError())
    }
}

private final class BridgeGitDataPlaneTimeoutRace<ReturnValue: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: CheckedContinuation<ReturnValue, Error>
    private var didResume = false
    private var readTask: Task<Void, Never>?
    private var scheduledTimeout: BridgeGitDataPlaneScheduledTimeout?

    init(continuation: CheckedContinuation<ReturnValue, Error>) {
        self.continuation = continuation
    }

    func install(readTask: Task<Void, Never>, scheduledTimeout: BridgeGitDataPlaneScheduledTimeout) -> Bool {
        lock.lock()
        if didResume {
            lock.unlock()
            readTask.cancel()
            scheduledTimeout.cancel()
            return false
        }
        self.readTask = readTask
        self.scheduledTimeout = scheduledTimeout
        lock.unlock()
        return true
    }

    func succeed(_ value: ReturnValue) {
        resume(.success(value))
    }

    func fail(_ error: Error) {
        resume(.failure(error))
    }

    private func resume(_ result: Result<ReturnValue, Error>) {
        let workToCancel: (Task<Void, Never>?, BridgeGitDataPlaneScheduledTimeout?)
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        workToCancel = (readTask, scheduledTimeout)
        readTask = nil
        scheduledTimeout = nil
        lock.unlock()

        workToCancel.0?.cancel()
        workToCancel.1?.cancel()
        continuation.resume(with: result)
    }
}
