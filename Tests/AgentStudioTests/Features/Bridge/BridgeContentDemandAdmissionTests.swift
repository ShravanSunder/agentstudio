import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class BridgeContentDemandAdmissionTests {
    @Test
    func test_backgroundContentDemandYieldsUntilVisibleDemandFinishes() async {
        let admission = BridgeContentDemandAdmission()
        await admission.start(.visible)
        let backgroundWaiter = BridgeContentDemandEventRecorder()
        let backgroundTask = Task {
            await admission.waitForBackgroundTurn()
            await backgroundWaiter.recordEvent()
        }
        await Task.yield()

        #expect(await backgroundWaiter.recordedEventCount() == 0)

        await admission.finish(.visible)
        _ = await backgroundTask.result

        #expect(await backgroundWaiter.recordedEventCount() == 1)
    }

    @Test
    func test_backgroundWaiterLifetimeIsOwnedByAdmissionActor() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Bridge/Transport/BridgeContentDemandAdmission.swift"
            ),
            encoding: .utf8
        )

        #expect(!source.contains("final class BackgroundWaiter"))
        #expect(!source.contains("NSLock"))
        #expect(!source.contains("@unchecked Sendable"))
        #expect(source.contains("backgroundWaiterIds"))
        #expect(source.contains("backgroundWaiterContinuationsById"))
        #expect(source.contains("backgroundWaiterCancellationTombstones"))
    }

    @Test
    func test_withAdmissionFinishesUserDemandExactlyOnceWhenOperationThrows() async {
        let clock = TestPushClock()
        let admission = BridgeContentDemandAdmission(clock: clock)

        await #expect(throws: BridgeContentDemandAdmissionTestError.expected) {
            try await admission.withAdmission(for: .visible) {
                throw BridgeContentDemandAdmissionTestError.expected
            }
        }
        await clock.waitForPendingSleepCount()

        let cooldownSnapshot = await admission.snapshot()
        #expect(cooldownSnapshot.pendingUserDemandCount == 0)
        #expect(cooldownSnapshot.backgroundWaiterCount == 0)
        #expect(cooldownSnapshot.backgroundWaiterRegistrationCount == 0)
        #expect(cooldownSnapshot.backgroundCancellationTombstoneCount == 0)
        #expect(cooldownSnapshot.hasBackgroundPacingTask == false)
        #expect(cooldownSnapshot.hasBackgroundCooldownTask)

        clock.advance(by: AppPolicies.Bridge.contentBackgroundFillInteractiveCooldown)
        await clock.waitForPendingSleepCount(exactly: 0)

        let terminalSnapshot = await terminalSnapshot(from: admission)
        #expect(terminalSnapshot.pendingUserDemandCount == 0)
        #expect(terminalSnapshot.backgroundWaiterCount == 0)
        #expect(terminalSnapshot.backgroundWaiterRegistrationCount == 0)
        #expect(terminalSnapshot.backgroundCancellationTombstoneCount == 0)
        #expect(terminalSnapshot.hasBackgroundPacingTask == false)
        #expect(terminalSnapshot.hasBackgroundCooldownTask == false)
    }

    @Test
    func test_closeAndDrainRejectsNewDemandAndWaitsForAdmittedOperation() async throws {
        let admission = BridgeContentDemandAdmission()
        let operationGate = BridgeContentDemandTestGate()
        let admittedOperation = Task {
            try await admission.withAdmission(for: .visible) {
                await operationGate.waitUntilOpened()
            }
        }
        await operationGate.waitUntilBlocked()

        let drainTask = Task {
            await admission.closeAndDrain()
        }
        #expect(await waitForClosedAdmission(admission))
        await #expect(throws: CancellationError.self) {
            try await admission.withAdmission(for: .selected) {}
        }
        let closingSnapshot = await admission.snapshot()
        #expect(closingSnapshot.isClosed)
        #expect(closingSnapshot.activeScopedAdmissionCount == 1)

        await operationGate.open()
        try await admittedOperation.value
        await drainTask.value

        let terminalSnapshot = await admission.snapshot()
        #expect(terminalSnapshot.isClosed)
        #expect(terminalSnapshot.activeScopedAdmissionCount == 0)
        #expect(terminalSnapshot.pendingUserDemandCount == 0)
        #expect(terminalSnapshot.backgroundWaiterCount == 0)
        #expect(terminalSnapshot.backgroundWaiterRegistrationCount == 0)
        #expect(terminalSnapshot.backgroundCancellationTombstoneCount == 0)
        #expect(terminalSnapshot.hasBackgroundPacingTask == false)
        #expect(terminalSnapshot.hasBackgroundCooldownTask == false)
    }

    @Test
    func test_closeAndDrainCancelsQueuedBackgroundDemandWithoutResidue() async {
        let admission = BridgeContentDemandAdmission()
        await admission.start(.visible)
        let queuedBackgroundDemand = Task {
            try await admission.withAdmission(for: .background) {}
        }
        #expect(await waitForBackgroundWaiterCount(1, admission: admission))

        await admission.closeAndDrain()

        await #expect(throws: CancellationError.self) {
            try await queuedBackgroundDemand.value
        }
        let terminalSnapshot = await admission.snapshot()
        #expect(terminalSnapshot.isClosed)
        #expect(terminalSnapshot.activeScopedAdmissionCount == 0)
        #expect(terminalSnapshot.pendingUserDemandCount == 0)
        #expect(terminalSnapshot.backgroundWaiterCount == 0)
        #expect(terminalSnapshot.backgroundWaiterRegistrationCount == 0)
        #expect(terminalSnapshot.backgroundCancellationTombstoneCount == 0)
        #expect(terminalSnapshot.hasBackgroundPacingTask == false)
        #expect(terminalSnapshot.hasBackgroundCooldownTask == false)
    }

    @Test
    func test_backgroundAdmissionCancelledBeforeRegistrationLeavesNoResidue() async {
        let admission = BridgeContentDemandAdmission()
        let admissionGate = BridgeContentDemandTestGate()
        let operationRecorder = BridgeContentDemandEventRecorder()
        let backgroundTask = Task {
            await admissionGate.waitUntilOpened()
            try await admission.withAdmission(for: .background) {
                await operationRecorder.recordEvent()
            }
        }
        await admissionGate.waitUntilBlocked()

        backgroundTask.cancel()
        await admissionGate.open()

        await #expect(throws: CancellationError.self) {
            try await backgroundTask.value
        }
        #expect(await operationRecorder.recordedEventCount() == 0)
        let snapshot = await admission.snapshot()
        #expect(snapshot.backgroundWaiterCount == 0)
        #expect(snapshot.backgroundWaiterRegistrationCount == 0)
        #expect(snapshot.backgroundCancellationTombstoneCount == 0)
        #expect(snapshot.hasBackgroundPacingTask == false)
        #expect(snapshot.hasBackgroundCooldownTask == false)
    }

    @Test
    func test_backgroundAdmissionCancelledAfterRegistrationLeavesNoResidue() async {
        let clock = TestPushClock()
        let admission = BridgeContentDemandAdmission(clock: clock)
        await admission.start(.visible)
        let backgroundTask = Task {
            try await admission.withAdmission(for: .background) {}
        }

        var observedQueuedWaiter = false
        for _ in 0..<1000 {
            if await admission.snapshot().backgroundWaiterCount == 1 {
                observedQueuedWaiter = true
                break
            }
            await Task.yield()
        }
        #expect(observedQueuedWaiter)

        backgroundTask.cancel()
        await #expect(throws: CancellationError.self) {
            try await backgroundTask.value
        }
        let cancellationSnapshot = await admission.snapshot()
        #expect(cancellationSnapshot.backgroundWaiterCount == 0)
        #expect(cancellationSnapshot.backgroundWaiterRegistrationCount == 0)
        #expect(cancellationSnapshot.backgroundCancellationTombstoneCount == 0)

        await admission.finish(.visible)
        await clock.waitForPendingSleepCount()
        clock.advance(by: AppPolicies.Bridge.contentBackgroundFillInteractiveCooldown)
        await clock.waitForPendingSleepCount(exactly: 0)

        let terminalSnapshot = await terminalSnapshot(from: admission)
        #expect(terminalSnapshot.pendingUserDemandCount == 0)
        #expect(terminalSnapshot.backgroundWaiterCount == 0)
        #expect(terminalSnapshot.backgroundWaiterRegistrationCount == 0)
        #expect(terminalSnapshot.backgroundCancellationTombstoneCount == 0)
        #expect(terminalSnapshot.hasBackgroundPacingTask == false)
        #expect(terminalSnapshot.hasBackgroundCooldownTask == false)
    }

    @Test
    func test_backgroundReleaseAndCancellationSettleExactlyOnceWithoutResidue() async {
        let clock = TestPushClock()
        let admission = BridgeContentDemandAdmission(clock: clock)
        let operationRecorder = BridgeContentDemandEventRecorder()
        await admission.start(.visible)
        let backgroundTask = Task {
            try await admission.withAdmission(for: .background) {
                await operationRecorder.recordEvent()
            }
        }
        #expect(await waitForBackgroundWaiterCount(1, admission: admission))

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                backgroundTask.cancel()
            }
            group.addTask {
                await admission.finish(.visible)
            }
        }

        switch await backgroundTask.result {
        case .success:
            break
        case .failure(let error):
            #expect(error is CancellationError)
        }
        #expect(await operationRecorder.recordedEventCount() <= 1)

        await clock.waitForPendingSleepCount()
        clock.advance(by: AppPolicies.Bridge.contentBackgroundFillInteractiveCooldown)
        await clock.waitForPendingSleepCount(exactly: 0)

        let terminalSnapshot = await terminalSnapshot(from: admission)
        #expect(terminalSnapshot.pendingUserDemandCount == 0)
        #expect(terminalSnapshot.backgroundWaiterCount == 0)
        #expect(terminalSnapshot.backgroundWaiterRegistrationCount == 0)
        #expect(terminalSnapshot.backgroundCancellationTombstoneCount == 0)
        #expect(terminalSnapshot.hasBackgroundPacingTask == false)
        #expect(terminalSnapshot.hasBackgroundCooldownTask == false)
    }

    @Test
    func test_backgroundPacingReleasesWaitersInRegistrationOrder() async {
        let clock = TestPushClock()
        let admission = BridgeContentDemandAdmission(clock: clock)
        let operationRecorder = BridgeContentDemandEventRecorder()
        await admission.start(.visible)
        await admission.finish(.visible)
        for _ in 0..<AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget {
            await admission.start(.background)
        }

        let firstTask = Task {
            try await admission.withAdmission(for: .background) {
                await operationRecorder.recordEvent("first")
            }
        }
        #expect(await waitForBackgroundWaiterCount(1, admission: admission))
        let secondTask = Task {
            try await admission.withAdmission(for: .background) {
                await operationRecorder.recordEvent("second")
            }
        }
        #expect(await waitForBackgroundWaiterCount(2, admission: admission))
        await clock.waitForPendingSleepCount(atLeast: 2)

        clock.advance(by: AppPolicies.Bridge.contentBackgroundFillInteractiveRefillInterval)
        await operationRecorder.waitForRecordedEventCount(1)

        #expect(await operationRecorder.recordedEvents() == ["first"])
        #expect(await admission.snapshot().backgroundWaiterCount == 1)
        _ = await firstTask.result

        secondTask.cancel()
        await #expect(throws: CancellationError.self) {
            try await secondTask.value
        }
        let postCancellationSnapshot = await admission.snapshot()
        #expect(postCancellationSnapshot.backgroundWaiterCount == 0)
        #expect(postCancellationSnapshot.backgroundWaiterRegistrationCount == 0)
        #expect(postCancellationSnapshot.backgroundCancellationTombstoneCount == 0)
        #expect(postCancellationSnapshot.hasBackgroundPacingTask == false)

        clock.advance(
            by: AppPolicies.Bridge.contentBackgroundFillInteractiveCooldown
                - AppPolicies.Bridge.contentBackgroundFillInteractiveRefillInterval
        )
        await clock.waitForPendingSleepCount(exactly: 0)
        let terminalSnapshot = await terminalSnapshot(from: admission)
        #expect(terminalSnapshot.backgroundWaiterCount == 0)
        #expect(terminalSnapshot.backgroundWaiterRegistrationCount == 0)
        #expect(terminalSnapshot.backgroundCancellationTombstoneCount == 0)
        #expect(terminalSnapshot.hasBackgroundCooldownTask == false)
    }

    @Test
    func test_backgroundFillCooldownEnforcesBurstBudget() async {
        let clock = TestPushClock()
        let admission = BridgeContentDemandAdmission(clock: clock)
        await admission.start(.visible)
        await admission.finish(.visible)

        for _ in 0..<AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget {
            await admission.start(.background)
        }

        let backgroundWaiter = BridgeContentDemandEventRecorder()
        let backgroundTask = Task {
            await admission.start(.background)
            await backgroundWaiter.recordEvent()
        }
        await clock.waitForPendingSleepCount(atLeast: 2)
        await Task.yield()

        #expect(await backgroundWaiter.recordedEventCount() == 0)

        clock.advance(by: AppPolicies.Bridge.contentBackgroundFillInteractiveRefillInterval)
        _ = await backgroundTask.result

        #expect(await backgroundWaiter.recordedEventCount() == 1)
    }

    @Test
    func test_backgroundFillCooldownKeepsFillPacedAfterVisibleDemandFinishes() async {
        let clock = TestPushClock()
        let admission = BridgeContentDemandAdmission(clock: clock)
        await admission.start(.visible)
        await admission.finish(.visible)

        for _ in 0..<AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget {
            await admission.start(.background)
        }

        let backgroundWaiter = BridgeContentDemandEventRecorder()
        let backgroundTask = Task {
            await admission.start(.background)
            await backgroundWaiter.recordEvent()
        }
        await clock.waitForPendingSleepCount(atLeast: 2)
        await Task.yield()

        #expect(await backgroundWaiter.recordedEventCount() == 0)

        clock.advance(by: AppPolicies.Bridge.contentBackgroundFillInteractiveCooldown)
        _ = await backgroundTask.result

        for _ in 0..<(AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget + 3) {
            await admission.start(.background)
        }

        #expect(await backgroundWaiter.recordedEventCount() == 1)
        #expect(clock.pendingSleepCount == 0)
    }

    @Test
    func test_backgroundFillIdlePathPreservesFullRateAdmission() async {
        let clock = TestPushClock()
        let admission = BridgeContentDemandAdmission(clock: clock)

        for _ in 0..<(AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget * 2) {
            await admission.start(.background)
        }

        #expect(clock.pendingSleepCount == 0)
    }

    private func terminalSnapshot(
        from admission: BridgeContentDemandAdmission
    ) async -> BridgeContentDemandAdmissionSnapshot {
        for _ in 0..<1000 {
            let snapshot = await admission.snapshot()
            if snapshot.pendingUserDemandCount == 0,
                snapshot.backgroundWaiterCount == 0,
                snapshot.backgroundWaiterRegistrationCount == 0,
                snapshot.backgroundCancellationTombstoneCount == 0,
                snapshot.hasBackgroundPacingTask == false,
                snapshot.hasBackgroundCooldownTask == false
            {
                return snapshot
            }
            await Task.yield()
        }
        return await admission.snapshot()
    }

    private func waitForBackgroundWaiterCount(
        _ expectedCount: Int,
        admission: BridgeContentDemandAdmission
    ) async -> Bool {
        for _ in 0..<1000 {
            if await admission.snapshot().backgroundWaiterCount == expectedCount {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private func waitForClosedAdmission(
        _ admission: BridgeContentDemandAdmission
    ) async -> Bool {
        for _ in 0..<1000 {
            if await admission.snapshot().isClosed {
                return true
            }
            await Task.yield()
        }
        return false
    }
}

private actor BridgeContentDemandEventRecorder {
    private var events: [String] = []
    private var eventCountWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func recordEvent(_ event: String = "event") {
        events.append(event)
        let satisfiedCounts = eventCountWaiters.keys.filter { $0 <= events.count }
        for count in satisfiedCounts {
            let waiters = eventCountWaiters.removeValue(forKey: count) ?? []
            for waiter in waiters { waiter.resume() }
        }
    }

    func recordedEventCount() -> Int {
        events.count
    }

    func recordedEvents() -> [String] {
        events
    }

    func waitForRecordedEventCount(_ count: Int) async {
        guard events.count < count else { return }
        await withCheckedContinuation { continuation in
            eventCountWaiters[count, default: []].append(continuation)
        }
    }
}

private actor BridgeContentDemandTestGate {
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var isBlocked = false
    private var isOpen = false
    private var openWaiter: CheckedContinuation<Void, Never>?

    func waitUntilOpened() async {
        guard !isOpen else { return }
        isBlocked = true
        let waiters = blockedWaiters
        blockedWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                openWaiter = continuation
            }
        }
    }

    func waitUntilBlocked() async {
        guard !isBlocked else { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        openWaiter?.resume()
        openWaiter = nil
    }
}

private enum BridgeContentDemandAdmissionTestError: Error {
    case expected
}
