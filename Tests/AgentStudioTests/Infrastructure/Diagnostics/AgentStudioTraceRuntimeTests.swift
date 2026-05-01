import Foundation
@_spi(Testing) import InMemoryTracing
import Instrumentation
import Testing
import Tracing

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

        await runtime.record(
            tag: .runtime,
            body: "runtime.event",
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
                "AGENTSTUDIO_TRACE_NAME": "runtime-run",
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
            ]),
            processIdentifier: 456,
            serviceVersion: "test-version",
            sessionID: "session-1",
            timeUnixNano: { 42 }
        )

        await runtime.record(
            tag: .runtime,
            body: "runtime.event",
            traceID: "trace-1",
            spanID: "span-1",
            attributes: [
                "agentstudio.runtime.source": .string("terminal")
            ]
        )
        try await runtime.flush()

        let outputFileURL = try #require(runtime.outputFileURL)
        let lines = try String(contentsOf: outputFileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        #expect(runtime.isEnabled(.runtime))
        #expect(lines.count == 1)
        #expect(lines[0].contains("\"body\":\"runtime.event\""))
        #expect(lines[0].contains("\"time_unix_nano\":42"))
        #expect(lines[0].contains("\"trace_id\":\"trace-1\""))
        #expect(lines[0].contains("\"span_id\":\"span-1\""))
        #expect(lines[0].contains("\"agentstudio.trace.tag\":\"runtime\""))
        #expect(lines[0].contains("\"agentstudio.runtime.source\":\"terminal\""))
        #expect(lines[0].contains("\"agentstudio.session.id\":\"session-1\""))
        #expect(lines[0].contains("\"process.pid\":\"456\""))
        #expect(lines[0].contains("\"service.version\":\"test-version\""))
        #expect(outputFileURL.lastPathComponent == "agentstudio-runtime-run-456.jsonl")
    }

    @Test
    func enabledRuntimeSkipsDisabledTags() async throws {
        let evaluationFlag = AttributeEvaluationFlag()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
            ]),
            processIdentifier: 789,
            timeUnixNano: { 1 }
        )

        await runtime.record(
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

    @Test
    func recordCopiesServiceContextCorrelationIDIntoAttributes() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
            ]),
            processIdentifier: 321,
            timeUnixNano: { 99 }
        )
        var context = ServiceContext.topLevel
        context.agentStudioCorrelationID = "runtime-flow-1"

        await ServiceContext.withValue(context) {
            await runtime.record(tag: .runtime, body: "runtime.update")
        }
        try await runtime.flush()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"agentstudio.correlation_id\":\"runtime-flow-1\""))
    }

    @Test
    func immediateFlushWritesWithoutExplicitFlush() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_FLUSH": "immediate",
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
            ]),
            processIdentifier: 654,
            timeUnixNano: { 101 }
        )

        await runtime.record(tag: .runtime, body: "runtime.immediate")

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"runtime.immediate\""))
    }

    @Test
    func concurrentEmissionWritesUncorruptedJsonLines() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_TAGS": "eventbus",
            ]),
            processIdentifier: 987,
            timeUnixNano: { 202 }
        )

        await withTaskGroup(of: Void.self) { group in
            for sequence in 0..<50 {
                group.addTask {
                    await runtime.record(
                        tag: .eventbus,
                        body: "eventbus.concurrent",
                        attributes: ["agentstudio.eventbus.sequence": .int(sequence)]
                    )
                }
            }
        }
        try await runtime.flush()

        let outputFileURL = try #require(runtime.outputFileURL)
        let lines = try String(contentsOf: outputFileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        #expect(lines.count == 50)
        for line in lines {
            let data = try #require(line.data(using: .utf8))
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["body"] as? String == "eventbus.concurrent")
        }
    }

    @Test
    func serviceContextPropagatesThroughStructuredTaskButNotDetachedTask() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
            ]),
            processIdentifier: 753,
            timeUnixNano: { 303 }
        )
        var context = ServiceContext.topLevel
        context.agentStudioCorrelationID = "structured-flow"

        await ServiceContext.withValue(context) {
            await Task {
                await runtime.record(tag: .runtime, body: "runtime.structured-task")
            }.value
            // swiftlint:disable:next no_task_detached
            await Task.detached {
                await runtime.record(tag: .runtime, body: "runtime.detached-task")
            }.value
        }
        try await runtime.flush()

        let outputFileURL = try #require(runtime.outputFileURL)
        let lines = try String(contentsOf: outputFileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let structuredLine = try #require(lines.first { $0.contains("runtime.structured-task") })
        let detachedLine = try #require(lines.first { $0.contains("runtime.detached-task") })
        #expect(structuredLine.contains("\"agentstudio.correlation_id\":\"structured-flow\""))
        #expect(!detachedLine.contains("\"agentstudio.correlation_id\""))
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

@Suite(.serialized)
struct AgentStudioTraceRuntimeInstrumentationTests {
    @Test
    func jsonlOnlyBackendDoesNotCreateTracingSpans() async throws {
        let tracer = InMemoryTracer()
        InstrumentationSystem.bootstrap(tracer)

        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
            ]),
            processIdentifier: 852,
            timeUnixNano: { 404 }
        )

        await runtime.record(tag: .runtime, body: "runtime.local-jsonl")
        await runtime.record(tag: .runtime, body: "runtime.local-jsonl-again")
        try await runtime.flush()

        #expect(tracer.finishedSpans.isEmpty)
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-trace-runtime-instrumentation-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
