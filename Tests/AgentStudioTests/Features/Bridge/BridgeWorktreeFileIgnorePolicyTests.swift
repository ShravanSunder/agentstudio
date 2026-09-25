import AgentStudioCore
import AgentStudioTestHarness
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge worktree file ignore policy")
struct BridgeWorktreeFileIgnorePolicyTests {
    @Test("tracked path timeout falls back to filesystem enumeration")
    func trackedPathTimeoutFallsBackToFilesystemEnumeration() async throws {
        // Arrange
        let trackedPathReadGate = HeldStep<Void>("trackedPathReadGate", cancellation: .holdThroughCancellation)
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
                    try? await trackedPathReadGate.arrive(())
                    return ["Sources/App.swift"]
                }
            )
        }
        try await trackedPathReadGate.firstArrival()

        // Act
        #expect(deadlineScheduler.fireNextActiveDeadline())
        _ = await eventProbe.waitFor(.draining)
        let policy = await loadTask.value

        // Assert
        #expect(policy.publishableFilePaths == nil)
        trackedPathReadGate.release()
        _ = await eventProbe.waitFor(.slotReleased)
        await scheduler.shutdown()
    }
}
