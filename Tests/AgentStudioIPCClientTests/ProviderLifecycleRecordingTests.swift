import AgentStudioCLIStore
import AgentStudioPrimitives
import AgentStudioProgrammaticControl
import AgentStudioTestHarness
import Foundation
import Synchronization
import Testing

@testable import AgentStudioIPCClientCore

@Suite("Provider lifecycle write before send")
struct ProviderLifecycleRecordingTests {
    @Test("Codex commits its exact envelope before live delivery", arguments: ["SessionStart", "SessionEnd"])
    func codexWritesBeforeDelivery(eventName: String) async throws {
        let observed = try await valueFromDedicatedThread {
            let fixture = try LifecycleHookFileFixture()
            defer { fixture.remove() }
            let writer = try CLIStore.openWriter(url: fixture.storeURL, channel: .debug).get()
            let deliveries = Mutex<[LifecycleHookDeliveryObservation]>([])
            let result = ProviderHookInvocation.runCodexHook(
                .init(
                    eventName: eventName, environment: fixture.environment,
                    standardInput: { fixture.payload(eventName: eventName) }, correlationIdProvider: UUIDv7.generate,
                    delivery: .init { params, _ in
                        let rows = try CLIStore.openReader(url: fixture.storeURL, expectedChannel: .debug).get()
                            .readLifecycleReports(after: 0).get().reports
                        deliveries.withLock { $0.append(.init(params: params, rowsAtSend: rows)) }
                    }, standardErrorSink: { _ in }))
            return (result, writer.identity.storeID, fixture.paneID, deliveries.withLock { $0 })
        }
        #expect(observed.0 == 0)
        let delivery = try #require(observed.3.first)
        #expect(observed.3.count == 1)
        let report = try #require(delivery.rowsAtSend.first)
        #expect(delivery.rowsAtSend.count == 1)
        #expect(report.record.reportID == delivery.params.event.occurrenceId)
        #expect(report.record.correlationID == delivery.params.correlationId)
        #expect(report.record.paneID == observed.2)
        #expect(report.record.conversationID == delivery.params.event.conversationId)
        #expect(delivery.params.lifecycleReport == .init(storeId: observed.1, sequence: report.sequence))
        #expect(
            report.record.event == (eventName == "SessionStart" ? .sessionStart : .sessionEnd(reason: "private reason"))
        )
    }

    @Test(
        "Claude records even when the subsequent live socket delivery is unavailable",
        arguments: ["SessionStart", "SessionEnd"])
    func claudeRecordsBeforeFailedSend(eventName: String) async throws {
        let observed = try await valueFromDedicatedThread {
            let fixture = try LifecycleHookFileFixture()
            defer { fixture.remove() }
            _ = try CLIStore.openWriter(url: fixture.storeURL, channel: .debug).get()
            let occurrence = UUIDv7.generate()
            let diagnostics = Mutex<[String]>([])
            let code = ClaudeCodeHookInvocation.handle(
                .init(
                    arguments: ["hook", "claude", eventName], environment: fixture.environment,
                    standardInput: { fixture.payload(eventName: eventName) }, identifierGenerator: { occurrence },
                    diagnosticSink: { line in diagnostics.withLock { $0.append(line) } }))
            let rows = try CLIStore.openReader(url: fixture.storeURL, expectedChannel: .debug).get()
                .readLifecycleReports(after: 0).get().reports
            return (code, occurrence, rows, diagnostics.withLock { $0 })
        }
        #expect(observed.0 == 0)
        #expect(observed.2.count == 1)
        #expect(observed.2.first?.record.reportID == observed.1)
        #expect(!observed.3.joined().contains("private reason"))
    }

    @Test("store unavailability sends live once without a sequence and diagnostics contain no raw payload")
    func unavailableStoreDoesNotSuppressLiveHook() async throws {
        let observed = try await valueFromDedicatedThread {
            let fixture = try LifecycleHookFileFixture()
            defer { fixture.remove() }
            var environment = fixture.environment
            environment["AGENTSTUDIO_CLI_STORE"] = fixture.rootURL.path  // a directory, never a database
            let sent = Mutex<[IPCSessionEventParams]>([])
            let diagnostics = Mutex<[String]>([])
            let code = ProviderHookInvocation.runCodexHook(
                .init(
                    eventName: "SessionEnd", environment: environment,
                    standardInput: { fixture.payload(eventName: "SessionEnd") }, correlationIdProvider: UUIDv7.generate,
                    delivery: .init { params, _ in sent.withLock { $0.append(params) } },
                    standardErrorSink: { text in diagnostics.withLock { $0.append(text) } }))
            return (code, sent.withLock { $0 }, diagnostics.withLock { $0 })
        }
        #expect(observed.0 == 0)
        #expect(observed.1.count == 1)
        #expect(observed.1.first?.lifecycleReport == nil)
        #expect(!observed.2.joined().contains("private reason"))
    }

    @Test("activity hooks never create lifecycle reports", arguments: ["UserPromptSubmit", "Stop", "PreToolUse"])
    func activityHookIsNeverRecorded(eventName: String) async throws {
        let rows = try await valueFromDedicatedThread {
            let fixture = try LifecycleHookFileFixture()
            defer { fixture.remove() }
            _ = try CLIStore.openWriter(url: fixture.storeURL, channel: .debug).get()
            _ = ProviderHookInvocation.runCodexHook(
                .init(
                    eventName: eventName, environment: fixture.environment,
                    standardInput: { fixture.payload(eventName: eventName) }, correlationIdProvider: UUIDv7.generate,
                    delivery: .init { _, _ in }, standardErrorSink: { _ in }))
            return try CLIStore.openReader(url: fixture.storeURL, expectedChannel: .debug).get()
                .readLifecycleReports(after: 0).get().reports
        }
        #expect(rows.isEmpty)
    }
}

private struct LifecycleHookDeliveryObservation: Sendable {
    let params: IPCSessionEventParams
    let rowsAtSend: [CLILifecycleReport]
}

private struct LifecycleHookFileFixture: Sendable {
    let rootURL: URL
    let storeURL: URL
    let paneID = UUIDv7.generate()
    let sessionID = UUIDv7.generate().uuidString
    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appending(path: "hook-report-\(UUIDv7.generate())")
        storeURL = rootURL.appending(path: "cli.sqlite")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }
    var environment: [String: String] {
        [
            "AGENTSTUDIO_CLI_STORE": storeURL.path, "AGENTSTUDIO_CLI_STORE_CHANNEL": "debug",
            "AGENTSTUDIO_PANE_ID": paneID.uuidString, "AGENTSTUDIO_PANE_TOKEN": "test-pane-token",
            "AGENTSTUDIO_IPC_SOCKET": rootURL.appending(path: "missing.sock").path,
            "AGENTSTUDIO_CLI": "/unused/agentstudio",
        ]
    }
    func payload(eventName: String) -> Data {
        Data(
            """
            {"session_id":"\(sessionID)","hook_event_name":"\(eventName)","reason":"private reason",
             "turn_id":"turn-1","prompt_id":"turn-1","tool_use_id":"tool-1","tool_name":"shell"}
            """.utf8)
    }
    func remove() { try? FileManager.default.removeItem(at: rootURL) }
}
