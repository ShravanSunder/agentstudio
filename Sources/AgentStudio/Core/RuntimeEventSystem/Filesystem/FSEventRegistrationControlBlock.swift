import Dispatch
import Foundation
import os

enum FSEventRegistrationClosingPhase: Equatable, Sendable {
    case admissionClosed
    case streamInvalidated
    case callbackQueueDrained
    case leasesDrained
    case recoveryTransferred
    case mailboxGenerationInvalidated
}

enum FSEventRegistrationLifecycleSnapshot: Equatable, Sendable {
    case open(activeLeaseCount: Int)
    case closing(FSEventRegistrationClosingPhase, activeLeaseCount: Int)
    case closed
}

enum FSEventRegistrationControlTransitionResult: Equatable, Sendable {
    case applied
    case alreadyApplied
    case invalidTransition(FSEventRegistrationLifecycleSnapshot)
}

enum FSEventCallbackQueueDrainResult: Equatable, Sendable {
    case leasesDrained
    case waitingForLeases(activeLeaseCount: Int)
    case invalidTransition(FSEventRegistrationLifecycleSnapshot)
}

enum FSEventCallbackLeaseReleaseResult: Equatable, Sendable {
    case released
    case alreadyReleased
    case unknownLease
}

enum FSEventCallbackLeaseAcquisition: Equatable, Sendable {
    case acquired(FSEventCallbackLease)
    case staleRegistration
    case leaseIdentityExhausted
    case closing
    case closed
}

final class FSEventCallbackLease: @unchecked Sendable, Equatable {
    private enum State: Sendable {
        case held(
            controlBlock: FSEventRegistrationControlBlock,
            leaseID: UInt64,
            registration: FSEventRegistrationToken
        )
        case released(registration: FSEventRegistrationToken)
    }

    private let lock: OSAllocatedUnfairLock<State>

    fileprivate init(
        controlBlock: FSEventRegistrationControlBlock,
        leaseID: UInt64,
        registration: FSEventRegistrationToken
    ) {
        lock = OSAllocatedUnfairLock(
            initialState: .held(
                controlBlock: controlBlock,
                leaseID: leaseID,
                registration: registration
            )
        )
    }

    static func == (lhs: FSEventCallbackLease, rhs: FSEventCallbackLease) -> Bool {
        lhs === rhs
    }

    var registration: FSEventRegistrationToken {
        lock.withLock { state in
            switch state {
            case .held(
                controlBlock: _,
                leaseID: _, let registration
            ), .released(let registration):
                registration
            }
        }
    }

    func release() -> FSEventCallbackLeaseReleaseResult {
        let heldState:
            (
                controlBlock: FSEventRegistrationControlBlock,
                leaseID: UInt64,
                registration: FSEventRegistrationToken
            )? = lock.withLock { state in
                switch state {
                case .held(let controlBlock, let leaseID, let registration):
                    state = .released(registration: registration)
                    return (controlBlock, leaseID, registration)
                case .released:
                    return nil
                }
            }
        guard let heldState else { return .alreadyReleased }
        return heldState.controlBlock.releaseCallbackLease(
            leaseID: heldState.leaseID,
            registration: heldState.registration
        )
    }

    deinit {
        _ = release()
    }
}

final class FSEventRegistrationControlBlock: @unchecked Sendable {
    private struct OpenState: Sendable {
        var activeLeaseIDs: Set<UInt64>
        var nextLeaseID: UInt64
    }

    private struct ClosingState: Sendable {
        var phase: FSEventRegistrationClosingPhase
        var activeLeaseIDs: Set<UInt64>
        var leaseDrainWaiters: [CheckedContinuation<Void, Never>]
    }

    private enum State: Sendable {
        case open(OpenState)
        case closing(ClosingState)
        case closed
    }

    let registration: FSEventRegistrationToken
    let watchRoot: WatchRoot
    let captureLimits: FSEventCaptureLimits
    let callbackQueue: DispatchQueue

    private let lock = OSAllocatedUnfairLock(
        initialState: State.open(OpenState(activeLeaseIDs: [], nextLeaseID: 0))
    )

    init(
        registration: FSEventRegistrationToken,
        watchRoot: WatchRoot,
        captureLimits: FSEventCaptureLimits,
        callbackQueue: DispatchQueue
    ) throws {
        guard registration.sourceID == watchRoot.sourceID else {
            throw FSEventRegistrationControlBlockError.watchRootSourceMismatch
        }
        self.registration = registration
        self.watchRoot = watchRoot
        self.captureLimits = captureLimits
        self.callbackQueue = callbackQueue
    }

    var lifecycleSnapshot: FSEventRegistrationLifecycleSnapshot {
        lock.withLock { Self.snapshot(for: $0) }
    }

    func acquireCallbackLease(
        for expectedRegistration: FSEventRegistrationToken
    ) -> FSEventCallbackLeaseAcquisition {
        guard expectedRegistration == registration else { return .staleRegistration }
        enum AcquisitionTransition {
            case acquired(UInt64)
            case identityExhausted
            case closing
            case closed
        }
        let transition = lock.withLock { state -> AcquisitionTransition in
            switch state {
            case .open(var openState):
                let leaseID = openState.nextLeaseID
                let (nextLeaseID, overflow) = leaseID.addingReportingOverflow(1)
                guard !overflow else { return .identityExhausted }
                openState.nextLeaseID = nextLeaseID
                openState.activeLeaseIDs.insert(leaseID)
                state = .open(openState)
                return .acquired(leaseID)
            case .closing:
                return .closing
            case .closed:
                return .closed
            }
        }
        switch transition {
        case .acquired(let leaseID):
            return .acquired(
                FSEventCallbackLease(
                    controlBlock: self,
                    leaseID: leaseID,
                    registration: registration
                )
            )
        case .identityExhausted:
            return .leaseIdentityExhausted
        case .closing:
            return .closing
        case .closed:
            return .closed
        }
    }

    func beginClosing() -> FSEventRegistrationControlTransitionResult {
        lock.withLock { state in
            switch state {
            case .open(let openState):
                state = .closing(
                    ClosingState(
                        phase: .admissionClosed,
                        activeLeaseIDs: openState.activeLeaseIDs,
                        leaseDrainWaiters: []
                    )
                )
                return .applied
            case .closing:
                return .alreadyApplied
            case .closed:
                return .invalidTransition(.closed)
            }
        }
    }

    func markStreamInvalidated() -> FSEventRegistrationControlTransitionResult {
        advance(from: .admissionClosed, to: .streamInvalidated)
    }

    func markCallbackQueueDrained() -> FSEventCallbackQueueDrainResult {
        let waiters: [CheckedContinuation<Void, Never>]
        let result: FSEventCallbackQueueDrainResult
        (result, waiters) = lock.withLock { state in
            guard case .closing(var closingState) = state,
                closingState.phase == .streamInvalidated
            else {
                return (.invalidTransition(Self.snapshot(for: state)), [])
            }
            if closingState.activeLeaseIDs.isEmpty {
                closingState.phase = .leasesDrained
                let waiters = closingState.leaseDrainWaiters
                closingState.leaseDrainWaiters.removeAll(keepingCapacity: false)
                state = .closing(closingState)
                return (.leasesDrained, waiters)
            }
            closingState.phase = .callbackQueueDrained
            state = .closing(closingState)
            return (
                .waitingForLeases(activeLeaseCount: closingState.activeLeaseIDs.count),
                []
            )
        }
        for waiter in waiters { waiter.resume() }
        return result
    }

    func waitUntilLeasesDrained() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeImmediately = lock.withLock { state -> Bool in
                switch state {
                case .closing(var closingState):
                    if Self.isAtOrAfterLeasesDrained(closingState.phase) {
                        return true
                    }
                    closingState.leaseDrainWaiters.append(continuation)
                    state = .closing(closingState)
                    return false
                case .closed:
                    return true
                case .open:
                    preconditionFailure("lease drain wait requires closing registration")
                }
            }
            if resumeImmediately { continuation.resume() }
        }
    }

    func markRecoveryTransferred() -> FSEventRegistrationControlTransitionResult {
        advance(from: .leasesDrained, to: .recoveryTransferred)
    }

    func markMailboxGenerationInvalidated() -> FSEventRegistrationControlTransitionResult {
        advance(from: .recoveryTransferred, to: .mailboxGenerationInvalidated)
    }

    func finishClosing() -> FSEventRegistrationControlTransitionResult {
        lock.withLock { state in
            guard case .closing(let closingState) = state,
                closingState.phase == .mailboxGenerationInvalidated
            else {
                return .invalidTransition(Self.snapshot(for: state))
            }
            state = .closed
            return .applied
        }
    }

    fileprivate func releaseCallbackLease(
        leaseID: UInt64,
        registration: FSEventRegistrationToken
    ) -> FSEventCallbackLeaseReleaseResult {
        guard registration == self.registration else { return .unknownLease }
        let waiters: [CheckedContinuation<Void, Never>]?
        waiters = lock.withLock { state in
            switch state {
            case .open(var openState):
                guard openState.activeLeaseIDs.remove(leaseID) != nil else { return nil }
                state = .open(openState)
                return []
            case .closing(var closingState):
                guard closingState.activeLeaseIDs.remove(leaseID) != nil else { return nil }
                var waiters: [CheckedContinuation<Void, Never>] = []
                if closingState.phase == .callbackQueueDrained,
                    closingState.activeLeaseIDs.isEmpty
                {
                    closingState.phase = .leasesDrained
                    waiters = closingState.leaseDrainWaiters
                    closingState.leaseDrainWaiters.removeAll(keepingCapacity: false)
                }
                state = .closing(closingState)
                return waiters
            case .closed:
                return nil
            }
        }
        guard let waiters else { return .unknownLease }
        for waiter in waiters { waiter.resume() }
        return .released
    }

    private func advance(
        from expectedPhase: FSEventRegistrationClosingPhase,
        to nextPhase: FSEventRegistrationClosingPhase
    ) -> FSEventRegistrationControlTransitionResult {
        lock.withLock { state in
            guard case .closing(var closingState) = state,
                closingState.phase == expectedPhase
            else {
                return .invalidTransition(Self.snapshot(for: state))
            }
            closingState.phase = nextPhase
            state = .closing(closingState)
            return .applied
        }
    }

    private static func snapshot(for state: State) -> FSEventRegistrationLifecycleSnapshot {
        switch state {
        case .open(let openState):
            .open(activeLeaseCount: openState.activeLeaseIDs.count)
        case .closing(let closingState):
            .closing(closingState.phase, activeLeaseCount: closingState.activeLeaseIDs.count)
        case .closed:
            .closed
        }
    }

    private static func isAtOrAfterLeasesDrained(
        _ phase: FSEventRegistrationClosingPhase
    ) -> Bool {
        switch phase {
        case .admissionClosed, .streamInvalidated, .callbackQueueDrained:
            false
        case .leasesDrained, .recoveryTransferred, .mailboxGenerationInvalidated:
            true
        }
    }
}

enum FSEventRegistrationControlBlockError: Error, Equatable {
    case watchRootSourceMismatch
}
