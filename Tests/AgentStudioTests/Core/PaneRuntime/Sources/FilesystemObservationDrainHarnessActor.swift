import Dispatch
import Testing
import os

@testable import AgentStudio

enum FilesystemObservationDrainHarnessTakeResult: Sendable {
    case configurationRejected(
        FilesystemObservationFleetShutdownDrainConfigurationRejection
    )
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
    private enum ConfigurationPreflight: Sendable {
        case accepted
        case rejected(FilesystemObservationFleetShutdownDrainConfigurationRejection)
    }

    private enum RecoveryContextPreflight {
        case resolved(
            [FixedFilesystemRecoveryEvidenceRevision: FilesystemObservationRecoveryAdmissionContext]
        )
        case unavailable(
            binding: FilesystemObservationSlotBinding,
            evidence: FixedFilesystemRecoveryEvidenceRevision
        )
    }

    private let acknowledgementController: DrainHarnessAcknowledgementController
    private let configurationPreflight: ConfigurationPreflight
    private let consumerPort: FilesystemObservationActorConsumerPort
    private let waiterPort: FilesystemObservationActorWaiterPort
    private let bindingsInDeclarationOrder: [FilesystemObservationSlotBinding]
    private let recoveryEvidenceLookup:
        @Sendable (FilesystemObservationSlotBinding) -> FixedFilesystemRecoveryEvidenceSnapshotResult
    private let recoveryContextResolver: FilesystemObservationRecoveryContextResolver
    private var consumerBinding: AdmissionConsumerBinding
    private var transfer: FilesystemObservationLeaseTransfer
    private var sourceGatesByBinding: [FilesystemObservationSlotBinding: FilesystemSourceGate]
    private var semanticSink = FilesystemObservationDrainHarnessSemanticSink()

    init(
        mailbox: FilesystemObservationMailbox,
        bindings: [FilesystemObservationSlotBinding],
        maximumContributionsPerLease: Int,
        consumerPort suppliedConsumerPort: FilesystemObservationActorConsumerPort? = nil,
        recoveryContextResolver: FilesystemObservationRecoveryContextResolver = .unavailable
    ) throws {
        let baseConsumerPort = suppliedConsumerPort ?? mailbox.actorConsumerPort
        let acknowledgementController =
            DrainHarnessAcknowledgementController(
                underlyingPort: baseConsumerPort
            )
        self.acknowledgementController = acknowledgementController
        let mailboxPhysicalSlotIDsInDeclarationOrder = mailbox.physicalSlotIDs
        let actorPhysicalSlotIDsInDeclarationOrder = bindings.map(\.physicalSlotID)
        if actorPhysicalSlotIDsInDeclarationOrder.count
            == mailboxPhysicalSlotIDsInDeclarationOrder.count,
            Set(actorPhysicalSlotIDsInDeclarationOrder)
                == Set(mailboxPhysicalSlotIDsInDeclarationOrder)
        {
            configurationPreflight = .accepted
        } else {
            configurationPreflight = .rejected(
                .physicalSlotCoverageMismatch(
                    mailboxPhysicalSlotIDsInDeclarationOrder:
                        mailboxPhysicalSlotIDsInDeclarationOrder,
                    actorBindingsInDeclarationOrder: bindings
                )
            )
        }
        consumerPort = acknowledgementController.interceptedPort
        waiterPort = mailbox.actorWaiterPort
        bindingsInDeclarationOrder = bindings
        recoveryEvidenceLookup = { binding in
            mailbox.recoveryEvidence(for: binding)
        }
        self.recoveryContextResolver = recoveryContextResolver
        consumerBinding = consumerPort.bindConsumer().binding
        transfer = try FilesystemObservationLeaseTransfer(
            physicalSlotIDs: bindings.map(\.physicalSlotID),
            maximumContributionsPerLease: maximumContributionsPerLease
        )
        sourceGatesByBinding = Dictionary(
            uniqueKeysWithValues: bindings.map { ($0, FilesystemSourceGate(binding: $0)) }
        )
    }

    var fleetShutdownDrainPort: FilesystemObservationFleetShutdownDrainPort {
        FilesystemObservationFleetShutdownDrainPort(
            snapshot: { await self.fleetShutdownActorDebtSnapshot() },
            advanceOneTurn: { await self.advanceFleetShutdownDrainOneTurn() },
            beginOneReadySourceGateShutdown: {
                await self.beginOneReadySourceGateShutdown()
            }
        )
    }

    func takeLease() -> FilesystemObservationDrainHarnessTakeResult {
        if case .rejected(let rejection) = configurationPreflight {
            return .configurationRejected(rejection)
        }
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

    func replaceSourceGateForTesting(_ sourceGate: FilesystemSourceGate) -> Bool {
        guard sourceGatesByBinding[sourceGate.binding] != nil else { return false }
        sourceGatesByBinding[sourceGate.binding] = sourceGate
        return true
    }

    func sourceGateState(
        for binding: FilesystemObservationSlotBinding
    ) -> FilesystemObservationDrainHarnessSourceGateLookup {
        guard let state = sourceGatesByBinding[binding]?.state else {
            return .undeclaredBinding
        }
        return .state(state)
    }

    private func fleetShutdownActorDebtSnapshot()
        -> FilesystemObservationFleetShutdownActorDebtSnapshot
    {
        FilesystemObservationFleetShutdownActorDebtSnapshot(
            semanticReplay: transfer.semanticShutdownDebtSnapshot,
            sourceGatesInBindingDeclarationOrder: bindingsInDeclarationOrder.map(
                sourceGateShutdownDebt
            )
        )
    }

    private func sourceGateShutdownDebt(
        for binding: FilesystemObservationSlotBinding
    ) -> FilesystemSourceGateShutdownDebtSnapshot {
        guard let sourceGate = sourceGatesByBinding[binding] else {
            preconditionFailure("Declared SourceGate disappeared from actor ownership")
        }
        return sourceGate.shutdownDebtSnapshot
    }

    private func advanceFleetShutdownDrainOneTurn()
        -> FilesystemObservationFleetShutdownDrainAdvanceResult
    {
        if case .rejected(let rejection) = configurationPreflight {
            return .noProgress(.configurationRejected(rejection))
        }
        let recoveryContextsByRevision:
            [FixedFilesystemRecoveryEvidenceRevision: FilesystemObservationRecoveryAdmissionContext]
        switch preflightRecoveryContexts() {
        case .resolved(let resolvedContexts):
            recoveryContextsByRevision = resolvedContexts
        case .unavailable(let binding, let evidence):
            return .noProgress(
                .recoveryContextUnavailable(
                    binding: binding,
                    evidence: evidence
                )
            )
        }

        switch consumerPort.takeDrain(binding: consumerBinding) {
        case .lease(let lease):
            guard var sourceGate = sourceGatesByBinding[lease.binding] else {
                return .noProgress(.undeclaredBinding(lease.binding))
            }
            let recoveryContext = recoveryContext(
                for: lease,
                resolvedContextsByRevision: recoveryContextsByRevision
            )
            let result = transfer.transfer(
                lease,
                sourceGate: &sourceGate,
                recoveryContext: recoveryContext,
                semanticSink: &semanticSink,
                consumerPort: consumerPort
            )
            sourceGatesByBinding[lease.binding] = sourceGate
            return .leaseTransfer(binding: lease.binding, result)
        case .cleanupRequired:
            return .cleanup(consumerPort.performCleanup())
        case .empty:
            return .noProgress(.mailboxEmpty)
        case .alreadyLeased:
            return .noProgress(.activeLeaseAlreadyTaken)
        case .closed:
            return .noProgress(.mailboxClosed)
        }
    }

    private func beginOneReadySourceGateShutdown()
        -> FilesystemObservationSourceGateShutdownTurnResult
    {
        for binding in bindingsInDeclarationOrder {
            guard var sourceGate = sourceGatesByBinding[binding] else {
                preconditionFailure("Declared SourceGate disappeared from actor ownership")
            }
            guard sourceGate.shutdownDebtSnapshot.shutdownBeginReadiness == .ready else {
                continue
            }
            guard case .applied(let debt) = sourceGate.beginShutdown() else {
                preconditionFailure("Ready SourceGate did not begin shutdown")
            }
            sourceGatesByBinding[binding] = sourceGate
            return .applied(binding: binding, debt: debt)
        }

        let snapshot = fleetShutdownActorDebtSnapshot()
        if snapshot.sourceGatesInBindingDeclarationOrder.allSatisfy({
            $0.shutdownBeginReadiness == .alreadyBegan
        }) {
            return .allGatesAlreadyShutdown(snapshot)
        }
        return .outstandingDebt(snapshot)
    }

    private func preflightRecoveryContexts() -> RecoveryContextPreflight {
        var contextsByRevision:
            [FixedFilesystemRecoveryEvidenceRevision: FilesystemObservationRecoveryAdmissionContext] = [:]
        for binding in bindingsInDeclarationOrder {
            guard case .retained(let evidence) = recoveryEvidenceLookup(binding) else {
                continue
            }
            switch recoveryContextResolver.resolve(binding: binding, evidence: evidence) {
            case .resolved(let context):
                contextsByRevision[evidence.revision] = context
            case .unavailable:
                return .unavailable(
                    binding: binding,
                    evidence: evidence.revision
                )
            }
        }
        return .resolved(contextsByRevision)
    }

    private func recoveryContext(
        for lease: FilesystemObservationDrainLease,
        resolvedContextsByRevision: [FixedFilesystemRecoveryEvidenceRevision:
            FilesystemObservationRecoveryAdmissionContext]
    ) -> FilesystemObservationRecoveryAdmissionContext {
        let evidence: FixedFilesystemRecoveryEvidenceSnapshot
        switch lease.payload {
        case .contributions:
            return .notRequired
        case .contributionsWithRecovery(_, let retainedEvidence),
            .recovery(let retainedEvidence):
            evidence = retainedEvidence
        }
        guard let context = resolvedContextsByRevision[evidence.revision] else {
            preconditionFailure(
                "Fleet shutdown drain requires frozen recovery evidence before taking a lease"
            )
        }
        return context
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
