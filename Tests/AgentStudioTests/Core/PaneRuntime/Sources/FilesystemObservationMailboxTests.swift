import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation mailbox")
struct FilesystemObservationMailboxTests {
    private let generation = AdmissionGeneration(owner: .filesystemObservation, value: 71)

    @Test("capacity contraction installs overflow evidence before signaling")
    func contractionInstallsRecoveryBeforeWakeBecomesVisible() throws {
        // Arrange
        let registration = makeRegistration(index: 1)
        let mailbox = try makeMailbox(
            registrations: [registration],
            limits: limits(global: 0, perRegistration: 1, perLease: 1)
        )
        let producer: FilesystemObservationCallbackProducerPort = mailbox.callbackProducerPort
        let signaler: FilesystemObservationCallbackSignalerPort = mailbox.callbackSignalerPort
        let _: FilesystemObservationActorConsumerPort = mailbox.actorConsumerPort
        let _: FilesystemObservationActorWaiterPort = mailbox.actorWaiterPort
        let lifecycle: FilesystemObservationLifecyclePort = mailbox.lifecyclePort

        // Act
        let result = producer.offer(
            .authoritative(
                try makeObservation(registration: registration, path: "/root/overflow", eventID: 1)
            )
        )

        // Assert
        let recovery = requireContractedRecovery(result)
        let receipt = requireOfferReceipt(result)
        #expect(recovery.evidence.contains(.callbackAdmissionOverflow))
        #expect(lifecycle.diagnostics.recoveryEvidence(for: registration) == .evidence(recovery))
        #expect(lifecycle.diagnostics.doorbellState == .idle)
        #expect(receipt.wake == .scheduleDrain)
        signaler.apply(receipt.wake)
        #expect(lifecycle.diagnostics.doorbellState == .signalPending)
    }

    @Test("native recovery evidence is joined before retained work is signaled")
    func explicitRecoveryIsRetainedBeforeWakeBecomesVisible() throws {
        // Arrange
        let registration = makeRegistration(index: 2)
        let mailbox = try makeMailbox(registrations: [registration])
        let evidence = FilesystemRecoveryEvidence.continuityLoss
            .unioning(.rootIdentityRevalidation)

        // Act
        let result = mailbox.callbackProducerPort.offer(
            .requiresRecovery(
                try makeObservation(registration: registration, path: "/root/loss", eventID: 10),
                evidence: evidence
            )
        )

        // Assert
        let recovery = requireRetainedRecovery(result)
        let receipt = requireOfferReceipt(result)
        #expect(recovery.evidence.contains(.continuityLoss))
        #expect(recovery.evidence.contains(.rootIdentityRevalidation))
        #expect(mailbox.lifecyclePort.diagnostics.recoveryEvidence(for: registration) == .evidence(recovery))
        #expect(mailbox.lifecyclePort.diagnostics.doorbellState == .idle)
        mailbox.callbackSignalerPort.apply(receipt.wake)
        #expect(mailbox.lifecyclePort.diagnostics.doorbellState == .signalPending)
    }

    @Test("unknown registrations retain no payload evidence or wake")
    func unknownRegistrationHasNoSideEffects() throws {
        // Arrange
        let declared = makeRegistration(index: 3)
        let unknown = makeRegistration(index: 4)
        let mailbox = try makeMailbox(registrations: [declared])

        // Act
        let result = mailbox.callbackProducerPort.offer(
            .requiresRecovery(
                try makeObservation(registration: unknown, path: "/unknown/file", eventID: 20),
                evidence: .continuityLoss
            )
        )

        // Assert
        #expect(result == .undeclaredRegistration)
        #expect(mailbox.lifecyclePort.diagnostics.recoveryEvidence(for: unknown) == .unknownRegistration)
        #expect(mailbox.lifecyclePort.diagnostics.recoveryEvidence(for: declared) == .noEvidence(.sequenced(0)))
        #expect(mailbox.lifecyclePort.diagnostics.doorbellState == .idle)
        #expect(mailbox.lifecyclePort.diagnostics.gather.retainedContributionCount == 0)
    }

    @Test("an older recovery acknowledgement cannot clear newer joined evidence")
    func olderRecoveryAcknowledgementRetainsNewerEvidence() throws {
        // Arrange
        let registration = makeRegistration(index: 5)
        let mailbox = try makeMailbox(registrations: [registration])
        let consumer = mailbox.actorConsumerPort
        let binding = consumer.bindConsumer().binding
        let oldRecovery = requireRetainedRecovery(
            mailbox.callbackProducerPort.offer(
                .requiresRecovery(
                    try makeObservation(registration: registration, path: "/root/a", eventID: 30),
                    evidence: .continuityLoss
                )
            )
        )
        let oldLease = requireLease(consumer.takeDrain(binding: binding))
        #expect(requireRecovery(oldLease) == oldRecovery)
        let oldRecoveryAcceptance = try acceptRecovery(oldRecovery)
        let newestRecovery = requireRetainedRecovery(
            mailbox.callbackProducerPort.offer(
                .requiresRecovery(
                    try makeObservation(registration: registration, path: "/root/b", eventID: 31),
                    evidence: .unsupportedNativeFlags
                )
            )
        )

        // Act
        let acknowledgement = consumer.acknowledge(
            token: oldLease.token,
            disposition: .transferredRecovery(oldRecoveryAcceptance)
        )

        // Assert
        #expect(
            acknowledgement
                == .transferredRecovery(
                    evidence: .newerEvidenceRetained(newestRecovery),
                    wake: .scheduleDrain
                )
        )
        #expect(
            mailbox.lifecyclePort.diagnostics.recoveryEvidence(for: registration)
                == .evidence(newestRecovery)
        )
        #expect(newestRecovery.evidence.contains(.continuityLoss))
        #expect(newestRecovery.evidence.contains(.unsupportedNativeFlags))
    }

    @Test("global capacity counts pending plus leased custody")
    func globalCapacityCountsPendingAndLeasedObservations() async throws {
        // Arrange
        let alpha = makeRegistration(index: 6)
        let beta = makeRegistration(index: 7)
        let gamma = makeRegistration(index: 8)
        let mailbox = try makeMailbox(
            registrations: [alpha, beta, gamma],
            limits: limits(global: 2, perRegistration: 2, perLease: 1)
        )
        let producer = mailbox.callbackProducerPort
        let consumer = mailbox.actorConsumerPort
        let binding = consumer.bindConsumer().binding
        let alphaOffer = producer.offer(
            .authoritative(
                try makeObservation(registration: alpha, path: "/alpha/leased", eventID: 40)
            )
        )
        mailbox.callbackSignalerPort.apply(requireOfferReceipt(alphaOffer).wake)
        #expect(await mailbox.actorWaiterPort.nextSignal() == .signaled)
        let alphaLease = requireLease(
            consumer.takeDrain(binding: binding)
        )
        _ = producer.offer(
            .authoritative(
                try makeObservation(registration: beta, path: "/beta/pending", eventID: 41)
            )
        )

        // Act
        let overflow = producer.offer(
            .authoritative(
                try makeObservation(registration: gamma, path: "/gamma/overflow", eventID: 42)
            )
        )
        let diagnostics = mailbox.lifecyclePort.diagnostics.gather

        // Assert
        #expect(alphaLease.registration == alpha)
        #expect(diagnostics.retainedContributionCount == 2)
        #expect(diagnostics.pendingContributionCount == 1)
        #expect(diagnostics.leasedContributionCount == 1)
        #expect(requireContractedRecovery(overflow).evidence.contains(.callbackAdmissionOverflow))
    }

    @Test("per-registration capacity contracts only the noisy registration")
    func perRegistrationCapacityIncludesActiveLease() async throws {
        // Arrange
        let noisy = makeRegistration(index: 9)
        let quiet = makeRegistration(index: 10)
        let mailbox = try makeMailbox(
            registrations: [noisy, quiet],
            limits: limits(global: 4, perRegistration: 2, perLease: 1)
        )
        let producer = mailbox.callbackProducerPort
        let consumer = mailbox.actorConsumerPort
        let binding = consumer.bindConsumer().binding
        let firstOffer = producer.offer(
            .authoritative(
                try makeObservation(registration: noisy, path: "/noisy/leased", eventID: 50)
            )
        )
        mailbox.callbackSignalerPort.apply(requireOfferReceipt(firstOffer).wake)
        #expect(await mailbox.actorWaiterPort.nextSignal() == .signaled)
        _ = requireLease(consumer.takeDrain(binding: binding))
        _ = producer.offer(
            .authoritative(
                try makeObservation(registration: noisy, path: "/noisy/pending", eventID: 51)
            )
        )

        // Act
        let noisyOverflow = producer.offer(
            .authoritative(
                try makeObservation(registration: noisy, path: "/noisy/overflow", eventID: 52)
            )
        )
        let quietOffer = producer.offer(
            .authoritative(
                try makeObservation(registration: quiet, path: "/quiet/current", eventID: 53)
            )
        )

        // Assert
        let noisyRecovery = requireContractedRecovery(noisyOverflow)
        #expect(noisyRecovery.evidence.contains(.callbackAdmissionOverflow))
        expectRetained(quietOffer)
        #expect(
            mailbox.lifecyclePort.diagnostics.recoveryEvidence(for: quiet)
                == .noEvidence(.sequenced(0))
        )
        #expect(mailbox.lifecyclePort.diagnostics.gather.retainedContributionCount == 2)
        #expect(mailbox.lifecyclePort.diagnostics.gather.admission.contracted == 1)
    }

    @Test("one keyed lease preserves each opaque observation without semantic merging")
    func leaseIsKeyedBoundedAndValueOnly() async throws {
        // Arrange
        let alpha = makeRegistration(index: 11)
        let beta = makeRegistration(index: 12)
        let mailbox = try makeMailbox(
            registrations: [alpha, beta],
            limits: limits(global: 4, perRegistration: 3, perLease: 2)
        )
        let producer = mailbox.callbackProducerPort
        let consumer = mailbox.actorConsumerPort
        let binding = consumer.bindConsumer().binding
        let first = try makeObservation(
            registration: alpha,
            path: "/alpha/duplicate",
            flags: [.itemCreated],
            eventID: 60
        )
        let second = try makeObservation(
            registration: alpha,
            path: "/alpha/duplicate",
            flags: [.itemRemoved],
            eventID: 61
        )
        let betaObservation = try makeObservation(
            registration: beta,
            path: "/beta/file",
            eventID: 62
        )
        let firstOffer = producer.offer(.authoritative(first))
        let secondOffer = producer.offer(.authoritative(second))
        let betaOffer = producer.offer(.authoritative(betaObservation))
        let signaler = mailbox.callbackSignalerPort
        signaler.apply(requireOfferReceipt(firstOffer).wake)
        signaler.apply(requireOfferReceipt(secondOffer).wake)
        signaler.apply(requireOfferReceipt(betaOffer).wake)

        // Act
        #expect(mailbox.lifecyclePort.diagnostics.doorbellState == .signalPending)
        #expect(await mailbox.actorWaiterPort.nextSignal() == .signaled)
        #expect(mailbox.lifecyclePort.diagnostics.doorbellState == .idle)
        let lease = requireLease(
            consumer.takeDrain(binding: binding)
        )
        let observations = requireObservations(lease)

        // Assert
        #expect(lease.registration == alpha)
        #expect(observations.count == 2)
        #expect(observations.map { $0.records } == [first.records, second.records])
        #expect(observations.map { $0.eventIDWatermark } == [first.eventIDWatermark, second.eventIDWatermark])
        expectAlreadyLeased(
            consumer.takeDrain(binding: binding)
        )
    }

    @Test("rebind and retry preserve exact custody and fair key ordering")
    func rebindAndRetryPreserveCustody() throws {
        // Arrange
        let alpha = makeRegistration(index: 13)
        let beta = makeRegistration(index: 14)
        let mailbox = try makeMailbox(
            registrations: [alpha, beta],
            limits: limits(global: 4, perRegistration: 3, perLease: 1)
        )
        let producer = mailbox.callbackProducerPort
        let consumer = mailbox.actorConsumerPort
        let oldBinding = consumer.bindConsumer().binding
        let alphaRecovery = requireRetainedRecovery(
            producer.offer(
                .requiresRecovery(
                    try makeObservation(registration: alpha, path: "/alpha/retry", eventID: 70),
                    evidence: .continuityLoss
                )
            )
        )
        let oldLease = requireLease(
            consumer.takeDrain(binding: oldBinding)
        )
        let alphaRecoveryAcceptance = try acceptRecovery(alphaRecovery)
        _ = producer.offer(
            .authoritative(
                try makeObservation(registration: beta, path: "/beta/ready", eventID: 71)
            )
        )
        _ = producer.offer(
            .authoritative(
                try makeObservation(registration: alpha, path: "/alpha/newer", eventID: 72)
            )
        )

        // Act
        let replacementBinding = consumer.bindConsumer().binding
        let replacementLease = requireLease(
            consumer.takeDrain(binding: replacementBinding)
        )
        let lateOldAcknowledgement = consumer.acknowledge(
            token: oldLease.token,
            disposition: .transferredRecovery(alphaRecoveryAcceptance)
        )
        let retryAcknowledgement = consumer.acknowledge(
            token: replacementLease.token,
            disposition: .retry
        )
        let betaLease = requireLease(
            consumer.takeDrain(binding: replacementBinding)
        )
        _ = consumer.acknowledge(
            token: betaLease.token,
            disposition: .transferredAuthoritative
        )
        let retriedAlphaLease = requireLease(
            consumer.takeDrain(binding: replacementBinding)
        )

        // Assert
        #expect(replacementLease.token != oldLease.token)
        #expect(
            requireObservations(replacementLease).map { $0.records } == requireObservations(oldLease).map { $0.records }
        )
        #expect(requireRecovery(replacementLease) == alphaRecovery)
        #expect(lateOldAcknowledgement == .invalidToken)
        #expect(retryAcknowledgement == .retried(wake: .scheduleDrain))
        #expect(betaLease.registration == beta)
        #expect(retriedAlphaLease.registration == alpha)
        #expect(
            requireObservations(retriedAlphaLease).map { $0.records }
                == requireObservations(oldLease).map { $0.records })
        #expect(requireRecovery(retriedAlphaLease) == alphaRecovery)
    }

    private func makeMailbox(
        registrations: [FSEventRegistrationToken],
        limits: GatherMailboxLimits? = nil
    ) throws -> FilesystemObservationMailbox {
        try FilesystemObservationMailbox(
            generation: generation,
            declaredRegistrations: registrations,
            limits: limits ?? self.limits(global: 8, perRegistration: 4, perLease: 2)
        )
    }

    private func limits(
        global: Int,
        perRegistration: Int,
        perLease: Int
    ) -> GatherMailboxLimits {
        GatherMailboxLimits(
            maximumDeclaredKeys: 32,
            maximumRetainedContributions: global,
            maximumRetainedItems: global,
            maximumRetainedBytes: global * 64,
            maximumRetainedContributionsPerKey: perRegistration,
            maximumRetainedItemsPerKey: perRegistration,
            maximumRetainedBytesPerKey: perRegistration * 64,
            maximumContributionsPerLease: perLease,
            maximumItemsPerLease: perLease,
            maximumBytesPerLease: perLease * 64,
            cleanupQuantum: .entriesAndBytes(
                maximumEntries: max(1, perLease),
                maximumBytes: max(64, perLease * 64)
            )
        )
    }

    private func makeRegistration(index: Int) -> FSEventRegistrationToken {
        let suffix = String(format: "%012d", index)
        return FSEventRegistrationToken(
            sourceID: FilesystemSourceID(
                kind: .registeredWorktreeContent,
                rootID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-\(suffix)")!
            ),
            registrationGeneration: UInt64(index),
            rootGeneration: 1
        )
    }

    private func makeObservation(
        registration: FSEventRegistrationToken,
        path: String,
        flags: FSEventFlags = [.itemModified],
        eventID: UInt64
    ) throws -> FSEventObservation {
        try FSEventObservation(
            registration: registration,
            capturedAt: ContinuousClock.now,
            totalRecordCount: .exact(1),
            inspectedNativeRecordCount: 1,
            records: [FSEventRecord(path: path, flags: flags, eventID: eventID)],
            unionedInspectedFlags: flags,
            eventIDWatermark: .inspected(first: eventID, last: eventID),
            completeness: .complete
        )
    }

    private func requireRetainedRecovery(
        _ result: FilesystemObservationOfferResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FilesystemRecoveryEvidenceSnapshot {
        let receipt = requireOfferReceipt(result, sourceLocation: sourceLocation)
        guard case .retainedWithRecovery(let recovery) = receipt.disposition else {
            Issue.record("Expected retained recovery, got \(result)", sourceLocation: sourceLocation)
            preconditionFailure("Expected retained filesystem recovery")
        }
        return recovery
    }

    private func requireContractedRecovery(
        _ result: FilesystemObservationOfferResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FilesystemRecoveryEvidenceSnapshot {
        let receipt = requireOfferReceipt(result, sourceLocation: sourceLocation)
        guard case .contractedToRecovery(let recovery) = receipt.disposition else {
            Issue.record("Expected contracted recovery, got \(result)", sourceLocation: sourceLocation)
            preconditionFailure("Expected contracted filesystem recovery")
        }
        return recovery
    }

    private func requireOfferReceipt(
        _ result: FilesystemObservationOfferResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FilesystemObservationOfferReceipt {
        guard case .admitted(let receipt) = result else {
            Issue.record("Expected admitted observation, got \(result)", sourceLocation: sourceLocation)
            preconditionFailure("Expected admitted filesystem observation")
        }
        return receipt
    }

    private func expectRetained(
        _ result: FilesystemObservationOfferResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let receipt = requireOfferReceipt(result, sourceLocation: sourceLocation)
        guard case .retained = receipt.disposition else {
            Issue.record("Expected retained observation, got \(result)", sourceLocation: sourceLocation)
            return
        }
    }

    private func requireLease(
        _ result: FilesystemObservationTakeDrainResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FilesystemObservationDrainLease {
        guard case .lease(let lease) = result else {
            Issue.record("Expected filesystem observation lease, got \(result)", sourceLocation: sourceLocation)
            preconditionFailure("Expected filesystem observation lease")
        }
        return lease
    }

    private func requireObservations(
        _ lease: FilesystemObservationDrainLease,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> [FSEventObservation] {
        switch lease.payload {
        case .observations(let observations), .observationsWithRecovery(let observations, _):
            return [observations.first] + observations.remaining
        case .recovery:
            Issue.record("Expected observation-bearing lease", sourceLocation: sourceLocation)
            preconditionFailure("Expected observation-bearing lease")
        }
    }

    private func requireRecovery(
        _ lease: FilesystemObservationDrainLease,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FilesystemRecoveryEvidenceSnapshot {
        switch lease.payload {
        case .observationsWithRecovery(_, let recovery), .recovery(let recovery):
            return recovery
        case .observations:
            Issue.record("Expected recovery-bearing lease", sourceLocation: sourceLocation)
            preconditionFailure("Expected recovery-bearing lease")
        }
    }

    private func acceptRecovery(
        _ evidence: FilesystemRecoveryEvidenceSnapshot,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> FilesystemSourceGateRecoveryAcceptance {
        var sourceGate = FilesystemSourceGate(registration: evidence.revision.registration)
        let participants = Set(
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
        guard
            case .admitted(let acceptance) = sourceGate.acceptMailboxRecovery(
                evidence,
                trigger: .continuityLoss,
                watermark: .recoveryRevision(1),
                participants: participants
            )
        else {
            Issue.record("source gate rejected recovery evidence", sourceLocation: sourceLocation)
            throw TestFailure.recoveryNotAccepted
        }
        return acceptance
    }

    private func expectAlreadyLeased(
        _ result: FilesystemObservationTakeDrainResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard case .alreadyLeased = result else {
            Issue.record("Expected outstanding-lease rejection", sourceLocation: sourceLocation)
            return
        }
    }

    private enum TestFailure: Error {
        case recoveryNotAccepted
    }

}
