import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation fleet shutdown mailbox debt")
struct FilesystemObservationFleetShutdownDebtTests {
    private let generation = AdmissionGeneration(owner: .filesystemObservation, value: 951)

    @Test("freeze snapshots every physical slot in declaration order with exact owner debt")
    func freezeSnapshotsDeclarationOrderedExactOwnerDebt() throws {
        let startingRegistration = makeFleetRegistration(index: 951)
        let selectedRegistration = makeFleetRegistration(index: 952)
        let mailbox = try makeMailbox(slotCount: 3)
        #expect(mailbox.installTestConfiguration(startingRegistration).isShutdownDebtEnqueued)
        #expect(mailbox.installTestConfiguration(selectedRegistration).isShutdownDebtEnqueued)
        let startingSelection = requireShutdownDebtSelection(mailbox.selectNextDesiredSource())
        let startingLifetime = requireShutdownDebtStartingLifetime(
            mailbox.beginNativeLifetime(startingSelection.reservation)
        )
        let nativePorts = requireShutdownDebtNativePorts(
            mailbox.nativeGenerationPorts(for: startingLifetime)
        )
        let selected = requireShutdownDebtSelection(mailbox.selectNextDesiredSource())
        let observation = try makeObservation(
            registration: startingRegistration,
            path: "/shutdown-debt/queued",
            eventID: 951
        )
        expectShutdownDebtRetainedCallback(
            try admitShutdownDebtCallback(
                .authoritative(observation),
                startingLifetime: startingLifetime,
                nativePorts: nativePorts
            )
        )
        let lifecycle = FilesystemObservationFleetLifecycle()

        let snapshot = requireAppliedShutdownDebtSnapshot(
            lifecycle.beginShutdownAndSnapshot(mailbox: mailbox)
        )

        #expect(snapshot.shutdownIdentity.isUUIDv7)
        #expect(snapshot.fleetIngressLifecycle == .shutdownFrozen(snapshot.shutdownIdentity))
        #expect(snapshot.mailboxLifecycle == .open)
        #expect(snapshot.slots.map(\.physicalSlotID) == mailbox.physicalSlotIDs)
        #expect(snapshot.slots.count == 3)

        let startingSlot = snapshot.slots[0]
        guard case .starting(let startingReference) = startingSlot.registry.lifecycle else {
            Issue.record("First slot must retain starting registry lifecycle debt")
            return
        }
        #expect(startingReference.binding == startingLifetime.binding)
        #expect(startingSlot.generic.key == startingLifetime.binding.physicalSlotID)
        #expect(startingSlot.generic.queuedContributionCount == 1)
        #expect(startingSlot.recoveryEvidence == .clear(startingLifetime.binding))
        #expect(startingSlot.retryEvidence == .vacant)
        guard case .issued(_, let nativeProjection) = startingSlot.nativeOwner else {
            Issue.record("Starting slot must retain its exact persistent native-owner projection")
            return
        }
        #expect(nativeProjection.binding == startingLifetime.binding)
        guard case .creationAvailable(let nativeReference) = nativeProjection.nativePhase else {
            Issue.record("Native owner must retain creation-available phase")
            return
        }
        #expect(nativeReference.binding == startingLifetime.binding)

        let selectedSlot = snapshot.slots[1]
        guard case .selected(_, let selectedReservation) = selectedSlot.registry.lifecycle else {
            Issue.record("Second slot must retain selected registry lifecycle debt")
            return
        }
        #expect(selectedReservation == selected.reservation)
        #expect(selectedSlot.generic.key == selected.reservation.physicalSlotID)
        #expect(selectedSlot.generic.queuedContributionCount == 0)
        #expect(selectedSlot.nativeOwner == .vacant)
        #expect(selectedSlot.recoveryEvidence == .vacant)
        #expect(selectedSlot.retryEvidence == .vacant)

        let vacantSlot = snapshot.slots[2]
        #expect(vacantSlot.registry.lifecycle == .vacant)
        #expect(vacantSlot.generic.key == mailbox.physicalSlotIDs[2])
        #expect(vacantSlot.generic.queuedContributionCount == 0)
        #expect(vacantSlot.nativeOwner == .vacant)
        #expect(vacantSlot.recoveryEvidence == .vacant)
        #expect(vacantSlot.retryEvidence == .vacant)

        #expect(Set(snapshot.genericMailboxDebt.keyDebt.map(\.key)) == Set(mailbox.physicalSlotIDs))
        #expect(snapshot.genericMailboxDebt.activeLease == .vacant)
        #expect(snapshot.genericMailboxDebt.queuedCleanup == .vacant)
        #expect(snapshot.genericMailboxDebt.inFlightCleanup == .vacant)
        #expect(snapshot.activeLease == .vacant)
        #expect(snapshot.pendingWholeLeaseCompletion == .vacant)
        #expect(snapshot.fleetOrdinaryAdmissionDisposition == .ordinary)
        #expect(!snapshot.isQuiescent)
    }

    @Test("vacant fleet is quiescent and replay returns a fresh exact snapshot for one identity")
    func vacantFleetIsQuiescentAndReplayRetainsIdentity() throws {
        let mailbox = try makeMailbox(slotCount: 2)
        let lifecycle = FilesystemObservationFleetLifecycle()
        let first = requireAppliedShutdownDebtSnapshot(
            lifecycle.beginShutdownAndSnapshot(mailbox: mailbox)
        )

        let replay = requireAlreadyAppliedShutdownDebtSnapshot(
            mailbox.freezeFleetIngressAndSnapshot(for: first.shutdownIdentity)
        )

        #expect(replay == first)
        #expect(replay.slots.map(\.physicalSlotID) == mailbox.physicalSlotIDs)
        #expect(replay.slots.allSatisfy { $0.registry.lifecycle == .vacant })
        #expect(replay.slots.allSatisfy { $0.nativeOwner == .vacant })
        #expect(replay.slots.allSatisfy { $0.recoveryEvidence == .vacant })
        #expect(replay.slots.allSatisfy { $0.retryEvidence == .vacant })
        #expect(replay.slots.allSatisfy { $0.completedReleaseReplay == .vacant })
        #expect(replay.desiredCustody.isVacant)
        #expect(replay.isQuiescent)
    }

    @Test("vacant reserve slot retains deferred desired and exact pending continuity repair")
    func vacantSlotWithDeferredDesiredRetainsPendingRepair() throws {
        // Arrange
        let mailbox = try makeMailbox(slotCount: 2)
        let currentRegistration = makeFleetRegistration(index: 963)
        let replacementRegistration = FSEventRegistrationToken(
            sourceID: currentRegistration.sourceID,
            registrationGeneration: 964,
            rootGeneration: currentRegistration.rootGeneration
        )
        #expect(mailbox.installTestConfiguration(currentRegistration).isShutdownDebtEnqueued)
        let currentSelection = requireShutdownDebtSelection(mailbox.selectNextDesiredSource())
        let currentStartingLifetime = requireShutdownDebtStartingLifetime(
            mailbox.beginNativeLifetime(currentSelection.reservation)
        )
        let nativePorts = requireShutdownDebtNativePorts(
            mailbox.nativeGenerationPorts(for: currentStartingLifetime)
        )
        guard
            case .deferredToConfigurationCurrentness(let replacementDesired) =
                mailbox.installTestConfiguration(replacementRegistration)
        else {
            Issue.record("Replacement must retain pending desired currentness custody")
            return
        }
        guard
            case .creationAbandoned(let abandonment) =
                nativePorts.nativeOwner.abandonCreation()
        else {
            Issue.record("Fixture must close its never-created native generation")
            return
        }
        let retiringLifetime = requireShutdownDebtRetiringLifetime(
            mailbox.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                currentStartingLifetime
            )
        )
        let completion = DarwinFSEventUnpublishedNativeCompletion.creationAbandoned(
            abandonment
        )
        guard
            case .finalized(let finalReceipt) = mailbox.lifecyclePort
                .finalizeUnpublishedNativeGeneration(
                    retiringLifetime,
                    completion: completion
                ),
            case .finalized(let acknowledgement) = nativePorts.nativeOwner
                .finalizeNativeLifetime(
                    using: .unpublished(finalReceipt),
                    contextFinalizer: D3NativeFinalizationLedger()
                ),
            case .applied = mailbox.lifecyclePort
                .applyContextReleaseAcknowledgement(acknowledgement)
        else {
            Issue.record("Fixture must apply exact D3 context-release acknowledgement")
            return
        }

        // Act
        let snapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(mailbox: mailbox)
        )

        // Assert
        let vacantSlot = try #require(
            snapshot.slots.first {
                $0.physicalSlotID == currentStartingLifetime.binding.physicalSlotID
            }
        )
        #expect(vacantSlot.registry.lifecycle == .vacant)
        let deferredDesired = try #require(snapshot.desiredCustody.deferredFIFO.first)
        #expect(
            deferredDesired.desiredIdentity
                == replacementDesired.identity
        )
        #expect(snapshot.desiredCustody.pendingInDeclaredSlotOrder.isEmpty)
        let deferredPending = try #require(
            snapshot.desiredCustody.pendingInDeferredFIFOOrder.first
        )
        #expect(deferredPending.deferred.desiredIdentity == replacementDesired.identity)
        #expect(deferredPending.pending.desired.desiredIdentity == replacementDesired.identity)
        guard case .pending(let repair) = deferredPending.pending.continuityRepair else {
            Issue.record("Deferred pending desired must retain exact continuity-repair custody")
            return
        }
        #expect(repair.desiredIdentity == replacementDesired.identity)
        #expect(repair.registration == replacementDesired.configuration.registration)
        #expect(repair.cause == .nativeCreateOrStartFailure)
        #expect(snapshot.desiredCustody.detachedPending.pendingBySourceID.isEmpty)
        #expect(!snapshot.isQuiescent)
    }

    @Test("retiring predecessor does not claim deferred replacement repair before D3 release")
    func retiringPredecessorDoesNotClaimDeferredReplacementRepair() throws {
        let mailbox = try makeMailbox(slotCount: 2)
        let currentRegistration = makeFleetRegistration(index: 966)
        let replacementRegistration = FSEventRegistrationToken(
            sourceID: currentRegistration.sourceID,
            registrationGeneration: 967,
            rootGeneration: currentRegistration.rootGeneration
        )
        #expect(mailbox.installTestConfiguration(currentRegistration).isShutdownDebtEnqueued)
        let currentSelection = requireShutdownDebtSelection(mailbox.selectNextDesiredSource())
        let startingLifetime = requireShutdownDebtStartingLifetime(
            mailbox.beginNativeLifetime(currentSelection.reservation)
        )
        let nativePorts = requireShutdownDebtNativePorts(
            mailbox.nativeGenerationPorts(for: startingLifetime)
        )
        guard
            case .deferredToConfigurationCurrentness(let replacementDesired) =
                mailbox.installTestConfiguration(replacementRegistration),
            case .creationAbandoned = nativePorts.nativeOwner.abandonCreation()
        else {
            Issue.record("Fixture must retain replacement desired and abandon native creation")
            return
        }
        let retiringLifetime = requireShutdownDebtRetiringLifetime(
            mailbox.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(startingLifetime)
        )

        let snapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(mailbox: mailbox)
        )
        let retiringSlot = try #require(
            snapshot.slots.first { $0.physicalSlotID == startingLifetime.binding.physicalSlotID }
        )
        guard case .retiringUnpublished(let native, _, _) = retiringSlot.registry.lifecycle else {
            Issue.record("Old declared slot must retain its retiring native generation")
            return
        }
        #expect(native.binding == retiringLifetime.startingNativeLifetime.binding)
        #expect(snapshot.desiredCustody.pendingInDeclaredSlotOrder.isEmpty)
        let deferredDesired = try #require(snapshot.desiredCustody.deferredFIFO.first)
        #expect(deferredDesired.desiredIdentity == replacementDesired.identity)
        let deferredPending = try #require(
            snapshot.desiredCustody.pendingInDeferredFIFOOrder.first
        )
        #expect(deferredPending.deferred.desiredIdentity == replacementDesired.identity)
        #expect(deferredPending.pending.desired.desiredIdentity == replacementDesired.identity)
        guard case .pending(let repair) = deferredPending.pending.continuityRepair else {
            Issue.record("Replacement must retain exact deferred continuity-repair custody")
            return
        }
        #expect(repair.desiredIdentity == replacementDesired.identity)
        #expect(repair.registration == replacementDesired.configuration.registration)
        #expect(repair.cause == .nativeCreateOrStartFailure)
        #expect(!snapshot.isQuiescent)
    }

    @Test("completed unpublished release replays compact lineage without blocking slot quiescence")
    func completedReleaseReplaysCompactUnpublishedLineage() throws {
        // Arrange
        let fixture = try makeUnpublishedContextReleaseFixture(generationValue: 965)
        guard
            case .finalized(let acknowledgement) = fixture.nativeOwner.finalizeNativeLifetime(
                using: .unpublished(fixture.finalReceipt),
                contextFinalizer: fixture.contextFinalizer
            ),
            case .applied = fixture.mailbox.lifecyclePort
                .applyContextReleaseAcknowledgement(acknowledgement)
        else {
            Issue.record("Context-release fixture must reach completed replay custody")
            return
        }

        // Act
        let snapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(
                mailbox: fixture.mailbox
            )
        )

        // Assert
        let slot = try #require(
            snapshot.slots.first { $0.physicalSlotID == fixture.binding.physicalSlotID }
        )
        #expect(slot.registry.lifecycle == .vacant)
        guard
            case .completed(let retirement, let releaseAuthority) =
                slot.completedReleaseReplay
        else {
            Issue.record("Vacant slot must replay compact completed release lineage")
            return
        }
        #expect(retirement.native.binding == fixture.binding)
        guard
            case .unpublished(let retirementAuthority, let finalizationKind) =
                retirement.disposition,
            case .unpublished = acknowledgement
        else {
            Issue.record("Expected compact unpublished retirement lineage")
            return
        }
        #expect(retirementAuthority == fixture.finalReceipt.retirementAuthority)
        #expect(finalizationKind == fixture.finalReceipt.completion.finalizationKind)
        #expect(releaseAuthority == acknowledgement.releaseAuthority)
        #expect(slot.isQuiescent)
        #expect(!snapshot.desiredCustody.isVacant)
        #expect(!snapshot.isQuiescent)
    }

    @Test("active lease retry and recovery remain exact non-quiescent debt")
    func genericCustodyClassesRemainExactNonQuiescentDebt() throws {
        try assertActiveLeaseShutdownDebt()
        try assertRetryShutdownDebt()
        try assertRecoveryShutdownDebt()
    }

    private func assertActiveLeaseShutdownDebt() throws {
        // Arrange: an active lease over one queued contribution.
        let activeFixture = try makeStartingFixture(registrationIndex: 957)
        let activePorts = requireShutdownDebtNativePorts(
            activeFixture.mailbox.nativeGenerationPorts(for: activeFixture.startingLifetime)
        )
        expectShutdownDebtRetainedCallback(
            try admitShutdownDebtCallback(
                .authoritative(
                    try makeObservation(
                        registration: activeFixture.registration,
                        path: "/shutdown-debt/active-lease",
                        eventID: 957
                    )
                ),
                startingLifetime: activeFixture.startingLifetime,
                nativePorts: activePorts
            )
        )
        let activeConsumer = activeFixture.mailbox.actorConsumerPort
        let activeBinding = activeConsumer.bindConsumer().binding
        let activeLease = requireShutdownDebtLease(
            activeConsumer.takeDrain(binding: activeBinding)
        )

        // Act / Assert: both generic and filesystem active-lease unions are retained.
        let activeSnapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(
                mailbox: activeFixture.mailbox
            )
        )
        #expect(
            activeSnapshot.genericMailboxDebt.activeLease
                == .presented(
                    key: activeFixture.startingLifetime.binding.physicalSlotID,
                    token: activeLease.token
                )
        )
        guard
            case .authoritative(let token, let binding, let fingerprint) =
                activeSnapshot.activeLease
        else {
            Issue.record("Expected exact authoritative active lease debt")
            return
        }
        #expect(token == activeLease.token)
        #expect(binding == activeFixture.startingLifetime.binding)
        guard case .contributions(let contributionReferences) = fingerprint else {
            Issue.record("Expected payload-free contribution fingerprint")
            return
        }
        #expect(contributionReferences.count == 1)
        #expect(!activeSnapshot.isQuiescent)
    }

    private func assertRetryShutdownDebt() throws {
        // Arrange / Act / Assert: retry custody remains joined to the same slot.
        let retryFixture = try makeStartingFixture(registrationIndex: 958)
        let retryPorts = requireShutdownDebtNativePorts(
            retryFixture.mailbox.nativeGenerationPorts(for: retryFixture.startingLifetime)
        )
        expectShutdownDebtRetainedCallback(
            try admitShutdownDebtCallback(
                .authoritative(
                    try makeObservation(
                        registration: retryFixture.registration,
                        path: "/shutdown-debt/retry",
                        eventID: 958
                    )
                ),
                startingLifetime: retryFixture.startingLifetime,
                nativePorts: retryPorts
            )
        )
        let retryConsumer = retryFixture.mailbox.actorConsumerPort
        let retryBinding = retryConsumer.bindConsumer().binding
        let retryLease = requireShutdownDebtLease(
            retryConsumer.takeDrain(binding: retryBinding)
        )
        _ = retryConsumer.acknowledge(token: retryLease.token, disposition: .retry)
        let retrySnapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(
                mailbox: retryFixture.mailbox
            )
        )
        #expect(retrySnapshot.slots[0].generic.retryDisposition == .retained)
        #expect(retrySnapshot.slots[0].retryEvidence == .vacant)
        #expect(!retrySnapshot.isQuiescent)
    }

    private func assertRecoveryShutdownDebt() throws {
        // Arrange / Act / Assert: contraction retains exact recovery debt.
        let recoveryFixture = try makeStartingFixture(
            registrationIndex: 959,
            limits: fleetMailboxLimits(global: 0, perRegistration: 1, perLease: 1)
        )
        let recoveryPorts = requireShutdownDebtNativePorts(
            recoveryFixture.mailbox.nativeGenerationPorts(
                for: recoveryFixture.startingLifetime
            )
        )
        _ = try admitShutdownDebtCallback(
            .authoritative(
                try makeObservation(
                    registration: recoveryFixture.registration,
                    path: "/shutdown-debt/recovery-cleanup",
                    eventID: 959
                )
            ),
            startingLifetime: recoveryFixture.startingLifetime,
            nativePorts: recoveryPorts
        )
        let recoverySnapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(
                mailbox: recoveryFixture.mailbox
            )
        )
        guard case .retained = recoverySnapshot.slots[0].generic.recoveryDisposition else {
            Issue.record("Contracted contribution must retain exact generic recovery debt")
            return
        }
        guard
            case .retained = recoverySnapshot.slots[0].recoveryEvidence
        else {
            Issue.record("Contracted contribution must retain exact fixed recovery debt")
            return
        }
        #expect(!recoverySnapshot.isQuiescent)
    }

    @Test("pending whole-lease completion is retained as a strict non-quiescent union")
    func pendingWholeLeaseCompletionIsExactNonQuiescentDebt() throws {
        // Arrange
        let fixture = try makeStartingFixture(registrationIndex: 960)
        let nativePorts = requireShutdownDebtNativePorts(
            fixture.mailbox.nativeGenerationPorts(for: fixture.startingLifetime)
        )
        expectShutdownDebtRetainedCallback(
            try admitShutdownDebtCallback(
                .authoritative(
                    try makeObservation(
                        registration: fixture.registration,
                        path: "/shutdown-debt/pending-completion",
                        eventID: 960
                    )
                ),
                startingLifetime: fixture.startingLifetime,
                nativePorts: nativePorts
            )
        )
        let completionSuppressingPort = makeShutdownDebtCompletionSuppressingPort(
            fixture.mailbox.actorConsumerPort
        )
        let consumerBinding = completionSuppressingPort.bindConsumer().binding
        let lease = requireShutdownDebtLease(
            completionSuppressingPort.takeDrain(binding: consumerBinding)
        )
        var semanticSink = ShutdownDebtAcceptAllSemanticSink()
        var sourceGate = FilesystemSourceGate(binding: fixture.startingLifetime.binding)
        var transfer = try FilesystemObservationLeaseTransfer(
            physicalSlotIDs: fixture.mailbox.physicalSlotIDs,
            maximumContributionsPerLease: 1
        )
        guard
            case .rejected(.completion(.noAcknowledgedTransfer)) = transfer.transfer(
                lease,
                sourceGate: &sourceGate,
                recoveryContext: .notRequired,
                semanticSink: &semanticSink,
                consumerPort: completionSuppressingPort
            )
        else {
            Issue.record("Suppressed completion must leave acknowledged whole-lease custody pending")
            return
        }

        // Act
        let snapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(
                mailbox: fixture.mailbox
            )
        )

        // Assert
        guard
            case .ordinary(let authority, let acknowledgement) =
                snapshot.pendingWholeLeaseCompletion
        else {
            Issue.record("Acknowledged ordinary transfer must retain exact pending completion")
            return
        }
        #expect(authority.binding == fixture.startingLifetime.binding)
        #expect(authority.preflight.binding == fixture.startingLifetime.binding)
        #expect(authority.preflight.isUUIDv7)
        #expect(acknowledgement.binding == fixture.startingLifetime.binding)
        #expect(acknowledgement.matches(authority))
        guard case .contributions = authority.evidence else {
            Issue.record("Ordinary pending completion must retain contribution authority")
            return
        }
        #expect(!snapshot.isQuiescent)
    }

    @Test("exact ordinary and exhausted dispositions survive freeze snapshots")
    func admissionDispositionIsRetainedExactly() throws {
        // Arrange: ordinary
        let ordinaryMailbox = try makeMailbox(slotCount: 1)
        let ordinarySnapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(
                mailbox: ordinaryMailbox
            )
        )
        #expect(ordinarySnapshot.fleetOrdinaryAdmissionDisposition == .ordinary)

        // Arrange: exhaust the generic recovery authority exactly once.
        let registration = makeFleetRegistration(index: 961)
        let exhaustedFixture = try makeFleetMailboxFixture(
            generation: generation,
            registrations: [registration],
            limits: fleetMailboxLimits(global: 0, perRegistration: 1, perLease: 1),
            recoveryAuthoritySeed: .preseededSequenced(.max)
        )
        let terminalRecovery = requireContractedRecovery(
            try exhaustedFixture.admitCallback(
                .authoritative(
                    try makeObservation(
                        registration: registration,
                        path: "/shutdown-debt/exhausted",
                        eventID: 961
                    )
                ),
                for: registration
            )
        )
        let exactDebt = FilesystemObservationFleetAdmissionExhaustionDebt(
            triggeringBinding: exhaustedFixture.binding(for: registration),
            terminalGenericRecoveryRevision: terminalRecovery.revision.genericRecoveryRevision
        )

        // Act
        let exhaustedSnapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(
                mailbox: exhaustedFixture.mailbox
            )
        )

        // Assert
        #expect(
            exhaustedSnapshot.fleetOrdinaryAdmissionDisposition
                == .fleetAdmissionExhausted(exactDebt)
        )
    }

    @Test("freeze and snapshot are atomic and a foreign identity returns no snapshot")
    func freezeSnapshotIsAtomicAndForeignIdentityReturnsTypedRejection() throws {
        // Arrange
        let mailbox = try makeMailbox(slotCount: 1)
        let registration = makeFleetRegistration(index: 962)
        #expect(mailbox.installTestConfiguration(registration).isShutdownDebtEnqueued)
        let selected = requireShutdownDebtSelection(mailbox.selectNextDesiredSource())
        let lifecycle = FilesystemObservationFleetLifecycle()

        // Act: the returned snapshot must observe the same transaction that froze ingress.
        let applied = requireAppliedShutdownDebtSnapshot(
            lifecycle.beginShutdownAndSnapshot(mailbox: mailbox)
        )
        let rejectedCommit = mailbox.beginNativeLifetime(selected.reservation)
        let replay = requireAlreadyAppliedShutdownDebtSnapshot(
            mailbox.freezeFleetIngressAndSnapshot(for: applied.shutdownIdentity)
        )

        // Assert
        guard case .selected(_, let appliedReservation) = applied.slots[0].registry.lifecycle else {
            Issue.record("Atomic snapshot must retain selected lifecycle")
            return
        }
        #expect(appliedReservation == selected.reservation)
        #expect(rejectedCommit == .fleetShutdownInProgress(applied.shutdownIdentity))
        #expect(replay == applied)

        // Arrange: acquire another owner-minted identity without exposing construction.
        let foreignMailbox = try makeMailbox(slotCount: 1)
        let foreignSnapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(
                mailbox: foreignMailbox
            )
        )

        // Act / Assert: rejection carries identities only; there is no snapshot case payload.
        #expect(
            mailbox.freezeFleetIngressAndSnapshot(for: foreignSnapshot.shutdownIdentity)
                == .shutdownIdentityMismatch(
                    expected: applied.shutdownIdentity,
                    presented: foreignSnapshot.shutdownIdentity
                )
        )
    }

    private func makeMailbox(
        slotCount: Int,
        limits: GatherMailboxLimits? = nil
    ) throws -> FilesystemObservationMailbox {
        try makeShutdownDebtMailbox(
            generation: generation,
            slotCount: slotCount,
            limits: limits
        )
    }

    private func makeStartingFixture(
        registrationIndex: Int,
        limits: GatherMailboxLimits? = nil
    ) throws -> ShutdownDebtStartingFixture {
        try makeShutdownDebtStartingFixture(
            generation: generation,
            registrationIndex: registrationIndex,
            limits: limits
        )
    }
}

private struct ShutdownDebtAcceptAllSemanticSink: FilesystemObservationSemanticCustodySink {
    mutating func accept(
        _: FSEventObservation,
        identity _: FilesystemObservationContributionIdentity
    ) -> FilesystemObservationSemanticCustodyResult {
        .accepted
    }
}

private func makeShutdownDebtCompletionSuppressingPort(
    _ underlying: FilesystemObservationActorConsumerPort
) -> FilesystemObservationActorConsumerPort {
    FilesystemObservationActorConsumerPort(
        bind: underlying.bindConsumer,
        take: underlying.takeDrain,
        acknowledge: underlying.acknowledge,
        cleanup: underlying.performCleanup,
        preflightWholeLeaseTransfer: underlying.preflightWholeLeaseTransfer,
        completeWholeLeaseTransfer: { _, _, _, _, _ in
            .rejected(.noAcknowledgedTransfer)
        }
    )
}
