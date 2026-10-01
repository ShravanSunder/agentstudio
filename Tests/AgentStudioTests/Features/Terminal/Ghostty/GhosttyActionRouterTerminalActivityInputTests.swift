import Foundation
import Testing

@testable import AgentStudioTerminal

/// SR6b (Program Design item 13, "Arming"). The isolated-instance tests
/// prove `GhosttyTerminalActivityInputBinding`'s wait-then-bind mechanic
/// without touching the shared global singleton other test files already
/// bind/unbind against; the `.serialized` suite below proves
/// `Ghostty.ActionRouter.armRestorePhase`'s integration with that real
/// singleton in its already-bound state (the path production code takes in
/// every real launch, since the router binds during boot).
@Suite("Ghostty action router restore-phase arming: isolated binding")
struct GhosttyActivityInputBindingRestorePhaseTests {
    @Test("awaitBound resumes only after bind — never before, proven by ordering")
    @MainActor
    func awaitBoundResumesOnlyAfterBind() async {
        let binding = GhosttyTerminalActivityInputBinding()
        let log = OrderedEventLog()
        let registered = WaiterRegistrationSignal()

        // F7 (review round 1): a single `Task.yield()` only claims `waitTask`
        // reached registration — Swift's scheduler makes no such promise.
        // `onWaiterRegistered` fires synchronously at the real registration
        // point, so awaiting its signal is a fact, not a guess.
        let waitTask = Task { @MainActor in
            await binding.awaitBound(onWaiterRegistered: { registered.fire() })
            log.record("resumed")
        }
        await registered.wait()
        log.record("before-bind")
        #expect(!binding.isBound)

        binding.bind(
            id: UUID(), context: { _ in .init(isAttended: false, isAgentClassified: false, outputBurstThreshold: 1) },
            sink: { _ in })
        await waitTask.value

        #expect(log.events == ["before-bind", "resumed"])
    }

    @Test("already bound: awaitBound returns immediately without registering a waiter")
    @MainActor
    func alreadyBoundReturnsImmediately() async {
        let binding = GhosttyTerminalActivityInputBinding()
        binding.bind(
            id: UUID(), context: { _ in .init(isAttended: false, isAgentClassified: false, outputBurstThreshold: 1) },
            sink: { _ in })

        await binding.awaitBound()

        #expect(binding.isBound)
    }

    @Test("a cancelled wait resumes without ever binding")
    @MainActor
    func cancelledWaitResumesWithoutBinding() async {
        let binding = GhosttyTerminalActivityInputBinding()
        let registered = WaiterRegistrationSignal()

        let waitTask = Task { @MainActor in
            await binding.awaitBound(onWaiterRegistered: { registered.fire() })
        }
        await registered.wait()
        waitTask.cancel()
        await waitTask.value

        #expect(!binding.isBound)
    }
}

@MainActor
private final class OrderedEventLog {
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
}

/// F7: a one-shot, thread-safe "fire now, await later" signal for a
/// synchronous production callback (`onWaiterRegistered`) a test needs to
/// await from an async context. Not `HeldStep`: nothing here needs to hold
/// the firing call open for a later `release()` — it already returns
/// immediately on its own, and the real suspension these tests care about is
/// `awaitBound`'s own continuation, already in place by the time it fires.
private final class WaiterRegistrationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var hasFired = false
    private var continuation: CheckedContinuation<Void, Never>?

    func fire() {
        let resuming: CheckedContinuation<Void, Never>? = lock.withLock {
            hasFired = true
            defer { continuation = nil }
            return continuation
        }
        resuming?.resume()
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let shouldResumeNow = lock.withLock { () -> Bool in
                if hasFired { return true }
                self.continuation = continuation
                return false
            }
            if shouldResumeNow { continuation.resume() }
        }
    }
}

/// Exercises `Ghostty.ActionRouter.armRestorePhase` against the real shared
/// binding singleton, which several other test files also bind/unbind
/// against. `@MainActor` + `.serialized` together (matching
/// `TerminalActivityRouterAttentionTests`'s own pattern) put this suite in
/// the isolated-process phase, so it never shares that mutable global with
/// another suite's concurrent run — the fast lane's own concurrency, not a
/// per-test detail this suite could otherwise control.
@MainActor
@Suite("Ghostty action router restore-phase arming: shared singleton", .serialized)
struct GhosttyActionRouterRestorePhaseArmingTests {
    @Test("arming an already-bound router submits .restorePhaseArmed and returns .armed")
    func armingAnAlreadyBoundRouterSubmitsAndAcknowledges() async {
        let bindingID = UUID()
        let recorder = SubmittedInputRecorder()
        Ghostty.ActionRouter.bindTerminalActivityInput(
            id: bindingID,
            context: { _ in .init(isAttended: false, isAgentClassified: false, outputBurstThreshold: 1) },
            sink: { [recorder] input in recorder.record(input) }
        )
        defer { Ghostty.ActionRouter.unbindTerminalActivityInput(id: bindingID) }
        let paneID = UUID()
        let generation = RestoreGeneration(rawValue: 42)

        let acknowledgment = await Ghostty.ActionRouter.armRestorePhase(paneID: paneID, restoreGeneration: generation)

        #expect(acknowledgment == .armed)
        #expect(recorder.inputs == [.restorePhaseArmed(paneID: paneID, restoreGeneration: generation)])
    }
}

@MainActor
private final class SubmittedInputRecorder {
    private(set) var inputs: [TerminalActivitySourceInput] = []
    func record(_ input: TerminalActivitySourceInput) { inputs.append(input) }
}
