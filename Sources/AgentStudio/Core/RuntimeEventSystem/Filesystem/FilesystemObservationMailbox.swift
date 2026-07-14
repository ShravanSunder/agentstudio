/// Domain-facing filesystem observation mailbox.
///
/// This façade exposes the typed callback, actor, and lifecycle ports while the
/// lock-backed custody transaction remains owned by
/// `FilesystemObservationMailboxCore`. Forwarding through this façade adds no
/// actor, queue, lock, event hop, or runtime authority.
final class FilesystemObservationMailbox: @unchecked Sendable {
    private let core: FilesystemObservationMailboxCore

    init(
        generation: AdmissionGeneration,
        maximumSimultaneousSourceCount: Int,
        replacementReserveSlotCount: Int,
        limits: GatherMailboxLimits,
        recoveryAuthoritySeed: FilesystemObservationRecoveryAuthoritySeed = .initial
    ) throws {
        core = try FilesystemObservationMailboxCore(
            generation: generation,
            maximumSimultaneousSourceCount: maximumSimultaneousSourceCount,
            replacementReserveSlotCount: replacementReserveSlotCount,
            limits: limits,
            recoveryAuthoritySeed: recoveryAuthoritySeed
        )
    }

    var fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity {
        core.fleetMailboxIdentity
    }

    var physicalSlotIDs: [FilesystemObservationPhysicalSlotID] {
        core.physicalSlotIDs
    }

    func freezeFleetIngress(
        for shutdownIdentity: FilesystemObservationFleetShutdownIdentity
    ) -> FilesystemObservationFleetIngressFreezeResult {
        core.freezeFleetIngress(for: shutdownIdentity)
    }

    func freezeFleetIngressAndSnapshot(
        for shutdownIdentity: FilesystemObservationFleetShutdownIdentity
    ) -> FilesystemObservationFleetIngressFreezeAndSnapshotResult {
        core.freezeFleetIngressAndSnapshot(for: shutdownIdentity)
    }

    func fleetShutdownDebtSnapshot(
        for shutdownIdentity: FilesystemObservationFleetShutdownIdentity
    ) -> FilesystemObservationFleetIngressFreezeAndSnapshotResult {
        core.fleetShutdownDebtSnapshot(for: shutdownIdentity)
    }

    func advanceFleetShutdownOneTurn(
        for shutdownIdentity: FilesystemObservationFleetShutdownIdentity,
        contextFinalizer: any DarwinFSEventCallbackContextFinalizer =
            DarwinFSEventUnmanagedCallbackContextFinalizer()
    ) async -> FilesystemObservationFleetShutdownProgressResult {
        await core.advanceFleetShutdownOneTurn(
            for: shutdownIdentity,
            contextFinalizer: contextFinalizer
        )
    }

    func installDesiredConfiguration(
        _ configuration: FilesystemObservationSourceConfiguration,
        acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision
    ) -> FilesystemObservationDesiredUpdateResult {
        core.installDesiredConfiguration(
            configuration,
            acceptedTopologyRevision: acceptedTopologyRevision
        )
    }

    func admitConfigurationIntents(
        _ batch: FilesystemSourceConfigurationIntentBatch
    ) -> FilesystemConfigurationIntentBatchAdmissionResult {
        core.admitConfigurationIntents(batch)
    }

    func selectNextDesiredSource() -> FilesystemObservationDesiredSelectionResult {
        core.selectNextDesiredSource()
    }

    func beginNativeLifetime(
        _ reservation: FilesystemObservationSlotReservation
    ) -> FilesystemObservationNativeLifetimeCommitResult {
        core.beginNativeLifetime(reservation)
    }

    func retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
        _ failedStartingNativeLifetime: FilesystemObservationStartingNativeLifetime
    ) -> FilesystemObservationNativeLifetimeFailureResult {
        core.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
            failedStartingNativeLifetime
        )
    }

    func nativeGenerationPorts(
        for startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
        synchronization: any FilesystemObservationCallbackSynchronization =
            ImmediateFilesystemObservationCallbackSynchronization()
    ) -> FilesystemObservationNativeGenerationPortCreationResult {
        core.nativeGenerationPorts(
            for: startingNativeLifetime,
            retaining: self,
            synchronization: synchronization
        )
    }

    func physicalSlotState(
        of physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FilesystemObservationPhysicalSlotState {
        core.physicalSlotState(of: physicalSlotID)
    }

    var actorConsumerPort: FilesystemObservationActorConsumerPort {
        core.actorConsumerPort
    }

    var actorWaiterPort: FilesystemObservationActorWaiterPort {
        core.actorWaiterPort
    }

    var lifecyclePort: FilesystemObservationLifecyclePort {
        core.lifecyclePort
    }

    func bindConsumer() -> AdmissionConsumerBindResult {
        core.bindConsumer()
    }

    func takeDrain(
        binding: AdmissionConsumerBinding
    ) -> FilesystemObservationTakeDrainResult {
        core.takeDrain(binding: binding)
    }

    func acknowledge(
        token: AdmissionDrainToken,
        disposition: FilesystemObservationDrainDisposition
    ) -> FilesystemObservationDrainAcknowledgement {
        core.acknowledge(token: token, disposition: disposition)
    }

    func performCleanup() -> AdmissionCleanupTurnResult {
        core.performCleanup()
    }

    func seal() -> FilesystemObservationLifecycleTransitionResult {
        core.seal()
    }

    func invalidate() -> FilesystemObservationLifecycleTransitionResult {
        core.invalidate()
    }

    func finish() -> FilesystemObservationLifecycleTransitionResult {
        core.finish()
    }

    var diagnostics: FilesystemObservationMailboxDiagnostics {
        core.diagnostics
    }

    func recoveryEvidence(
        for binding: FilesystemObservationSlotBinding
    ) -> FixedFilesystemRecoveryEvidenceSnapshotResult {
        core.recoveryEvidence(for: binding)
    }
}
