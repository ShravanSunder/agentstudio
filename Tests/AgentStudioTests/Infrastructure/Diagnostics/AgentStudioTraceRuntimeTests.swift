import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioTraceRuntimeTests {
    @Test
    func disabledRuntimeDoesNotEvaluateAttributes() async throws {
        let evaluationFlag = AttributeEvaluationFlag()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [:]),
            processIdentifier: 123,
            timeUnixNano: { 1 }
        )

        try await runtime.record(
            tag: .drag,
            body: "drag.begin",
            attributes: [
                "side.effect": .bool(evaluationFlag.markEvaluated())
            ]
        )

        #expect(!runtime.isEnabled)
        #expect(runtime.outputFileURL == nil)
        #expect(!evaluationFlag.didEvaluate)
    }

    @Test
    func enabledRuntimeWritesTaggedRecord() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "drag-run",
                "AGENTSTUDIO_TRACE_TAGS": "drag",
            ]),
            processIdentifier: 456,
            serviceVersion: "test-version",
            timeUnixNano: { 42 }
        )

        try await runtime.record(
            tag: .drag,
            body: "drag.begin",
            traceID: "trace-1",
            spanID: "span-1",
            attributes: [
                "drag.session_id": .string("session-1")
            ]
        )
        try await runtime.flush()

        let outputFileURL = try #require(runtime.outputFileURL)
        let lines = try String(contentsOf: outputFileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        #expect(runtime.isEnabled(.drag))
        #expect(lines.count == 1)
        #expect(lines[0].contains("\"body\":\"drag.begin\""))
        #expect(lines[0].contains("\"time_unix_nano\":42"))
        #expect(lines[0].contains("\"trace_id\":\"trace-1\""))
        #expect(lines[0].contains("\"span_id\":\"span-1\""))
        #expect(lines[0].contains("\"agentstudio.trace.tag\":\"drag\""))
        #expect(lines[0].contains("\"drag.session_id\":\"session-1\""))
        #expect(lines[0].contains("\"process.pid\":\"456\""))
        #expect(lines[0].contains("\"service.version\":\"test-version\""))
        #expect(outputFileURL.lastPathComponent == "agentstudio-drag-run-456.jsonl")
    }

    @Test
    func enabledRuntimeSkipsDisabledTags() async throws {
        let evaluationFlag = AttributeEvaluationFlag()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_TAGS": "drag",
            ]),
            processIdentifier: 789,
            timeUnixNano: { 1 }
        )

        try await runtime.record(
            tag: .eventbus,
            body: "eventbus.deliver",
            attributes: [
                "side.effect": .bool(evaluationFlag.markEvaluated())
            ]
        )
        try await runtime.flush()

        let outputFileURL = try #require(runtime.outputFileURL)
        #expect(!FileManager.default.fileExists(atPath: outputFileURL.path))
        #expect(!evaluationFlag.didEvaluate)
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-trace-runtime-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private final class AttributeEvaluationFlag: @unchecked Sendable {
        private(set) var didEvaluate = false

        func markEvaluated() -> Bool {
            didEvaluate = true
            return true
        }
    }
}
