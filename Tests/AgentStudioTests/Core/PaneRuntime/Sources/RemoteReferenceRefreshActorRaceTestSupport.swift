import Foundation

actor RemoteReferenceInvalidationGate {
    private var suspensionContinuation: CheckedContinuation<Void, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    func suspendInvalidation() async {
        await withCheckedContinuation { continuation in
            suspensionContinuation = continuation
            let waiters = suspensionWaiters
            suspensionWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }

    func waitUntilInvalidationSuspended() async {
        guard suspensionContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func releaseInvalidation() {
        suspensionContinuation?.resume()
        suspensionContinuation = nil
    }
}

actor RemoteReferenceOneShotInvalidationGate {
    private var shouldSuspendNextInvalidation = true
    private var suspensionContinuation: CheckedContinuation<Void, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    func suspendNextInvalidation() async {
        guard shouldSuspendNextInvalidation else { return }
        shouldSuspendNextInvalidation = false
        await withCheckedContinuation { continuation in
            suspensionContinuation = continuation
            let waiters = suspensionWaiters
            suspensionWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }

    func waitUntilInvalidationSuspended() async {
        guard suspensionContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func releaseInvalidation() {
        suspensionContinuation?.resume()
        suspensionContinuation = nil
    }
}
