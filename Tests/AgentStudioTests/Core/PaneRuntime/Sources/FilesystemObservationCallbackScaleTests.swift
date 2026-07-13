import Foundation
import Testing
import os

@testable import AgentStudio

@Suite("Filesystem observation callback scale")
struct FilesystemObservationCallbackScaleTests {
    private let generation = AdmissionGeneration(owner: .filesystemObservation, value: 74)
    private let configuredSourceBound = 300

    @Test("one callback has the same operation shape across bound-slot scale")
    func callbackOutcomeIsIndependentOfBoundSlotCount() throws {
        // Arrange / Act
        let outcomes = try [1, 100, configuredSourceBound].map(runOneCallback)

        // Assert
        #expect(outcomes.map(\.boundSlotCount) == [1, 100, configuredSourceBound])
        #expect(outcomes.allSatisfy { $0.disposition == .retained })
        #expect(outcomes.allSatisfy { $0.wake == .applied })
        #expect(outcomes.allSatisfy { $0.selectedSlotRecoveryState == .clear($0.selectedBinding) })
        #expect(outcomes.allSatisfy { $0.drainedContributionCount == 1 })
        #expect(outcomes.allSatisfy { $0.acknowledgement == .transferredAuthoritative(wake: .noWake) })
        #expect(Set(outcomes.map(\.operationVector)).count == 1)
        #expect(outcomes.allSatisfy { $0.operationVector == .oneRetainedCallback })
    }

    @Test("configured source bound defers bound plus one without changing an active callback")
    func configuredBoundPlusOneDefersAtActiveSourceCapacity() throws {
        // Arrange
        let registrations = (1...(configuredSourceBound + 1)).map(makeRegistration)
        let mailbox = try FilesystemObservationMailbox(
            generation: generation,
            maximumSimultaneousSourceCount: configuredSourceBound,
            replacementReserveSlotCount: 0,
            limits: limits(boundSlotCount: configuredSourceBound)
        )
        for registration in registrations {
            guard case .enqueued = mailbox.recordDesiredRegistration(registration) else {
                throw FixedSlotFilesystemObservationTestFailure.fixtureConstructionFailed
            }
        }
        var startingNativeLifetimesByRegistration:
            [FSEventRegistrationToken: FilesystemObservationStartingNativeLifetime] = [:]
        for _ in 0..<configuredSourceBound {
            guard case .selected(let selection) = mailbox.selectNextDesiredSource(),
                case .committed(let startingNativeLifetime) =
                    mailbox.beginNativeLifetime(selection.reservation)
            else {
                throw FixedSlotFilesystemObservationTestFailure.fixtureConstructionFailed
            }
            startingNativeLifetimesByRegistration[startingNativeLifetime.binding.registration] =
                startingNativeLifetime
        }
        let selectedRegistration = try #require(registrations.dropLast().last)
        let fixture = FixedSlotFilesystemObservationMailboxFixture(
            mailbox: mailbox,
            startingNativeLifetimesByRegistration: startingNativeLifetimesByRegistration,
            captureLimits: try makeCaptureLimits(),
            callbackQueueLabel: "test.filesystem-observation.callback-scale.bound-plus-one"
        )

        // Act
        let capacityResult = mailbox.selectNextDesiredSource()
        let callbackOutcome = try runOneCallback(
            fixture: fixture,
            selectedRegistration: selectedRegistration
        )

        // Assert
        #expect(startingNativeLifetimesByRegistration.count == configuredSourceBound)
        #expect(capacityResult == .deferredBehindActiveSourceCapacity)
        #expect(callbackOutcome.boundSlotCount == configuredSourceBound)
        #expect(callbackOutcome.disposition == .retained)
        #expect(callbackOutcome.operationVector == .oneRetainedCallback)
        #expect(callbackOutcome.drainedContributionCount == 1)
        #expect(callbackOutcome.acknowledgement == .transferredAuthoritative(wake: .noWake))
    }

    private func runOneCallback(
        boundSlotCount: Int
    ) throws -> CallbackScaleOutcome {
        let registrations = (1...boundSlotCount).map(makeRegistration)
        let selectedRegistration = try #require(registrations.last)
        let fixture = try makeFixedSlotMailboxFixture(
            generation: generation,
            registrations: registrations,
            limits: limits(boundSlotCount: boundSlotCount),
            captureLimits: makeCaptureLimits(),
            callbackQueueLabel: "test.filesystem-observation.callback-scale.\(boundSlotCount)"
        )
        return try runOneCallback(
            fixture: fixture,
            selectedRegistration: selectedRegistration
        )
    }

    private func runOneCallback(
        fixture: FixedSlotFilesystemObservationMailboxFixture,
        selectedRegistration: FSEventRegistrationToken
    ) throws -> CallbackScaleOutcome {
        let selectedStartingNativeLifetime = try #require(
            fixture.startingNativeLifetimesByRegistration[selectedRegistration]
        )
        let synchronization = CallbackOperationRecorder()
        guard
            case .created(let nativeGenerationPorts) = fixture.mailbox.nativeGenerationPorts(
                for: selectedStartingNativeLifetime,
                synchronization: synchronization
            )
        else {
            throw FixedSlotFilesystemObservationTestFailure.callbackPortUnavailable
        }
        let controlBlock = try makeControlBlock(
            startingNativeLifetime: selectedStartingNativeLifetime,
            captureLimits: fixture.captureLimits,
            callbackQueueLabel: fixture.callbackQueueLabel
        )
        guard case .acquired(let lease) = controlBlock.acquireCallbackLease() else {
            throw FixedSlotFilesystemObservationTestFailure.callbackLeaseUnavailable
        }
        defer { _ = lease.release() }
        let selectedBinding = selectedStartingNativeLifetime.binding
        let observation = try makeObservation(
            registration: selectedRegistration,
            path: "/callback-scale/selected",
            eventID: 1
        )

        let result = nativeGenerationPorts.callbackAdmissionPort.admit(
            using: lease,
            preflight: FilesystemObservationCallbackPreflight(
                captureLimits: fixture.captureLimits
            )
        ) {
            synchronization.recordCaptureInvocation()
            return .offer(.authoritative(observation))
        }
        let disposition = requireCallbackDisposition(result)
        let wake = requireCallbackWake(result)
        let consumer = fixture.mailbox.actorConsumerPort
        let consumerBinding = consumer.bindConsumer().binding
        let drainedLease = try requireSingleContributionLease(
            consumer.takeDrain(binding: consumerBinding)
        )
        let acknowledgement = consumer.acknowledge(
            token: drainedLease.token,
            disposition: .transferredAuthoritative
        )
        let selectedSlotRecoveryState = fixture.mailbox.lifecyclePort.diagnostics.recoveryEvidence(
            for: selectedBinding.physicalSlotID
        )

        return CallbackScaleOutcome(
            boundSlotCount: fixture.startingNativeLifetimesByRegistration.count,
            selectedBinding: selectedBinding,
            disposition: disposition,
            wake: wake,
            selectedSlotRecoveryState: selectedSlotRecoveryState,
            drainedContributionCount: drainedLease.contributionCount,
            acknowledgement: acknowledgement,
            operationVector: synchronization.operationVector(wake: wake)
        )
    }

    private func requireSingleContributionLease(
        _ result: FilesystemObservationTakeDrainResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> (token: AdmissionDrainToken, contributionCount: Int) {
        guard case .lease(let lease) = result else {
            Issue.record("Expected one filesystem observation drain lease", sourceLocation: sourceLocation)
            throw FixedSlotFilesystemObservationTestFailure.fixtureConstructionFailed
        }
        guard case .contributions(let contributions) = lease.payload else {
            Issue.record("Expected an authoritative contribution-only lease", sourceLocation: sourceLocation)
            throw FixedSlotFilesystemObservationTestFailure.fixtureConstructionFailed
        }
        return (lease.token, 1 + contributions.remaining.count)
    }

    private func makeRegistration(index: Int) -> FSEventRegistrationToken {
        let rootIDSuffix = String(format: "%012d", index)
        return FSEventRegistrationToken(
            sourceID: FilesystemSourceID(
                kind: .registeredWorktreeContent,
                rootID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-\(rootIDSuffix)")!
            ),
            registrationGeneration: UInt64(index),
            rootGeneration: 1
        )
    }

    private func limits(boundSlotCount: Int) -> GatherMailboxLimits {
        GatherMailboxLimits(
            maximumDeclaredKeys: boundSlotCount,
            maximumRetainedContributions: 1,
            maximumRetainedItems: 1,
            maximumRetainedBytes: 4096,
            maximumRetainedContributionsPerKey: 1,
            maximumRetainedItemsPerKey: 1,
            maximumRetainedBytesPerKey: 4096,
            maximumContributionsPerLease: 1,
            maximumItemsPerLease: 1,
            maximumBytesPerLease: 4096,
            cleanupQuantum: .entriesAndBytes(maximumEntries: 1, maximumBytes: 4096)
        )
    }
}

private struct CallbackScaleOutcome {
    let boundSlotCount: Int
    let selectedBinding: FilesystemObservationSlotBinding
    let disposition: FilesystemObservationOfferDisposition
    let wake: FilesystemObservationCallbackWakeApplication
    let selectedSlotRecoveryState: FixedFilesystemRecoveryEvidenceSnapshotResult
    let drainedContributionCount: Int
    let acknowledgement: FilesystemObservationDrainAcknowledgement
    let operationVector: IndependentCallbackOperationVector
}

private struct IndependentCallbackOperationVector: Hashable, Sendable {
    let authorityConsumedSynchronizationCount: Int
    let captureInvocationCount: Int
    let mailboxOfferCompletedSynchronizationCount: Int
    let wake: FilesystemObservationCallbackWakeApplication

    static let oneRetainedCallback = Self(
        authorityConsumedSynchronizationCount: 1,
        captureInvocationCount: 1,
        mailboxOfferCompletedSynchronizationCount: 1,
        wake: .applied
    )
}

private final class CallbackOperationRecorder:
    @unchecked Sendable, FilesystemObservationCallbackSynchronization
{
    private struct State: Sendable {
        var authorityConsumedSynchronizationCount = 0
        var captureInvocationCount = 0
        var mailboxOfferCompletedSynchronizationCount = 0
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func afterAuthorityConsumedBeforeMailboxOffer() {
        lock.withLock { $0.authorityConsumedSynchronizationCount += 1 }
    }

    func recordCaptureInvocation() {
        lock.withLock { $0.captureInvocationCount += 1 }
    }

    func afterMailboxOfferBeforeWakeApplication() {
        lock.withLock { $0.mailboxOfferCompletedSynchronizationCount += 1 }
    }

    func operationVector(
        wake: FilesystemObservationCallbackWakeApplication
    ) -> IndependentCallbackOperationVector {
        let snapshot = lock.withLock { $0 }
        return IndependentCallbackOperationVector(
            authorityConsumedSynchronizationCount: snapshot.authorityConsumedSynchronizationCount,
            captureInvocationCount: snapshot.captureInvocationCount,
            mailboxOfferCompletedSynchronizationCount:
                snapshot.mailboxOfferCompletedSynchronizationCount,
            wake: wake
        )
    }
}
