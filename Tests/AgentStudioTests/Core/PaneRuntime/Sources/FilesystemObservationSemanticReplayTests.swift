import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation semantic replay")
struct FilesystemObservationSemanticReplayTests {
    @Test("strict accepted prefix survives retry presentation without duplicate semantic effects")
    func strictAcceptedPrefixSurvivesRetryPresentation() throws {
        for contributionCount in 1...4 {
            for acceptedPrefixCount in 0..<contributionCount {
                let leaseFixture = try makeLeaseFixture(
                    contributionCount: contributionCount,
                    registrationGeneration: UInt64(100 + contributionCount * 10 + acceptedPrefixCount)
                )
                let lease = leaseFixture.lease
                var replay = try FilesystemObservationSemanticReplay(
                    physicalSlotIDs: [lease.binding.physicalSlotID],
                    maximumContributionsPerLease: 4
                )
                let firstAttempt = requireBegan(replay.present(lease))
                #expect(firstAttempt.identity.isUUIDv7)
                let identities = contributionIdentities(in: lease)
                var semanticApplicationCountByIdentity: [FilesystemObservationContributionIdentity: Int] = [:]

                for index in 0..<acceptedPrefixCount {
                    #expect(
                        replay.decision(
                            for: identities[index],
                            at: index,
                            attempt: firstAttempt
                        ) == .requiresAcceptance(index: index, identity: identities[index])
                    )
                    #expect(
                        replay.recordAccepted(
                            .observationAccepted,
                            for: identities[index],
                            at: index,
                            attempt: firstAttempt
                        ) == .recorded(acceptedCount: index + 1, remainingCount: contributionCount - index - 1)
                    )
                    semanticApplicationCountByIdentity[identities[index], default: 0] += 1
                }

                guard
                    case .retried = leaseFixture.mailbox.actorConsumerPort.acknowledge(
                        token: lease.token,
                        disposition: .retry
                    )
                else {
                    Issue.record("Generic retry should retain the exact immutable lease")
                    continue
                }
                let reboundConsumer = leaseFixture.mailbox.actorConsumerPort.bindConsumer().binding
                let retriedLease = requireLease(
                    leaseFixture.mailbox.actorConsumerPort.takeDrain(binding: reboundConsumer)
                )
                #expect(retriedLease.token != lease.token)
                let resumed = requireResumed(replay.present(retriedLease))
                #expect(resumed.attempt.identity.isUUIDv7)
                #expect(resumed.acceptedPrefix.count == acceptedPrefixCount)
                #expect(resumed.attempt.identity != firstAttempt.identity)

                for index in identities.indices {
                    switch replay.decision(
                        for: identities[index],
                        at: index,
                        attempt: resumed.attempt
                    ) {
                    case .alreadyAccepted(let disposition, let acceptedIndex, let identity):
                        #expect(index < acceptedPrefixCount)
                        #expect(disposition == .observationAccepted)
                        #expect(acceptedIndex == index)
                        #expect(identity == identities[index])
                    case .requiresAcceptance(let requiredIndex, let identity):
                        #expect(index >= acceptedPrefixCount)
                        #expect(requiredIndex == index)
                        #expect(identity == identities[index])
                        #expect(
                            replay.recordAccepted(
                                .observationAccepted,
                                for: identity,
                                at: index,
                                attempt: resumed.attempt
                            )
                                == .recorded(
                                    acceptedCount: index + 1,
                                    remainingCount: contributionCount - index - 1
                                )
                        )
                        semanticApplicationCountByIdentity[identity, default: 0] += 1
                    case .outOfOrder:
                        Issue.record("Replay exposed a sparse semantic prefix")
                    case .identityOrIndexMismatch, .staleConsumerAttempt, .fingerprintMismatch,
                        .undeclaredPhysicalSlot:
                        Issue.record("Replay rejected its current exact lease")
                    }
                }

                let completion = requireSemanticCompletion(
                    replay.semanticCompletion(for: resumed.attempt)
                )
                #expect(completion.attemptIdentity == resumed.attempt.identity)
                #expect(semanticApplicationCountByIdentity.count == contributionCount)
                #expect(semanticApplicationCountByIdentity.values.allSatisfy { $0 == 1 })
                #expect(replay.diagnostics.retainedIdentityCount == contributionCount)
            }
        }
    }

    @Test("partial retries remain slot-local across consumer rebind and rotated resume")
    func partialRetriesRemainSlotLocalAcrossConsumerRebind() throws {
        let fixtures = try (0..<3).map { ordinal in
            try makeLeaseFixture(
                contributionCount: 4,
                registrationGeneration: UInt64(600 + ordinal)
            )
        }
        var replay = try FilesystemObservationSemanticReplay(
            physicalSlotIDs: fixtures.map(\.lease.binding.physicalSlotID),
            maximumContributionsPerLease: 4
        )
        var semanticApplicationCountByIdentity: [FilesystemObservationContributionIdentity: Int] = [:]

        for (slotIndex, fixture) in fixtures.enumerated() {
            let attempt = requireBegan(replay.present(fixture.lease))
            #expect(attempt.identity.isUUIDv7)
            let identities = contributionIdentities(in: fixture.lease)
            let acceptedPrefixCount = slotIndex + 1
            for contributionIndex in 0..<acceptedPrefixCount {
                #expect(
                    replay.recordAccepted(
                        .observationAccepted,
                        for: identities[contributionIndex],
                        at: contributionIndex,
                        attempt: attempt
                    )
                        == .recorded(
                            acceptedCount: contributionIndex + 1,
                            remainingCount: identities.count - contributionIndex - 1
                        )
                )
                semanticApplicationCountByIdentity[identities[contributionIndex], default: 0] += 1
            }
            guard
                case .retried = fixture.mailbox.actorConsumerPort.acknowledge(
                    token: fixture.lease.token,
                    disposition: .retry
                )
            else {
                Issue.record("Generic retry should retain every slot-local lease")
                return
            }
        }

        for slotIndex in [2, 0, 1] {
            let fixture = fixtures[slotIndex]
            let reboundConsumer = fixture.mailbox.actorConsumerPort.bindConsumer().binding
            let retriedLease = requireLease(
                fixture.mailbox.actorConsumerPort.takeDrain(binding: reboundConsumer)
            )
            #expect(retriedLease.token != fixture.lease.token)
            let resumed = requireResumed(replay.present(retriedLease))
            #expect(resumed.attempt.identity.isUUIDv7)
            #expect(resumed.acceptedPrefix.count == slotIndex + 1)
            let identities = contributionIdentities(in: retriedLease)

            for contributionIndex in identities.indices {
                switch replay.decision(
                    for: identities[contributionIndex],
                    at: contributionIndex,
                    attempt: resumed.attempt
                ) {
                case .alreadyAccepted:
                    #expect(contributionIndex < slotIndex + 1)
                case .requiresAcceptance:
                    #expect(contributionIndex >= slotIndex + 1)
                    #expect(
                        replay.recordAccepted(
                            .observationAccepted,
                            for: identities[contributionIndex],
                            at: contributionIndex,
                            attempt: resumed.attempt
                        )
                            == .recorded(
                                acceptedCount: contributionIndex + 1,
                                remainingCount: identities.count - contributionIndex - 1
                            )
                    )
                    semanticApplicationCountByIdentity[identities[contributionIndex], default: 0] += 1
                case .outOfOrder, .identityOrIndexMismatch, .staleConsumerAttempt,
                    .fingerprintMismatch, .undeclaredPhysicalSlot:
                    Issue.record("Rotated resume lost exact slot-local replay state")
                }
            }
            _ = requireSemanticCompletion(replay.semanticCompletion(for: resumed.attempt))
        }

        #expect(semanticApplicationCountByIdentity.count == 12)
        #expect(semanticApplicationCountByIdentity.values.allSatisfy { $0 == 1 })
        #expect(replay.diagnostics.retainedIdentityCount == 12)
        #expect(replay.diagnostics.retainedIdentityHighWater == 12)
        #expect(replay.diagnostics.maximumRetainedIdentityCapacity == 12)
    }

    @Test("stale attempts and mismatched vectors cannot mutate retained replay")
    func staleAttemptsAndMismatchedVectorsCannotMutateReplay() throws {
        let lease = try makeLease(contributionCount: 3, registrationGeneration: 201)
        var replay = try FilesystemObservationSemanticReplay(
            physicalSlotIDs: [lease.binding.physicalSlotID],
            maximumContributionsPerLease: 4
        )
        let firstAttempt = requireBegan(replay.present(lease))
        let identities = contributionIdentities(in: lease)
        #expect(
            replay.recordAccepted(
                .observationAccepted,
                for: identities[0],
                at: 0,
                attempt: firstAttempt
            ) == .recorded(acceptedCount: 1, remainingCount: 2)
        )
        let resumed = requireResumed(replay.present(lease))

        #expect(
            replay.recordAccepted(
                .observationAccepted,
                for: identities[1],
                at: 1,
                attempt: firstAttempt
            ) == .staleConsumerAttempt
        )
        #expect(replay.semanticCompletion(for: firstAttempt) == .staleConsumerAttempt)

        let reorderedLease = leaseReplacingContributions(
            in: lease,
            with: [identities[1], identities[0], identities[2]]
        )
        guard case .bindingOrIdentityVectorMismatch = replay.present(reorderedLease) else {
            Issue.record("Reordered identity vector should be rejected")
            return
        }
        let shortenedLease = leaseReplacingContributions(in: lease, with: [identities[0], identities[1]])
        guard case .bindingOrIdentityVectorMismatch = replay.present(shortenedLease) else {
            Issue.record("Shortened identity vector should be rejected")
            return
        }
        let extendedLease = leaseReplacingContributions(
            in: lease,
            with: identities + [identities[0]]
        )
        guard case .bindingOrIdentityVectorMismatch = replay.present(extendedLease) else {
            Issue.record("Extended identity vector should be rejected")
            return
        }
        let foreignBinding = FilesystemObservationSlotBinding(
            fleetMailboxIdentity: lease.binding.fleetMailboxIdentity,
            physicalSlotID: lease.binding.physicalSlotID,
            identity: FilesystemObservationSlotBindingIdentity(value: UUIDv7.generate()),
            registration: lease.binding.registration,
            controlBlockIdentity: FilesystemObservationControlBlockIdentity(value: UUIDv7.generate())
        )
        let foreignBindingLease = FilesystemObservationDrainLease(
            token: lease.token,
            binding: foreignBinding,
            payload: lease.payload
        )
        #expect(replay.present(foreignBindingLease) == .contributionBindingMismatch)
        #expect(replay.diagnostics.retainedIdentityCount == 3)
        #expect(
            replay.decision(
                for: identities[1],
                at: 1,
                attempt: resumed.attempt
            ) == .requiresAcceptance(index: 1, identity: identities[1])
        )
    }

    @Test("fixed slot capacity is bounded and failures are isolated by slot")
    func fixedSlotCapacityIsBoundedAndFailuresAreIsolated() throws {
        let leases = try (0..<3).map { ordinal in
            try makeLease(contributionCount: 4, registrationGeneration: UInt64(300 + ordinal))
        }
        var replay = try FilesystemObservationSemanticReplay(
            physicalSlotIDs: leases.map(\.binding.physicalSlotID),
            maximumContributionsPerLease: 4
        )

        for lease in leases {
            _ = requireBegan(replay.present(lease))
        }
        #expect(replay.diagnostics.retainedIdentityCount == 12)
        #expect(replay.diagnostics.retainedIdentityHighWater == 12)
        #expect(replay.diagnostics.maximumRetainedIdentityCapacity == 12)

        let firstIdentities = contributionIdentities(in: leases[0])
        let oversizedLease = leaseReplacingContributions(
            in: leases[0],
            with: firstIdentities + [firstIdentities[0]]
        )
        #expect(replay.present(oversizedLease) == .leaseTooLarge(maximum: 4, presented: 5))

        let undeclaredLease = try makeLease(contributionCount: 1, registrationGeneration: 400)
        #expect(replay.present(undeclaredLease) == .undeclaredPhysicalSlot)
        #expect(replay.diagnostics.retainedIdentityCount == 12)
        #expect(replay.diagnostics.retainedIdentityHighWater == 12)
    }

    @Test("semantic completion remains retained for H2 exact whole lease transfer")
    func semanticCompletionRemainsRetainedForH2Transfer() throws {
        let lease = try makeLease(contributionCount: 2, registrationGeneration: 501)
        var replay = try FilesystemObservationSemanticReplay(
            physicalSlotIDs: [lease.binding.physicalSlotID],
            maximumContributionsPerLease: 2
        )
        let attempt = requireBegan(replay.present(lease))
        let identities = contributionIdentities(in: lease)

        for index in identities.indices {
            _ = replay.recordAccepted(
                .observationAccepted,
                for: identities[index],
                at: index,
                attempt: attempt
            )
        }
        _ = requireSemanticCompletion(replay.semanticCompletion(for: attempt))

        #expect(replay.diagnostics.retainedLeaseCount == 1)
        #expect(replay.diagnostics.retainedIdentityCount == 2)
        let resumed = requireResumed(replay.present(lease))
        #expect(resumed.acceptedPrefix == [.observationAccepted, .observationAccepted])
        #expect(replay.diagnostics.retainedLeaseCount == 1)
    }

    private func makeLease(
        contributionCount: Int,
        registrationGeneration: UInt64
    ) throws -> FilesystemObservationDrainLease {
        try makeLeaseFixture(
            contributionCount: contributionCount,
            registrationGeneration: registrationGeneration
        ).lease
    }

    private struct SemanticLeaseFixture {
        let mailbox: FilesystemObservationMailbox
        let lease: FilesystemObservationDrainLease
    }

    private func makeLeaseFixture(
        contributionCount: Int,
        registrationGeneration: UInt64
    ) throws -> SemanticLeaseFixture {
        let registration = makeRegistration(registrationGeneration: registrationGeneration)
        let limits = GatherMailboxLimits(
            maximumDeclaredKeys: 1,
            maximumRetainedContributions: max(contributionCount, 1),
            maximumRetainedItems: max(contributionCount, 1),
            maximumRetainedBytes: 65_536,
            maximumRetainedContributionsPerKey: max(contributionCount, 1),
            maximumRetainedItemsPerKey: max(contributionCount, 1),
            maximumRetainedBytesPerKey: 65_536,
            maximumContributionsPerLease: max(contributionCount, 1),
            maximumItemsPerLease: max(contributionCount, 1),
            maximumBytesPerLease: 65_536,
            cleanupQuantum: .entriesAndBytes(maximumEntries: max(contributionCount, 1), maximumBytes: 65_536)
        )
        let fixture = try makeFixedSlotMailboxFixture(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: registrationGeneration),
            registrations: [registration],
            limits: limits,
            captureLimits: makeCaptureLimits(),
            callbackQueueLabel: "test.filesystem-observation-semantic-replay"
        )
        for ordinal in 0..<contributionCount {
            expectRetainedCallback(
                try fixture.admitCallback(
                    .authoritative(
                        makeObservation(
                            registration: registration,
                            path: "/semantic-replay/\(ordinal)",
                            eventID: UInt64(ordinal + 1)
                        )
                    )
                )
            )
        }
        let consumer = fixture.mailbox.actorConsumerPort
        return SemanticLeaseFixture(
            mailbox: fixture.mailbox,
            lease: requireLease(consumer.takeDrain(binding: consumer.bindConsumer().binding))
        )
    }

    private func contributionIdentities(
        in lease: FilesystemObservationDrainLease
    ) -> [FilesystemObservationContributionIdentity] {
        contributionBatch(in: lease).map(\.identity)
    }

    private func contributionBatch(
        in lease: FilesystemObservationDrainLease
    ) -> [FilesystemObservationMailboxContribution] {
        switch lease.payload {
        case .contributions(let contributions),
            .contributionsWithRecovery(let contributions, _):
            [contributions.first] + contributions.remaining
        case .recovery:
            preconditionFailure("Semantic replay test requires contribution-bearing lease")
        }
    }

    private func leaseReplacingContributions(
        in lease: FilesystemObservationDrainLease,
        with identities: [FilesystemObservationContributionIdentity]
    ) -> FilesystemObservationDrainLease {
        let originalByIdentity = Dictionary(
            uniqueKeysWithValues: contributionBatch(in: lease).map { ($0.identity, $0) }
        )
        let contributions = identities.map { identity in
            guard let contribution = originalByIdentity[identity] else {
                preconditionFailure("Replacement identity must come from the original lease")
            }
            return contribution
        }
        guard let first = contributions.first else {
            preconditionFailure("Semantic lease must remain nonempty")
        }
        return FilesystemObservationDrainLease(
            token: lease.token,
            binding: lease.binding,
            payload: .contributions(
                NonEmptyAdmissionBatch(first: first, remaining: Array(contributions.dropFirst()))
            )
        )
    }

    private func requireBegan(
        _ result: FilesystemObservationSemanticPresentationResult
    ) -> FilesystemObservationSemanticReplayAttempt {
        guard case .began(let attempt) = result else {
            preconditionFailure("Expected a new semantic replay attempt, got \(result)")
        }
        return attempt
    }

    private func requireResumed(
        _ result: FilesystemObservationSemanticPresentationResult
    ) -> (
        attempt: FilesystemObservationSemanticReplayAttempt,
        acceptedPrefix: [FilesystemObservationSemanticAcceptedDisposition]
    ) {
        guard case .resumed(let attempt, let acceptedPrefix) = result else {
            preconditionFailure("Expected a resumed semantic replay attempt, got \(result)")
        }
        return (attempt, acceptedPrefix)
    }

    private func requireSemanticCompletion(
        _ result: FilesystemObservationSemanticCompletionResult
    ) -> FilesystemSemanticLeaseAcceptanceAuthority {
        guard case .wholeLeaseSemanticallyAccepted(let authority) = result else {
            preconditionFailure("Expected semantic completion, got \(result)")
        }
        return authority
    }
}
