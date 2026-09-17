import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio

/// `applicationShouldTerminate` returns `.terminateLater`, so the AppKit quit
/// completes only when the reply fires. A drain stage that never finishes must
/// therefore not be able to withhold it.
@MainActor
@Suite("App termination drain deadline", .serialized)
struct AppTerminationDrainDeadlineTests {
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
