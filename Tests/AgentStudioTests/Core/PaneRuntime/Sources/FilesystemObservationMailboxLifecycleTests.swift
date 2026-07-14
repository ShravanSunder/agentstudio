import Dispatch
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
        let fixture = try makeMailboxFixture(registration: registration)
        let mailbox = fixture.mailbox
        let offer = try fixture.admitCallback(
            .authoritative(
                try makeObservation(registration: registration, path: "/sealed/file", eventID: 1)
            )
        )
        expectRetainedCallback(offer)
        let consumerBinding = mailbox.actorConsumerPort.bindConsumer().binding

        // Act
        #expect(mailbox.lifecyclePort.seal() == .applied)
        #expect(mailbox.lifecyclePort.stateSnapshot == .sealed)
        #expect(await mailbox.actorWaiterPort.nextSignal() == .signaled)
        let lease = requireLease(
            mailbox.actorConsumerPort.takeDrain(binding: consumerBinding)
        )
        let acknowledgement = try credentialedTransferAcknowledgement(
            for: lease,
            consumerPort: mailbox.actorConsumerPort
        )

        // Assert
        #expect(acknowledgement == .transferredAuthoritative(wake: .noWake))
        expectClosed(mailbox.actorConsumerPort.takeDrain(binding: consumerBinding))
        #expect(mailbox.lifecyclePort.stateSnapshot == .sealed)
    }

    @Test("recovery transfer requires source-gate acceptance of the leased snapshot")
    func recoveryTransferRequiresSourceGateAcceptance() throws {
        // Arrange
        let registration = makeRegistration(index: 2)
        let fixture = try makeMailboxFixture(registration: registration)
        let mailbox = fixture.mailbox
        let recovery = requireRetainedRecovery(
            try fixture.admitCallback(
                .requiresRecovery(
                    try makeObservation(registration: registration, path: "/recovery/file", eventID: 2),
                    evidence: .continuityLoss
                )
            )
        )
        let consumerBinding = mailbox.actorConsumerPort.bindConsumer().binding
        let lease = requireLease(
            mailbox.actorConsumerPort.takeDrain(binding: consumerBinding)
        )
        var sourceGate = FilesystemSourceGate(binding: recovery.revision.binding)
        let recoveryParticipants = makeRequiredParticipants()
        _ = requireRecoveryAcceptance(
            sourceGate.acceptMailboxRecovery(
                recovery,
                trigger: .continuityLoss,
                watermark: .recoveryRevision(1),
                participants: recoveryParticipants
            )
        )

        // Act
        let acknowledgement = try credentialedTransferAcknowledgement(
            for: lease,
            consumerPort: mailbox.actorConsumerPort,
            sourceGate: &sourceGate,
            recoveryContext: .required(
                trigger: .continuityLoss,
                watermark: .recoveryRevision(1),
                participants: recoveryParticipants
            )
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
            mailbox.lifecyclePort.diagnostics.recoveryEvidence(
                for: fixture.binding.physicalSlotID
            ) == .clear(fixture.binding)
        )
    }

    @Test("invalidation reports retained contribution custody")
    func invalidationRejectsRetainedContribution() throws {
        // Arrange
        let registration = makeRegistration(index: 3)
        let fixture = try makeMailboxFixture(registration: registration)
        let mailbox = fixture.mailbox
        _ = try fixture.admitCallback(
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
        let fixture = try makeMailboxFixture(registration: registration)
        let mailbox = fixture.mailbox
        _ = try fixture.admitCallback(
            .authoritative(
                try makeObservation(registration: registration, path: "/leased/file", eventID: 4)
            )
        )
        let consumerBinding = mailbox.actorConsumerPort.bindConsumer().binding
        _ = requireLease(
            mailbox.actorConsumerPort.takeDrain(binding: consumerBinding)
        )
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
        let fixture = try makeMailboxFixture(registration: registration)
        let mailbox = fixture.mailbox
        _ = try fixture.admitCallback(
            .requiresRecovery(
                try makeObservation(registration: registration, path: "/retry/file", eventID: 5),
                evidence: .continuityLoss
            )
        )
        let consumerBinding = mailbox.actorConsumerPort.bindConsumer().binding
        let lease = requireLease(
            mailbox.actorConsumerPort.takeDrain(binding: consumerBinding)
        )
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
        let fixture = try makeMailboxFixture(registration: registration)
        let mailbox = fixture.mailbox
        let recovery = requireRetainedRecovery(
            try fixture.admitCallback(
                .requiresRecovery(
                    try makeObservation(registration: registration, path: "/transfer/file", eventID: 6),
                    evidence: .continuityLoss
                )
            )
        )
        let consumerBinding = mailbox.actorConsumerPort.bindConsumer().binding
        let lease = requireLease(
            mailbox.actorConsumerPort.takeDrain(binding: consumerBinding)
        )
        var sourceGate = FilesystemSourceGate(binding: recovery.revision.binding)
        let recoveryParticipants = makeRequiredParticipants()
        _ = requireRecoveryAcceptance(
            sourceGate.acceptMailboxRecovery(
                recovery,
                trigger: .continuityLoss,
                watermark: .recoveryRevision(1),
                participants: recoveryParticipants
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
            try credentialedTransferAcknowledgement(
                for: lease,
                consumerPort: mailbox.actorConsumerPort,
                sourceGate: &sourceGate,
                recoveryContext: .required(
                    trigger: .continuityLoss,
                    watermark: .recoveryRevision(1),
                    participants: recoveryParticipants
                )
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
        let mailbox = try makeMailboxFixture(registration: registration).mailbox

        // Act / Assert
        #expect(mailbox.lifecyclePort.finish() == .invalidState(.open))
        #expect(mailbox.lifecyclePort.seal() == .applied)
        #expect(mailbox.lifecyclePort.finish() == .invalidState(.sealed))
        #expect(mailbox.lifecyclePort.stateSnapshot == .sealed)
    }

    private func makeMailboxFixture(
        registration: FSEventRegistrationToken
    ) throws -> FixedSlotFilesystemObservationMailboxFixture {
        try makeFixedSlotMailboxFixture(
            generation: generation,
            registrations: [registration],
            limits: GatherMailboxLimits(
                maximumDeclaredKeys: 1,
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
            ),
            captureLimits: try FSEventCaptureLimits(
                maximumInspectedNativeRecords: 8,
                maximumCopiedRecords: 8,
                maximumCopiedUTF8Bytes: 4096,
                maximumSinglePathUTF8Bytes: 1024
            ),
            callbackQueueLabel: "test.filesystem-observation-mailbox-lifecycle"
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

}
