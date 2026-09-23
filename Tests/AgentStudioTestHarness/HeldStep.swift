import Dispatch
import Synchronization

/// One point in the work under test where that work stops until the test
/// decides how the step ends.
///
/// A fake dependency calls ``arrive(_:)`` (async seam) or ``arriveBlocking(_:)``
/// (synchronous seam) at the point it stands in for. The test awaits
/// ``firstArrival()`` — which completes because the work got there, never
/// because time passed — then ends the step with ``release()``, ``fail(_:)`` or
/// ``retire()``. The first terminal call wins and is sticky: every parked
/// arrival resumes with it, and every later arrival passes (or throws the same
/// error) immediately. A terminal call made before any arrival is kept, so an
/// early `release()` cannot be lost.
///
/// This is a class over a `Mutex`, not an actor, so a synchronous production
/// seam can arrive without an `await`. No detached task relays a resume:
/// cancellation resumes a parked arrival inside its cancellation handler under
/// the same lock, and terminal transitions resume arrivals after the state
/// change is recorded, so an arrival that immediately arrives again sees the
/// terminal state.
package final class HeldStep<Arrival: Sendable>: Sendable {
    /// Names the step in the error a waiter throws when the runner's hang
    /// bound cancels it, so a step that is never reached is identifiable.
    package let name: String
    private let state = Mutex(HeldStepState<Arrival>())

    package init(_ name: String) {
        self.name = name
    }

    /// Records an arrival and suspends until the step is released, failed or
    /// retired. Throws the failure error on `fail`, and `CancellationError` on
    /// `retire` or when the arriving task is cancelled first.
    package func arrive(_ arrival: Arrival) async throws {
        let admission = admitArrival(arrival, parking: .async)
        if let terminal = admission.terminal {
            try terminal.resolveArrival()
            return
        }
        let parkingID = admission.parkingID
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let terminal = state.withLock { state -> HeldStepTerminal? in
                    if let terminal = state.terminal {
                        return terminal
                    }
                    if Task.isCancelled {
                        return .retired
                    }
                    state.parkedAsyncArrivals[parkingID] = continuation
                    return nil
                }
                terminal?.resume(continuation)
            }
        } onCancel: {
            state.withLock { state in
                state.parkedAsyncArrivals.removeValue(forKey: parkingID)?.resume(throwing: CancellationError())
            }
        }
    }

    /// Records an arrival and parks the calling thread until the step ends.
    ///
    /// For a synchronous seam such as a socket join or an FSEvents stream
    /// factory. The block lands on a semaphore this harness owns for this one
    /// arrival; call it only from a thread that may block (the seam's own
    /// thread or a dispatch queue), never from the cooperative pool.
    package func arriveBlocking(_ arrival: Arrival) throws {
        let parkingSemaphore = DispatchSemaphore(value: 0)
        let admission = admitArrival(arrival, parking: .blocking(parkingSemaphore))
        if let terminal = admission.terminal {
            try terminal.resolveArrival()
            return
        }
        parkingSemaphore.wait()
        let terminal = state.withLock { $0.terminal }
        guard let terminal else {
            preconditionFailure("HeldStep '\(name)' woke a blocking arrival before reaching a terminal state")
        }
        try terminal.resolveArrival()
    }

    /// The first arrival's value, once the work reaches the step.
    ///
    /// Has no deadline. When the step is never reached, the runner's hang bound
    /// cancels the waiting test and this throws ``HeldStepNeverReached``
    /// naming the step.
    package func firstArrival() async throws -> Arrival {
        let waiterID = state.withLock { $0.allocateID() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Arrival, any Error>) in
                state.withLock { state in
                    if let firstArrival = state.arrivals.first {
                        continuation.resume(returning: firstArrival)
                    } else if Task.isCancelled {
                        continuation.resume(throwing: HeldStepNeverReached(stepName: name))
                    } else {
                        state.firstArrivalWaiters[waiterID] = continuation
                    }
                }
            }
        } onCancel: {
            state.withLock { state in
                state.firstArrivalWaiters.removeValue(forKey: waiterID)?
                    .resume(throwing: HeldStepNeverReached(stepName: name))
            }
        }
    }

    /// Every arrival recorded so far, in arrival order. A synchronous read for
    /// asserting once, after the test has awaited whatever makes the count
    /// final.
    package var recordedArrivals: [Arrival] {
        state.withLock { $0.arrivals }
    }

    /// Resumes every current and later arrival normally.
    package func release() {
        settle(.released)
    }

    /// Makes every current and later arrival throw `error`.
    package func fail(_ error: any Error) {
        settle(.failed(error))
    }

    /// Resumes every current and later arrival as cancelled.
    package func retire() {
        settle(.retired)
    }

    private func admitArrival(_ arrival: Arrival, parking: HeldStepParking) -> HeldStepAdmission<Arrival> {
        let admission = state.withLock { $0.admit(arrival, parking: parking) }
        for waiter in admission.firstArrivalWaiters {
            waiter.resume(returning: arrival)
        }
        return admission
    }

    private func settle(_ terminal: HeldStepTerminal) {
        let settlement = state.withLock { $0.settle(terminal) }
        for continuation in settlement.parkedAsyncArrivals {
            terminal.resume(continuation)
        }
        for semaphore in settlement.parkedBlockingArrivals {
            semaphore.signal()
        }
    }
}

/// Thrown by ``HeldStep/firstArrival()`` when the waiting task is cancelled
/// before the work reached the step — in practice, the runner's hang bound.
package struct HeldStepNeverReached: Error, CustomStringConvertible {
    package let stepName: String

    package var description: String {
        "HeldStep '\(stepName)' was never reached"
    }
}

private enum HeldStepTerminal: Sendable {
    case released
    case failed(any Error)
    case retired

    func resolveArrival() throws {
        switch self {
        case .released:
            return
        case .failed(let error):
            throw error
        case .retired:
            throw CancellationError()
        }
    }

    func resume(_ continuation: CheckedContinuation<Void, any Error>) {
        switch self {
        case .released:
            continuation.resume()
        case .failed(let error):
            continuation.resume(throwing: error)
        case .retired:
            continuation.resume(throwing: CancellationError())
        }
    }
}

private enum HeldStepParking {
    case async
    case blocking(DispatchSemaphore)
}

private struct HeldStepAdmission<Arrival: Sendable> {
    let parkingID: UInt64
    let terminal: HeldStepTerminal?
    let firstArrivalWaiters: [CheckedContinuation<Arrival, any Error>]
}

/// The arrivals a terminal transition must resume, taken out of the state
/// under the lock and resumed after it is released.
private struct HeldStepSettlement {
    var parkedAsyncArrivals: [CheckedContinuation<Void, any Error>] = []
    var parkedBlockingArrivals: [DispatchSemaphore] = []
}

private struct HeldStepState<Arrival: Sendable> {
    var arrivals: [Arrival] = []
    var terminal: HeldStepTerminal?
    var parkedAsyncArrivals: [UInt64: CheckedContinuation<Void, any Error>] = [:]
    var parkedBlockingArrivals: [UInt64: DispatchSemaphore] = [:]
    var firstArrivalWaiters: [UInt64: CheckedContinuation<Arrival, any Error>] = [:]
    private var nextID: UInt64 = 1

    mutating func allocateID() -> UInt64 {
        defer { nextID += 1 }
        return nextID
    }

    /// Records the arrival. The first one takes every waiting `firstArrival`
    /// caller with it; a terminal state lets the arrival pass at once.
    mutating func admit(_ arrival: Arrival, parking: HeldStepParking) -> HeldStepAdmission<Arrival> {
        arrivals.append(arrival)
        var waiters: [CheckedContinuation<Arrival, any Error>] = []
        if arrivals.count == 1 {
            waiters = Array(firstArrivalWaiters.values)
            firstArrivalWaiters.removeAll()
        }
        if let terminal {
            return HeldStepAdmission(parkingID: 0, terminal: terminal, firstArrivalWaiters: waiters)
        }
        let parkingID = allocateID()
        if case .blocking(let semaphore) = parking {
            parkedBlockingArrivals[parkingID] = semaphore
        }
        return HeldStepAdmission(parkingID: parkingID, terminal: nil, firstArrivalWaiters: waiters)
    }

    /// Records the first terminal state and hands back every parked arrival.
    /// A later terminal call changes nothing and resumes nothing.
    mutating func settle(_ newTerminal: HeldStepTerminal) -> HeldStepSettlement {
        guard terminal == nil else {
            return HeldStepSettlement()
        }
        terminal = newTerminal
        let settlement = HeldStepSettlement(
            parkedAsyncArrivals: Array(parkedAsyncArrivals.values),
            parkedBlockingArrivals: Array(parkedBlockingArrivals.values)
        )
        parkedAsyncArrivals.removeAll()
        parkedBlockingArrivals.removeAll()
        return settlement
    }
}
