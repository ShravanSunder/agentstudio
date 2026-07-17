import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge worktree file ignore policy")
struct BridgeWorktreeFileIgnorePolicyTests {
    @Test("tracked path timeout falls back to filesystem enumeration")
    func trackedPathTimeoutFallsBackToFilesystemEnumeration() async {
        // Arrange
        let trackedPathReadGate = BridgeTrackedPathReadGate()
        let deadlineScheduler = BridgeGitReadManualDeadlineScheduler()
        let eventProbe = BridgeGitReadSchedulerEventProbe()
        let scheduler = BridgeGitReadScheduler(
            topology: makeBridgeGitReadSchedulerTopology(),
            deadlineScheduler: deadlineScheduler,
            eventSink: eventProbe.eventSink
        )
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
                gitReadContext: BridgeGitReadContext(
                    scheduler: scheduler,
                    worktreeKey: BridgeGitReadWorktreeKey(token: "tracked-path-timeout-worktree")
                ),
                statusProvider: statusProvider,
                trackedFilePathsTimeout: .seconds(999),
                trackedFilePathsLoader: { _ in
                    await trackedPathReadGate.recordStarted()
                    await trackedPathReadGate.waitUntilReleased()
                    return ["Sources/App.swift"]
                }
            )
        }
        await trackedPathReadGate.waitUntilStarted()

        // Act
        #expect(deadlineScheduler.fireNextActiveDeadline())
        _ = await eventProbe.waitFor(.draining)
        let policy = await loadTask.value

        // Assert
        #expect(policy.publishableFilePaths == nil)
        await trackedPathReadGate.release()
        _ = await eventProbe.waitFor(.slotReleased)
        await scheduler.shutdown()
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
