import Foundation
import os

struct FilesystemObservationFleetShutdownIdentity: Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    fileprivate init() {
        value = UUIDv7.generate()
    }
}

enum FilesystemObservationFleetIngressLifecycle: Equatable, Sendable {
    case accepting
    case shutdownFrozen(FilesystemObservationFleetShutdownIdentity)
}

struct FilesystemObservationFleetAdmissionExhaustionDebt: Equatable, Sendable {
    let triggeringBinding: FilesystemObservationSlotBinding
    let terminalGenericRecoveryRevision: GatherRecoveryRevision<FilesystemObservationPhysicalSlotID>
}

enum FilesystemFleetOrdinaryAdmissionDisposition: Equatable, Sendable {
    case ordinary
    case fleetAdmissionExhausted(FilesystemObservationFleetAdmissionExhaustionDebt)
}

enum FilesystemObservationFleetIngressFreezeResult: Equatable, Sendable {
    case applied(FilesystemObservationFleetShutdownIdentity)
    case alreadyApplied(FilesystemObservationFleetShutdownIdentity)
    case fleetMailboxMismatch(
        expected: FilesystemObservationFleetMailboxIdentity,
        presented: FilesystemObservationFleetMailboxIdentity
    )
    case shutdownIdentityMismatch(
        expected: FilesystemObservationFleetShutdownIdentity,
        presented: FilesystemObservationFleetShutdownIdentity
    )
    case terminationAlreadyAdvanced(FilesystemObservationLifecycleStateSnapshot)
}

// swiftlint:disable:next type_name
enum FilesystemObservationFleetShutdownDebtCaptureResult: Equatable, Sendable {
    case captured(
        snapshot: FilesystemObservationFleetShutdownDebtSnapshot,
        turnPlan: FilesystemObservationFleetShutdownTurnPlan
    )
    case shutdownNotBegun
    case shutdownFreezeInProgress
    case fleetMailboxMismatch(
        expected: FilesystemObservationFleetMailboxIdentity,
        presented: FilesystemObservationFleetMailboxIdentity
    )
    case shutdownIdentityMismatch(
        expected: FilesystemObservationFleetShutdownIdentity,
        presented: FilesystemObservationFleetShutdownIdentity
    )
    case shutdownRejected
    case terminationAlreadyAdvanced(FilesystemObservationLifecycleStateSnapshot)
    case debtJoinRejected(FilesystemObservationFleetShutdownDebtJoinRejection)
}

final class FilesystemObservationFleetLifecycle: @unchecked Sendable {
    private struct ShutdownBinding: Sendable {
        let fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity
        let shutdownIdentity: FilesystemObservationFleetShutdownIdentity
    }

    private enum ShutdownBindingResolution: Sendable {
        case bound(ShutdownBinding)
        case fleetMailboxMismatch(ShutdownBinding)
    }

    private enum ShutdownDebtCaptureBindingResolution: Sendable {
        case bound(ShutdownBinding)
        case shutdownNotBegun
        case shutdownFreezeInProgress
        case fleetMailboxMismatch(ShutdownBinding)
        case shutdownRejected
    }

    private enum State: Sendable {
        case open
        case freezing(ShutdownBinding)
        case draining(ShutdownBinding)
        case rejected(ShutdownBinding)
    }

    private let lock = OSAllocatedUnfairLock(initialState: State.open)

    @discardableResult
    func beginShutdown(
        mailbox: FilesystemObservationMailbox
    ) -> FilesystemObservationFleetIngressFreezeResult {
        switch beginShutdownAndSnapshot(mailbox: mailbox) {
        case .applied(let snapshot):
            return .applied(snapshot.shutdownIdentity)
        case .alreadyApplied(let snapshot):
            return .alreadyApplied(snapshot.shutdownIdentity)
        case .fleetMailboxMismatch(let expected, let presented):
            return .fleetMailboxMismatch(expected: expected, presented: presented)
        case .shutdownIdentityMismatch(let expected, let presented):
            return .shutdownIdentityMismatch(expected: expected, presented: presented)
        case .terminationAlreadyAdvanced(let lifecycle):
            return .terminationAlreadyAdvanced(lifecycle)
        }
    }

    func beginShutdownAndSnapshot(
        mailbox: FilesystemObservationMailbox
    ) -> FilesystemObservationFleetIngressFreezeAndSnapshotResult {
        let bindingResult = lock.withLock { state -> ShutdownBindingResolution in
            switch state {
            case .open:
                let binding = ShutdownBinding(
                    fleetMailboxIdentity: mailbox.fleetMailboxIdentity,
                    shutdownIdentity: FilesystemObservationFleetShutdownIdentity()
                )
                state = .freezing(binding)
                return .bound(binding)
            case .freezing(let binding), .draining(let binding), .rejected(let binding):
                guard binding.fleetMailboxIdentity == mailbox.fleetMailboxIdentity else {
                    return .fleetMailboxMismatch(binding)
                }
                return .bound(binding)
            }
        }

        let binding: ShutdownBinding
        switch bindingResult {
        case .bound(let retainedBinding):
            binding = retainedBinding
        case .fleetMailboxMismatch(let retainedBinding):
            return .fleetMailboxMismatch(
                expected: retainedBinding.fleetMailboxIdentity,
                presented: mailbox.fleetMailboxIdentity
            )
        }

        let result = mailbox.freezeFleetIngressAndSnapshot(for: binding.shutdownIdentity)
        lock.withLock { state in
            guard
                case .freezing(let retainedBinding) = state,
                retainedBinding.shutdownIdentity == binding.shutdownIdentity,
                retainedBinding.fleetMailboxIdentity == binding.fleetMailboxIdentity
            else {
                return
            }
            switch result {
            case .applied, .alreadyApplied:
                state = .draining(binding)
            case .fleetMailboxMismatch:
                preconditionFailure("Bound mailbox returned a fleet mailbox mismatch")
            case .shutdownIdentityMismatch, .terminationAlreadyAdvanced:
                state = .rejected(binding)
            }
        }
        return result
    }

    func shutdownDebtSnapshot(
        mailbox: FilesystemObservationMailbox,
        drainPort: FilesystemObservationFleetShutdownDrainPort
    ) async -> FilesystemObservationFleetShutdownDebtCaptureResult {
        let bindingResolution = lock.withLock { state in
            switch state {
            case .open:
                return ShutdownDebtCaptureBindingResolution.shutdownNotBegun
            case .freezing(let binding):
                guard binding.fleetMailboxIdentity == mailbox.fleetMailboxIdentity else {
                    return .fleetMailboxMismatch(binding)
                }
                return .shutdownFreezeInProgress
            case .draining(let binding):
                guard binding.fleetMailboxIdentity == mailbox.fleetMailboxIdentity else {
                    return .fleetMailboxMismatch(binding)
                }
                return .bound(binding)
            case .rejected:
                return .shutdownRejected
            }
        }

        let binding: ShutdownBinding
        switch bindingResolution {
        case .bound(let retainedBinding):
            binding = retainedBinding
        case .shutdownNotBegun:
            return .shutdownNotBegun
        case .shutdownFreezeInProgress:
            return .shutdownFreezeInProgress
        case .fleetMailboxMismatch(let retainedBinding):
            return .fleetMailboxMismatch(
                expected: retainedBinding.fleetMailboxIdentity,
                presented: mailbox.fleetMailboxIdentity
            )
        case .shutdownRejected:
            return .shutdownRejected
        }

        let mailboxSnapshot: FilesystemObservationFleetShutdownMailboxDebtSnapshot
        switch mailbox.fleetShutdownDebtSnapshot(for: binding.shutdownIdentity) {
        case .applied(let snapshot), .alreadyApplied(let snapshot):
            mailboxSnapshot = snapshot
        case .fleetMailboxMismatch(let expected, let presented):
            return .fleetMailboxMismatch(expected: expected, presented: presented)
        case .shutdownIdentityMismatch(let expected, let presented):
            return .shutdownIdentityMismatch(expected: expected, presented: presented)
        case .terminationAlreadyAdvanced(let lifecycle):
            return .terminationAlreadyAdvanced(lifecycle)
        }

        let actorSnapshot = await drainPort.snapshot()
        switch FilesystemObservationFleetShutdownDebtJoiner.join(
            mailbox: mailboxSnapshot,
            actor: actorSnapshot
        ) {
        case .joined(let snapshot):
            return .captured(
                snapshot: snapshot,
                turnPlan: FilesystemObservationFleetShutdownTurnPlanner.plan(snapshot)
            )
        case .rejected(let rejection):
            return .debtJoinRejected(rejection)
        }
    }
}
