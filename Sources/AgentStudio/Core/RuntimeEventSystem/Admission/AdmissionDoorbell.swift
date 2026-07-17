import os

enum AdmissionDoorbellStateSnapshot: Sendable, Equatable {
    case idle
    case signalPending
    case consumerWaiting
    case finished
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

    private enum State: Sendable {
        case idle
        case signalPending
        case consumerWaiting(WaitingConsumer)
        case finished
    }

    private enum WaitRegistrationTransition: Sendable {
        case suspended
        case resume(AdmissionDoorbellResult)
    }

    private let lock = OSAllocatedUnfairLock(initialState: State.idle)
    private let onConsumerRegistered: (@Sendable () -> Void)?

    init(onConsumerRegistered: (@Sendable () -> Void)? = nil) {
        self.onConsumerRegistered = onConsumerRegistered
    }

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
            switch state {
            case .idle:
                state = .signalPending
                return nil
            case .signalPending:
                return nil
            case .consumerWaiting(let waitingConsumer):
                state = .idle
                return waitingConsumer
            case .finished:
                return nil
            }
        }

        waitingConsumer?.continuation.resume(returning: .signaled)
    }

    fileprivate func nextSignal() async -> AdmissionDoorbellResult {
        let waitingConsumerIdentity = AdmissionOpaqueIdentity()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let transition = lock.withLock { state -> WaitRegistrationTransition in
                    if Task.isCancelled {
                        return .resume(.finished)
                    }
                    switch state {
                    case .idle:
                        state = .consumerWaiting(
                            WaitingConsumer(
                                identity: waitingConsumerIdentity,
                                continuation: continuation
                            )
                        )
                        return .suspended
                    case .signalPending:
                        state = .idle
                        return .resume(.signaled)
                    case .consumerWaiting:
                        preconditionFailure(
                            "AdmissionDoorbell supports exactly one long-lived consumer"
                        )
                    case .finished:
                        return .resume(.finished)
                    }
                }

                switch transition {
                case .suspended:
                    onConsumerRegistered?()
                case .resume(let immediateResult):
                    continuation.resume(returning: immediateResult)
                }
            }
        } onCancel: {
            self.cancelWaitingConsumer(identity: waitingConsumerIdentity)
        }
    }

    fileprivate func finish() {
        let waitingConsumer: WaitingConsumer? = lock.withLock { state in
            switch state {
            case .idle, .signalPending:
                state = .finished
                return nil
            case .consumerWaiting(let waitingConsumer):
                state = .finished
                return waitingConsumer
            case .finished:
                return nil
            }
        }

        waitingConsumer?.continuation.resume(returning: .finished)
    }

    fileprivate var stateSnapshot: AdmissionDoorbellStateSnapshot {
        lock.withLock { state in
            switch state {
            case .idle: .idle
            case .signalPending: .signalPending
            case .consumerWaiting: .consumerWaiting
            case .finished: .finished
            }
        }
    }

    private func cancelWaitingConsumer(identity: AdmissionOpaqueIdentity) {
        let cancelledConsumer: WaitingConsumer? = lock.withLock { state in
            guard case .consumerWaiting(let waitingConsumer) = state,
                waitingConsumer.identity == identity
            else { return nil }
            state = .idle
            return waitingConsumer
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
