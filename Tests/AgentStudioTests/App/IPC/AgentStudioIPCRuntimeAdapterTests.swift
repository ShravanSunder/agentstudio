import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("AgentStudio IPC runtime adapter")
struct AgentStudioIPCRuntimeAdapterTests {
    @Test("terminal status reads registered runtime lifecycle and capabilities")
    func terminalStatusReadsRegisteredRuntimeLifecycleAndCapabilities() throws {
        let harness = RuntimeAdapterHarness()
        let pane = harness.createTerminalPane()
        let runtime = RecordingTerminalIPCRuntime(paneId: PaneId(uuid: pane.id))
        runtime.lifecycle = .created
        runtime.capabilities = [.input, .resize, .search]
        harness.runtimeRegistry.register(runtime)

        let status = try harness.adapter.terminalStatus(IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id)))

        #expect(status.paneId == pane.id)
        #expect(status.lifecycle == .created)
        #expect(status.isReady == false)
        #expect(status.backend == .local)
        #expect(status.capabilities == ["input", "resize", "search"])
    }

    @Test("terminal snapshot omits title cwd search progress and output-bearing fields")
    func terminalSnapshotOmitsSensitiveRuntimeFields() throws {
        let harness = RuntimeAdapterHarness()
        let secretCWD = URL(fileURLWithPath: "/tmp/agentstudio-terminal-secret-cwd")
        let pane = harness.createTerminalPane(
            metadata: PaneMetadata(
                launchDirectory: secretCWD,
                title: "Secret Terminal Title"
            )
        )
        let runtime = RecordingTerminalIPCRuntime(paneId: PaneId(uuid: pane.id))
        runtime.metadata = PaneMetadata(
            paneId: PaneId(uuid: pane.id),
            contentType: .terminal,
            launchDirectory: secretCWD,
            title: "Secret Terminal Title"
        )
        runtime.lastSeq = 42
        harness.runtimeRegistry.register(runtime)

        let snapshot = try harness.adapter.terminalSnapshot(IPCHandle(kind: .pane, reference: .friendlyOrdinal(1)))
        let encoded = try encodedJSONString(snapshot)

        #expect(snapshot.paneId == pane.id)
        #expect(snapshot.lastSequence == 42)
        #expect(!encoded.contains("Secret Terminal Title"))
        #expect(!encoded.contains(secretCWD.path))
        #expect(!encoded.contains("searchState"))
        #expect(!encoded.contains("progress"))
        #expect(!encoded.contains("output"))
        #expect(!encoded.contains("scrollback"))
        #expect(!encoded.contains("zmx"))
    }

    @Test("terminal send uses ActionExecutor runtime dispatch and preserves correlation id")
    func terminalSendUsesActionExecutorRuntimeDispatchAndPreservesCorrelationId() async throws {
        try await withAsyncTestAtomRegistry { _ in
            let harness = makeHarness()
            let pane = harness.store.createPane(title: "Terminal")
            let tab = Tab(paneId: pane.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            let runtime = RecordingTerminalIPCRuntime(paneId: PaneId(uuid: pane.id))
            harness.runtimeRegistry.register(runtime)
            let adapter = AgentStudioIPCRuntimeAdapter(
                workspaceStore: harness.store,
                runtimeRegistry: harness.runtimeRegistry,
                commandDispatcher: ActionExecutorRuntimeCommandDispatcher(actionExecutor: harness.executor)
            )
            let correlationId = UUID()

            let result = try await adapter.sendTerminalInput(
                to: IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id)),
                input: "echo hi\n",
                correlationId: correlationId
            )

            #expect(result.paneId == pane.id)
            #expect(result.disposition == .accepted)
            #expect(result.correlationId == correlationId)
            #expect(runtime.receivedCommands.count == 1)
            #expect(runtime.receivedCommands.first?.correlationId == correlationId)
            if case .terminal(.sendInput(let input)) = runtime.receivedCommands.first?.command {
                #expect(input == "echo hi\n")
            } else {
                Issue.record("terminal.send did not dispatch RuntimeCommand.terminal(.sendInput)")
            }
            #expect(result.commandId == runtime.receivedCommands.first?.commandId)
        }
    }

    @Test("terminal send reports missing pane as target not found")
    func terminalSendReportsMissingPaneAsTargetNotFound() async throws {
        let harness = RuntimeAdapterHarness()

        do {
            _ = try await harness.adapter.sendTerminalInput(
                to: IPCHandle(kind: .pane, reference: .canonicalUUID(UUID())),
                input: "echo hi\n",
                correlationId: nil
            )
            Issue.record("terminal.send unexpectedly succeeded for a missing pane")
        } catch let error as AppIPCRuntimeError {
            #expect(error.reason == .targetNotFound)
        }
    }

    @Test("terminal send reports missing runtime separately from missing pane")
    func terminalSendReportsMissingRuntimeSeparatelyFromMissingPane() async throws {
        let harness = RuntimeAdapterHarness()
        let pane = harness.createTerminalPane()

        do {
            _ = try await harness.adapter.sendTerminalInput(
                to: IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id)),
                input: "echo hi\n",
                correlationId: nil
            )
            Issue.record("terminal.send unexpectedly succeeded without a registered runtime")
        } catch let error as AppIPCRuntimeError {
            #expect(error.reason == .noRuntime)
        }
    }

    @Test("terminal send maps runtime not ready unsupported and backend unavailable failures")
    func terminalSendMapsRuntimeCommandFailures() async throws {
        let paneId = UUID()
        let commandId = UUID()

        try await expectTerminalSendFailure(
            paneId: paneId,
            actionResult: .failure(.runtimeNotReady(lifecycle: .created)),
            reason: .runtimeNotReady
        )
        try await expectTerminalSendFailure(
            paneId: paneId,
            actionResult: .failure(.unsupportedCommand(command: "terminal.send", required: .input)),
            reason: .unsupportedCommand
        )
        try await expectTerminalSendFailure(
            paneId: paneId,
            actionResult: .failure(.backendUnavailable(backend: "SurfaceManager")),
            reason: .backendUnavailable
        )
        try await expectTerminalSendFailure(
            paneId: paneId,
            actionResult: .failure(.timeout(commandId: commandId)),
            reason: .timeout
        )
    }

    @Test("terminal methods reject non-terminal panes and non-pane handles")
    func terminalMethodsRejectNonTerminalPanesAndNonPaneHandles() throws {
        let harness = RuntimeAdapterHarness()
        let webPane = harness.workspaceStore.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com")!)),
            metadata: PaneMetadata(title: "Web")
        )
        harness.workspaceStore.appendTab(Tab(paneId: webPane.id))

        do {
            _ = try harness.adapter.terminalStatus(IPCHandle(kind: .pane, reference: .canonicalUUID(webPane.id)))
            Issue.record("terminal.status unexpectedly accepted a web pane")
        } catch let error as AppIPCRuntimeError {
            #expect(error.reason == .unsupportedCommand)
        }

        do {
            _ = try harness.adapter.terminalStatus(IPCHandle(kind: .workspace, reference: .friendlyOrdinal(1)))
            Issue.record("terminal.status unexpectedly accepted a workspace handle")
        } catch let error as AppIPCRuntimeError {
            #expect(error.reason == .validationRejected)
        }
    }

    private func expectTerminalSendFailure(
        paneId _: UUID,
        actionResult: ActionResult,
        reason: AppIPCRuntimeError.Reason
    ) async throws {
        let harness = RuntimeAdapterHarness(commandDispatcher: StaticRuntimeCommandDispatcher(result: actionResult))
        let pane = harness.createTerminalPane()
        harness.runtimeRegistry.register(RecordingTerminalIPCRuntime(paneId: PaneId(uuid: pane.id)))

        do {
            _ = try await harness.adapter.sendTerminalInput(
                to: IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id)),
                input: "echo hi\n",
                correlationId: nil
            )
            Issue.record("terminal.send unexpectedly succeeded for \(reason)")
        } catch let error as AppIPCRuntimeError {
            #expect(error.reason == reason)
        }
    }
}

@MainActor
private struct RuntimeAdapterHarness {
    let workspaceStore: WorkspaceStore
    let runtimeRegistry: RuntimeRegistry
    let adapter: AgentStudioIPCRuntimeAdapter

    init(
        commandDispatcher: any AppIPCRuntimeCommandDispatching = StaticRuntimeCommandDispatcher(
            result: .success(commandId: UUID()))
    ) {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-ipc-runtime-adapter-\(UUID().uuidString)")
        workspaceStore = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        runtimeRegistry = RuntimeRegistry()
        adapter = AgentStudioIPCRuntimeAdapter(
            workspaceStore: workspaceStore,
            runtimeRegistry: runtimeRegistry,
            commandDispatcher: commandDispatcher
        )
    }

    func createTerminalPane(metadata: PaneMetadata = PaneMetadata(title: "Terminal")) -> Pane {
        let pane = workspaceStore.createPane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .temporary)),
            metadata: metadata
        )
        workspaceStore.appendTab(Tab(paneId: pane.id))
        workspaceStore.setActiveTab(workspaceStore.tabs[0].id)
        return pane
    }
}

@MainActor
private struct StaticRuntimeCommandDispatcher: AppIPCRuntimeCommandDispatching {
    let result: ActionResult

    func dispatchRuntimeCommand(
        _ command: RuntimeCommand,
        target: RuntimeCommandTarget,
        correlationId: UUID?
    ) async -> ActionResult {
        result
    }
}

@MainActor
private final class RecordingTerminalIPCRuntime: PaneRuntime {
    let paneId: PaneId
    var metadata: PaneMetadata
    var lifecycle: PaneRuntimeLifecycle = .ready
    var capabilities: Set<PaneCapability> = [.input, .resize, .search]
    var lastSeq: UInt64 = 0
    private(set) var receivedCommands: [RuntimeCommandEnvelope] = []

    private let stream: AsyncStream<RuntimeEnvelope>
    private let continuation: AsyncStream<RuntimeEnvelope>.Continuation

    init(paneId: PaneId) {
        self.paneId = paneId
        self.metadata = PaneMetadata(paneId: paneId, contentType: .terminal, title: "Terminal")
        let (stream, continuation) = AsyncStream.makeStream(of: RuntimeEnvelope.self)
        self.stream = stream
        self.continuation = continuation
    }

    func handleCommand(_ envelope: RuntimeCommandEnvelope) async -> ActionResult {
        receivedCommands.append(envelope)
        return .success(commandId: envelope.commandId)
    }

    func subscribe() -> AsyncStream<RuntimeEnvelope> {
        stream
    }

    func snapshot() -> PaneRuntimeSnapshot {
        PaneRuntimeSnapshot(
            paneId: paneId,
            metadata: metadata,
            lifecycle: lifecycle,
            capabilities: capabilities,
            lastSeq: lastSeq,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    func eventsSince(seq: UInt64) async -> EventReplayBuffer.ReplayResult {
        EventReplayBuffer.ReplayResult(events: [], nextSeq: seq, gapDetected: false)
    }

    func shutdown(timeout: Duration) async -> [UUID] {
        continuation.finish()
        return []
    }
}

private func encodedJSONString<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder().encode(value)
    return try #require(String(data: data, encoding: .utf8))
}
