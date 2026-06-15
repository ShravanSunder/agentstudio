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

    @Test("terminal wait attachReady resolves from ready runtime lifecycle")
    func terminalWaitAttachReadyResolvesFromReadyRuntimeLifecycle() async throws {
        let harness = RuntimeAdapterHarness()
        let pane = harness.createTerminalPane()
        harness.runtimeRegistry.register(RecordingTerminalIPCRuntime(paneId: PaneId(uuid: pane.id)))

        let result = try await harness.adapter.waitForTerminal(
            IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id)),
            condition: .attachReady,
            timeout: .milliseconds(1)
        )

        #expect(result.paneId == pane.id)
        #expect(result.condition == .attachReady)
        #expect(result.eventName == .terminalAttachReady)
    }

    @Test("terminal wait attachReady resolves when runtime becomes ready after wait starts")
    func terminalWaitAttachReadyResolvesAfterRuntimeBecomesReady() async throws {
        let harness = RuntimeAdapterHarness()
        let pane = harness.createTerminalPane()
        let runtime = RecordingTerminalIPCRuntime(paneId: PaneId(uuid: pane.id))
        runtime.lifecycle = .created
        harness.runtimeRegistry.register(runtime)

        let waitTask = Task {
            try await harness.adapter.waitForTerminal(
                IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id)),
                condition: .attachReady,
                timeout: .seconds(1)
            )
        }
        await Task.yield()
        runtime.lifecycle = .ready

        let result = try await waitTask.value
        #expect(result.paneId == pane.id)
        #expect(result.condition == .attachReady)
        #expect(result.eventName == .terminalAttachReady)
    }

    @Test("terminal wait commandFinished resolves from pane runtime event")
    func terminalWaitCommandFinishedResolvesFromPaneRuntimeEvent() async throws {
        let harness = RuntimeAdapterHarness()
        let pane = harness.createTerminalPane()
        let paneId = PaneId(uuid: pane.id)
        let runtime = RecordingTerminalIPCRuntime(paneId: paneId)
        harness.runtimeRegistry.register(runtime)
        let commandId = UUID()
        let correlationId = UUID()

        let waitTask = Task {
            try await harness.adapter.waitForTerminal(
                IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id)),
                condition: .commandFinished,
                timeout: .milliseconds(100)
            )
        }
        runtime.emit(
            RuntimeEnvelope.pane(
                PaneEnvelope(
                    source: .pane(paneId),
                    seq: 1,
                    timestamp: ContinuousClock.now,
                    correlationId: correlationId,
                    commandId: commandId,
                    paneId: paneId,
                    paneKind: .terminal,
                    event: .terminal(.commandFinished(exitCode: 7, duration: 42))
                )
            )
        )

        let result = try await waitTask.value
        #expect(result.paneId == pane.id)
        #expect(result.condition == .commandFinished)
        #expect(result.eventName == .terminalCommandFinished)
        #expect(result.commandId == commandId)
        #expect(result.correlationId == correlationId)
        #expect(result.exitCode == 7)
        #expect(result.duration == 42)
    }

    @Test("terminal wait commandFinished replays events after requested runtime sequence")
    func terminalWaitCommandFinishedReplaysEventsAfterRequestedRuntimeSequence() async throws {
        let harness = RuntimeAdapterHarness()
        let pane = harness.createTerminalPane()
        let paneId = PaneId(uuid: pane.id)
        let runtime = RecordingTerminalIPCRuntime(paneId: paneId)
        let commandId = UUID()
        let correlationId = UUID()
        runtime.replayEvents = [
            RuntimeEnvelope.pane(
                PaneEnvelope(
                    source: .pane(paneId),
                    seq: 2,
                    timestamp: ContinuousClock.now,
                    correlationId: correlationId,
                    commandId: commandId,
                    paneId: paneId,
                    paneKind: .terminal,
                    event: .terminal(.commandFinished(exitCode: 0, duration: 12))
                )
            )
        ]
        harness.runtimeRegistry.register(runtime)

        let result = try await harness.adapter.waitForTerminal(
            IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id)),
            condition: .commandFinished,
            timeout: .milliseconds(1),
            afterSequence: 1
        )

        #expect(result.paneId == pane.id)
        #expect(result.condition == .commandFinished)
        #expect(result.eventName == .terminalCommandFinished)
        #expect(result.commandId == commandId)
        #expect(result.correlationId == correlationId)
        #expect(result.exitCode == 0)
        #expect(result.duration == 12)
    }

    @Test("terminal wait ignores live events at or before requested runtime sequence")
    func terminalWaitIgnoresLiveEventsAtOrBeforeRequestedRuntimeSequence() async throws {
        let harness = RuntimeAdapterHarness()
        let pane = harness.createTerminalPane()
        let paneId = PaneId(uuid: pane.id)
        let runtime = RecordingTerminalIPCRuntime(paneId: paneId)
        harness.runtimeRegistry.register(runtime)
        let expectedCommandId = UUID()

        let waitTask = Task {
            try await harness.adapter.waitForTerminal(
                IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id)),
                condition: .titleChanged,
                timeout: .seconds(1),
                afterSequence: 10
            )
        }
        await Task.yield()
        runtime.emit(
            RuntimeEnvelope.pane(
                PaneEnvelope(
                    source: .pane(paneId),
                    seq: 10,
                    timestamp: ContinuousClock.now,
                    correlationId: nil,
                    commandId: nil,
                    paneId: paneId,
                    paneKind: .terminal,
                    event: .terminal(.titleChanged("stale"))
                )
            )
        )
        runtime.emit(
            RuntimeEnvelope.pane(
                PaneEnvelope(
                    source: .pane(paneId),
                    seq: 11,
                    timestamp: ContinuousClock.now,
                    correlationId: nil,
                    commandId: expectedCommandId,
                    paneId: paneId,
                    paneKind: .terminal,
                    event: .terminal(.titleChanged("fresh"))
                )
            )
        )

        let result = try await waitTask.value
        #expect(result.paneId == pane.id)
        #expect(result.condition == .titleChanged)
        #expect(result.eventName == .terminalTitleChanged)
        #expect(result.commandId == expectedCommandId)
    }

    @Test("terminal wait fails fast when after sequence replay has a gap")
    func terminalWaitFailsFastWhenAfterSequenceReplayHasGap() async throws {
        let harness = RuntimeAdapterHarness()
        let pane = harness.createTerminalPane()
        let runtime = RecordingTerminalIPCRuntime(paneId: PaneId(uuid: pane.id))
        runtime.replayGapDetected = true
        harness.runtimeRegistry.register(runtime)

        do {
            _ = try await harness.adapter.waitForTerminal(
                IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id)),
                condition: .commandFinished,
                timeout: .seconds(1),
                afterSequence: 1
            )
            Issue.record("terminal.wait unexpectedly succeeded with a replay gap")
        } catch let error as AppIPCRuntimeError {
            #expect(error.reason == .replayGap)
        }
    }

    @Test("terminal wait times out when no exported fact matches")
    func terminalWaitTimesOutWhenNoExportedFactMatches() async throws {
        let eventBus = makeTestPaneRuntimeEventBus()
        let harness = RuntimeAdapterHarness(eventBus: eventBus)
        let pane = harness.createTerminalPane()
        harness.runtimeRegistry.register(RecordingTerminalIPCRuntime(paneId: PaneId(uuid: pane.id)))

        do {
            _ = try await harness.adapter.waitForTerminal(
                IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id)),
                condition: .commandFinished,
                timeout: .milliseconds(1)
            )
            Issue.record("terminal.wait unexpectedly succeeded without a matching event")
        } catch let error as AppIPCRuntimeError {
            #expect(error.reason == .timeout)
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
            result: .success(commandId: UUID())),
        eventBus: EventBus<RuntimeEnvelope> = makeTestPaneRuntimeEventBus()
    ) {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-ipc-runtime-adapter-\(UUID().uuidString)")
        workspaceStore = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        runtimeRegistry = RuntimeRegistry()
        adapter = AgentStudioIPCRuntimeAdapter(
            workspaceStore: workspaceStore,
            runtimeRegistry: runtimeRegistry,
            commandDispatcher: commandDispatcher,
            eventBus: eventBus
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
    var replayEvents: [RuntimeEnvelope] = []
    var replayGapDetected = false
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

    func emit(_ envelope: RuntimeEnvelope) {
        continuation.yield(envelope)
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
        let events = replayEvents.filter { $0.seq > seq }
        return EventReplayBuffer.ReplayResult(
            events: events,
            nextSeq: events.last?.seq ?? seq,
            gapDetected: replayGapDetected
        )
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
