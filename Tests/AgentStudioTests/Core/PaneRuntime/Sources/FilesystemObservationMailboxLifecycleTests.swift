import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation mailbox lifecycle")
struct FilesystemObservationMailboxLifecycleTests {
    private let generation = AdmissionGeneration(owner: .filesystemObservation, value: 72)

    @Test("a sealed mailbox remains drainable until retained custody is transferred")
    func sealedMailboxRemainsDrainable() async throws {
        // Arrange
        let registration = makeRegistration(index: 1)
        let mailbox = try makeMailbox(registration: registration)
        let offer = mailbox.callbackProducerPort.offer(
            .authoritative(
                try makeObservation(registration: registration, path: "/sealed/file", eventID: 1)
            )
        )
        let receipt = requireOfferReceipt(offer)
        mailbox.callbackSignalerPort.apply(receipt.wake)
        let binding = mailbox.actorConsumerPort.bindConsumer().binding

        // Act
        #expect(mailbox.lifecyclePort.seal() == .applied)
        #expect(mailbox.lifecyclePort.stateSnapshot == .sealed)
        #expect(await mailbox.actorWaiterPort.nextSignal() == .signaled)
        let lease = requireLease(mailbox.actorConsumerPort.takeDrain(binding: binding))
        let acknowledgement = mailbox.actorConsumerPort.acknowledge(
            token: lease.token,
            disposition: .transferredAuthoritative
        )

        // Assert
        #expect(acknowledgement == .transferredAuthoritative(wake: .noWake))
        expectClosed(mailbox.actorConsumerPort.takeDrain(binding: binding))
        #expect(mailbox.lifecyclePort.stateSnapshot == .sealed)
    }

    @Test("recovery transfer requires source-gate acceptance of the leased snapshot")
    func recoveryTransferRequiresSourceGateAcceptance() throws {
        // Arrange
        let registration = makeRegistration(index: 2)
        let mailbox = try makeMailbox(registration: registration)
        let recovery = requireRetainedRecovery(
            mailbox.callbackProducerPort.offer(
                .requiresRecovery(
                    try makeObservation(registration: registration, path: "/recovery/file", eventID: 2),
                    evidence: .continuityLoss
                )
            )
        )
        let binding = mailbox.actorConsumerPort.bindConsumer().binding
        let lease = requireLease(mailbox.actorConsumerPort.takeDrain(binding: binding))
        var sourceGate = FilesystemSourceGate(registration: registration)
        let acceptance = requireRecoveryAcceptance(
            sourceGate.acceptMailboxRecovery(
                recovery,
                trigger: .continuityLoss,
                watermark: .recoveryRevision(1),
                participants: makeRequiredParticipants()
            )
        )

        // Act
        let acknowledgement = mailbox.actorConsumerPort.acknowledge(
            token: lease.token,
            disposition: .transferredRecovery(acceptance)
        )

        // Assert
        #expect(
            acknowledgement
                == .transferredRecovery(
                    evidence: .cleared(recovery.revision),
                    wake: .noWake
                )
        )
        #expect(
            mailbox.lifecyclePort.diagnostics.recoveryEvidence(for: registration)
                == .noEvidence(recovery.revision.stamp))
    }

    @Test("invalidation reports retained contribution custody")
    func invalidationRejectsRetainedContribution() throws {
        // Arrange
        let registration = makeRegistration(index: 3)
        let mailbox = try makeMailbox(registration: registration)
        _ = mailbox.callbackProducerPort.offer(
            .authoritative(
                try makeObservation(registration: registration, path: "/pending/file", eventID: 3)
            )
        )
        #expect(mailbox.lifecyclePort.seal() == .applied)

        // Act
        let result = mailbox.lifecyclePort.invalidate()

        // Assert
        let custody = requireOutstandingCustody(result)
        #expect(custody.retainedContributionCount == 1)
        #expect(custody.activeLeaseCount == 0)
        #expect(mailbox.lifecyclePort.stateSnapshot == .sealed)
    }

    @Test("invalidation reports active lease custody")
    func invalidationRejectsActiveLease() throws {
        // Arrange
        let registration = makeRegistration(index: 4)
        let mailbox = try makeMailbox(registration: registration)
        _ = mailbox.callbackProducerPort.offer(
            .authoritative(
                try makeObservation(registration: registration, path: "/leased/file", eventID: 4)
            )
        )
        let binding = mailbox.actorConsumerPort.bindConsumer().binding
        _ = requireLease(mailbox.actorConsumerPort.takeDrain(binding: binding))
        #expect(mailbox.lifecyclePort.seal() == .applied)

        // Act
        let result = mailbox.lifecyclePort.invalidate()

        // Assert
        let custody = requireOutstandingCustody(result)
        #expect(custody.activeLeaseCount == 1)
        #expect(custody.retainedContributionCount == 1)
        #expect(mailbox.lifecyclePort.stateSnapshot == .sealed)
    }

    @Test("invalidation reports retry and recovery-evidence custody")
    func invalidationRejectsRetryAndRecoveryEvidence() throws {
        // Arrange
        let registration = makeRegistration(index: 5)
        let mailbox = try makeMailbox(registration: registration)
        _ = mailbox.callbackProducerPort.offer(
            .requiresRecovery(
                try makeObservation(registration: registration, path: "/retry/file", eventID: 5),
                evidence: .continuityLoss
            )
        )
        let binding = mailbox.actorConsumerPort.bindConsumer().binding
        let lease = requireLease(mailbox.actorConsumerPort.takeDrain(binding: binding))
        #expect(
            mailbox.actorConsumerPort.acknowledge(token: lease.token, disposition: .retry)
                == .retried(wake: .scheduleDrain)
        )
        #expect(mailbox.lifecyclePort.seal() == .applied)

        // Act
        let result = mailbox.lifecyclePort.invalidate()

        // Assert
        let custody = requireOutstandingCustody(result)
        #expect(custody.retryEvidenceRegistrationCount == 1)
        #expect(custody.recoveryEvidenceRegistrationCount == 1)
        #expect(mailbox.lifecyclePort.stateSnapshot == .sealed)
    }

    @Test("exact accepted recovery transfer permits quiescent invalidation and finish")
    func acceptedRecoveryTransferPermitsInvalidationAndFinish() throws {
        // Arrange
        let registration = makeRegistration(index: 6)
        let mailbox = try makeMailbox(registration: registration)
        let recovery = requireRetainedRecovery(
            mailbox.callbackProducerPort.offer(
                .requiresRecovery(
                    try makeObservation(registration: registration, path: "/transfer/file", eventID: 6),
                    evidence: .continuityLoss
                )
            )
        )
        let binding = mailbox.actorConsumerPort.bindConsumer().binding
        let lease = requireLease(mailbox.actorConsumerPort.takeDrain(binding: binding))
        var sourceGate = FilesystemSourceGate(registration: registration)
        let acceptance = requireRecoveryAcceptance(
            sourceGate.acceptMailboxRecovery(
                recovery,
                trigger: .continuityLoss,
                watermark: .recoveryRevision(1),
                participants: makeRequiredParticipants()
            )
        )
        #expect(mailbox.lifecyclePort.seal() == .applied)
        let rejectedInvalidation = requireOutstandingCustody(
            mailbox.lifecyclePort.invalidate()
        )
        #expect(rejectedInvalidation.activeLeaseCount == 1)
        #expect(rejectedInvalidation.recoveryEvidenceRegistrationCount == 1)

        // Act: exact accepted transfer makes the sealed mailbox quiescent.
        #expect(
            mailbox.actorConsumerPort.acknowledge(
                token: lease.token,
                disposition: .transferredRecovery(acceptance)
            )
                == .transferredRecovery(
                    evidence: .cleared(recovery.revision),
                    wake: .noWake
                )
        )
        #expect(mailbox.lifecyclePort.diagnostics.gather.isQuiescent)

        // Act
        let invalidation = mailbox.lifecyclePort.invalidate()
        let finish = mailbox.lifecyclePort.finish()

        // Assert
        #expect(invalidation == .applied)
        #expect(finish == .applied)
        #expect(mailbox.lifecyclePort.stateSnapshot == .finished)
    }

    @Test("finish rejects every lifecycle state before invalidation")
    func finishRejectsBeforeInvalidation() throws {
        // Arrange
        let registration = makeRegistration(index: 7)
        let mailbox = try makeMailbox(registration: registration)

        // Act / Assert
        #expect(mailbox.lifecyclePort.finish() == .invalidState(.open))
        #expect(mailbox.lifecyclePort.seal() == .applied)
        #expect(mailbox.lifecyclePort.finish() == .invalidState(.sealed))
        #expect(mailbox.lifecyclePort.stateSnapshot == .sealed)
    }

    private func makeMailbox(
        registration: FSEventRegistrationToken
    ) throws -> FilesystemObservationMailbox {
        try FilesystemObservationMailbox(
            generation: generation,
            declaredRegistrations: [registration],
            limits: GatherMailboxLimits(
                maximumDeclaredKeys: 8,
                maximumRetainedContributions: 8,
                maximumRetainedItems: 8,
                maximumRetainedBytes: 512,
                maximumRetainedContributionsPerKey: 8,
                maximumRetainedItemsPerKey: 8,
                maximumRetainedBytesPerKey: 512,
                maximumContributionsPerLease: 4,
                maximumItemsPerLease: 4,
                maximumBytesPerLease: 256,
                cleanupQuantum: .entriesAndBytes(maximumEntries: 4, maximumBytes: 256)
            )
        )
    }

    private func makeRegistration(index: Int) -> FSEventRegistrationToken {
        let suffix = String(format: "%012d", index)
        return FSEventRegistrationToken(
            sourceID: FilesystemSourceID(
                kind: .registeredWorktreeContent,
                rootID: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-\(suffix)")!
            ),
            registrationGeneration: UInt64(index),
            rootGeneration: 1
        )
    }

    private func makeObservation(
        registration: FSEventRegistrationToken,
        path: String,
        eventID: UInt64
    ) throws -> FSEventObservation {
        try FSEventObservation(
            registration: registration,
            capturedAt: ContinuousClock.now,
            totalRecordCount: .exact(1),
            inspectedNativeRecordCount: 1,
            records: [FSEventRecord(path: path, flags: [.itemModified], eventID: eventID)],
            unionedInspectedFlags: [.itemModified],
            eventIDWatermark: .inspected(first: eventID, last: eventID),
            completeness: .complete
        )
    }

    private func makeRequiredParticipants() -> Set<FilesystemRepairParticipantToken> {
        Set(
            [
                FilesystemRepairParticipantKind.contentRepairProjector,
                .gitWorkingDirectoryProjector,
                .paneFilesystemProjection,
            ].map {
                FilesystemRepairParticipantToken(
                    kind: $0,
                    participantID: UUID(),
                    participantGeneration: 1
                )
            }
        )
    }

    private func requireOfferReceipt(
        _ result: FilesystemObservationOfferResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FilesystemObservationOfferReceipt {
        guard case .admitted(let receipt) = result else {
            Issue.record("observation was not admitted: \(result)", sourceLocation: sourceLocation)
            preconditionFailure("Expected admitted filesystem observation")
        }
        return receipt
    }

    private func requireRetainedRecovery(
        _ result: FilesystemObservationOfferResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FilesystemRecoveryEvidenceSnapshot {
        let receipt = requireOfferReceipt(result, sourceLocation: sourceLocation)
        guard case .retainedWithRecovery(let recovery) = receipt.disposition else {
            Issue.record("expected retained recovery: \(result)", sourceLocation: sourceLocation)
            preconditionFailure("Expected retained recovery evidence")
        }
        return recovery
    }

    private func requireLease(
        _ result: FilesystemObservationTakeDrainResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FilesystemObservationDrainLease {
        guard case .lease(let lease) = result else {
            Issue.record("expected drain lease: \(result)", sourceLocation: sourceLocation)
            preconditionFailure("Expected filesystem drain lease")
        }
        return lease
    }

    private func requireRecoveryAcceptance(
        _ result: FilesystemSourceGateRecoveryAdmissionResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FilesystemSourceGateRecoveryAcceptance {
        guard case .admitted(let acceptance) = result else {
            Issue.record("mailbox recovery was not accepted: \(result)", sourceLocation: sourceLocation)
            preconditionFailure("Expected accepted mailbox recovery")
        }
        return acceptance
    }

    private func requireOutstandingCustody(
        _ result: FilesystemObservationLifecycleTransitionResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FilesystemObservationOutstandingCustody {
        guard case .outstandingCustody(let custody) = result else {
            Issue.record("expected outstanding custody: \(result)", sourceLocation: sourceLocation)
            preconditionFailure("Expected outstanding filesystem custody")
        }
        return custody
    }

    private func expectClosed(
        _ result: FilesystemObservationTakeDrainResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard case .closed = result else {
            Issue.record("expected closed drain result: \(result)", sourceLocation: sourceLocation)
            return
        }
    }
}
