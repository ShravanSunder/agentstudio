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

    private enum ShutdownResumeClaim: Sendable {
        case claimed(
            binding: ShutdownBinding,
            retainedDebt: FilesystemObservationFleetShutdownRetainedDebt
        )
        case shutdownNotBegun
        case shutdownFreezeInProgress
        case fleetMailboxMismatch(ShutdownBinding)
        case resumeAlreadyInProgress(FilesystemObservationFleetShutdownRetainedDebt)
        case shutdownRejected
    }

    private enum ShutdownTurnExecutionResult: Sendable {
        case executed
        case awaitingActorProgress(FilesystemFleetShutdownAwaitedActorProgress)
        case rejected(FilesystemObservationFleetShutdownResumeFailure)
    }

    private enum State: Sendable {
        case open
        case freezing(ShutdownBinding)
        case draining(
            ShutdownBinding,
            retainedDebt: FilesystemObservationFleetShutdownRetainedDebt
        )
        case resuming(
            ShutdownBinding,
            retainedDebt: FilesystemObservationFleetShutdownRetainedDebt
        )
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
            case .freezing(let binding), .draining(let binding, _), .resuming(let binding, _),
                .rejected(let binding):
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
                state = .draining(binding, retainedDebt: .awaitingInitialCapture)
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
            case .draining(let binding, _), .resuming(let binding, _):
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

    func resumeShutdown(
        mailbox: FilesystemObservationMailbox,
        drainPort: FilesystemObservationFleetShutdownDrainPort,
        contextFinalizer: any DarwinFSEventCallbackContextFinalizer =
            DarwinFSEventUnmanagedCallbackContextFinalizer()
    ) async -> FilesystemObservationFleetShutdownResumeResult {
        let claim = claimResume(mailbox: mailbox)

        let binding: ShutdownBinding
        let priorDebt: FilesystemObservationFleetShutdownRetainedDebt
        switch claim {
        case .claimed(let retainedBinding, let retainedDebt):
            binding = retainedBinding
            priorDebt = retainedDebt
        case .shutdownNotBegun:
            return .unavailable(.shutdownNotBegun)
        case .shutdownFreezeInProgress:
            return .unavailable(.shutdownFreezeInProgress)
        case .fleetMailboxMismatch(let retainedBinding):
            return .unavailable(
                .fleetMailboxMismatch(
                    expected: retainedBinding.fleetMailboxIdentity,
                    presented: mailbox.fleetMailboxIdentity
                )
            )
        case .resumeAlreadyInProgress(let retainedDebt):
            return .resumeAlreadyInProgress(retainedDebt)
        case .shutdownRejected:
            return .unavailable(.shutdownRejected)
        }

        let firstCapture = await shutdownDebtSnapshot(mailbox: mailbox, drainPort: drainPort)
        guard case .captured(let firstSnapshot, let firstPlan) = firstCapture else {
            restoreDrainingState(binding: binding, retainedDebt: priorDebt)
            return .unavailable(resumeFailure(from: firstCapture))
        }
        retainInFlightDebt(
            binding: binding,
            snapshot: firstSnapshot,
            turnPlan: firstPlan
        )

        let executionResult: ShutdownTurnExecutionResult
        switch firstPlan {
        case .advanceMailbox:
            executionResult = await executeMailboxTurn(
                mailbox: mailbox,
                binding: binding,
                contextFinalizer: contextFinalizer
            )
        case .advanceActorDrain:
            executionResult = await executeActorDrainTurn(drainPort: drainPort)
        case .beginSourceGateShutdown:
            _ = await drainPort.beginOneReadySourceGateShutdown()
            executionResult = .executed
        case .awaitOwnedProgress:
            return retainIncomplete(
                binding: binding,
                snapshot: firstSnapshot,
                turnPlan: firstPlan
            )
        case .readyForCompletion:
            return retainCompletion(binding: binding, finalDebt: firstSnapshot)
        }
        if case .rejected(let failure) = executionResult {
            restoreDrainingState(
                binding: binding,
                retainedDebt: .incomplete(snapshot: firstSnapshot, turnPlan: firstPlan)
            )
            return .unavailable(failure)
        }

        let freshCapture = await shutdownDebtSnapshot(mailbox: mailbox, drainPort: drainPort)
        guard case .captured(let freshSnapshot, let freshPlan) = freshCapture else {
            restoreDrainingState(
                binding: binding,
                retainedDebt: .incomplete(snapshot: firstSnapshot, turnPlan: firstPlan)
            )
            return .unavailable(resumeFailure(from: freshCapture))
        }
        guard freshPlan == .readyForCompletion else {
            if case .awaitingActorProgress(let awaitedProgress) = executionResult {
                retainDebt(binding: binding, snapshot: freshSnapshot, turnPlan: freshPlan)
                return .awaitingActorProgress(
                    awaitedProgress,
                    snapshot: freshSnapshot,
                    turnPlan: freshPlan
                )
            }
            return retainIncomplete(
                binding: binding,
                snapshot: freshSnapshot,
                turnPlan: freshPlan
            )
        }
        return retainCompletion(binding: binding, finalDebt: freshSnapshot)
    }

    private func claimResume(
        mailbox: FilesystemObservationMailbox
    ) -> ShutdownResumeClaim {
        lock.withLock { state in
            switch state {
            case .open:
                return .shutdownNotBegun
            case .freezing(let binding):
                guard binding.fleetMailboxIdentity == mailbox.fleetMailboxIdentity else {
                    return .fleetMailboxMismatch(binding)
                }
                return .shutdownFreezeInProgress
            case .draining(let binding, let retainedDebt):
                guard binding.fleetMailboxIdentity == mailbox.fleetMailboxIdentity else {
                    return .fleetMailboxMismatch(binding)
                }
                state = .resuming(binding, retainedDebt: retainedDebt)
                return .claimed(binding: binding, retainedDebt: retainedDebt)
            case .resuming(let binding, let retainedDebt):
                guard binding.fleetMailboxIdentity == mailbox.fleetMailboxIdentity else {
                    return .fleetMailboxMismatch(binding)
                }
                return .resumeAlreadyInProgress(retainedDebt)
            case .rejected:
                return .shutdownRejected
            }
        }
    }

    private func restoreDrainingState(
        binding: ShutdownBinding,
        retainedDebt: FilesystemObservationFleetShutdownRetainedDebt
    ) {
        lock.withLock { state in
            guard case .resuming(let retainedBinding, _) = state,
                retainedBinding.shutdownIdentity == binding.shutdownIdentity,
                retainedBinding.fleetMailboxIdentity == binding.fleetMailboxIdentity
            else { return }
            state = .draining(binding, retainedDebt: retainedDebt)
        }
    }

    private func retainInFlightDebt(
        binding: ShutdownBinding,
        snapshot: FilesystemObservationFleetShutdownDebtSnapshot,
        turnPlan: FilesystemObservationFleetShutdownTurnPlan
    ) {
        let retainedDebt = FilesystemObservationFleetShutdownRetainedDebt.incomplete(
            snapshot: snapshot,
            turnPlan: turnPlan
        )
        lock.withLock { state in
            guard case .resuming(let retainedBinding, _) = state,
                retainedBinding.shutdownIdentity == binding.shutdownIdentity,
                retainedBinding.fleetMailboxIdentity == binding.fleetMailboxIdentity
            else { return }
            state = .resuming(binding, retainedDebt: retainedDebt)
        }
    }

    private func retainIncomplete(
        binding: ShutdownBinding,
        snapshot: FilesystemObservationFleetShutdownDebtSnapshot,
        turnPlan: FilesystemObservationFleetShutdownTurnPlan
    ) -> FilesystemObservationFleetShutdownResumeResult {
        retainDebt(binding: binding, snapshot: snapshot, turnPlan: turnPlan)
        return .incomplete(snapshot: snapshot, turnPlan: turnPlan)
    }

    private func retainDebt(
        binding: ShutdownBinding,
        snapshot: FilesystemObservationFleetShutdownDebtSnapshot,
        turnPlan: FilesystemObservationFleetShutdownTurnPlan
    ) {
        let retainedDebt = FilesystemObservationFleetShutdownRetainedDebt.incomplete(
            snapshot: snapshot,
            turnPlan: turnPlan
        )
        lock.withLock { state in
            guard case .resuming(let retainedBinding, _) = state,
                retainedBinding.shutdownIdentity == binding.shutdownIdentity,
                retainedBinding.fleetMailboxIdentity == binding.fleetMailboxIdentity
            else { return }
            state = .draining(binding, retainedDebt: retainedDebt)
        }
    }

    private func retainCompletion(
        binding: ShutdownBinding,
        finalDebt: FilesystemObservationFleetShutdownDebtSnapshot
    ) -> FilesystemObservationFleetShutdownResumeResult {
        retainDebt(
            binding: binding,
            snapshot: finalDebt,
            turnPlan: .readyForCompletion
        )
        return .readyForCompletion(finalDebt)
    }

    private func executeMailboxTurn(
        mailbox: FilesystemObservationMailbox,
        binding: ShutdownBinding,
        contextFinalizer: any DarwinFSEventCallbackContextFinalizer
    ) async -> ShutdownTurnExecutionResult {
        switch await mailbox.advanceFleetShutdownOneTurn(
            for: binding.shutdownIdentity,
            contextFinalizer: contextFinalizer
        ) {
        case .progressed, .noProgress:
            return .executed
        case .shutdownNotFrozen:
            return .rejected(.mailboxShutdownNotFrozen)
        case .shutdownIdentityMismatch(let expected, let presented):
            return .rejected(
                .shutdownIdentityMismatch(expected: expected, presented: presented)
            )
        case .terminationAlreadyAdvanced(let lifecycle):
            return .rejected(.terminationAlreadyAdvanced(lifecycle))
        }
    }

    private func executeActorDrainTurn(
        drainPort: FilesystemObservationFleetShutdownDrainPort
    ) async -> ShutdownTurnExecutionResult {
        switch await drainPort.advanceOneTurn() {
        case .leaseTransfer, .cleanup:
            return .executed
        case .noProgress(.configurationRejected(let rejection)):
            return .rejected(.actorDrainConfigurationRejected(rejection))
        case .noProgress(.undeclaredBinding(let binding)):
            return .rejected(.actorDrainUndeclaredBinding(binding))
        case .noProgress(.mailboxClosed):
            return .rejected(.actorDrainMailboxClosed)
        case .noProgress(.recoveryContextUnavailable(let binding, let evidence)):
            return .awaitingActorProgress(
                .recoveryContextUnavailable(binding: binding, evidence: evidence)
            )
        case .noProgress(.mailboxEmpty), .noProgress(.activeLeaseAlreadyTaken):
            return .executed
        }
    }

    private func resumeFailure(
        from capture: FilesystemObservationFleetShutdownDebtCaptureResult
    ) -> FilesystemObservationFleetShutdownResumeFailure {
        switch capture {
        case .captured:
            preconditionFailure("Captured shutdown debt is not a resume failure")
        case .shutdownNotBegun:
            return .shutdownNotBegun
        case .shutdownFreezeInProgress:
            return .shutdownFreezeInProgress
        case .fleetMailboxMismatch(let expected, let presented):
            return .fleetMailboxMismatch(expected: expected, presented: presented)
        case .shutdownIdentityMismatch(let expected, let presented):
            return .shutdownIdentityMismatch(expected: expected, presented: presented)
        case .shutdownRejected:
            return .shutdownRejected
        case .terminationAlreadyAdvanced(let lifecycle):
            return .terminationAlreadyAdvanced(lifecycle)
        case .debtJoinRejected(let rejection):
            return .debtJoinRejected(rejection)
        }
    }
}
