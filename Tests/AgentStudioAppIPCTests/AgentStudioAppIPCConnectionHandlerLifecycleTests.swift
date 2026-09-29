import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

/// `joinConnectionHandlers()` is the completion contract `AppDelegate`'s
/// production shutdown path relies on: it must not return while a connection
/// handler is still doing real work, and it must leave nothing tracked once
/// it does.
@Suite("App IPC connection handler lifecycle")
struct AgentStudioAppIPCConnectionHandlerLifecycleTests {
    @Test("joinConnectionHandlers waits for a handler held inside a request, then clears its entry")
    func joinWaitsForAHeldHandlerThenClearsItsEntry() async throws {
        let paneId = UUID()
        let port = SuspendingTerminalWaitPort()
        let fixture = try LiveServerFixture(
            accessMode: .unsafeDebug,
            channel: .debug,
            panes: [makePaneSummary(id: paneId, ordinal: 1)],
            runtimePort: port
        )
        defer { fixture.cleanup() }
        try fixture.server.start()

        // Sent from its own Task, off the cooperative pool: this request
        // parks inside the port until cancellation reaches it, so it must
        // not block the test's own async execution while it's held.
        let heldRequest = Task {
            try await sendRequestWithoutBlockingCooperativePool(
                socketPath: fixture.paths.socketURL.path,
                request: JSONRPCClientRequest(
                    id: .number(1),
                    method: "terminal.wait",
                    params: .object([
                        "handle": .string("pane:1"),
                        "condition": .string(IPCTerminalWaitCondition.commandFinished.rawValue),
                        "timeoutSeconds": .number(60),
                    ])
                )
            )
        }

        // Event-driven: waits for the port to have genuinely parked a
        // continuation, not for a fixed duration. Asserts on what the wait
        // itself observed (a genuine entry, not one already recorded before
        // this call), not on a second, later read.
        let handlerHadToPark = await port.waitUntilEntered()
        #expect(handlerHadToPark)
        #expect(fixture.server.trackedConnectionHandlerCount == 1)

        await fixture.server.joinConnectionHandlers()

        #expect(port.observedCancellation)
        #expect(fixture.server.trackedConnectionHandlerCount == 0)

        // Nothing left to cancel or await: a second join is a no-op over an
        // empty tracked set.
        await fixture.server.joinConnectionHandlers()
        #expect(fixture.server.trackedConnectionHandlerCount == 0)

        _ = try? await heldRequest.value
    }
}

/// A runtime port whose `waitForTerminal` parks on a continuation until the
/// awaiting task is cancelled, so a `terminal.wait` request can hold a
/// connection handler open on command. Unlike the production runtime
/// adapter's own `waitForTerminal` (bounded only by its own timeout, not by
/// task cancellation — see the accompanying report), this fake is explicitly
/// cancellation-aware, so it proves `joinConnectionHandlers()`'s own
/// cancel-then-await mechanism in isolation.
final class SuspendingTerminalWaitPort: AppIPCRuntimePort, @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var pendingWaitContinuation: CheckedContinuation<IPCTerminalWaitResult, Error>?
    nonisolated(unsafe) private var entrySignalContinuation: CheckedContinuation<Bool, Never>?
    nonisolated(unsafe) private var hasEntered = false
    nonisolated(unsafe) private var cancelled = false

    nonisolated init() {}

    nonisolated var observedCancellation: Bool {
        lock.withLock { cancelled }
    }

    /// Suspends until `waitForTerminal` has stored its continuation — the
    /// request has genuinely reached and parked inside this port, not merely
    /// been dispatched to the connection handler. Returns `true` when this
    /// call itself observed that entry (the normal case); `false` if entry
    /// had already happened before this call, so a caller asserts on the
    /// wait's own observation rather than a second, later read.
    nonisolated func waitUntilEntered() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let alreadyEntered = lock.withLock { () -> Bool in
                if hasEntered { return true }
                entrySignalContinuation = continuation
                return false
            }
            if alreadyEntered {
                continuation.resume(returning: false)
            }
        }
    }

    nonisolated private func markEntered() {
        let waitingSignal = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            hasEntered = true
            let signal = entrySignalContinuation
            entrySignalContinuation = nil
            return signal
        }
        waitingSignal?.resume(returning: true)
    }

    nonisolated func terminalStatus(_: IPCHandle, ownPaneAssertion _: AppIPCOwnPaneAssertion?) throws
        -> IPCTerminalStatusResult
    {
        throw AppIPCRuntimeError(reason: .noRuntime)
    }

    nonisolated func terminalSnapshot(_: IPCHandle, ownPaneAssertion _: AppIPCOwnPaneAssertion?) throws
        -> IPCTerminalSnapshotResult
    {
        throw AppIPCRuntimeError(reason: .noRuntime)
    }

    nonisolated func sendTerminalInput(
        to _: IPCHandle,
        input _: String,
        correlationId _: UUID?,
        ownPaneAssertion _: AppIPCOwnPaneAssertion?
    ) async throws -> IPCTerminalSendInputResult {
        throw AppIPCRuntimeError(reason: .noRuntime)
    }

    nonisolated func waitForTerminal(
        _: IPCHandle,
        condition _: IPCTerminalWaitCondition,
        timeout _: Duration,
        afterSequence _: UInt64?,
        ownPaneAssertion _: AppIPCOwnPaneAssertion?
    ) async throws -> IPCTerminalWaitResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { pendingWaitContinuation = continuation }
                markEntered()
            }
        } onCancel: {
            let pending = lock.withLock { () -> CheckedContinuation<IPCTerminalWaitResult, Error>? in
                cancelled = true
                let continuation = pendingWaitContinuation
                pendingWaitContinuation = nil
                return continuation
            }
            pending?.resume(throwing: CancellationError())
        }
    }
}
