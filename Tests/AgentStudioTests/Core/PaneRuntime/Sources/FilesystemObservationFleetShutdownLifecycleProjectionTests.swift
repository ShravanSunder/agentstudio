import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation fleet shutdown lifecycle projection")
struct FilesystemFleetShutdownLifecycleProjectionTests {
    private let generation = AdmissionGeneration(owner: .filesystemObservation, value: 951)

    @Test("retired fence-backed generation retains exact context-release debt")
    func retiredFenceBackedGenerationRetainsExactContextReleaseDebt() async throws {
        let fixture = try await makeFenceBackedContextReleaseFixture(generationValue: 969)
        let snapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(
                mailbox: fixture.mailbox
            )
        )
        let slot = try #require(
            snapshot.slots.first { $0.physicalSlotID == fixture.binding.physicalSlotID }
        )
        guard
            case .retiredAwaitingContextRelease(let retirement, let order) =
                slot.registry.lifecycle,
            case .fenceBacked(let release) = fixture.acknowledgement,
            case .fenceBacked(
                let fenceIdentity,
                let disposition,
                let retirementAuthority
            ) = retirement.disposition
        else {
            Issue.record("Retired slot must retain exact fence-backed D3 release debt")
            return
        }
        #expect(retirement.native.binding == fixture.binding)
        #expect(fenceIdentity == fixture.retirementReceipt.fenceIdentity)
        #expect(disposition == fixture.retirementReceipt.disposition)
        #expect(retirementAuthority == fixture.retirementReceipt.retirementAuthority)
        #expect(release.receipt == fixture.retirementReceipt)
        #expect(order == .oldest)
        #expect(slot.completedReleaseReplay == .vacant)
        #expect(!slot.isQuiescent)
        #expect(!snapshot.isQuiescent)
    }

    @Test("selected starting accepting and retiring registry lifecycles are exact incomplete debt")
    func everyLiveRegistryLifecycleIsNonQuiescent() throws {
        try assertSelectedLifecycle()
        try assertStartingLifecycle()
        try assertAcceptingLifecycle()
        try assertRetiringUnpublishedLifecycle()
    }

    @Test("callback-drain closing retains exact native identity and post-start publication")
    func callbackDrainClosingRetainsExactNativeIdentity() throws {
        let fixture = try makeStartingFixture(registrationIndex: 968)
        let nativePorts = requireShutdownDebtNativePorts(
            fixture.mailbox.nativeGenerationPorts(for: fixture.startingLifetime)
        )
        let acceptingLifetime = requireShutdownDebtAcceptingLifetime(
            nativePorts.lifecyclePort.publishAccepting(fixture.startingLifetime)
        )
        guard
            case .transitioned(let closingLifetime) = nativePorts.lifecyclePort
                .beginClosingAwaitingCallbackLeaseDrain(acceptingLifetime)
        else {
            Issue.record("Fixture must enter callback-lease-drain closing")
            return
        }
        let snapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(
                mailbox: fixture.mailbox
            )
        )
        guard
            case .closingAwaitingCallbackLeaseDrain(let nativeReference) =
                snapshot.slots[0].registry.lifecycle,
            case .retained(let publicationReference, let disposition) =
                snapshot.slots[0].registry.postStartPublication
        else {
            Issue.record("Closing slot must retain lifecycle and publication debt")
            return
        }
        #expect(nativeReference.binding == closingLifetime.binding)
        #expect(publicationReference.binding == acceptingLifetime.binding)
        #expect(disposition == .current)
        #expect(!snapshot.isQuiescent)
    }

    @Test("starting removal projects awaiting publication with exact native identity")
    func startingRemovalProjectsAwaitingAcceptingPublication() throws {
        let fixture = try makeStartingFixture(registrationIndex: 970)
        let result = fixture.mailbox.admitConfigurationIntents(
            removalBatch(binding: fixture.startingLifetime.binding, revision: 970)
        )
        guard
            case .admitted(let admission) = result,
            case .removal(.awaitingAcceptingPublication(let awaiting)) =
                admission.admissionsBySourceID[fixture.registration.sourceID]
        else {
            Issue.record("Starting removal must await successful-start publication")
            return
        }
        let snapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        guard
            case .awaitingAcceptingPublication(let reference) =
                snapshot.slots[0].registry.lifecycle
        else {
            Issue.record("Snapshot must project awaiting-accepting-publication debt")
            return
        }
        #expect(reference.binding == awaiting.startingNativeLifetime.binding)
        #expect(reference.binding == fixture.startingLifetime.binding)
        #expect(!snapshot.isQuiescent)
    }

    @Test("accepting removal retains exact publication and removal authority")
    func acceptingRemovalProjectsRetainedAfterRemoval() throws {
        let fixture = try makeStartingFixture(registrationIndex: 971)
        let ports = requireShutdownDebtNativePorts(
            fixture.mailbox.nativeGenerationPorts(for: fixture.startingLifetime)
        )
        let accepting = requireShutdownDebtAcceptingLifetime(
            ports.lifecyclePort.publishAccepting(fixture.startingLifetime)
        )
        let result = fixture.mailbox.admitConfigurationIntents(
            removalBatch(binding: accepting.binding, revision: 971)
        )
        guard
            case .admitted(let admission) = result,
            case .removal(.closeAccepting(let obligation)) =
                admission.admissionsBySourceID[fixture.registration.sourceID]
        else {
            Issue.record("Accepting removal must mint one exact close obligation")
            return
        }
        let snapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        guard
            case .retainedAfterRemoval(
                let reference,
                let disposition,
                let removalAuthority
            ) = snapshot.slots[0].registry.postStartPublication
        else {
            Issue.record("Snapshot must retain exact post-removal publication debt")
            return
        }
        #expect(reference.binding == accepting.binding)
        #expect(disposition == .current)
        #expect(removalAuthority == obligation.removalAuthority)
        #expect(removalAuthority.exactPriorBinding == accepting.binding)
        #expect(!snapshot.isQuiescent)
    }

    @Test("fence request projects exact pending retirement debt after contraction")
    func contractedFenceProjectsRetirementFencePending() async throws {
        let fixture = try await makeShutdownDebtClosedFenceFixture(
            generationValue: 972,
            limits: fleetMailboxLimits(global: 0, perRegistration: 1, perLease: 1)
        )
        guard
            case .pendingAfterContraction(let pending, _) =
                fixture.mailbox.lifecyclePort.requestRetirementFence(fixture.receipt)
        else {
            Issue.record("Zero global capacity must retain a contracted pending fence")
            return
        }
        let snapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        guard
            case .retirementFencePending(
                let binding,
                let receipt,
                let fence,
                let order
            ) = snapshot.slots[0].registry.lifecycle
        else {
            Issue.record("Snapshot must project exact pending-fence custody")
            return
        }
        #expect(binding == fixture.binding)
        #expect(receipt == fixture.receipt)
        #expect(fence == pending.fence)
        #expect(order == .oldest)
    }

    @Test("atomic fence completion snapshots installed before and retired after")
    func atomicFenceCompletionHasNoTransferredSnapshotInterleaving() async throws {
        let fixture = try await makeShutdownDebtClosedFenceFixture(generationValue: 973)
        guard
            case .installed(let installed) =
                fixture.mailbox.lifecyclePort.requestRetirementFence(fixture.receipt)
        else {
            Issue.record("Fixture must install its exact retirement fence")
            return
        }
        let snapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        guard
            case .retirementFenceInstalled(
                let binding,
                let receipt,
                let fence,
                let contributionIdentity,
                let order
            ) = snapshot.slots[0].registry.lifecycle
        else {
            Issue.record("Pre-completion snapshot must retain installed-fence debt")
            return
        }
        #expect(binding == fixture.binding)
        #expect(receipt == fixture.receipt)
        #expect(fence == installed.fence)
        #expect(contributionIdentity == installed.contributionIdentity)
        #expect(order == .oldest)
        // transferRetirementFence and completeRetirement share one mailbox lock transaction;
        // no fleet shutdown snapshot can interleave at transferred-awaiting-cleanup.
        #expect(!snapshot.isQuiescent)
    }

    @Test("acknowledged fence transfer retains exact pending retirement completion")
    func acknowledgedFenceTransferProjectsPendingRetirementCompletion() async throws {
        let fixture = try await makeShutdownDebtClosedFenceFixture(generationValue: 974)
        guard
            case .installed(let installed) =
                fixture.mailbox.lifecyclePort.requestRetirementFence(fixture.receipt)
        else {
            Issue.record("Fixture must install its exact retirement fence")
            return
        }
        let consumer = completionSuppressingPort(fixture.mailbox.actorConsumerPort)
        let consumerBinding = consumer.bindConsumer().binding
        let lease = requireShutdownDebtLease(consumer.takeDrain(binding: consumerBinding))
        var semanticSink = ShutdownLifecycleAcceptAllSemanticSink()
        var sourceGate = FilesystemSourceGate(binding: fixture.binding)
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
                consumerPort: consumer
            )
        else {
            Issue.record("Suppressed completion must retain acknowledged retirement custody")
            return
        }
        let snapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        guard
            case .retirement(
                let authority,
                let acknowledgement,
                let binding,
                let fenceIdentity,
                let contributionIdentity,
                let disposition
            ) = snapshot.pendingWholeLeaseCompletion
        else {
            Issue.record("Snapshot must retain exact pending retirement completion")
            return
        }
        #expect(authority.binding == fixture.binding)
        #expect(acknowledgement.matches(authority))
        #expect(binding == fixture.binding)
        #expect(fenceIdentity == installed.fence.identity)
        #expect(contributionIdentity == installed.contributionIdentity)
        #expect(disposition == .quiescentWithoutRecovery)
        #expect(!snapshot.isQuiescent)
    }

    @Test("successor close projects exact awaiting-predecessor retirement order")
    func successorCloseProjectsClosingAwaitingPredecessor() async throws {
        let fixture = try await makeShutdownDebtAwaitingPredecessorFixture(
            generationValue: 975
        )
        let snapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        let predecessorSlot = try #require(
            snapshot.slots.first {
                $0.physicalSlotID == fixture.installedPredecessor.binding.physicalSlotID
            }
        )
        let successorSlot = try #require(
            snapshot.slots.first {
                $0.physicalSlotID == fixture.awaitingSuccessor.binding.physicalSlotID
            }
        )
        guard
            case .retirementFenceInstalled(_, _, let predecessorFence, _, let predecessorOrder) =
                predecessorSlot.registry.lifecycle,
            case .closingAwaitingPredecessor(
                let successorReference,
                let successorReceipt,
                let successorOrder
            ) = successorSlot.registry.lifecycle
        else {
            Issue.record("Snapshot must retain exact predecessor and successor retirement chain")
            return
        }
        #expect(predecessorFence == fixture.installedPredecessor.fence)
        #expect(predecessorOrder == .oldest)
        #expect(successorReference.binding == fixture.awaitingSuccessor.binding)
        #expect(successorReceipt == fixture.awaitingSuccessor.leaseDrainReceipt)
        #expect(successorOrder == .successor)
        #expect(!snapshot.isQuiescent)
    }

    private func assertSelectedLifecycle() throws {
        let mailbox = try makeShutdownDebtMailbox(generation: generation, slotCount: 1)
        let registration = makeFleetRegistration(index: 953)
        #expect(mailbox.installTestConfiguration(registration).isShutdownDebtEnqueued)
        let selected = requireShutdownDebtSelection(mailbox.selectNextDesiredSource())
        let snapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(mailbox: mailbox)
        )
        guard case .selected(_, let reservation) = snapshot.slots[0].registry.lifecycle else {
            Issue.record("Expected selected shutdown lifecycle")
            return
        }
        #expect(reservation == selected.reservation)
        #expect(!snapshot.isQuiescent)
    }

    private func assertStartingLifecycle() throws {
        let fixture = try makeStartingFixture(registrationIndex: 954)
        let snapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        guard case .starting(let reference) = snapshot.slots[0].registry.lifecycle else {
            Issue.record("Expected starting shutdown lifecycle")
            return
        }
        #expect(reference.binding == fixture.startingLifetime.binding)
        #expect(!snapshot.isQuiescent)
    }

    private func assertAcceptingLifecycle() throws {
        let fixture = try makeStartingFixture(registrationIndex: 955)
        let nativePorts = requireShutdownDebtNativePorts(
            fixture.mailbox.nativeGenerationPorts(for: fixture.startingLifetime)
        )
        let accepting = requireShutdownDebtAcceptingLifetime(
            nativePorts.lifecyclePort.publishAccepting(fixture.startingLifetime)
        )
        let snapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        guard
            case .accepting(let reference, _) = snapshot.slots[0].registry.lifecycle,
            case .retained(let retainedReference, let disposition) =
                snapshot.slots[0].registry.postStartPublication
        else {
            Issue.record("Expected exact accepting lifecycle and post-start publication")
            return
        }
        #expect(reference.binding == accepting.binding)
        #expect(retainedReference.binding == accepting.binding)
        #expect(disposition == .current)
        #expect(!snapshot.isQuiescent)
    }

    private func assertRetiringUnpublishedLifecycle() throws {
        let fixture = try makeStartingFixture(registrationIndex: 956)
        let retiring = requireShutdownDebtRetiringLifetime(
            fixture.mailbox.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                fixture.startingLifetime
            )
        )
        let snapshot = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        guard
            case .retiringUnpublished(let reference, _, _) =
                snapshot.slots[0].registry.lifecycle
        else {
            Issue.record("Expected retiring-unpublished shutdown lifecycle")
            return
        }
        #expect(reference.binding == retiring.startingNativeLifetime.binding)
        #expect(!snapshot.isQuiescent)
    }

    private func makeStartingFixture(
        registrationIndex: Int
    ) throws -> ShutdownDebtStartingFixture {
        try makeShutdownDebtStartingFixture(
            generation: generation,
            registrationIndex: registrationIndex
        )
    }

    private func removalBatch(
        binding: FilesystemObservationSlotBinding,
        revision: UInt64
    ) -> FilesystemSourceConfigurationIntentBatch {
        FilesystemSourceConfigurationIntentBatch(
            acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(value: revision),
            intentsBySourceID: [
                binding.registration.sourceID: .remove(
                    FilesystemSourceRemovalIntent(exactPriorBinding: binding)
                )
            ]
        )
    }

    private func completionSuppressingPort(
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
}

private struct ShutdownLifecycleAcceptAllSemanticSink: FilesystemObservationSemanticCustodySink {
    mutating func accept(
        _: FSEventObservation,
        identity _: FilesystemObservationContributionIdentity
    ) -> FilesystemObservationSemanticCustodyResult {
        .accepted
    }
}
