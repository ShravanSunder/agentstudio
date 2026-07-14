import Dispatch
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
        let fixture = try makeMailboxFixture(
            registrations: [registration],
            limits: limits(global: 0, perRegistration: 1, perLease: 1)
        )
        let mailbox = fixture.mailbox
        let preWakeProbe = CallbackPreWakeProbe(mailbox: mailbox)

        // Act
        let result = try fixture.admitCallback(
            .authoritative(
                try makeObservation(registration: registration, path: "/root/overflow", eventID: 1)
            ),
            for: registration,
            synchronization: preWakeProbe
        )

        // Assert
        let recovery = requireContractedRecovery(result)
        #expect(recovery.evidence.contains(.callbackAdmissionOverflow))
        #expect(mailbox.recoveryEvidence(for: fixture.binding(for: registration)) == .retained(recovery))
        #expect(preWakeProbe.observedDoorbellState == .idle)
        #expect(requireCallbackWake(result) == .applied)
        #expect(mailbox.lifecyclePort.diagnostics.doorbellState == .signalPending)
    }

    @Test("native recovery evidence is joined before retained work is signaled")
    func explicitRecoveryIsRetainedBeforeWakeBecomesVisible() throws {
        // Arrange
        let registration = makeRegistration(index: 2)
        let fixture = try makeMailboxFixture(registrations: [registration])
        let mailbox = fixture.mailbox
        let preWakeProbe = CallbackPreWakeProbe(mailbox: mailbox)
        let evidence = FilesystemRecoveryEvidence.continuityLoss
            .unioning(.rootIdentityRevalidation)

        // Act
        let result = try fixture.admitCallback(
            .requiresRecovery(
                try makeObservation(registration: registration, path: "/root/loss", eventID: 10),
                evidence: evidence
            ),
            for: registration,
            synchronization: preWakeProbe
        )

        // Assert
        let recovery = requireRetainedRecovery(result)
        #expect(recovery.evidence.contains(.continuityLoss))
        #expect(recovery.evidence.contains(.rootIdentityRevalidation))
        #expect(mailbox.recoveryEvidence(for: fixture.binding(for: registration)) == .retained(recovery))
        #expect(preWakeProbe.observedDoorbellState == .idle)
        #expect(requireCallbackWake(result) == .applied)
        #expect(mailbox.lifecyclePort.diagnostics.doorbellState == .signalPending)
    }

    @Test("invalid callback footprint rejects before native capture")
    func invalidCallbackFootprintSkipsNativeCapture() throws {
        let registration = makeRegistration(index: 30)
        let fixture = try makeMailboxFixture(registrations: [registration])
        let (callbackAdmissionPort, controlBlock) = try makeCallbackHarness(
            fixture: fixture,
            registration: registration
        )
        let lease = try #require(acquiredLease(from: controlBlock))
        defer { _ = lease.release() }
        let inspectionLedger = NativeInspectionLedger()
        let preflight = FilesystemObservationCallbackPreflight(
            captureLimits: fixture.captureLimits,
            maximumFootprint: GatherFootprint(itemCount: -1, byteCount: 0)
        )

        let result = callbackAdmissionPort.admit(
            using: lease,
            preflight: preflight
        ) {
            inspectionLedger.recordInspection()
            return .ignoredEmptyCallback
        }

        expectRejection(result, expected: .mailbox(.invalidFootprint))
        #expect(inspectionLedger.inspectionCount == 0)
        #expect(fixture.mailbox.lifecyclePort.diagnostics.gather.admission.offered == 0)
    }

    @Test("callback footprint configuration mismatch rejects before native capture")
    func callbackFootprintConfigurationMismatchSkipsNativeCapture() throws {
        let registration = makeRegistration(index: 31)
        let fixture = try makeMailboxFixture(registrations: [registration])
        let (callbackAdmissionPort, controlBlock) = try makeCallbackHarness(
            fixture: fixture,
            registration: registration
        )
        let lease = try #require(acquiredLease(from: controlBlock))
        defer { _ = lease.release() }
        let inspectionLedger = NativeInspectionLedger()
        let preflight = FilesystemObservationCallbackPreflight(
            captureLimits: fixture.captureLimits,
            maximumFootprint: GatherFootprint(
                itemCount: fixture.captureLimits.maximumCopiedRecords - 1,
                byteCount: fixture.captureLimits.maximumCopiedUTF8Bytes
            )
        )

        let result = callbackAdmissionPort.admit(
            using: lease,
            preflight: preflight
        ) {
            inspectionLedger.recordInspection()
            return .ignoredEmptyCallback
        }

        expectRejection(result, expected: .mailbox(.captureConfigurationMismatch))
        #expect(inspectionLedger.inspectionCount == 0)
        #expect(fixture.mailbox.lifecyclePort.diagnostics.gather.admission.offered == 0)
    }

    @Test("fleet-sealed callback rejects before native capture or generic offer")
    func fleetSealedCallbackSkipsNativeCapture() throws {
        let registration = makeRegistration(index: 32)
        let fixture = try makeMailboxFixture(
            registrations: [registration],
            limits: limits(global: 0, perRegistration: 1, perLease: 1),
            recoveryAuthoritySeed: .preseededSequenced(.max)
        )
        let terminalRecovery = requireContractedRecovery(
            try fixture.admitCallback(
                .authoritative(
                    try makeObservation(
                        registration: registration,
                        path: "/root/exhaust",
                        eventID: 32
                    )
                ),
                for: registration
            )
        )
        let diagnosticsBeforeRejection = fixture.mailbox.lifecyclePort.diagnostics.gather
        let (callbackAdmissionPort, controlBlock) = try makeCallbackHarness(
            fixture: fixture,
            registration: registration
        )
        let lease = try #require(acquiredLease(from: controlBlock))
        defer { _ = lease.release() }
        let inspectionLedger = NativeInspectionLedger()

        let result = callbackAdmissionPort.admit(
            using: lease,
            preflight: FilesystemObservationCallbackPreflight(
                captureLimits: fixture.captureLimits
            )
        ) {
            inspectionLedger.recordInspection()
            return .ignoredEmptyCallback
        }

        expectRejection(
            result,
            expected: .mailbox(
                .fleetAdmissionExhausted(
                    FilesystemObservationFleetAdmissionExhaustionDebt(
                        triggeringBinding: fixture.binding(for: registration),
                        terminalGenericRecoveryRevision:
                            terminalRecovery.revision.genericRecoveryRevision
                    )
                )
            )
        )
        #expect(inspectionLedger.inspectionCount == 0)
        #expect(
            fixture.mailbox.lifecyclePort.diagnostics.gather.admission.offered
                == diagnosticsBeforeRejection.admission.offered
        )
    }

    @Test("mismatched registrations retain no payload evidence or wake")
    func mismatchedRegistrationHasNoSideEffects() throws {
        // Arrange
        let declared = makeRegistration(index: 3)
        let unknown = makeRegistration(index: 4)
        let fixture = try makeMailboxFixture(registrations: [declared])
        let mailbox = fixture.mailbox
        let binding = fixture.binding(for: declared)
        let undeclaredPhysicalSlotID = FilesystemObservationPhysicalSlotID(value: UUIDv7.generate())

        // Act
        let result = try fixture.admitCallback(
            .requiresRecovery(
                try makeObservation(registration: unknown, path: "/unknown/file", eventID: 20),
                evidence: .continuityLoss
            ),
            for: declared
        )

        // Assert
        expectRejection(result, expected: .mailbox(.fenced))
        #expect(
            mailbox.lifecyclePort.diagnostics.recoveryEvidence(for: undeclaredPhysicalSlotID)
                == .undeclaredPhysicalSlot
        )
        #expect(mailbox.recoveryEvidence(for: binding) == .clear(binding))
        #expect(mailbox.lifecyclePort.diagnostics.doorbellState == .idle)
        #expect(mailbox.lifecyclePort.diagnostics.gather.retainedContributionCount == 0)
    }

    @Test("an older recovery acknowledgement cannot clear newer joined evidence")
    func olderRecoveryAcknowledgementRetainsNewerEvidence() throws {
        // Arrange
        let registration = makeRegistration(index: 5)
        let fixture = try makeMailboxFixture(registrations: [registration])
        let mailbox = fixture.mailbox
        let slotBinding = fixture.binding(for: registration)
        let consumer = mailbox.actorConsumerPort
        let consumerBinding = consumer.bindConsumer().binding
        let oldRecovery = requireRetainedRecovery(
            try fixture.admitCallback(
                .requiresRecovery(
                    try makeObservation(registration: registration, path: "/root/a", eventID: 30),
                    evidence: .continuityLoss
                ),
                for: registration
            )
        )
        let oldLease = requireLease(consumer.takeDrain(binding: consumerBinding))
        #expect(requireRecovery(oldLease) == oldRecovery)
        var sourceGate = FilesystemSourceGate(binding: oldLease.binding)
        let newestRecovery = requireRetainedRecovery(
            try fixture.admitCallback(
                .requiresRecovery(
                    try makeObservation(registration: registration, path: "/root/b", eventID: 31),
                    evidence: .unsupportedNativeFlags
                ),
                for: registration
            )
        )

        // Act
        let acknowledgement = try credentialedTransferAcknowledgement(
            for: oldLease,
            consumerPort: consumer,
            sourceGate: &sourceGate,
            recoveryContext: requiredRecoveryAdmissionContext()
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
            mailbox.recoveryEvidence(for: slotBinding) == .retained(newestRecovery)
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
        let fixture = try makeMailboxFixture(
            registrations: [alpha, beta, gamma],
            limits: limits(global: 2, perRegistration: 2, perLease: 1)
        )
        let mailbox = fixture.mailbox
        let consumer = mailbox.actorConsumerPort
        let consumerBinding = consumer.bindConsumer().binding
        _ = try fixture.admitCallback(
            .authoritative(
                try makeObservation(registration: alpha, path: "/alpha/leased", eventID: 40)
            ),
            for: alpha
        )
        #expect(await mailbox.actorWaiterPort.nextSignal() == .signaled)
        let alphaLease = requireLease(
            consumer.takeDrain(binding: consumerBinding)
        )
        _ = try fixture.admitCallback(
            .authoritative(
                try makeObservation(registration: beta, path: "/beta/pending", eventID: 41)
            ),
            for: beta
        )

        // Act
        let overflow = try fixture.admitCallback(
            .authoritative(
                try makeObservation(registration: gamma, path: "/gamma/overflow", eventID: 42)
            ),
            for: gamma
        )
        let diagnostics = mailbox.lifecyclePort.diagnostics.gather

        // Assert
        #expect(alphaLease.binding == fixture.binding(for: alpha))
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
        let fixture = try makeMailboxFixture(
            registrations: [noisy, quiet],
            limits: limits(global: 4, perRegistration: 2, perLease: 1)
        )
        let mailbox = fixture.mailbox
        let consumer = mailbox.actorConsumerPort
        let consumerBinding = consumer.bindConsumer().binding
        _ = try fixture.admitCallback(
            .authoritative(
                try makeObservation(registration: noisy, path: "/noisy/leased", eventID: 50)
            ),
            for: noisy
        )
        #expect(await mailbox.actorWaiterPort.nextSignal() == .signaled)
        _ = requireLease(consumer.takeDrain(binding: consumerBinding))
        _ = try fixture.admitCallback(
            .authoritative(
                try makeObservation(registration: noisy, path: "/noisy/pending", eventID: 51)
            ),
            for: noisy
        )

        // Act
        let noisyOverflow = try fixture.admitCallback(
            .authoritative(
                try makeObservation(registration: noisy, path: "/noisy/overflow", eventID: 52)
            ),
            for: noisy
        )
        let quietOffer = try fixture.admitCallback(
            .authoritative(
                try makeObservation(registration: quiet, path: "/quiet/current", eventID: 53)
            ),
            for: quiet
        )

        // Assert
        let noisyRecovery = requireContractedRecovery(noisyOverflow)
        #expect(noisyRecovery.evidence.contains(.callbackAdmissionOverflow))
        expectRetainedCallback(quietOffer)
        #expect(
            mailbox.recoveryEvidence(for: fixture.binding(for: quiet))
                == .clear(fixture.binding(for: quiet))
        )
        #expect(mailbox.lifecyclePort.diagnostics.gather.retainedContributionCount == 2)
        #expect(mailbox.lifecyclePort.diagnostics.gather.admission.contracted == 1)
    }

    @Test("one keyed lease preserves each opaque observation without semantic merging")
    func leaseIsKeyedBoundedAndValueOnly() async throws {
        // Arrange
        let alpha = makeRegistration(index: 11)
        let beta = makeRegistration(index: 12)
        let fixture = try makeMailboxFixture(
            registrations: [alpha, beta],
            limits: limits(global: 4, perRegistration: 3, perLease: 2)
        )
        let mailbox = fixture.mailbox
        let consumer = mailbox.actorConsumerPort
        let consumerBinding = consumer.bindConsumer().binding
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
        _ = try fixture.admitCallback(.authoritative(first), for: alpha)
        _ = try fixture.admitCallback(.authoritative(second), for: alpha)
        _ = try fixture.admitCallback(.authoritative(betaObservation), for: beta)

        // Act
        #expect(mailbox.lifecyclePort.diagnostics.doorbellState == .signalPending)
        #expect(await mailbox.actorWaiterPort.nextSignal() == .signaled)
        #expect(mailbox.lifecyclePort.diagnostics.doorbellState == .idle)
        let lease = requireLease(
            consumer.takeDrain(binding: consumerBinding)
        )
        let observations = requireObservations(lease)

        // Assert
        #expect(lease.binding == fixture.binding(for: alpha))
        #expect(observations.count == 2)
        #expect(observations.map { $0.records } == [first.records, second.records])
        #expect(observations.map { $0.eventIDWatermark } == [first.eventIDWatermark, second.eventIDWatermark])
        expectAlreadyLeased(
            consumer.takeDrain(binding: consumerBinding)
        )
    }

    @Test("rebind and retry preserve exact custody and fair key ordering")
    func rebindAndRetryPreserveCustody() throws {
        // Arrange
        let alpha = makeRegistration(index: 13)
        let beta = makeRegistration(index: 14)
        let fixture = try makeMailboxFixture(
            registrations: [alpha, beta],
            limits: limits(global: 4, perRegistration: 3, perLease: 1)
        )
        let mailbox = fixture.mailbox
        let consumer = mailbox.actorConsumerPort
        let oldBinding = consumer.bindConsumer().binding
        let alphaRecovery = requireRetainedRecovery(
            try fixture.admitCallback(
                .requiresRecovery(
                    try makeObservation(registration: alpha, path: "/alpha/retry", eventID: 70),
                    evidence: .continuityLoss
                ),
                for: alpha
            )
        )
        let oldLease = requireLease(
            consumer.takeDrain(binding: oldBinding)
        )
        _ = try fixture.admitCallback(
            .authoritative(
                try makeObservation(registration: beta, path: "/beta/ready", eventID: 71)
            ),
            for: beta
        )
        _ = try fixture.admitCallback(
            .authoritative(
                try makeObservation(registration: alpha, path: "/alpha/newer", eventID: 72)
            ),
            for: alpha
        )

        // Act
        let replacementBinding = consumer.bindConsumer().binding
        let replacementLease = requireLease(
            consumer.takeDrain(binding: replacementBinding)
        )
        let lateOldAcknowledgement = consumer.acknowledge(
            token: oldLease.token,
            disposition: .retry
        )
        let retryAcknowledgement = consumer.acknowledge(
            token: replacementLease.token,
            disposition: .retry
        )
        let betaLease = requireLease(
            consumer.takeDrain(binding: replacementBinding)
        )
        _ = try credentialedTransferAcknowledgement(
            for: betaLease,
            consumerPort: consumer
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
        #expect(betaLease.binding == fixture.binding(for: beta))
        #expect(retriedAlphaLease.binding == fixture.binding(for: alpha))
        #expect(
            requireObservations(retriedAlphaLease).map { $0.records }
                == requireObservations(oldLease).map { $0.records })
        #expect(requireRecovery(retriedAlphaLease) == alphaRecovery)
    }

    private func makeMailboxFixture(
        registrations: [FSEventRegistrationToken],
        limits: GatherMailboxLimits? = nil,
        recoveryAuthoritySeed: FilesystemObservationRecoveryAuthoritySeed = .initial
    ) throws -> FixedSlotFilesystemObservationMailboxFixture {
        try makeFixedSlotMailboxFixture(
            generation: generation,
            registrations: registrations,
            limits: limits ?? self.limits(global: 8, perRegistration: 4, perLease: 2),
            captureLimits: FSEventCaptureLimits(
                maximumInspectedNativeRecords: 32,
                maximumCopiedRecords: 16,
                maximumCopiedUTF8Bytes: 4096,
                maximumSinglePathUTF8Bytes: 1024
            ),
            callbackQueueLabel: "test.filesystem-observation-mailbox",
            recoveryAuthoritySeed: recoveryAuthoritySeed
        )
    }

    private func makeCallbackHarness(
        fixture: FixedSlotFilesystemObservationMailboxFixture,
        registration: FSEventRegistrationToken
    ) throws -> (FilesystemObservationCallbackAdmissionPort, FSEventRegistrationControlBlock) {
        let startingNativeLifetime = try #require(
            fixture.startingNativeLifetimesByRegistration[registration]
        )
        let callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort
        switch fixture.mailbox.nativeGenerationPorts(for: startingNativeLifetime) {
        case .created(let ports):
            callbackAdmissionPort = ports.callbackAdmissionPort
        case .foreignFleet, .undeclaredPhysicalSlot, .bindingNotCurrent:
            throw FixedSlotFilesystemObservationTestFailure.callbackPortUnavailable
        }
        return (
            callbackAdmissionPort,
            try makeControlBlock(
                startingNativeLifetime: startingNativeLifetime,
                captureLimits: fixture.captureLimits,
                callbackQueueLabel: fixture.callbackQueueLabel
            )
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

    private func requireRetainedRecovery(
        _ result: FilesystemObservationOfferResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FixedFilesystemRecoveryEvidenceSnapshot {
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
    ) -> FixedFilesystemRecoveryEvidenceSnapshot {
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

    private func requireRetainedRecovery(
        _ result: DarwinFSEventObservationCaptureResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FixedFilesystemRecoveryEvidenceSnapshot {
        let disposition = requireCallbackDisposition(result, sourceLocation: sourceLocation)
        guard case .retainedWithRecovery(let recovery) = disposition else {
            Issue.record(
                "Expected retained callback recovery, got \(result)",
                sourceLocation: sourceLocation
            )
            preconditionFailure("Expected retained callback recovery")
        }
        return recovery
    }

    private func requireContractedRecovery(
        _ result: DarwinFSEventObservationCaptureResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FixedFilesystemRecoveryEvidenceSnapshot {
        let disposition = requireCallbackDisposition(result, sourceLocation: sourceLocation)
        guard case .contractedToRecovery(let recovery) = disposition else {
            Issue.record(
                "Expected contracted callback recovery, got \(result)",
                sourceLocation: sourceLocation
            )
            preconditionFailure("Expected contracted callback recovery")
        }
        return recovery
    }

    private func requireCallbackDisposition(
        _ result: DarwinFSEventObservationCaptureResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FilesystemObservationOfferDisposition {
        guard case .admitted(_, let admission) = result,
            case .admitted(let disposition, _) = admission
        else {
            Issue.record("Expected admitted callback, got \(result)", sourceLocation: sourceLocation)
            preconditionFailure("Expected admitted callback")
        }
        return disposition
    }

    private func requireCallbackWake(
        _ result: DarwinFSEventObservationCaptureResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FilesystemObservationCallbackWakeApplication {
        guard case .admitted(_, let admission) = result,
            case .admitted(_, let wake) = admission
        else {
            Issue.record("Expected admitted callback, got \(result)", sourceLocation: sourceLocation)
            preconditionFailure("Expected admitted callback")
        }
        return wake
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
        case .contributions(let contributions),
            .contributionsWithRecovery(let contributions, _):
            let retainedContributions = [contributions.first] + contributions.remaining
            for contribution in retainedContributions {
                #expect(contribution.identity.binding == lease.binding)
                #expect(contribution.identity.isUUIDv7)
            }
            return retainedContributions.map { contribution in
                switch contribution {
                case .observation(_, let observation):
                    return observation
                case .retirementFence:
                    Issue.record(
                        "Expected observation contribution, got retirement fence",
                        sourceLocation: sourceLocation
                    )
                    preconditionFailure("Expected observation contribution")
                }
            }
        case .recovery:
            Issue.record("Expected observation-bearing lease", sourceLocation: sourceLocation)
            preconditionFailure("Expected observation-bearing lease")
        }
    }

    private func requireRecovery(
        _ lease: FilesystemObservationDrainLease,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FixedFilesystemRecoveryEvidenceSnapshot {
        switch lease.payload {
        case .contributionsWithRecovery(_, let recovery), .recovery(let recovery):
            return recovery
        case .contributions:
            Issue.record("Expected recovery-bearing lease", sourceLocation: sourceLocation)
            preconditionFailure("Expected recovery-bearing lease")
        }
    }

}
