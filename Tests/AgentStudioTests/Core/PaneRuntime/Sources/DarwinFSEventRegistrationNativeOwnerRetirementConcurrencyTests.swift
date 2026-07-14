import Dispatch
import Testing
import os

@testable import AgentStudio

private let d3ConcurrencyProofTimeout: DispatchTimeInterval = .seconds(30)

@Suite("Darwin FSEvent native owner retirement concurrency")
struct DarwinNativeOwnerRetirementConcurrencyTests {
    @Test("concurrent finalization releases retained callback context exactly once")
    func concurrentFinalizationReleasesRetainedContextExactlyOnce() async throws {
        // Arrange
        let fixture = try makeD3NativeOwnerRetirementFixture(generationValue: 907)
        let permit = try await prepareRetainedContextPermit(fixture)
        let blockingFinalizer = D3BlockingNativeContextFinalizer()
        let secondInvocation = D3BoundedConcurrencySignal()

        // Act
        // A detached task is intentional: the fake finalizer blocks one thread so a second
        // independent executor job can prove the release-once serialization boundary.
        // swiftlint:disable:next no_task_detached
        let firstTask = Task.detached {
            fixture.nativeOwner.finalizeNativeLifetime(
                using: permit,
                contextFinalizer: blockingFinalizer
            )
        }
        guard blockingFinalizer.waitUntilReleaseEntered() else {
            blockingFinalizer.allowReleaseToComplete()
            _ = await firstTask.value
            Issue.record("first finalization did not enter retained-pointer release")
            return
        }
        // See the detached-task justification above; inheriting one actor would not test overlap.
        // swiftlint:disable:next no_task_detached
        let secondTask = Task.detached {
            secondInvocation.signal()
            return fixture.nativeOwner.finalizeNativeLifetime(
                using: permit,
                contextFinalizer: blockingFinalizer
            )
        }
        guard secondInvocation.wait() else {
            blockingFinalizer.allowReleaseToComplete()
            _ = await firstTask.value
            _ = await secondTask.value
            Issue.record("second finalization did not reach the concurrent invocation boundary")
            return
        }
        blockingFinalizer.allowReleaseToComplete()
        let results = await [firstTask.value, secondTask.value]

        // Assert
        var finalizedAcknowledgements: [FilesystemObservationContextReleaseAcknowledgement] = []
        var replayedAcknowledgements: [FilesystemObservationContextReleaseAcknowledgement] = []
        for result in results {
            switch result {
            case .finalized(let acknowledgement):
                finalizedAcknowledgements.append(acknowledgement)
            case .alreadyFinalized(let acknowledgement):
                replayedAcknowledgements.append(acknowledgement)
            case .rejected(let rejection):
                Issue.record("concurrent exact permit was rejected: \(rejection)")
            }
        }
        #expect(blockingFinalizer.retainedPointerReleaseCount == 1)
        #expect(!blockingFinalizer.didTimeOutWaitingForReleasePermission)
        #expect(finalizedAcknowledgements.count == 1)
        #expect(replayedAcknowledgements.count == 1)
        #expect(finalizedAcknowledgements.first == replayedAcknowledgements.first)
    }

    private func prepareRetainedContextPermit(
        _ fixture: D3NativeOwnerRetirementFixture
    ) async throws -> FilesystemObservationNativeRetirementPermit {
        let creationResult = fixture.nativeOwner.createOrReplay(
            controlBlock: fixture.controlBlock,
            adapter: fixture.adapter,
            nativeDriver: fixture.nativeDriver,
            callbackQueueBarrier: fixture.callbackQueueBarrier
        )
        guard case .created(let generation) = creationResult else {
            throw D3NativeOwnerRetirementConcurrencyFailure.expectedCreatedGeneration
        }
        let startResult = await fixture.nativeOwner.abandonStartAfterCreate(
            creation: generation
        )
        guard case .unpublished(.createdNeverStartedClosed(let quiescence)) = startResult else {
            throw D3NativeOwnerRetirementConcurrencyFailure.expectedRetainedContextQuiescence
        }
        let retirementResult =
            fixture.mailbox.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                fixture.startingNativeLifetime
            )
        guard case .retirementRequired(let retiringLifetime) = retirementResult else {
            throw D3NativeOwnerRetirementConcurrencyFailure.expectedRetiringLifetime
        }
        let finalReceiptResult = fixture.mailbox.lifecyclePort
            .finalizeUnpublishedNativeGeneration(
                retiringLifetime,
                completion: .createdNeverStartedClosed(quiescence)
            )
        guard case .finalized(let finalReceipt) = finalReceiptResult else {
            throw D3NativeOwnerRetirementConcurrencyFailure.expectedUnpublishedFinalReceipt
        }
        let permit = FilesystemObservationNativeRetirementPermit.unpublished(finalReceipt)
        #expect(fixture.nativeOwner.retainRetirementPermit(permit) == .alreadyRetained)
        return permit
    }
}

private final class D3BoundedConcurrencySignal: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    func signal() {
        semaphore.signal()
    }

    func wait() -> Bool {
        semaphore.wait(timeout: .now() + d3ConcurrencyProofTimeout) == .success
    }
}

private enum D3NativeOwnerRetirementConcurrencyFailure: Error {
    case expectedCreatedGeneration
    case expectedRetainedContextQuiescence
    case expectedRetiringLifetime
    case expectedUnpublishedFinalReceipt
}

private final class D3BlockingNativeContextFinalizer:
    DarwinFSEventCallbackContextFinalizer,
    @unchecked Sendable
{
    private struct State: Sendable {
        var retainedPointerAddresses: [UInt] = []
        var didTimeOutWaitingForReleasePermission = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let releaseEntered = DispatchSemaphore(value: 0)
    private let releasePermission = DispatchSemaphore(value: 0)

    var retainedPointerReleaseCount: Int {
        state.withLock { $0.retainedPointerAddresses.count }
    }

    var didTimeOutWaitingForReleasePermission: Bool {
        state.withLock { $0.didTimeOutWaitingForReleasePermission }
    }

    func releaseRetainedContext(at pointerAddress: UInt) {
        state.withLock { $0.retainedPointerAddresses.append(pointerAddress) }
        releaseEntered.signal()
        guard releasePermission.wait(timeout: .now() + d3ConcurrencyProofTimeout) == .success else {
            state.withLock { $0.didTimeOutWaitingForReleasePermission = true }
            return
        }
    }

    func waitUntilReleaseEntered() -> Bool {
        releaseEntered.wait(timeout: .now() + d3ConcurrencyProofTimeout) == .success
    }

    func allowReleaseToComplete() {
        releasePermission.signal()
    }
}
