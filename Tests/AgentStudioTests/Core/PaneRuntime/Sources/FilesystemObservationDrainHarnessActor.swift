import Dispatch
import Testing
import os

@testable import AgentStudio

enum FilesystemObservationDrainHarnessTakeResult: Sendable {
    case lease(FilesystemObservationDrainLease)
    case cleanupRequired
    case empty
    case alreadyLeased
    case closed
}

enum FilesystemObservationDrainHarnessTransferResult: Sendable {
    case completed(FilesystemObservationLeaseTransferResult)
    case undeclaredBinding(FilesystemObservationSlotBinding)
}

private enum DrainHarnessAcceptanceDirective: Sendable {
    case acceptAll
    case retryBefore(FilesystemObservationContributionIdentity)
}

private struct FilesystemObservationDrainHarnessSemanticSink:
    FilesystemObservationSemanticCustodySink,
    Sendable
{
    private var acceptanceDirective: DrainHarnessAcceptanceDirective =
        .acceptAll
    private(set) var acceptanceCountByIdentity: [FilesystemObservationContributionIdentity: Int] = [:]

    mutating func requestRetry(
        before identity: FilesystemObservationContributionIdentity
    ) {
        acceptanceDirective = .retryBefore(identity)
    }

    mutating func accept(
        _ observation: FSEventObservation,
        identity: FilesystemObservationContributionIdentity
    ) -> FilesystemObservationSemanticCustodyResult {
        switch acceptanceDirective {
        case .retryBefore(let retryIdentity) where retryIdentity == identity:
            acceptanceDirective = .acceptAll
            return .retryRequested
        case .acceptAll, .retryBefore:
            precondition(observation.registration == identity.binding.registration)
            acceptanceCountByIdentity[identity, default: 0] += 1
            return .accepted
        }
    }
}

private final class DrainHarnessAcknowledgementController:
    @unchecked Sendable
{
    private enum Disposition: Sendable {
        case delegate
        case rejectNextThenDelegate
        case replayPreviousReceiptThenDelegate
    }

    private enum AcknowledgementDecision: Sendable {
        case delegate
        case reject
        case replay(FilesystemLeaseAcknowledgementReceipt)
    }

    private enum ReceiptHistory: Sendable {
        case vacant
        case retained(FilesystemLeaseAcknowledgementReceipt)
    }

    private struct State: Sendable {
        var disposition: Disposition = .delegate
        var receiptHistory: ReceiptHistory = .vacant
    }

    private let underlyingPort: FilesystemObservationActorConsumerPort
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(underlyingPort: FilesystemObservationActorConsumerPort) {
        self.underlyingPort = underlyingPort
    }

    var interceptedPort: FilesystemObservationActorConsumerPort {
        FilesystemObservationActorConsumerPort(
            bind: underlyingPort.bindConsumer,
            take: underlyingPort.takeDrain,
            acknowledge: acknowledge,
            cleanup: underlyingPort.performCleanup,
            preflightWholeLeaseTransfer: underlyingPort.preflightWholeLeaseTransfer,
            completeWholeLeaseTransfer: underlyingPort.completeWholeLeaseTransfer
        )
    }

    func rejectNextAcknowledgement() {
        state.withLock { state in
            state.disposition = .rejectNextThenDelegate
        }
    }

    func replayPreviousAcknowledgementReceiptOnce() -> Bool {
        state.withLock { state in
            guard case .retained = state.receiptHistory else { return false }
            state.disposition = .replayPreviousReceiptThenDelegate
            return true
        }
    }

    private func acknowledge(
        token: AdmissionDrainToken,
        disposition requestedDisposition: FilesystemObservationDrainDisposition
    ) -> FilesystemObservationDrainAcknowledgement {
        let decision = state.withLock { state in
            switch state.disposition {
            case .delegate:
                return AcknowledgementDecision.delegate
            case .rejectNextThenDelegate:
                state.disposition = .delegate
                return AcknowledgementDecision.reject
            case .replayPreviousReceiptThenDelegate:
                state.disposition = .delegate
                guard case .retained(let receipt) = state.receiptHistory else {
                    preconditionFailure("Scheduled stale ACK replay lost retained receipt")
                }
                return .replay(receipt)
            }
        }
        switch decision {
        case .reject:
            return .invalidToken
        case .delegate:
            let acknowledgement = underlyingPort.acknowledge(
                token: token,
                disposition: requestedDisposition
            )
            switch acknowledgement {
            case .transferredAuthoritative(let receipt, _),
                .transferredRecovery(let receipt, _, _):
                state.withLock { state in
                    state.receiptHistory = .retained(receipt)
                }
            case .retried, .dispositionMismatch, .invalidToken, .closed:
                break
            }
            return acknowledgement
        case .replay(let staleReceipt):
            switch requestedDisposition {
            case .transferredAuthoritative:
                return .transferredAuthoritative(receipt: staleReceipt, wake: .noWake)
            case .transferredRecovery(_, let acceptance):
                return .transferredRecovery(
                    receipt: staleReceipt,
                    evidence: .cleared(acceptance.acceptedEvidence.revision),
                    wake: .noWake
                )
            case .retry:
                return .invalidToken
            }
        }
    }
}

/// Dormant H2 integration harness. The actor is the sole owner of one consumer,
/// one waiter, the task-free transfer state, SourceGate state, and semantic sink.
actor FilesystemObservationDrainHarnessActor {
    private let acknowledgementController: DrainHarnessAcknowledgementController
    private let consumerPort: FilesystemObservationActorConsumerPort
    private let waiterPort: FilesystemObservationActorWaiterPort
    private var consumerBinding: AdmissionConsumerBinding
    private var transfer: FilesystemObservationLeaseTransfer
    private var sourceGatesByBinding: [FilesystemObservationSlotBinding: FilesystemSourceGate]
    private var semanticSink = FilesystemObservationDrainHarnessSemanticSink()

    init(
        mailbox: FilesystemObservationMailbox,
        bindings: [FilesystemObservationSlotBinding],
        maximumContributionsPerLease: Int
    ) throws {
        let acknowledgementController =
            DrainHarnessAcknowledgementController(
                underlyingPort: mailbox.actorConsumerPort
            )
        self.acknowledgementController = acknowledgementController
        consumerPort = acknowledgementController.interceptedPort
        waiterPort = mailbox.actorWaiterPort
        consumerBinding = consumerPort.bindConsumer().binding
        transfer = try FilesystemObservationLeaseTransfer(
            physicalSlotIDs: bindings.map(\.physicalSlotID),
            maximumContributionsPerLease: maximumContributionsPerLease
        )
        sourceGatesByBinding = Dictionary(
            uniqueKeysWithValues: bindings.map { ($0, FilesystemSourceGate(binding: $0)) }
        )
    }

    func takeLease() -> FilesystemObservationDrainHarnessTakeResult {
        switch consumerPort.takeDrain(binding: consumerBinding) {
        case .lease(let lease):
            return .lease(lease)
        case .cleanupRequired:
            return .cleanupRequired
        case .empty:
            return .empty
        case .alreadyLeased:
            return .alreadyLeased
        case .closed:
            return .closed
        }
    }

    func transferLease(
        _ lease: FilesystemObservationDrainLease,
        recoveryContext: FilesystemObservationRecoveryAdmissionContext
    ) -> FilesystemObservationDrainHarnessTransferResult {
        guard var sourceGate = sourceGatesByBinding[lease.binding] else {
            return .undeclaredBinding(lease.binding)
        }
        let result = transfer.transfer(
            lease,
            sourceGate: &sourceGate,
            recoveryContext: recoveryContext,
            semanticSink: &semanticSink,
            consumerPort: consumerPort
        )
        sourceGatesByBinding[lease.binding] = sourceGate
        return .completed(result)
    }

    func requestSemanticRetry(
        before identity: FilesystemObservationContributionIdentity
    ) {
        semanticSink.requestRetry(before: identity)
    }

    func rejectNextAcknowledgement() {
        acknowledgementController.rejectNextAcknowledgement()
    }

    func replayPreviousAcknowledgementReceiptOnce() -> Bool {
        acknowledgementController.replayPreviousAcknowledgementReceiptOnce()
    }

    func rebindConsumer() {
        consumerBinding = consumerPort.bindConsumer().binding
    }

    func nextSignal() async -> AdmissionDoorbellResult {
        await waiterPort.nextSignal()
    }

    func semanticAcceptanceCount(
        for identity: FilesystemObservationContributionIdentity
    ) -> Int {
        semanticSink.acceptanceCountByIdentity[identity, default: 0]
    }

    var transferDiagnostics: FilesystemObservationLeaseTransferDiagnostics {
        transfer.diagnostics
    }

    func sourceGateState(
        for binding: FilesystemObservationSlotBinding
    ) -> FilesystemObservationDrainHarnessSourceGateLookup {
        guard let state = sourceGatesByBinding[binding]?.state else {
            return .undeclaredBinding
        }
        return .state(state)
    }
}

enum FilesystemObservationDrainHarnessSourceGateLookup: Sendable {
    case state(FilesystemSourceGateState)
    case undeclaredBinding
}

func leaseTransferMailboxLimits() -> GatherMailboxLimits {
    GatherMailboxLimits(
        maximumDeclaredKeys: 1,
        maximumRetainedContributions: 8,
        maximumRetainedItems: 8,
        maximumRetainedBytes: 65_536,
        maximumRetainedContributionsPerKey: 8,
        maximumRetainedItemsPerKey: 8,
        maximumRetainedBytesPerKey: 65_536,
        maximumContributionsPerLease: 3,
        maximumItemsPerLease: 8,
        maximumBytesPerLease: 65_536,
        cleanupQuantum: .entriesAndBytes(maximumEntries: 8, maximumBytes: 65_536)
    )
}

func recoveryOnlyLeaseTransferMailboxLimits() -> GatherMailboxLimits {
    GatherMailboxLimits(
        maximumDeclaredKeys: 1,
        maximumRetainedContributions: 0,
        maximumRetainedItems: 1,
        maximumRetainedBytes: 256,
        maximumRetainedContributionsPerKey: 1,
        maximumRetainedItemsPerKey: 1,
        maximumRetainedBytesPerKey: 256,
        maximumContributionsPerLease: 1,
        maximumItemsPerLease: 1,
        maximumBytesPerLease: 256,
        cleanupQuantum: .entriesAndBytes(maximumEntries: 1, maximumBytes: 256)
    )
}

final class LeaseTransferCallbackAdapter:
    DarwinFSEventRegistrationCallbackAdapter,
    @unchecked Sendable
{
    let controlBlock: FSEventRegistrationControlBlock
    let callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort

    init(
        controlBlock: FSEventRegistrationControlBlock,
        callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort
    ) {
        self.controlBlock = controlBlock
        self.callbackAdmissionPort = callbackAdmissionPort
    }

    func capture(
        input _: DarwinFSEventNativeCallbackInput
    ) -> DarwinFSEventObservationCaptureResult {
        .ignoredEmptyCallback
    }
}

struct LeaseTransferNativeDriver: DarwinFSEventNativeDriver {
    func createStream(
        request _: DarwinFSEventNativeStreamCreationRequest
    ) -> Result<DarwinFSEventNativeStreamHandle, DarwinFSEventNativeStreamCreationFailure> {
        .success(.testHandle())
    }

    func startStream(_: DarwinFSEventNativeStreamHandle) -> Bool { true }
    func stopStream(_: DarwinFSEventNativeStreamHandle) {}
    func invalidateStream(_: DarwinFSEventNativeStreamHandle) {}
    func releaseStream(_: DarwinFSEventNativeStreamHandle) {}
}

struct LeaseTransferCallbackQueueBarrier: DarwinFSEventCallbackQueueBarrier {
    func waitForBarrier(on _: DispatchQueue) async {}
}
