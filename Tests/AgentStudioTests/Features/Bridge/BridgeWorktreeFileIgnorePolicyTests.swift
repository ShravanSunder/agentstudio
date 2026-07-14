import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge worktree file ignore policy")
struct BridgeWorktreeFileIgnorePolicyTests {
    @Test("tracked path timeout falls back to filesystem enumeration")
    func trackedPathTimeoutFallsBackToFilesystemEnumeration() async {
        // Arrange
        let trackedPathReadGate = BridgeTrackedPathReadGate()
        let timeoutScheduler = ManualBridgeTrackedPathTimeoutScheduler()
        let statusProvider = StubGitWorkingTreeStatusProvider { _ in
            GitWorkingTreeStatus(
                summary: .init(changed: 0, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
            )
        }
        let loadTask = Task {
            await BridgeWorktreeFileIgnorePolicy.load(
                rootURL: URL(fileURLWithPath: "/tmp/bridge-tracked-path-timeout"),
                statusProvider: statusProvider,
                trackedFilePathsTimeout: .seconds(999),
                timeoutScheduler: timeoutScheduler,
                trackedFilePathsLoader: { _ in
                    await trackedPathReadGate.recordStarted()
                    await trackedPathReadGate.waitUntilReleased()
                    return ["Sources/App.swift"]
                }
            )
        }
        await trackedPathReadGate.waitUntilStarted()
        await timeoutScheduler.waitUntilScheduled()

        // Act
        timeoutScheduler.fireScheduledTimeout()
        let policy = await loadTask.value

        // Assert
        #expect(policy.publishableFilePaths == nil)
        await trackedPathReadGate.release()
    }
}

private actor BridgeTrackedPathReadGate {
    private var didStart = false
    private var didRelease = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func recordStarted() {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilReleased() async {
        guard !didRelease else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func release() {
        didRelease = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private final class ManualBridgeTrackedPathTimeoutScheduler: BridgeGitDataPlaneTimeoutScheduler,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var scheduledHandler: (@Sendable () -> Void)?
    private var scheduleWaiters: [CheckedContinuation<Void, Never>] = []

    func scheduleTimeout(
        after _: Duration,
        _ handler: @escaping @Sendable () -> Void
    ) -> BridgeGitDataPlaneScheduledTimeout {
        let waiters: [CheckedContinuation<Void, Never>]
        lock.lock()
        scheduledHandler = handler
        waiters = scheduleWaiters
        scheduleWaiters.removeAll(keepingCapacity: false)
        lock.unlock()
        for waiter in waiters {
            waiter.resume()
        }
        return BridgeGitDataPlaneScheduledTimeout { [weak self] in
            self?.clearScheduledTimeout()
        }
    }

    func waitUntilScheduled() async {
        guard !hasScheduledTimeout() else { return }
        await withCheckedContinuation { continuation in
            if !appendScheduleWaiterIfNeeded(continuation) {
                continuation.resume()
            }
        }
    }

    func fireScheduledTimeout() {
        let handler: (@Sendable () -> Void)?
        lock.lock()
        handler = scheduledHandler
        scheduledHandler = nil
        lock.unlock()
        handler?()
    }

    private func hasScheduledTimeout() -> Bool {
        lock.lock()
        let result = scheduledHandler != nil
        lock.unlock()
        return result
    }

    private func appendScheduleWaiterIfNeeded(
        _ continuation: CheckedContinuation<Void, Never>
    ) -> Bool {
        lock.lock()
        guard scheduledHandler == nil else {
            lock.unlock()
            return false
        }
        scheduleWaiters.append(continuation)
        lock.unlock()
        return true
    }

    private func clearScheduledTimeout() {
        lock.lock()
        scheduledHandler = nil
        lock.unlock()
    }
}
