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

        let waitTask = Task { @MainActor in
            await binding.awaitBound()
            log.record("resumed")
        }
        // Let `waitTask` reach its continuation registration before this
        // test body proceeds — `awaitBound`'s body up to that point is
        // entirely synchronous, so one yield is sufficient and
        // deterministic, not a polling re-check.
        await Task.yield()
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

        let waitTask = Task { @MainActor in
            await binding.awaitBound()
        }
        await Task.yield()
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
