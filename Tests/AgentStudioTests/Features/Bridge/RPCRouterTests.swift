import Foundation
import Testing

@testable import AgentStudio

/// Tests for scheme-command dispatch, error handling, batch rejection, and commandId dedup.
///
/// The scheme command dispatcher is the typed command channel entry point.
/// Scheme RPC JSON flows into BridgeSchemeCommandDispatcher after page-load bootstrap.
/// The dispatcher routes registered handlers, deduplicates by __commandId (sliding window of 100),
/// and rejects batch requests.
/// Error codes follow JSON-RPC 2.0 standard (§5.3).
@MainActor
@Suite(.serialized)
final class RPCRouterTests {
    private struct NoResponse: Codable, Sendable {}

    private struct DiffRequestFileContentsMethod: RPCMethod {
        struct Params: Decodable {
            let fileId: String
        }

        typealias Result = NoResponse
        static let method = "test.probe"
    }

    private struct ReviewMarkFileViewedFixtureMethod: RPCMethod {
        struct Params: Decodable {
            let fileId: String
        }

        typealias Result = NoResponse
        static let method = "review.markFileViewed"
    }

    private struct FailingMethod: RPCMethod {
        struct Params: Decodable {}

        typealias Result = NoResponse
        static let method = "agent.fail"
    }

    private struct SafeDiagnosticFailingMethod: RPCMethod {
        struct Params: Decodable {}

        typealias Result = NoResponse
        static let method = "agent.safeDiagnosticFail"
    }

    private struct NoParamsMethod: RPCMethod {
        struct Params: Decodable {}

        typealias Result = NoResponse
        static let method = "agent.noParams"
    }

    private struct ResponseMethod: RPCMethod {
        struct Params: Decodable, Sendable {
            let value: String
        }

        struct ResultPayload: Codable, Sendable {
            let echoed: String
        }

        typealias Result = ResultPayload
        static let method = "agent.response"
    }

    private actor SendableBox<Value> {
        private var value: Value

        init(_ value: Value) {
            self.value = value
        }

        func set(_ newValue: Value) {
            value = newValue
        }

        func get() -> Value {
            value
        }

        func update(_ transform: @Sendable (Value) -> Value) {
            value = transform(value)
        }
    }

    private actor BridgeTelemetryRecorderSpy: BridgePerformanceTraceRecording {
        private var recordedSamples: [BridgeTelemetrySample] = []
        private var recordedDrops: [BridgeTelemetryDropReason] = []

        func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async {
            recordedSamples.append(sample)
        }

        func recordDrop(
            reason: BridgeTelemetryDropReason,
            droppedCount: Int,
            firstRejectedEventName: String?,
            receivedAtUnixNano: UInt64
        ) async {
            _ = firstRejectedEventName
            recordedDrops.append(reason)
        }

        func samples() -> [BridgeTelemetrySample] {
            recordedSamples
        }

        func drops() -> [BridgeTelemetryDropReason] {
            recordedDrops
        }

        func drain() async throws {}
    }

    private actor BridgeTelemetryIngestorSpy: BridgeTelemetryBatchIngesting {
        private var ingestCount = 0

        func ingest(_ data: Data) async -> BridgeTelemetryIngestResult {
            ingestCount += 1
            return .accepted(sampleCount: 1)
        }

        func count() -> Int {
            ingestCount
        }
    }

    // MARK: - Dispatch

    @Test
    func test_dispatches_to_registered_handler() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let receivedFileId = SendableBox<String?>(nil)

        router.register(method: ReviewMarkFileViewedFixtureMethod.self) { params in
            await receivedFileId.set(params.fileId)
            return nil
        }

        // Act
        let fixture = try loadFixture("valid/rpc-command-notification.json")
        await router.dispatch(json: fixture, isBridgeReady: true)

        // Assert
        #expect((await receivedFileId.get()) == "abc123")
    }

    @Test
    func test_request_with_id_emits_success_response_envelope() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let responseJSON = SendableBox<String?>(nil)
        router.register(method: ResponseMethod.self) { params in
            .init(echoed: params.value)
        }
        router.onResponse = { json in
            await responseJSON.set(json)
        }

        // Act
        await router.dispatch(
            json: #"{ "jsonrpc": "2.0", "id": "req-1", "method":"agent.response", "params": { "value": "hello" } }"#,
            isBridgeReady: true
        )

        // Assert
        let envelope = try parseJSONObject(try #require(await responseJSON.get()))
        #expect(envelope["jsonrpc"] as? String == "2.0")
        #expect(envelope["id"] as? String == "req-1")
        let result = envelope["result"] as? [String: Any]
        #expect(result?["echoed"] as? String == "hello")
        #expect(envelope["error"] == nil)
    }

    @Test
    func test_success_response_round_trips_double_id() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let responseJSON = SendableBox<String?>(nil)
        router.register(method: ResponseMethod.self) { params in
            .init(echoed: params.value)
        }
        router.onResponse = { json in
            await responseJSON.set(json)
        }

        // Act
        await router.dispatch(
            json: #"{ "jsonrpc": "2.0", "id": 12.5, "method":"agent.response", "params": { "value": "hello" } }"#,
            isBridgeReady: true
        )

        // Assert
        let envelope = try parseJSONObject(try #require(await responseJSON.get()))
        #expect((envelope["id"] as? NSNumber)?.doubleValue == 12.5)
        let result = envelope["result"] as? [String: Any]
        #expect(result?["echoed"] as? String == "hello")
        #expect(envelope["error"] == nil)
    }

    @Test
    func test_nil_handler_result_emits_result_null() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let responseJSON = SendableBox<String?>(nil)
        router.register(method: DiffRequestFileContentsMethod.self) { _ in
            nil
        }
        router.onResponse = { json in
            await responseJSON.set(json)
        }

        // Act
        await router.dispatch(
            json:
                #"{ "jsonrpc": "2.0", "id": 7, "method":"test.probe", "params": { "fileId": "abc123" } }"#,
            isBridgeReady: true
        )

        // Assert
        let envelope = try parseJSONObject(try #require(await responseJSON.get()))
        #expect((envelope["id"] as? NSNumber)?.intValue == 7)
        #expect(envelope["result"] is NSNull)
        #expect(envelope["error"] == nil)
    }

    @Test
    func test_request_with_null_id_echoes_null_in_response() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let responseJSON = SendableBox<String?>(nil)
        router.register(method: ResponseMethod.self) { params in
            .init(echoed: params.value)
        }
        router.onResponse = { json in
            await responseJSON.set(json)
        }

        // Act
        await router.dispatch(
            json: #"{ "jsonrpc": "2.0", "id": null, "method":"agent.response", "params": { "value": "hello" } }"#,
            isBridgeReady: true
        )

        // Assert
        let envelope = try parseJSONObject(try #require(await responseJSON.get()))
        #expect(envelope["id"] is NSNull)
        let result = envelope["result"] as? [String: Any]
        #expect(result?["echoed"] as? String == "hello")
    }

    @Test
    func test_notification_without_id_does_not_emit_response() async {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let responseCount = SendableBox(0)
        router.register(method: ResponseMethod.self) { params in
            .init(echoed: params.value)
        }
        router.onResponse = { _ in
            await responseCount.update { $0 + 1 }
        }

        // Act
        await router.dispatch(
            json: #"{ "jsonrpc": "2.0", "method":"agent.response", "params": { "value": "hello" } }"#,
            isBridgeReady: true
        )

        // Assert
        #expect(await responseCount.get() == 0)
    }

    @Test
    func rpc_trace_context_is_decoded_outside_params_and_recorded() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let recorder = BridgeTelemetryRecorderSpy()
        let receivedFileId = SendableBox<String?>(nil)
        router.telemetryRecorder = recorder
        router.register(method: ReviewMarkFileViewedFixtureMethod.self) { params in
            await receivedFileId.set(params.fileId)
            return nil
        }

        // Act
        await router.dispatch(
            json: """
                {
                    "jsonrpc": "2.0",
                    "method": "review.markFileViewed",
                    "__traceContext": {
                        "traceId": "11111111111111111111111111111111",
                        "spanId": "2222222222222222",
                        "parentSpanId": null,
                        "sampled": true
                    },
                    "params": { "fileId": "abc123" }
                }
                """,
            isBridgeReady: true
        )

        // Assert
        #expect((await receivedFileId.get()) == "abc123")
        let samples = await recorder.samples()
        #expect(samples.map(\.name).contains("performance.bridge.webkit.rpc_dispatch"))
        #expect(samples.map(\.name).contains("performance.bridge.webkit.rpc_response"))
        #expect(samples.allSatisfy { $0.traceContext?.traceId == "11111111111111111111111111111111" })
        #expect(samples.allSatisfy { $0.stringAttributes["agentstudio.bridge.rpc.method_class"] == "review" })
        #expect(samples.allSatisfy { $0.stringAttributes["agentstudio.bridge.plane"] == "control" })
        #expect(samples.allSatisfy { $0.stringAttributes["agentstudio.bridge.priority"] == "warm" })
        #expect(samples.allSatisfy { $0.stringAttributes["agentstudio.bridge.slice"] == "review_rpc" })
    }

    @Test
    func invalid_rpc_trace_context_does_not_reject_valid_command() async {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let recorder = BridgeTelemetryRecorderSpy()
        let receivedFileId = SendableBox<String?>(nil)
        var errorCode: Int?
        router.telemetryRecorder = recorder
        router.onError = { code, _, _ in errorCode = code }
        router.register(method: ReviewMarkFileViewedFixtureMethod.self) { params in
            await receivedFileId.set(params.fileId)
            return nil
        }

        // Act
        await router.dispatch(
            json: """
                {
                    "jsonrpc": "2.0",
                    "method": "review.markFileViewed",
                    "__traceContext": {
                        "traceId": "INVALID",
                        "spanId": "2222222222222222",
                        "sampled": true
                    },
                    "params": { "fileId": "abc123" }
                }
                """,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == nil)
        #expect((await receivedFileId.get()) == "abc123")
        let samples = await recorder.samples()
        #expect(samples.allSatisfy { $0.traceContext == nil })
    }

    @Test
    func bridge_telemetry_rpc_is_method_not_found_without_ingest_or_generic_rpc_self_observation() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let recorder = BridgeTelemetryRecorderSpy()
        let ingestor = BridgeTelemetryIngestorSpy()
        router.telemetryRecorder = recorder
        router.telemetryIngestor = ingestor

        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "test",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.rpc_send",
                    durationMilliseconds: 1,
                    traceContext: nil,
                    stringAttributes: [:],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )
        let paramsData = try JSONEncoder().encode(batch)
        let paramsJSON = try #require(String(data: paramsData, encoding: .utf8))

        // Act
        await router.dispatch(
            json: #"{"jsonrpc":"2.0","method":"system.bridgeTelemetry","params":\#(paramsJSON)}"#,
            isBridgeReady: true
        )

        // Assert
        #expect(await ingestor.count() == 0)
        let sampleNames = await recorder.samples().map(\.name)
        #expect(sampleNames.isEmpty)
    }

    @Test
    func bridge_telemetry_rpc_is_method_not_found_without_ingestor() async {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        var errorCode: Int?
        router.onError = { code, _, _ in errorCode = code }

        // Act
        await router.dispatch(
            json:
                #"{"jsonrpc":"2.0","method":"system.bridgeTelemetry","params":{"schemaVersion":1,"scenario":"test","samples":[]}}"#,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_601)
    }

    @Test
    func test_pre_ready_request_with_id_emits_bridge_not_ready_error_response() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let responseJSON = SendableBox<String?>(nil)
        var errorCode: Int?
        router.register(method: ResponseMethod.self) { _ in
            .init(echoed: "unexpected")
        }
        router.onError = { code, _, _ in errorCode = code }
        router.onResponse = { json in
            await responseJSON.set(json)
        }

        // Act
        await router.dispatch(
            json: #"{ "jsonrpc": "2.0", "id":"pre-ready", "method":"agent.response", "params": { "value": "hello" } }"#,
            isBridgeReady: false
        )

        // Assert
        #expect(errorCode == -32_004)
        let envelope = try parseJSONObject(try #require(await responseJSON.get()))
        #expect(envelope["id"] as? String == "pre-ready")
        let error = envelope["error"] as? [String: Any]
        #expect((error?["code"] as? NSNumber)?.intValue == -32_004)
    }

    @Test
    func test_pre_ready_notification_reports_bridge_not_ready_without_response() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let responseCount = SendableBox(0)
        var errorCode: Int?
        router.register(method: ResponseMethod.self) { _ in
            .init(echoed: "unexpected")
        }
        router.onError = { code, _, _ in errorCode = code }
        router.onResponse = { _ in
            await responseCount.update { $0 + 1 }
        }

        // Act
        await router.dispatch(
            json: #"{ "jsonrpc": "2.0", "method":"agent.response", "params": { "value": "hello" } }"#,
            isBridgeReady: false
        )

        // Assert
        #expect(errorCode == -32_004)
        #expect(await responseCount.get() == 0)
    }

    @Test
    func test_pre_ready_review_intake_ready_is_accepted_as_control_signal() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let receivedParams = SendableBox<BridgeIntakeReadyMethod.Params?>(nil)
        var errorCode: Int?
        router.register(method: BridgeIntakeReadyMethod.self) { params in
            await receivedParams.set(params)
            return nil
        }
        router.onError = { code, _, _ in errorCode = code }

        // Act
        let intakeReadyNotification = """
            { "jsonrpc": "2.0", "method":"bridge.intakeReady", "params": { "protocolId": "review", "streamId": "review:pane-1" } }
            """
        await router.dispatch(
            json: intakeReadyNotification,
            isBridgeReady: false
        )

        // Assert
        let params = try #require(await receivedParams.get())
        #expect(params.protocolId == "review")
        #expect(params.streamId == "review:pane-1")
        #expect(errorCode == nil)
    }

    // MARK: - Unknown method

    @Test
    func test_unknown_method_reports_32601() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        var errorCode: Int?

        router.onError = { code, _, _ in errorCode = code }

        // Act
        await router.dispatch(
            json: """
                    {"jsonrpc":"2.0","method":"nonexistent.method","params":{}}
                """,
            isBridgeReady: true)

        // Assert
        #expect(errorCode == -32_601)
    }

    // MARK: - Missing method field

    @Test
    func test_missing_method_reports_32600() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        var errorCode: Int?

        router.onError = { code, _, _ in errorCode = code }

        // Act
        let fixture = try loadFixture("invalid/rpc-missing-method.json")
        await router.dispatch(json: fixture, isBridgeReady: true)

        // Assert
        #expect(errorCode == -32_600)
    }

    @Test
    func test_invalid_request_with_id_emits_32600_error_response() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let responseJSON = SendableBox<String?>(nil)
        var errorCode: Int?
        router.onError = { code, _, _ in errorCode = code }
        router.onResponse = { json in
            await responseJSON.set(json)
        }

        // Act
        await router.dispatch(
            json: #"{ "jsonrpc": "2.0", "id":"bad-request" }"#,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_600)
        let envelope = try parseJSONObject(try #require(await responseJSON.get()))
        #expect(envelope["id"] as? String == "bad-request")
        #expect((envelope["result"] as Any?) == nil)
        let error = envelope["error"] as? [String: Any]
        #expect((error?["code"] as? NSNumber)?.intValue == -32_600)
    }

    @Test
    func test_invalid_jsonrpc_version_reports_32600() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        var errorCode: Int?
        router.onError = { code, _, _ in errorCode = code }

        // Act
        await router.dispatch(
            json: """
                {"jsonrpc":"1.0","method":"test.probe","params":{"fileId":"abc123"}}
                """,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_600)
    }

    @Test
    func test_invalid_id_reports_32600() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        var errorCode: Int?
        router.onError = { code, _, _ in errorCode = code }

        // Act
        await router.dispatch(
            json: """
                {"jsonrpc":"2.0","id":true,"method":"test.probe","params":{"fileId":"abc123"}}
                """,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_600)
    }

    @Test
    func test_id_false_is_rejected() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        var errorCode: Int?

        router.onError = { code, _, _ in errorCode = code }

        // Act
        await router.dispatch(json: #"{"jsonrpc":"2.0","id":false,"method":"agent.fail"}"#, isBridgeReady: true)

        // Assert
        #expect(errorCode == -32_600)
    }

    // MARK: - Invalid params

    @Test
    func test_missing_params_reports_32602() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        var errorCode: Int?
        let requestedFileId = SendableBox<String?>(nil)

        router.register(method: DiffRequestFileContentsMethod.self) { params in
            await requestedFileId.set(params.fileId)
            return nil
        }

        router.onError = { code, _, _ in errorCode = code }

        // Act
        let fixture = #"{"jsonrpc":"2.0","method":"test.probe"}"#
        await router.dispatch(json: fixture, isBridgeReady: true)

        // Assert
        #expect(errorCode == -32_602)
        #expect((await requestedFileId.get()) == nil)
    }

    @Test
    func test_invalid_params_with_id_emits_32602_error_response() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let responseJSON = SendableBox<String?>(nil)
        var errorCode: Int?
        router.register(method: DiffRequestFileContentsMethod.self) { _ in nil }
        router.onError = { code, _, _ in errorCode = code }
        router.onResponse = { json in
            await responseJSON.set(json)
        }

        // Act
        await router.dispatch(
            json: #"{ "jsonrpc":"2.0", "id":"bad-params", "method":"test.probe" }"#,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_602)
        let envelope = try parseJSONObject(try #require(await responseJSON.get()))
        #expect(envelope["id"] as? String == "bad-params")
        let error = envelope["error"] as? [String: Any]
        #expect((error?["code"] as? NSNumber)?.intValue == -32_602)
    }

    @Test
    func test_null_params_is_rejected() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        var errorCode: Int?

        router.register(method: DiffRequestFileContentsMethod.self) { _ in
            nil
        }

        router.onError = { code, _, _ in errorCode = code }

        // Act
        await router.dispatch(
            json: #"{"jsonrpc":"2.0","method":"test.probe","params":null}"#,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_602)
    }

    @Test
    func test_wrong_params_shape_reports_32602() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        var errorCode: Int?

        router.register(method: DiffRequestFileContentsMethod.self) { _ in nil }

        router.onError = { code, _, _ in errorCode = code }

        // Act
        await router.dispatch(
            json: """
                {"jsonrpc":"2.0","method":"test.probe","params":"abc"}
                """,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_602)
    }

    @Test
    func test_array_params_reports_32602() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        var errorCode: Int?

        router.register(method: DiffRequestFileContentsMethod.self) { _ in nil }
        router.onError = { code, _, _ in errorCode = code }

        // Act
        await router.dispatch(
            json: #"{ "jsonrpc": "2.0", "method":"test.probe", "params":[1,2,3] }"#,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_602)
    }

    @Test
    func test_handler_failure_reports_32603() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        var errorCode: Int?
        var errorMessage: String?

        router.register(method: FailingMethod.self) { _ in
            throw NSError(domain: "agent-studio-tests", code: 9001, userInfo: [NSLocalizedDescriptionKey: "boom"])
        }

        router.onError = { code, message, _ in
            errorCode = code
            errorMessage = message
        }

        // Act
        await router.dispatch(
            json: #"{"jsonrpc":"2.0","method":"agent.fail","id":1}"#,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_603)
        #expect(errorMessage == "Internal error")
    }

    @Test
    func test_handler_failure_with_id_emits_32603_error_response() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let responseJSON = SendableBox<String?>(nil)
        var errorCode: Int?
        router.register(method: FailingMethod.self) { _ in
            throw NSError(domain: "agent-studio-tests", code: 9001, userInfo: [NSLocalizedDescriptionKey: "boom"])
        }
        router.onError = { code, _, _ in errorCode = code }
        router.onResponse = { json in
            await responseJSON.set(json)
        }

        // Act
        await router.dispatch(
            json: #"{"jsonrpc":"2.0","method":"agent.fail","id":123}"#,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_603)
        let envelope = try parseJSONObject(try #require(await responseJSON.get()))
        #expect((envelope["id"] as? NSNumber)?.int64Value == 123)
        let error = envelope["error"] as? [String: Any]
        #expect((error?["code"] as? NSNumber)?.intValue == -32_603)
        #expect(error?["message"] as? String == "Internal error")
    }

    @Test
    func test_safe_dispatch_diagnostic_code_survives_error_response() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let responseJSON = SendableBox<String?>(nil)
        router.register(method: SafeDiagnosticFailingMethod.self) { _ in
            throw RPCMethodDispatchError.invalidParams("worktree_file.root_token_mismatch")
        }
        router.onResponse = { json in
            await responseJSON.set(json)
        }

        // Act
        await router.dispatch(
            json: #"{"jsonrpc":"2.0","method":"agent.safeDiagnosticFail","id":"safe-1"}"#,
            isBridgeReady: true
        )

        // Assert
        let envelope = try parseJSONObject(try #require(await responseJSON.get()))
        let error = envelope["error"] as? [String: Any]
        #expect((error?["code"] as? NSNumber)?.intValue == -32_602)
        #expect(error?["message"] as? String == "worktree_file.root_token_mismatch")
    }

    @Test
    func test_unsafe_dispatch_error_message_stays_generic() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let responseJSON = SendableBox<String?>(nil)
        router.register(method: SafeDiagnosticFailingMethod.self) { _ in
            throw RPCMethodDispatchError.handlerFailure("raw failure at /Users/example/private")
        }
        router.onResponse = { json in
            await responseJSON.set(json)
        }

        // Act
        await router.dispatch(
            json: #"{"jsonrpc":"2.0","method":"agent.safeDiagnosticFail","id":"unsafe-1"}"#,
            isBridgeReady: true
        )

        // Assert
        let envelope = try parseJSONObject(try #require(await responseJSON.get()))
        let error = envelope["error"] as? [String: Any]
        #expect((error?["code"] as? NSNumber)?.intValue == -32_603)
        #expect(error?["message"] as? String == "Internal error")
    }

    // MARK: - Batch rejection (§5.5)

    @Test
    func test_batch_array_reports_32600() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        var errorCode: Int?

        router.onError = { code, _, _ in errorCode = code }

        // Act
        let fixture = try loadFixture("invalid/rpc-batch-array.json")
        await router.dispatch(json: fixture, isBridgeReady: true)

        // Assert
        #expect(errorCode == -32_600)
    }

    // MARK: - Malformed JSON parse error

    @Test
    func test_malformed_json_reports_32700() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        var errorCode: Int?
        let responseJSON = SendableBox<String?>(nil)
        router.onError = { code, _, _ in errorCode = code }
        router.onResponse = { json in
            await responseJSON.set(json)
        }

        // Act
        await router.dispatch(json: "{ not valid json !!!", isBridgeReady: true)

        // Assert
        #expect(errorCode == -32_700, "Malformed JSON should report parse error -32700, not -32600")
        let envelope = try parseJSONObject(try #require(await responseJSON.get()))
        #expect(envelope["id"] is NSNull, "Parse errors must emit id: null per JSON-RPC 2.0")
        let error = envelope["error"] as? [String: Any]
        #expect((error?["code"] as? NSNumber)?.intValue == -32_700)
    }

    // MARK: - Duplicate commandId idempotency

    @Test
    func test_duplicate_commandId_is_idempotent() async throws {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let callCount = SendableBox(0)

        router.register(method: ReviewMarkFileViewedFixtureMethod.self) { _ in
            await callCount.update { $0 + 1 }
            return nil
        }

        // Act
        let fixture = try loadFixture("edge/rpc-duplicate-commandId.json")
        await router.dispatch(json: fixture, isBridgeReady: true)
        await router.dispatch(json: fixture, isBridgeReady: true)

        // Assert
        #expect((await callCount.get()) == 1, "Duplicate commandId should not execute twice")
    }

    @Test
    func test_dedup_history_eviction_allows_redispatch() async {
        // Arrange
        let router = BridgeSchemeCommandDispatcher(maxCommandIdHistory: 2)
        let callCount = SendableBox(0)
        router.register(method: DiffRequestFileContentsMethod.self) { _ in
            await callCount.update { $0 + 1 }
            return nil
        }

        // Act
        await router.dispatch(
            json:
                #"{ "jsonrpc":"2.0", "method":"test.probe", "params":{"fileId":"a"}, "__commandId":"cmd-1" }"#,
            isBridgeReady: true
        )
        await router.dispatch(
            json:
                #"{ "jsonrpc":"2.0", "method":"test.probe", "params":{"fileId":"b"}, "__commandId":"cmd-2" }"#,
            isBridgeReady: true
        )
        await router.dispatch(
            json:
                #"{ "jsonrpc":"2.0", "method":"test.probe", "params":{"fileId":"c"}, "__commandId":"cmd-3" }"#,
            isBridgeReady: true
        )
        await router.dispatch(
            json:
                #"{ "jsonrpc":"2.0", "method":"test.probe", "params":{"fileId":"a"}, "__commandId":"cmd-1" }"#,
            isBridgeReady: true
        )

        // Assert
        #expect(await callCount.get() == 4)
    }

}
