import Dispatch
import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation mailbox lifecycle")
struct FilesystemObservationMailboxLifecycleTests {
    private let generation = AdmissionGeneration(owner: .filesystemObservation, value: 72)

    @Test("repeated native port creation replays the fixed slot native owner")
    func repeatedNativePortCreationReplaysFixedSlotNativeOwner() throws {
        // Arrange
        let fixture = try makeMailboxFixture(registration: makeRegistration(index: 8))
        let startingNativeLifetime = try #require(
            fixture.startingNativeLifetimesByRegistration.values.first
        )

        // Act
        guard
            case .created(let firstPorts) = fixture.mailbox.nativeGenerationPorts(
                for: startingNativeLifetime
            ),
            case .created(let replayedPorts) = fixture.mailbox.nativeGenerationPorts(
                for: startingNativeLifetime
            )
        else {
            Issue.record("exact starting custody must create and replay native ports")
            return
        }

        // Assert
        #expect(firstPorts.nativeOwner === replayedPorts.nativeOwner)
    }

    @Test("mailbox fixed slot retains native owner after caller references are dropped")
    func mailboxFixedSlotRetainsNativeOwner() throws {
        // Arrange
        let fixture = try makeMailboxFixture(registration: makeRegistration(index: 9))
        let mailbox = fixture.mailbox
        let startingNativeLifetime = try #require(
            fixture.startingNativeLifetimesByRegistration.values.first
        )
        weak var retainedNativeOwner: DarwinFSEventRegistrationNativeOwner?

        // Act
        do {
            guard
                case .created(let ports) = mailbox.nativeGenerationPorts(
                    for: startingNativeLifetime
                )
            else {
                Issue.record("exact starting custody must create native ports")
                return
            }
            retainedNativeOwner = ports.nativeOwner
        }

        // Assert
        withExtendedLifetime(mailbox) {
            #expect(retainedNativeOwner != nil)
        }
    }

    @Test("fleet ingress freeze preserves drain progress for admitted observations")
    func fleetIngressFreezePreservesAdmittedDrainProgress() async throws {
        // Arrange
        let registration = makeRegistration(index: 1)
        let fixture = try makeMailboxFixture(registration: registration)
        let mailbox = fixture.mailbox
        let offer = try fixture.admitCallback(
            .authoritative(
                try makeObservation(registration: registration, path: "/frozen/file", eventID: 1)
            )
        )
        expectRetainedCallback(offer)
        let consumerBinding = mailbox.actorConsumerPort.bindConsumer().binding
        let lifecycle = FilesystemObservationFleetLifecycle()

        // Act
        guard
            case .applied(let shutdown) = lifecycle.beginShutdownAndSnapshot(mailbox: mailbox)
        else {
            Issue.record("fleet shutdown did not freeze ingress with exact retained debt")
            return
        }
        #expect(await mailbox.doorbellConsumerPort.nextSignal() == .signaled)
        let lease = requireLease(
            mailbox.actorConsumerPort.takeDrain(binding: consumerBinding)
        )
        let acknowledgement = try credentialedTransferAcknowledgement(
            for: lease,
            consumerPort: mailbox.actorConsumerPort
        )

        // Assert
        #expect(shutdown.fleetMailboxIdentity == mailbox.fleetMailboxIdentity)
        #expect(!shutdown.isQuiescent)
        #expect(acknowledgement == .transferredAuthoritative(wake: .noWake))
        guard case .empty = mailbox.actorConsumerPort.takeDrain(binding: consumerBinding) else {
            Issue.record("frozen mailbox must remain open and empty after admitted drain")
            return
        }
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
