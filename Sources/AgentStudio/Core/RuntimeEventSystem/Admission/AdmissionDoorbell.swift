import os

struct AdmissionDoorbellStateSnapshot: Sendable, Equatable {
    let hasPendingSignal: Bool
    let hasWaitingConsumer: Bool
    let isFinished: Bool
}

struct AdmissionDoorbellSignalerPort: AdmissionDoorbellSignaler {
    private let doorbell: AdmissionDoorbell

    fileprivate init(doorbell: AdmissionDoorbell) {
        self.doorbell = doorbell
    }

    func signal() {
        doorbell.signal()
    }
}

struct AdmissionDoorbellConsumerPort: AdmissionDoorbellConsumer {
    private let doorbell: AdmissionDoorbell

    fileprivate init(doorbell: AdmissionDoorbell) {
        self.doorbell = doorbell
    }

    func nextSignal() async -> AdmissionDoorbellResult {
        await doorbell.nextSignal()
    }
}

struct AdmissionDoorbellLifecyclePort: AdmissionDoorbellLifecycle {
    private let doorbell: AdmissionDoorbell

    fileprivate init(doorbell: AdmissionDoorbell) {
        self.doorbell = doorbell
    }

    func finish() {
        doorbell.finish()
    }

    var stateSnapshot: AdmissionDoorbellStateSnapshot {
        doorbell.stateSnapshot
    }
}

final class AdmissionDoorbell: @unchecked Sendable {
    private struct WaitingConsumer: Sendable {
        let identity: AdmissionOpaqueIdentity
        let continuation: CheckedContinuation<AdmissionDoorbellResult, Never>
    }

    private struct State: Sendable {
        var hasPendingSignal = false
        var waitingConsumer: WaitingConsumer?
        var isFinished = false
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var signalerPort: AdmissionDoorbellSignalerPort {
        AdmissionDoorbellSignalerPort(doorbell: self)
    }

    var consumerPort: AdmissionDoorbellConsumerPort {
        AdmissionDoorbellConsumerPort(doorbell: self)
    }

    var lifecyclePort: AdmissionDoorbellLifecyclePort {
        AdmissionDoorbellLifecyclePort(doorbell: self)
    }

    var ownerPort: AdmissionDoorbellOwnerPort {
        AdmissionDoorbellOwnerPort(doorbell: self)
    }

    fileprivate func signal() {
        let waitingConsumer: WaitingConsumer? = lock.withLock { state in
            guard state.isFinished == false else { return nil }
            guard let waitingConsumer = state.waitingConsumer else {
                state.hasPendingSignal = true
                return nil
            }

            state.waitingConsumer = nil
            return waitingConsumer
        }

        waitingConsumer?.continuation.resume(returning: .signaled)
    }

    fileprivate func nextSignal() async -> AdmissionDoorbellResult {
        let waitingConsumerIdentity = AdmissionOpaqueIdentity()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let immediateResult = lock.withLock { state -> AdmissionDoorbellResult? in
                    if state.isFinished || Task.isCancelled {
                        return .finished
                    }
                    if state.hasPendingSignal {
                        state.hasPendingSignal = false
                        return .signaled
                    }

                    precondition(
                        state.waitingConsumer == nil,
                        "AdmissionDoorbell supports exactly one long-lived consumer"
                    )
                    state.waitingConsumer = WaitingConsumer(
                        identity: waitingConsumerIdentity,
                        continuation: continuation
                    )
                    return nil
                }

                if let immediateResult {
                    continuation.resume(returning: immediateResult)
                }
            }
        } onCancel: {
            self.cancelWaitingConsumer(identity: waitingConsumerIdentity)
        }
    }

    fileprivate func finish() {
        let waitingConsumer: WaitingConsumer? = lock.withLock { state in
            guard state.isFinished == false else { return nil }
            state.isFinished = true
            state.hasPendingSignal = false
            let waitingConsumer = state.waitingConsumer
            state.waitingConsumer = nil
            return waitingConsumer
        }

        waitingConsumer?.continuation.resume(returning: .finished)
    }

    fileprivate var stateSnapshot: AdmissionDoorbellStateSnapshot {
        lock.withLock { state in
            AdmissionDoorbellStateSnapshot(
                hasPendingSignal: state.hasPendingSignal,
                hasWaitingConsumer: state.waitingConsumer != nil,
                isFinished: state.isFinished
            )
        }
    }

    private func cancelWaitingConsumer(identity: AdmissionOpaqueIdentity) {
        let cancelledConsumer: WaitingConsumer? = lock.withLock { state in
            guard state.waitingConsumer?.identity == identity else { return nil }
            let cancelledConsumer = state.waitingConsumer
            state.waitingConsumer = nil
            return cancelledConsumer
        }

        cancelledConsumer?.continuation.resume(returning: .finished)
    }
}

struct AdmissionDoorbellOwnerPort: AdmissionDoorbellOwner {
    private let doorbell: AdmissionDoorbell

    fileprivate init(doorbell: AdmissionDoorbell) {
        self.doorbell = doorbell
    }

    func signal() {
        doorbell.signal()
    }

    func nextSignal() async -> AdmissionDoorbellResult {
        await doorbell.nextSignal()
    }

    func finish() {
        doorbell.finish()
    }

    func apply(_ directive: AdmissionWakeDirective) {
        guard directive == .scheduleDrain else { return }
        doorbell.signal()
    }

    var stateSnapshot: AdmissionDoorbellStateSnapshot {
        doorbell.stateSnapshot
    }
}

struct AdmissionBindingDoorbellCoordinator: Sendable {
    private let doorbellOwner: AdmissionDoorbellOwnerPort

    init(doorbellOwner: AdmissionDoorbellOwnerPort) {
        self.doorbellOwner = doorbellOwner
    }

    func bind<Source: AdmissionConsumerBindingSource>(
        _ source: Source
    ) -> AdmissionConsumerBindResult {
        let result = source.bindConsumer()
        doorbellOwner.apply(result.wake)
        return result
    }
}
