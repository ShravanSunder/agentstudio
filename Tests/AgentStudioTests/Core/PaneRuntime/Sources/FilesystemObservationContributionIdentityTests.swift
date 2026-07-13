import Foundation
import Testing
import os

@testable import AgentStudio

// Later-binding and recycle identity are F2-owned; this suite proves one current binding only.
@Suite("Filesystem observation contribution identity")
struct FilesystemObservationContributionIdentityTests {
    private let generation = AdmissionGeneration(owner: .filesystemObservation, value: 73)

    @Test("concurrent admission mints unique UUIDv7 identities in generic FIFO order")
    func concurrentAdmissionMintsUniqueIdentitiesInGenericFIFOOrder() async throws {
        // Arrange
        let contributionCount = 128
        let registration = makeRegistration(registrationGeneration: 73)
        let fixture = try makeFixedSlotMailboxFixture(
            generation: generation,
            registrations: [registration],
            limits: limits(contributionCount: contributionCount),
            captureLimits: makeCaptureLimits(),
            callbackQueueLabel: "test.filesystem-observation-contribution-identity"
        )
        guard
            let startingNativeLifetime =
                fixture.startingNativeLifetimesByRegistration[registration],
            case .created(let nativeGenerationPorts) = fixture.mailbox.nativeGenerationPorts(
                for: startingNativeLifetime
            )
        else {
            throw FixedSlotFilesystemObservationTestFailure.callbackPortUnavailable
        }
        let controlBlock = try makeControlBlock(
            startingNativeLifetime: startingNativeLifetime,
            captureLimits: fixture.captureLimits,
            callbackQueueLabel: fixture.callbackQueueLabel
        )
        let observations = try (0..<contributionCount).map { admissionOrdinal in
            try makeObservation(
                registration: registration,
                path: "/concurrent/\(admissionOrdinal)",
                eventID: UInt64(admissionOrdinal)
            )
        }
        let admissionOrdinalSource = GenericAdmissionOrdinalSource()
        let consumer = fixture.mailbox.actorConsumerPort
        let consumerBinding = consumer.bindConsumer().binding

        // Act
        let admissionResults = try await withThrowingTaskGroup(
            of: DarwinFSEventObservationCaptureResult.self,
            returning: [DarwinFSEventObservationCaptureResult].self
        ) { taskGroup in
            for _ in 0..<contributionCount {
                taskGroup.addTask {
                    guard case .acquired(let lease) = controlBlock.acquireCallbackLease() else {
                        throw FixedSlotFilesystemObservationTestFailure.callbackLeaseUnavailable
                    }
                    defer { _ = lease.release() }
                    return nativeGenerationPorts.callbackAdmissionPort.admit(
                        using: lease,
                        preflight: FilesystemObservationCallbackPreflight(
                            captureLimits: fixture.captureLimits
                        )
                    ) {
                        // Capture runs under the mailbox lock immediately before the generic offer.
                        // This ordinal is the admitted contribution order, not task scheduling order.
                        let admissionOrdinal = admissionOrdinalSource.takeNext()
                        return .offer(.authoritative(observations[admissionOrdinal]))
                    }
                }
            }

            var results: [DarwinFSEventObservationCaptureResult] = []
            for try await result in taskGroup {
                results.append(result)
            }
            return results
        }
        let lease = requireLease(consumer.takeDrain(binding: consumerBinding))
        let contributions = requireContributions(lease)

        // Assert
        #expect(admissionResults.count == contributionCount)
        for result in admissionResults {
            expectRetainedCallback(result)
        }
        #expect(admissionOrdinalSource.count == contributionCount)
        #expect(contributions.count == contributionCount)
        #expect(contributions.allSatisfy { $0.identity.binding == fixture.binding })
        #expect(contributions.allSatisfy { $0.identity.isUUIDv7 })
        #expect(Set(contributions.map(\.identity)).count == contributionCount)
        #expect(
            contributions.map(requiredSingleEventID)
                == (0..<contributionCount).map(UInt64.init)
        )
        #expect(
            consumer.acknowledge(
                token: lease.token,
                disposition: .transferredAuthoritative
            ) == .transferredAuthoritative(wake: .noWake)
        )
    }

    private func limits(contributionCount: Int) -> GatherMailboxLimits {
        GatherMailboxLimits(
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
    }

    private func requireContributions(
        _ lease: FilesystemObservationDrainLease,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> [FilesystemObservationMailboxContribution] {
        guard case .contributions(let contributions) = lease.payload else {
            Issue.record(
                "Expected contribution-only filesystem observation lease",
                sourceLocation: sourceLocation
            )
            return []
        }
        return [contributions.first] + contributions.remaining
    }

    private func requiredSingleEventID(
        _ contribution: FilesystemObservationMailboxContribution
    ) -> UInt64 {
        guard contribution.observation.records.count == 1,
            let eventID = contribution.observation.records.first?.eventID
        else {
            preconditionFailure("Expected one event record per contribution")
        }
        return eventID
    }
}

private final class GenericAdmissionOrdinalSource: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    var count: Int {
        lock.withLock { $0 }
    }

    func takeNext() -> Int {
        lock.withLock { nextOrdinal in
            defer { nextOrdinal += 1 }
            return nextOrdinal
        }
    }
}
