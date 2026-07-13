import Dispatch
import Foundation
import os

enum FSEventRegistrationClosingPhase: Equatable, Sendable {
    case admissionClosed
    case streamInvalidated
    case callbackQueueDrained
    case leasesDrained
}

enum FSEventRegistrationLifecycleSnapshot: Equatable, Sendable {
    case open(activeLeaseCount: Int)
    case closing(FSEventRegistrationClosingPhase, activeLeaseCount: Int)
}

enum FSEventCallbackLeaseDrainCompletionSnapshot: Equatable, Sendable {
    case pending(waiterCount: Int)
    case completed(resumedWaiterCount: Int)
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
    case leaseIdentityExhausted
    case closing
}

enum FSEventCallbackLeaseAuthorityRejection: Equatable, Sendable {
    case released
    case foreignControlBlock
    case registrationMismatch
    case slotBindingMismatch
    case captureConfigurationMismatch
    case alreadyConsumed
}

enum FSEventCallbackLeaseAdmissionResult<TResult: Sendable>: Sendable {
    case admitted(TResult)
    case authorityRejected(FSEventCallbackLeaseAuthorityRejection)
}

final class FSEventCallbackLease: @unchecked Sendable, Equatable {
    private enum Admission: Sendable {
        case available
        case consumed
    }

    private struct HeldState: Sendable {
        let controlBlock: FSEventRegistrationControlBlock
        let controlBlockIdentity: FilesystemObservationControlBlockIdentity
        let leaseID: UInt64
        let registration: FSEventRegistrationToken
        let binding: FilesystemObservationSlotBinding
        let captureLimits: FSEventCaptureLimits
        var admission: Admission
    }

    private enum State: Sendable {
        case held(HeldState)
        case released(registration: FSEventRegistrationToken)
    }

    private let lock: OSAllocatedUnfairLock<State>

    fileprivate init(
        controlBlock: FSEventRegistrationControlBlock,
        leaseID: UInt64
    ) {
        lock = OSAllocatedUnfairLock(
            initialState: .held(
                HeldState(
                    controlBlock: controlBlock,
                    controlBlockIdentity: controlBlock.controlBlockIdentity,
                    leaseID: leaseID,
                    registration: controlBlock.registration,
                    binding: controlBlock.binding,
                    captureLimits: controlBlock.captureLimits,
                    admission: .available
                )
            )
        )
    }

    static func == (lhs: FSEventCallbackLease, rhs: FSEventCallbackLease) -> Bool {
        lhs === rhs
    }

    var registration: FSEventRegistrationToken {
        lock.withLock { state in
            switch state {
            case .held(let heldState): heldState.registration
            case .released(let registration): registration
            }
        }
    }

    /// Executes one bounded callback admission while the lease remains held.
    ///
    /// The callback port supplies its bound admission authority. Rejection occurs before
    /// `body` runs, and the one-shot authority is consumed atomically with entry.
    func withOneShotCallbackAdmission<TResult: Sendable>(
        authority: FilesystemObservationMailboxCore.CallbackLeaseAdmissionAuthority,
        expectedCaptureLimits: FSEventCaptureLimits,
        _ body: () -> TResult
    ) -> FSEventCallbackLeaseAdmissionResult<TResult> {
        // The admission body executes synchronously while the lock is held and cannot escape.
        // It may close over callback-duration native pointers, so it must not be `Sendable`.
        lock.withLockUnchecked { state in
            switch state {
            case .released:
                return .authorityRejected(.released)
            case .held(var heldState):
                guard authority.controlBlockIdentity == heldState.controlBlockIdentity else {
                    return .authorityRejected(.foreignControlBlock)
                }
                guard authority.registration == heldState.registration else {
                    return .authorityRejected(.registrationMismatch)
                }
                guard authority.binding == heldState.binding else {
                    return .authorityRejected(.slotBindingMismatch)
                }
                guard expectedCaptureLimits == heldState.captureLimits else {
                    return .authorityRejected(.captureConfigurationMismatch)
                }
                guard heldState.admission == .available else {
                    return .authorityRejected(.alreadyConsumed)
                }
                heldState.admission = .consumed
                state = .held(heldState)
                return .admitted(body())
            }
        }
    }

    func release() -> FSEventCallbackLeaseReleaseResult {
        let heldOwner: (controlBlock: FSEventRegistrationControlBlock, leaseID: UInt64)? =
            lock.withLock { state in
                switch state {
                case .held(let heldState):
                    state = .released(registration: heldState.registration)
                    return (heldState.controlBlock, heldState.leaseID)
                case .released:
                    return nil
                }
            }
        guard let heldOwner else { return .alreadyReleased }
        return heldOwner.controlBlock.releaseCallbackLease(leaseID: heldOwner.leaseID)
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
    }

    private enum State: Sendable {
        case open(OpenState)
        case closing(ClosingState)
    }

    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let binding: FilesystemObservationSlotBinding
    let controlBlockIdentity: FilesystemObservationControlBlockIdentity
    let registration: FSEventRegistrationToken
    let watchRoot: WatchRoot
    let captureLimits: FSEventCaptureLimits
    let callbackQueue: DispatchQueue

    private let leaseDrainCompletion = FSEventCallbackLeaseDrainCompletion()
    private let lock = OSAllocatedUnfairLock(
        initialState: State.open(OpenState(activeLeaseIDs: [], nextLeaseID: 0))
    )

    init(
        startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        watchRoot: WatchRoot,
        captureLimits: FSEventCaptureLimits,
        callbackQueue: DispatchQueue
    ) throws {
        let binding = startingNativeLifetime.binding
        guard binding.registration.sourceID == watchRoot.sourceID else {
            throw FSEventRegistrationControlBlockError.watchRootSourceMismatch
        }
        self.startingNativeLifetime = startingNativeLifetime
        self.binding = binding
        controlBlockIdentity = binding.controlBlockIdentity
        registration = binding.registration
        self.watchRoot = watchRoot
        self.captureLimits = captureLimits
        self.callbackQueue = callbackQueue
    }

    var lifecycleSnapshot: FSEventRegistrationLifecycleSnapshot {
        lock.withLock { Self.snapshot(for: $0) }
    }

    var leaseDrainCompletionSnapshot: FSEventCallbackLeaseDrainCompletionSnapshot {
        leaseDrainCompletion.snapshot
    }

    func acquireCallbackLease() -> FSEventCallbackLeaseAcquisition {
        enum AcquisitionTransition {
            case acquired(UInt64)
            case identityExhausted
            case closing
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
            }
        }
        switch transition {
        case .acquired(let leaseID):
            return .acquired(FSEventCallbackLease(controlBlock: self, leaseID: leaseID))
        case .identityExhausted:
            return .leaseIdentityExhausted
        case .closing:
            return .closing
        }
    }

    func beginClosing() -> FSEventRegistrationControlTransitionResult {
        lock.withLock { state in
            switch state {
            case .open(let openState):
                state = .closing(
                    ClosingState(
                        phase: .admissionClosed,
                        activeLeaseIDs: openState.activeLeaseIDs
                    )
                )
                return .applied
            case .closing:
                return .alreadyApplied
            }
        }
    }

    func markStreamInvalidated() -> FSEventRegistrationControlTransitionResult {
        advance(from: .admissionClosed, to: .streamInvalidated)
    }

    func markCallbackQueueDrained() -> FSEventCallbackQueueDrainResult {
        let didDrainLeases: Bool
        let result: FSEventCallbackQueueDrainResult
        (result, didDrainLeases) = lock.withLock { state in
            guard case .closing(var closingState) = state,
                closingState.phase == .streamInvalidated
            else {
                return (.invalidTransition(Self.snapshot(for: state)), false)
            }
            if closingState.activeLeaseIDs.isEmpty {
                closingState.phase = .leasesDrained
                state = .closing(closingState)
                return (.leasesDrained, true)
            }
            closingState.phase = .callbackQueueDrained
            state = .closing(closingState)
            return (
                .waitingForLeases(activeLeaseCount: closingState.activeLeaseIDs.count),
                false
            )
        }
        if didDrainLeases { leaseDrainCompletion.complete() }
        return result
    }

    func waitUntilLeasesDrained() async {
        guard case .closing = lifecycleSnapshot else {
            preconditionFailure("lease drain wait requires closing registration")
        }
        await leaseDrainCompletion.wait()
    }

    fileprivate func releaseCallbackLease(
        leaseID: UInt64
    ) -> FSEventCallbackLeaseReleaseResult {
        let transition: (released: Bool, didDrainLeases: Bool) = lock.withLock { state in
            switch state {
            case .open(var openState):
                guard openState.activeLeaseIDs.remove(leaseID) != nil else {
                    return (false, false)
                }
                state = .open(openState)
                return (true, false)
            case .closing(var closingState):
                guard closingState.activeLeaseIDs.remove(leaseID) != nil else {
                    return (false, false)
                }
                let didDrainLeases =
                    closingState.phase == .callbackQueueDrained
                    && closingState.activeLeaseIDs.isEmpty
                if didDrainLeases {
                    closingState.phase = .leasesDrained
                }
                state = .closing(closingState)
                return (true, didDrainLeases)
            }
        }
        guard transition.released else { return .unknownLease }
        if transition.didDrainLeases { leaseDrainCompletion.complete() }
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
        }
    }
}

/// Lazily retains only callers that actually wait for the bounded drain event.
private final class FSEventCallbackLeaseDrainCompletion: @unchecked Sendable {
    private enum State: Sendable {
        case pending([CheckedContinuation<Void, Never>])
        case completed(resumedWaiterCount: Int)
    }

    private let lock = OSAllocatedUnfairLock(initialState: State.pending([]))

    var snapshot: FSEventCallbackLeaseDrainCompletionSnapshot {
        lock.withLock { state in
            switch state {
            case .pending(let waiters):
                .pending(waiterCount: waiters.count)
            case .completed(let resumedWaiterCount):
                .completed(resumedWaiterCount: resumedWaiterCount)
            }
        }
    }

    func complete() {
        let waiters = lock.withLock { state -> [CheckedContinuation<Void, Never>] in
            switch state {
            case .pending(let waiters):
                state = .completed(resumedWaiterCount: waiters.count)
                return waiters
            case .completed:
                return []
            }
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResumeImmediately = lock.withLock { state in
                switch state {
                case .pending(var waiters):
                    waiters.append(continuation)
                    state = .pending(waiters)
                    return false
                case .completed:
                    return true
                }
            }
            if shouldResumeImmediately {
                continuation.resume()
            }
        }
    }
}

enum FSEventRegistrationControlBlockError: Error, Equatable {
    case watchRootSourceMismatch
}
