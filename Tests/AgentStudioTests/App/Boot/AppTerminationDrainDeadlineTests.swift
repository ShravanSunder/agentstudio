import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

/// `applicationShouldTerminate` returns `.terminateLater`, so the AppKit quit
/// completes only when the reply fires. A drain stage that never finishes must
/// therefore not be able to withhold it.
@MainActor
@Suite("App termination drain deadline", .serialized)
struct AppTerminationDrainDeadlineTests {
    init() { installTestCoreAtomsIfNeeded() }

    @Test("the AppKit reply fires when a drain stage never completes")
    func replyFiresWhenTheDrainNeverCompletes() async {
        let recorder = TerminationReplyRecorder()
        // A drain that can only be released by the test, so nothing but the
        // deadline can produce the reply.
        let neverCompletingDrain = ReleasableGate()

        await replyToApplicationTerminationAfterBoundedDrain(
            timeout: .seconds(2),
            delay: .immediate,
            drain: { await neverCompletingDrain.wait() },
            reply: { recorder.record($0) }
        )

        #expect(recorder.outcomes == [.timedOut])
        neverCompletingDrain.release()
    }

    @Test("a drain that finishes reports completion and replies once")
    func replyReportsCompletionForAFinishedDrain() async {
        let recorder = TerminationReplyRecorder()
        // A deadline the test holds open, so a completing drain is the only
        // way the reply can be produced.
        let withheldDeadline = ReleasableGate()

        await replyToApplicationTerminationAfterBoundedDrain(
            timeout: .seconds(2),
            delay: AsyncDelay { _ in await withheldDeadline.wait() },
            drain: {},
            reply: { recorder.record($0) }
        )

        #expect(recorder.outcomes == [.completed])
        withheldDeadline.release()
    }
    @Test("the workspace flush completes even when the IPC drain never does")
    func workspaceFlushSurvivesAnUnfinishedIPCDrain() async {
        let stages = TerminationStageRecorder()
        let neverCompletingIPCDrain = ReleasableGate()

        let outcome = await runBoundedIPCDrainAfterWorkspaceFlush(
            timeout: .seconds(2),
            delay: .immediate,
            workspaceFlush: { stages.record("workspaceFlush") },
            ipcDrain: {
                stages.record("ipcDrainStarted")
                await neverCompletingIPCDrain.wait()
                stages.record("ipcDrainCompleted")
            }
        )

        #expect(outcome == .timedOut)
        // The flush is durable before the drain is even attempted, so the
        // drain overrunning its bound cannot cost the workspace layout.
        #expect(stages.names.first == "workspaceFlush")
        #expect(!stages.names.contains("ipcDrainCompleted"))
        neverCompletingIPCDrain.release()
    }

    @Test("no IPC request is accepted once the stop stage has run")
    func ipcStopRefusesFurtherRequests() async throws {
        let harness = try await SessionsVerticalHarness.make()
        defer { harness.tearDown() }

        let beforeStop = try await harness.response(method: "system.ping", params: .object([:]))
        #expect(beforeStop.error == nil)

        await harness.appDelegate.stopAcceptingAppIPCConnections()

        // Connecting must fail outright rather than be refused after login:
        // the listener is closed, so there is no path by which a late
        // command.execute or Bridge open reaches the app and mutates state the
        // workspace flush is about to write.
        #expect(throws: (any Error).self) {
            try UnixSocketClient.connect(
                endpoint: UnixSocketEndpoint(path: harness.socketPath)
            ).close()
        }
    }

    @Test("a completing IPC drain still runs after the workspace flush")
    func ipcDrainRunsAfterTheWorkspaceFlush() async {
        let stages = TerminationStageRecorder()
        let withheldDeadline = ReleasableGate()

        let outcome = await runBoundedIPCDrainAfterWorkspaceFlush(
            timeout: .seconds(2),
            delay: AsyncDelay { _ in await withheldDeadline.wait() },
            workspaceFlush: { stages.record("workspaceFlush") },
            ipcDrain: { stages.record("ipcDrain") }
        )

        #expect(outcome == .completed)
        #expect(stages.names == ["workspaceFlush", "ipcDrain"])
        withheldDeadline.release()
    }
}

@MainActor
private final class TerminationStageRecorder {
    private(set) var names: [String] = []

    func record(_ name: String) {
        names.append(name)
    }
}

@MainActor
private final class TerminationReplyRecorder {
    private(set) var outcomes: [TerminationDrainOutcome] = []

    func record(_ outcome: TerminationDrainOutcome) {
        outcomes.append(outcome)
    }
}

/// Suspends until the test releases it, with no timer of its own, so a case
/// proves the deadline rather than a race between two sleeps. Every gate is
/// released before its test returns, so no task outlives the case.
private final class ReleasableGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResumeImmediately = lock.withLock { () -> Bool in
                guard !isReleased else { return true }
                self.continuation = continuation
                return false
            }
            if shouldResumeImmediately { continuation.resume() }
        }
    }

    func release() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            isReleased = true
            let stored = continuation
            continuation = nil
            return stored
        }
        pending?.resume()
    }
}

extension AsyncDelay {
    /// Fires the deadline without spending wall-clock time.
    fileprivate static let immediate = Self { _ in }
}
