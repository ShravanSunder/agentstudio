import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation semantic shutdown debt")
struct FilesystemObservationSemanticShutdownDebtTests {
    @Test("declared vacant slots are quiescent in physical declaration order")
    func declaredVacantSlotsAreQuiescentInPhysicalDeclarationOrder() throws {
        let fixtures = try makeFixtures(count: 3)
        let declaredOrder = [
            fixtures[2].lease.binding.physicalSlotID,
            fixtures[0].lease.binding.physicalSlotID,
            fixtures[1].lease.binding.physicalSlotID,
        ]
        let transfer = try FilesystemObservationLeaseTransfer(
            physicalSlotIDs: declaredOrder,
            maximumContributionsPerLease: 3
        )

        let snapshot = transfer.semanticShutdownDebtSnapshot

        #expect(snapshot.isQuiescent)
        #expect(snapshot.slots.map(\.physicalSlotID) == declaredOrder)
        #expect(
            snapshot.slots.allSatisfy { slot in
                if case .vacant = slot { return true }
                return false
            })
    }

    @Test("presentation retains exact fingerprint and current UUIDv7 attempt before acceptance")
    func presentationRetainsExactFingerprintAndCurrentAttemptBeforeAcceptance() throws {
        let fixture = try makeFixture(registrationGeneration: 1101)
        var replay = try FilesystemObservationSemanticReplay(
            physicalSlotIDs: [fixture.lease.binding.physicalSlotID],
            maximumContributionsPerLease: 3
        )
        let attempt = requireBegan(replay.present(fixture.lease))

        let snapshot = replay.shutdownDebtSnapshot

        #expect(!snapshot.isQuiescent)
        guard case .retained(let retained) = try #require(snapshot.slots.first) else {
            Issue.record("Presented semantic lease must be retained")
            return
        }
        #expect(retained.fingerprint == attempt.fingerprint)
        #expect(retained.currentAttemptIdentity == attempt.identity)
        #expect(retained.currentAttemptIdentity.isUUIDv7)
        #expect(retained.acceptedPrefix.isEmpty)
    }

    @Test("shutdown debt retains the exact strict accepted prefix")
    func shutdownDebtRetainsExactStrictAcceptedPrefix() throws {
        let fixture = try makeFixture(registrationGeneration: 1102, contributionCount: 3)
        var replay = try FilesystemObservationSemanticReplay(
            physicalSlotIDs: [fixture.lease.binding.physicalSlotID],
            maximumContributionsPerLease: 3
        )
        let attempt = requireBegan(replay.present(fixture.lease))
        let identities = contributionIdentities(in: fixture.lease)
        #expect(
            replay.recordAccepted(
                .observationAccepted,
                for: identities[0],
                at: 0,
                attempt: attempt
            ) == .recorded(acceptedCount: 1, remainingCount: 2)
        )

        let snapshot = replay.shutdownDebtSnapshot

        guard case .retained(let retained) = try #require(snapshot.slots.first) else {
            Issue.record("Partially accepted semantic lease must remain retained")
            return
        }
        #expect(retained.acceptedPrefix == [.observationAccepted])
        #expect(retained.fingerprint.orderedContributionIdentities == identities)
    }

    @Test("physical slot order remains stable while independent slots change")
    func physicalSlotOrderRemainsStableWhileIndependentSlotsChange() throws {
        let fixtures = try makeFixtures(count: 3)
        let declaredOrder = [
            fixtures[1].lease.binding.physicalSlotID,
            fixtures[2].lease.binding.physicalSlotID,
            fixtures[0].lease.binding.physicalSlotID,
        ]
        var replay = try FilesystemObservationSemanticReplay(
            physicalSlotIDs: declaredOrder,
            maximumContributionsPerLease: 3
        )

        _ = requireBegan(replay.present(fixtures[0].lease))
        let afterFirstPresentation = replay.shutdownDebtSnapshot
        _ = requireBegan(replay.present(fixtures[2].lease))
        let afterSecondPresentation = replay.shutdownDebtSnapshot

        #expect(afterFirstPresentation.slots.map(\.physicalSlotID) == declaredOrder)
        #expect(afterSecondPresentation.slots.map(\.physicalSlotID) == declaredOrder)
    }

    @Test("exact transferred acknowledgement clears semantic shutdown debt")
    func exactTransferredAcknowledgementClearsSemanticShutdownDebt() throws {
        let fixture = try makeFixture(registrationGeneration: 1103, contributionCount: 2)
        var transfer = try FilesystemObservationLeaseTransfer(
            physicalSlotIDs: [fixture.lease.binding.physicalSlotID],
            maximumContributionsPerLease: 3
        )
        var sourceGate = FilesystemSourceGate(binding: fixture.lease.binding)
        var semanticSink = AcceptAllSemanticShutdownDebtSink()

        let result = transfer.transfer(
            fixture.lease,
            sourceGate: &sourceGate,
            recoveryContext: .notRequired,
            semanticSink: &semanticSink,
            consumerPort: fixture.mailbox.actorConsumerPort
        )

        guard case .transferred = result else {
            Issue.record("Exact whole-lease transfer should complete, got \(result)")
            return
        }
        #expect(transfer.semanticShutdownDebtSnapshot.isQuiescent)
        #expect(
            transfer.semanticShutdownDebtSnapshot.slots == [
                .vacant(fixture.lease.binding.physicalSlotID)
            ])
    }

    @Test("stale and foreign attempts cannot alter exact shutdown debt")
    func staleAndForeignAttemptsCannotAlterExactShutdownDebt() throws {
        let fixture = try makeFixture(registrationGeneration: 1104, contributionCount: 2)
        var replay = try FilesystemObservationSemanticReplay(
            physicalSlotIDs: [fixture.lease.binding.physicalSlotID],
            maximumContributionsPerLease: 3
        )
        let staleAttempt = requireBegan(replay.present(fixture.lease))
        let currentAttempt = requireResumed(replay.present(fixture.lease))
        let identities = contributionIdentities(in: fixture.lease)
        let beforeRejectedMutations = replay.shutdownDebtSnapshot

        #expect(
            replay.recordAccepted(
                .observationAccepted,
                for: identities[0],
                at: 0,
                attempt: staleAttempt
            ) == .staleConsumerAttempt
        )
        let foreignBinding = FilesystemObservationSlotBinding(
            fleetMailboxIdentity: fixture.lease.binding.fleetMailboxIdentity,
            physicalSlotID: fixture.lease.binding.physicalSlotID,
            identity: FilesystemObservationSlotBindingIdentity(value: UUIDv7.generate()),
            registration: fixture.lease.binding.registration,
            controlBlockIdentity: FilesystemObservationControlBlockIdentity(value: UUIDv7.generate())
        )
        let foreignLease = FilesystemObservationDrainLease(
            token: fixture.lease.token,
            binding: foreignBinding,
            payload: fixture.lease.payload
        )
        #expect(replay.present(foreignLease) == .contributionBindingMismatch)

        #expect(replay.shutdownDebtSnapshot == beforeRejectedMutations)
        guard case .retained(let retained) = try #require(replay.shutdownDebtSnapshot.slots.first) else {
            Issue.record("Current semantic attempt must remain retained")
            return
        }
        #expect(retained.currentAttemptIdentity == currentAttempt.identity)
    }

    private struct Fixture {
        let mailbox: FilesystemObservationMailbox
        let lease: FilesystemObservationDrainLease
    }

    private func makeFixtures(count: Int) throws -> [Fixture] {
        try (0..<count).map { ordinal in
            try makeFixture(registrationGeneration: UInt64(1200 + ordinal))
        }
    }

    private func makeFixture(
        registrationGeneration: UInt64,
        contributionCount: Int = 1
    ) throws -> Fixture {
        let registration = makeRegistration(registrationGeneration: registrationGeneration)
        let limits = GatherMailboxLimits(
            maximumDeclaredKeys: 1,
            maximumRetainedContributions: contributionCount,
            maximumRetainedItems: contributionCount,
            maximumRetainedBytes: 65_536,
            maximumRetainedContributionsPerKey: contributionCount,
            maximumRetainedItemsPerKey: contributionCount,
            maximumRetainedBytesPerKey: 65_536,
            maximumContributionsPerLease: contributionCount,
            maximumItemsPerLease: contributionCount,
            maximumBytesPerLease: 65_536,
            cleanupQuantum: .entriesAndBytes(
                maximumEntries: contributionCount,
                maximumBytes: 65_536
            )
        )
        let fixture = try makeFixedSlotMailboxFixture(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: registrationGeneration),
            registrations: [registration],
            limits: limits,
            captureLimits: makeCaptureLimits(),
            callbackQueueLabel: "test.filesystem-observation-semantic-shutdown-debt"
        )
        for ordinal in 0..<contributionCount {
            expectRetainedCallback(
                try fixture.admitCallback(
                    .authoritative(
                        makeObservation(
                            registration: registration,
                            path: "/semantic-shutdown-debt/\(ordinal)",
                            eventID: UInt64(ordinal + 1)
                        )
                    )
                )
            )
        }
        let consumerPort = fixture.mailbox.actorConsumerPort
        return Fixture(
            mailbox: fixture.mailbox,
            lease: requireLease(
                consumerPort.takeDrain(binding: consumerPort.bindConsumer().binding)
            )
        )
    }

    private func contributionIdentities(
        in lease: FilesystemObservationDrainLease
    ) -> [FilesystemObservationContributionIdentity] {
        switch lease.payload {
        case .contributions(let contributions),
            .contributionsWithRecovery(let contributions, _):
            return ([contributions.first] + contributions.remaining).map(\.identity)
        case .recovery:
            preconditionFailure("Semantic shutdown debt fixture must contain contributions")
        }
    }

    private func requireBegan(
        _ result: FilesystemObservationSemanticPresentationResult
    ) -> FilesystemObservationSemanticReplayAttempt {
        guard case .began(let attempt) = result else {
            preconditionFailure("Expected semantic attempt to begin, got \(result)")
        }
        return attempt
    }

    private func requireResumed(
        _ result: FilesystemObservationSemanticPresentationResult
    ) -> FilesystemObservationSemanticReplayAttempt {
        guard case .resumed(let attempt, _) = result else {
            preconditionFailure("Expected semantic attempt to resume, got \(result)")
        }
        return attempt
    }
}

private struct AcceptAllSemanticShutdownDebtSink: FilesystemObservationSemanticCustodySink {
    mutating func accept(
        _: FSEventObservation,
        identity _: FilesystemObservationContributionIdentity
    ) -> FilesystemObservationSemanticCustodyResult {
        .accepted
    }
}
