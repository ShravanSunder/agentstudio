import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio

private let schedulerStressIPCWaitTimeout: Duration = .seconds(30)

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

    @Test("terminal snapshot maps runtime-owned health facts")
    func terminalSnapshotMapsRuntimeOwnedHealthFacts() throws {
        let harness = RuntimeAdapterHarness()
        let pane = harness.createTerminalPane()
        let runtime = RecordingTerminalIPCRuntime(paneId: PaneId(uuid: pane.id))
        runtime.terminalSnapshotFacts = TerminalRuntimeSnapshotFacts(
            rendererHealthy: true,
            readOnly: false,
            secureInput: true
        )
        harness.runtimeRegistry.register(runtime)

        let snapshot = try harness.adapter.terminalSnapshot(IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id)))

        #expect(snapshot.rendererHealthy == true)
        #expect(snapshot.readOnly == false)
        #expect(snapshot.secureInput == true)
    }

    @Test("terminal send uses runtime dispatcher and preserves correlation id")
    func terminalSendUsesRuntimeDispatcherAndPreservesCorrelationId() async throws {
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
                commandDispatcher: harness.coordinator
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
                Issue.record("terminal.send did not dispatch PaneRuntimeCommand.terminal(.sendInput)")
            }
            #expect(result.commandId == runtime.receivedCommands.first?.commandId)
        }
    }

    @Test("runtime IPC composition does not depend on action executor dispatch")
    func runtimeIPCCompositionDoesNotDependOnActionExecutorDispatch() throws {
        let source = try Self.projectSource(
            "Sources/AgentStudio/App/IPCComposition/AgentStudioIPCRuntimeAdapter.swift"
        )

        #expect(!source.contains("ActionExecutorRuntimeCommandDispatcher"))
        #expect(!source.contains("workspaceActionExecutor.dispatchRuntimeCommand"))
    }

    @Test("runtime IPC snapshots do not downcast to concrete terminal runtime")
    func runtimeIPCSnapshotsDoNotDowncastToConcreteTerminalRuntime() throws {
        let source = try Self.projectSource(
            "Sources/AgentStudio/App/IPCComposition/AgentStudioIPCRuntimeAdapter.swift"
        )

        #expect(!source.contains("as? TerminalRuntime"))
        #expect(!source.contains("as! TerminalRuntime"))
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
                timeout: schedulerStressIPCWaitTimeout
            )
        }
        await runtime.waitForSubscriptionCount(atLeast: 1)
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
                timeout: schedulerStressIPCWaitTimeout,
                afterSequence: 10
            )
        }
        await Task.yield()
        await runtime.waitForSubscriptionCount(atLeast: 1)
        await runtime.waitForReplayCallCount(atLeast: 1)
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
        commandDispatcher: any PaneRuntimeCommandDispatching = StaticRuntimeCommandDispatcher(
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

extension AgentStudioIPCRuntimeAdapterTests {
    private static func projectSource(_ relativePath: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try String(contentsOf: projectRoot.appending(path: relativePath), encoding: .utf8)
    }
}

@MainActor
private struct StaticRuntimeCommandDispatcher: PaneRuntimeCommandDispatching {
    let result: ActionResult

    func dispatchRuntimeCommand(
        _ command: PaneRuntimeCommand,
        target: RuntimeCommandTarget,
        correlationId: UUID?
    ) async -> ActionResult {
        result
    }
}

@MainActor
private final class RecordingTerminalIPCRuntime: TerminalRuntimeSnapshotFactProviding {
    let paneId: PaneId
    var metadata: PaneMetadata
    var lifecycle: PaneRuntimeLifecycle = .ready
    var capabilities: Set<PaneCapability> = [.input, .resize, .search]
    var lastSeq: UInt64 = 0
    var terminalSnapshotFacts: TerminalRuntimeSnapshotFacts?
    var replayEvents: [RuntimeEnvelope] = []
    var replayGapDetected = false
    private(set) var receivedCommands: [RuntimeCommandEnvelope] = []

    private var liveContinuations: [UUID: AsyncStream<RuntimeEnvelope>.Continuation] = [:]
    private var subscriptionCount = 0
    private var subscriptionWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var replayCallCount = 0
    private var replayCallWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(paneId: PaneId) {
        self.paneId = paneId
        self.metadata = PaneMetadata(paneId: paneId, contentType: .terminal, title: "Terminal")
    }

    func handleCommand(_ envelope: RuntimeCommandEnvelope) async -> ActionResult {
        receivedCommands.append(envelope)
        return .success(commandId: envelope.commandId)
    }

    func subscribe() -> AsyncStream<RuntimeEnvelope> {
        subscriptionCount += 1
        resumeSatisfiedSubscriptionWaiters()
        let subscriptionId = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: RuntimeEnvelope.self)
        liveContinuations[subscriptionId] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.liveContinuations.removeValue(forKey: subscriptionId)
            }
        }
        return stream
    }

    func emit(_ envelope: RuntimeEnvelope) {
        for continuation in liveContinuations.values {
            continuation.yield(envelope)
        }
    }

    func waitForSubscriptionCount(atLeast count: Int) async {
        if subscriptionCount >= count { return }
        await withCheckedContinuation { continuation in
            subscriptionWaiters.append((count: count, continuation: continuation))
        }
    }

    func waitForReplayCallCount(atLeast count: Int) async {
        if replayCallCount >= count { return }
        await withCheckedContinuation { continuation in
            replayCallWaiters.append((count: count, continuation: continuation))
        }
    }

    private func resumeSatisfiedSubscriptionWaiters() {
        var remainingWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        var satisfiedWaiters: [CheckedContinuation<Void, Never>] = []
        for waiter in subscriptionWaiters {
            if subscriptionCount >= waiter.count {
                satisfiedWaiters.append(waiter.continuation)
            } else {
                remainingWaiters.append(waiter)
            }
        }
        subscriptionWaiters = remainingWaiters
        for continuation in satisfiedWaiters {
            continuation.resume()
        }
    }

    private func resumeSatisfiedReplayCallWaiters() {
        var remainingWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        var satisfiedWaiters: [CheckedContinuation<Void, Never>] = []
        for waiter in replayCallWaiters {
            if replayCallCount >= waiter.count {
                satisfiedWaiters.append(waiter.continuation)
            } else {
                remainingWaiters.append(waiter)
            }
        }
        replayCallWaiters = remainingWaiters
        for continuation in satisfiedWaiters {
            continuation.resume()
        }
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

    func terminalRuntimeSnapshotFacts() -> TerminalRuntimeSnapshotFacts {
        terminalSnapshotFacts
            ?? TerminalRuntimeSnapshotFacts(
                rendererHealthy: nil,
                readOnly: nil,
                secureInput: nil
            )
    }

    func eventsSince(seq: UInt64) async -> EventReplayBuffer.ReplayResult {
        replayCallCount += 1
        resumeSatisfiedReplayCallWaiters()
        let events = replayEvents.filter { $0.seq > seq }
        return EventReplayBuffer.ReplayResult(
            events: events,
            nextSeq: events.last?.seq ?? seq,
            gapDetected: replayGapDetected
        )
    }

    func shutdown(timeout: Duration) async -> [UUID] {
        for continuation in liveContinuations.values {
            continuation.finish()
        }
        liveContinuations.removeAll()
        return []
    }
}

private func encodedJSONString<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder().encode(value)
    return try #require(String(data: data, encoding: .utf8))
}
