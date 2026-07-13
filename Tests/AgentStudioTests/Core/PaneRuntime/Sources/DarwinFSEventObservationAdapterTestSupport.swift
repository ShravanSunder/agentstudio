import Dispatch
import Foundation
import Testing
import os

@testable import AgentStudio

enum AdapterFixtureError: Error {
    case fixtureConstructionFailed
}

final class LeaseCountRecorder: FilesystemObservationCallbackSynchronization,
    @unchecked Sendable
{
    private enum State: Sendable {
        case awaitingControlBlock
        case attached(controlBlock: FSEventRegistrationControlBlock, observedActiveLeaseCount: Int)
    }

    private let lock = OSAllocatedUnfairLock(initialState: State.awaitingControlBlock)

    func attach(to controlBlock: FSEventRegistrationControlBlock) {
        lock.withLock { state in
            guard case .awaitingControlBlock = state else {
                Issue.record("lease recorder control block must be attached exactly once")
                return
            }
            state = .attached(controlBlock: controlBlock, observedActiveLeaseCount: 0)
        }
    }

    func afterAuthorityConsumedBeforeMailboxOffer() {
        lock.withLock { state in
            guard case .attached(let controlBlock, _) = state,
                case .open(let activeLeaseCount) = controlBlock.lifecycleSnapshot
            else { return }
            state = .attached(controlBlock: controlBlock, observedActiveLeaseCount: activeLeaseCount)
        }
    }

    func afterMailboxOfferBeforeWakeApplication() {}

    var observedActiveLeaseCount: Int {
        lock.withLock { state in
            switch state {
            case .awaitingControlBlock: 0
            case .attached(_, let observedActiveLeaseCount): observedActiveLeaseCount
            }
        }
    }
}

enum CaptureAdmissionPause: Equatable, Sendable {
    case afterAuthorityConsumption
    case afterMailboxOffer
}

final class CaptureAdmissionGate: FilesystemObservationCallbackSynchronization,
    @unchecked Sendable
{
    private enum State: Sendable {
        case pending
        case completed(DarwinFSEventObservationCaptureResult)
    }

    private let pause: CaptureAdmissionPause
    let admissionEntered = DispatchSemaphore(value: 0)
    let releaseAdmission = DispatchSemaphore(value: 0)
    private let completed = DispatchSemaphore(value: 0)
    private let state = OSAllocatedUnfairLock(initialState: State.pending)

    init(pause: CaptureAdmissionPause) {
        self.pause = pause
    }

    func afterAuthorityConsumedBeforeMailboxOffer() {
        guard pause == .afterAuthorityConsumption else { return }
        pauseAdmission()
    }

    func afterMailboxOfferBeforeWakeApplication() {
        guard pause == .afterMailboxOffer else { return }
        pauseAdmission()
    }

    private func pauseAdmission() {
        admissionEntered.signal()
        if releaseAdmission.wait(timeout: .now() + 5) != .success {
            Issue.record("timed out waiting to release gated callback admission")
        }
    }

    func finish(with result: DarwinFSEventObservationCaptureResult) {
        state.withLock { $0 = .completed(result) }
        completed.signal()
    }

    func waitForAdmissionEntry() -> Bool {
        admissionEntered.wait(timeout: .now() + 5) == .success
    }

    func waitForCompletion() -> DarwinFSEventObservationCaptureResult? {
        guard completed.wait(timeout: .now() + 5) == .success else {
            Issue.record("timed out waiting for gated callback completion")
            return nil
        }
        return state.withLock { state in
            guard case .completed(let result) = state else { return nil }
            return result
        }
    }
}

final class NativeInspectionLedger: @unchecked Sendable {
    private let count = OSAllocatedUnfairLock(initialState: 0)

    func recordInspection() {
        count.withLock { $0 += 1 }
    }

    var inspectionCount: Int { count.withLock { $0 } }
}

func requireAuthoritative(
    _ result: DarwinFSEventObservationCaptureResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FSEventObservation {
    guard
        case .admitted(
            offer: .authoritative(let observation),
            admission: .admitted(.retained, _)
        ) = result
    else {
        Issue.record("expected retained authoritative admission", sourceLocation: sourceLocation)
        preconditionFailure("expected authoritative callback admission")
    }
    return observation
}

func requireRecovery(
    _ result: DarwinFSEventObservationCaptureResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> (FSEventObservation, FilesystemRecoveryEvidence) {
    guard
        case .admitted(
            offer: .requiresRecovery(let observation, let evidence),
            admission: .admitted(.retainedWithRecovery, _)
        ) = result
    else {
        Issue.record("expected retained recovery admission", sourceLocation: sourceLocation)
        preconditionFailure("expected recovery callback admission")
    }
    return (observation, evidence)
}

func acquiredLease(
    from controlBlock: FSEventRegistrationControlBlock
) -> FSEventCallbackLease? {
    switch controlBlock.acquireCallbackLease() {
    case .acquired(let lease): lease
    case .leaseIdentityExhausted, .closing: nil
    }
}

func expectRejection(
    _ result: DarwinFSEventObservationCaptureResult,
    expected: DarwinFSEventObservationCaptureRejection,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .rejected(let actual) = result else {
        Issue.record("expected callback rejection", sourceLocation: sourceLocation)
        return
    }
    #expect(actual == expected, sourceLocation: sourceLocation)
}

func expectNoActiveLease(
    _ controlBlock: FSEventRegistrationControlBlock,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    switch controlBlock.lifecycleSnapshot {
    case .open(let activeLeaseCount), .closing(_, let activeLeaseCount):
        #expect(activeLeaseCount == 0, sourceLocation: sourceLocation)
    }
}

func expectMalformedPrefix(
    _ observation: FSEventObservation,
    reportedCount: Int = 2,
    availableCount: Int,
    retainedPath: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        observation.totalRecordCount
            == .malformed(
                .nativeArrayCountMismatch(
                    reportedRecordCount: reportedCount,
                    availableRecordCount: availableCount
                )
            ),
        sourceLocation: sourceLocation
    )
    #expect(observation.inspectedNativeRecordCount == availableCount, sourceLocation: sourceLocation)
    #expect(observation.records.map(\.path) == [retainedPath], sourceLocation: sourceLocation)
    #expect(observation.completeness == .truncated([.malformedNativeShape]), sourceLocation: sourceLocation)
}
