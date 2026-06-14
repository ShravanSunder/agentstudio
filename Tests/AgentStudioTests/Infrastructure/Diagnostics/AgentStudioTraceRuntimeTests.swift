import Foundation
import Testing
import Tracing

@testable import AgentStudio

@Suite
struct AgentStudioTraceRuntimeTests {
    @Test
    func disabledRuntimeDoesNotEvaluateAttributes() async throws {
        let evaluationFlag = AttributeEvaluationFlag()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(
                environment: [:],
                releaseChannel: .stable,
                isDebugBuild: false
            ),
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
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
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
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
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
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
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
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
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
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
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
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
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

    @Test
    func jsonlBackendRecordsOnlyJsonlSink() async throws {
        let recordingSinks = RecordingTraceSinks()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
            ]),
            processIdentifier: 741,
            sinkFactory: recordingSinks.factory(),
            timeUnixNano: { 10 }
        )

        await runtime.record(tag: .runtime, body: "runtime.jsonl-only")

        #expect(runtime.outputFileURL?.lastPathComponent == "agentstudio-trace-741.jsonl")
        #expect(await recordingSinks.jsonl.bodies() == ["runtime.jsonl-only"])
        #expect(await recordingSinks.otlp.bodies().isEmpty)
    }

    @Test
    func otlpBackendRecordsOnlyOTLPSinkAndHasNoOutputFile() async throws {
        let recordingSinks = RecordingTraceSinks()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "otlp",
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
            ]),
            processIdentifier: 742,
            sinkFactory: recordingSinks.factory(),
            timeUnixNano: { 11 }
        )

        await runtime.record(tag: .runtime, body: "runtime.otlp-only")

        #expect(runtime.outputFileURL == nil)
        #expect(await recordingSinks.jsonl.bodies().isEmpty)
        #expect(await recordingSinks.otlp.bodies() == ["runtime.otlp-only"])
    }

    @Test
    func bothBackendFansOutOneRecordToBothSinks() async throws {
        let recordingSinks = RecordingTraceSinks()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "both",
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
            ]),
            processIdentifier: 743,
            sinkFactory: recordingSinks.factory(),
            timeUnixNano: { 12 }
        )

        await runtime.record(tag: .runtime, body: "runtime.both")

        #expect(runtime.outputFileURL?.lastPathComponent == "agentstudio-trace-743.jsonl")
        #expect(await recordingSinks.jsonl.bodies() == ["runtime.both"])
        #expect(await recordingSinks.otlp.bodies() == ["runtime.both"])
    }

    @Test
    func runtimeRecordIncludesSafeIdentityResourceWhenWorktreeAttributeIsKnown() async throws {
        let worktreeId = UUID()
        let identityStore = AgentStudioTraceIdentityStore()
        await identityStore.update(
            AgentStudioTraceIdentitySnapshot(
                worktreeIdentitiesByWorktreeId: [
                    worktreeId: AgentStudioTraceWorktreeIdentity(
                        repoHash: "repo-hash",
                        worktreeHash: "worktree-hash",
                        branch: "otel-integration"
                    )
                ]
            )
        )
        let recordingSinks = RecordingTraceSinks()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(
                environment: [
                    "AGENTSTUDIO_TRACE_BACKEND": "otlp",
                    "AGENTSTUDIO_TRACE_TAGS": "runtime",
                ],
                releaseChannel: .beta,
                isDebugBuild: true
            ),
            processIdentifier: 747,
            sinkFactory: recordingSinks.factory(),
            identityStore: identityStore,
            timeUnixNano: { 16 }
        )

        await runtime.record(
            tag: .runtime,
            body: "runtime.identity",
            attributes: [
                "agentstudio.worktree.id": .string(worktreeId.uuidString)
            ]
        )

        let resources = await recordingSinks.otlp.resources()
        let resource = try #require(resources.first)
        #expect(resource["agentstudio.runtime_flavor"] == "debug")
        #expect(resource["agentstudio.release_channel"] == "beta")
        #expect(resource["dev.runtime.flavor"] == "debug")
        #expect(resource["dev.release.channel"] == "beta")
        #expect(resource["dev.repo.name"] == nil)
        #expect(resource["dev.repo.hash"] == "repo-hash")
        #expect(resource["dev.worktree.hash"] == "worktree-hash")
        #expect(resource["dev.branch.name"] == "otel-integration")
        #expect(resource["agentstudio.worktree.id"] == nil)
    }

    @Test
    func otlpSinkFailureDoesNotPreventJsonlSinkRecord() async throws {
        let recordingSinks = RecordingTraceSinks()
        await recordingSinks.otlp.setRecordError(RecordingTraceSinkError.recordFailed)
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "both",
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
            ]),
            processIdentifier: 744,
            sinkFactory: recordingSinks.factory(),
            timeUnixNano: { 13 }
        )

        await runtime.record(tag: .runtime, body: "runtime.otlp-fails")

        #expect(await recordingSinks.jsonl.bodies() == ["runtime.otlp-fails"])
        #expect(await recordingSinks.otlp.bodies().isEmpty)
    }

    @Test
    func recordDispatchStartsLaterSinkBeforeEarlierSinkCompletes() async throws {
        let recordingSinks = RecordingTraceSinks()
        await recordingSinks.jsonl.suspendRecords()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "both",
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
            ]),
            processIdentifier: 987,
            sinkFactory: recordingSinks.factory(),
            timeUnixNano: { 16 }
        )

        let recordTask = Task {
            await runtime.record(tag: .runtime, body: "runtime.concurrent-dispatch")
        }
        await recordingSinks.jsonl.waitForRecordAttempt()

        let didRecordOTLP = await waitForBodyByYielding("runtime.concurrent-dispatch", in: recordingSinks.otlp)
        await recordingSinks.jsonl.resumeRecords()
        await recordTask.value

        #expect(didRecordOTLP)
        #expect(await recordingSinks.jsonl.bodies() == ["runtime.concurrent-dispatch"])
        #expect(await recordingSinks.otlp.bodies() == ["runtime.concurrent-dispatch"])
    }

    @Test
    func flushFansOutToAllLiveSinks() async throws {
        let recordingSinks = RecordingTraceSinks()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "both",
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
            ]),
            processIdentifier: 745,
            sinkFactory: recordingSinks.factory(),
            timeUnixNano: { 14 }
        )

        try await runtime.flush()

        #expect(await recordingSinks.jsonl.flushCount() == 1)
        #expect(await recordingSinks.otlp.flushCount() == 1)
    }

    @Test
    func shutdownFansOutToAllLiveSinks() async throws {
        let recordingSinks = RecordingTraceSinks()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "both",
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
            ]),
            processIdentifier: 746,
            sinkFactory: recordingSinks.factory(),
            timeUnixNano: { 15 }
        )

        try await runtime.shutdown()

        #expect(await recordingSinks.jsonl.shutdownCount() == 1)
        #expect(await recordingSinks.otlp.shutdownCount() == 1)
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-trace-runtime-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func waitForBodyByYielding(_ body: String, in sink: RecordingTraceSink) async -> Bool {
        for _ in 0..<100 {
            if await sink.bodies().contains(body) {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private final class AttributeEvaluationFlag: @unchecked Sendable {
        private(set) var didEvaluate = false

        func markEvaluated() -> Bool {
            didEvaluate = true
            return true
        }
    }

    private struct RecordingTraceSinks: Sendable {
        let jsonl = RecordingTraceSink()
        let otlp = RecordingTraceSink()

        func factory() -> AgentStudioTraceSinkFactory {
            AgentStudioTraceSinkFactory(
                makeJSONLSink: { _ in jsonl },
                makeOTLPSink: { _ in otlp }
            )
        }
    }

    private actor RecordingTraceSink: AgentStudioTraceSink {
        private var records: [AgentStudioTraceRecord] = []
        private var recordedFlushCount = 0
        private var recordedShutdownCount = 0
        private var recordError: Error?
        private var flushError: Error?
        private var shouldSuspendRecords = false
        private var suspendedRecordContinuations: [CheckedContinuation<Void, Never>] = []
        private var recordAttemptCount = 0
        private var recordAttemptContinuations: [CheckedContinuation<Void, Never>] = []

        func record(_ record: AgentStudioTraceRecord) async throws {
            recordAttemptCount += 1
            let waitingContinuations = recordAttemptContinuations
            recordAttemptContinuations.removeAll()
            for continuation in waitingContinuations {
                continuation.resume()
            }

            if shouldSuspendRecords {
                await withCheckedContinuation { continuation in
                    suspendedRecordContinuations.append(continuation)
                }
            }

            if let recordError {
                throw recordError
            }
            records.append(record)
        }

        func flush() throws {
            recordedFlushCount += 1
            if let flushError {
                throw flushError
            }
        }

        func shutdown() throws {
            recordedShutdownCount += 1
        }

        func diagnostics() -> AgentStudioTraceWriterDiagnostics {
            .empty
        }

        func setRecordError(_ error: Error?) {
            recordError = error
        }

        func suspendRecords() {
            shouldSuspendRecords = true
        }

        func resumeRecords() {
            shouldSuspendRecords = false
            let continuations = suspendedRecordContinuations
            suspendedRecordContinuations.removeAll()
            for continuation in continuations {
                continuation.resume()
            }
        }

        func waitForRecordAttempt() async {
            guard recordAttemptCount == 0 else { return }
            await withCheckedContinuation { continuation in
                recordAttemptContinuations.append(continuation)
            }
        }

        func bodies() -> [String] {
            records.map(\.body)
        }

        func resources() -> [[String: String]] {
            records.map(\.resource)
        }

        func flushCount() -> Int {
            recordedFlushCount
        }

        func shutdownCount() -> Int {
            recordedShutdownCount
        }
    }

    private enum RecordingTraceSinkError: Error {
        case recordFailed
    }
}
