import Foundation
import Testing

@testable import AgentStudio

/// Tests for RPCRouter dispatch, error handling, batch rejection, and commandId dedup.
///
/// The RPC router is the command channel entry point (design doc §5.1, §9.2).
/// React sends JSON-RPC 2.0 notifications via postMessage → bridge world →
/// RPCMessageHandler → RPCRouter. The router dispatches to registered handlers,
/// deduplicates by __commandId (sliding window of 100), and rejects batch requests.
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
        static let method = "diff.requestFileContents"
    }

    private struct FailingMethod: RPCMethod {
        struct Params: Decodable {}

        typealias Result = NoResponse
        static let method = "agent.fail"
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

    // MARK: - Dispatch

    @Test
    func test_dispatches_to_registered_handler() async throws {
        // Arrange
        let router = RPCRouter()
        let receivedFileId = SendableBox<String?>(nil)

        router.register(method: DiffRequestFileContentsMethod.self) { params in
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
        let router = RPCRouter()
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
    func test_notification_without_id_does_not_emit_response() async {
        // Arrange
        let router = RPCRouter()
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

    // MARK: - Unknown method

    @Test
    func test_unknown_method_reports_32601() async throws {
        // Arrange
        let router = RPCRouter()
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
        let router = RPCRouter()
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
        let router = RPCRouter()
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
        let router = RPCRouter()
        var errorCode: Int?
        router.onError = { code, _, _ in errorCode = code }

        // Act
        await router.dispatch(
            json: """
                {"jsonrpc":"1.0","method":"diff.requestFileContents","params":{"fileId":"abc123"}}
                """,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_600)
    }

    @Test
    func test_invalid_id_reports_32600() async throws {
        // Arrange
        let router = RPCRouter()
        var errorCode: Int?
        router.onError = { code, _, _ in errorCode = code }

        // Act
        await router.dispatch(
            json: """
                {"jsonrpc":"2.0","id":true,"method":"diff.requestFileContents","params":{"fileId":"abc123"}}
                """,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_600)
    }

    @Test
    func test_id_false_is_rejected() async throws {
        // Arrange
        let router = RPCRouter()
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
        let router = RPCRouter()
        var errorCode: Int?
        let requestedFileId = SendableBox<String?>(nil)

        router.register(method: DiffRequestFileContentsMethod.self) { params in
            await requestedFileId.set(params.fileId)
            return nil
        }

        router.onError = { code, _, _ in errorCode = code }

        // Act
        let fixture = #"{"jsonrpc":"2.0","method":"diff.requestFileContents"}"#
        await router.dispatch(json: fixture, isBridgeReady: true)

        // Assert
        #expect(errorCode == -32_602)
        #expect((await requestedFileId.get()) == nil)
    }

    @Test
    func test_invalid_params_with_id_emits_32602_error_response() async throws {
        // Arrange
        let router = RPCRouter()
        let responseJSON = SendableBox<String?>(nil)
        var errorCode: Int?
        router.register(method: DiffRequestFileContentsMethod.self) { _ in nil }
        router.onError = { code, _, _ in errorCode = code }
        router.onResponse = { json in
            await responseJSON.set(json)
        }

        // Act
        await router.dispatch(
            json: #"{ "jsonrpc":"2.0", "id":"bad-params", "method":"diff.requestFileContents" }"#,
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
        let router = RPCRouter()
        var errorCode: Int?

        router.register(method: DiffRequestFileContentsMethod.self) { _ in
            nil
        }

        router.onError = { code, _, _ in errorCode = code }

        // Act
        await router.dispatch(
            json: #"{"jsonrpc":"2.0","method":"diff.requestFileContents","params":null}"#,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_602)
    }

    @Test
    func test_wrong_params_shape_reports_32602() async throws {
        // Arrange
        let router = RPCRouter()
        var errorCode: Int?

        router.register(method: DiffRequestFileContentsMethod.self) { _ in nil }

        router.onError = { code, _, _ in errorCode = code }

        // Act
        await router.dispatch(
            json: """
                {"jsonrpc":"2.0","method":"diff.requestFileContents","params":"abc"}
                """,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_602)
    }

    @Test
    func test_handler_failure_reports_32603() async throws {
        // Arrange
        let router = RPCRouter()
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
        #expect(errorMessage?.contains("boom") == true)
    }

    @Test
    func test_handler_failure_with_id_emits_32603_error_response() async throws {
        // Arrange
        let router = RPCRouter()
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
    }

    // MARK: - Batch rejection (§5.5)

    @Test
    func test_batch_array_reports_32600() async throws {
        // Arrange
        let router = RPCRouter()
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
        let router = RPCRouter()
        var errorCode: Int?
        let responseCount = SendableBox(0)
        router.onError = { code, _, _ in errorCode = code }
        router.onResponse = { _ in
            await responseCount.update { $0 + 1 }
        }

        // Act
        await router.dispatch(json: "{ not valid json !!!", isBridgeReady: true)

        // Assert
        #expect(errorCode == -32_700, "Malformed JSON should report parse error -32700, not -32600")
        #expect(await responseCount.get() == 0, "Malformed JSON has no request id and must not emit response")
    }

    // MARK: - Duplicate commandId idempotency

    @Test
    func test_duplicate_commandId_is_idempotent() async throws {
        // Arrange
        let router = RPCRouter()
        let callCount = SendableBox(0)

        router.register(method: DiffRequestFileContentsMethod.self) { _ in
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
    func test_parse_request_id_string_is_preserved() async throws {
        // Arrange
        let router = RPCRouter()
        var requestID: RPCIdentifier?

        router.register(method: FailingMethod.self) { _ in
            nil
        }
        router.onError = { _, _, id in requestID = id }

        // Act
        await router.dispatch(
            json: #"{ "jsonrpc": "2.0", "id": "abc123", "method":"nonexistent.method" }"#,
            isBridgeReady: true
        )

        // Assert
        #expect(requestID == .string("abc123"))
    }

    @Test
    func test_parse_request_id_integer_is_preserved() async throws {
        // Arrange
        let router = RPCRouter()
        var requestID: RPCIdentifier?

        router.register(method: FailingMethod.self) { _ in
            nil
        }
        router.onError = { _, _, id in requestID = id }

        // Act
        await router.dispatch(
            json: #"{ "jsonrpc": "2.0", "id": 123, "method":"nonexistent.method" }"#,
            isBridgeReady: true
        )

        // Assert
        #expect(requestID == .integer(123))
    }

    @Test
    func test_parse_request_id_null_is_preserved() async throws {
        // Arrange
        let router = RPCRouter()
        var requestID: RPCIdentifier?

        router.register(method: FailingMethod.self) { _ in
            nil
        }
        router.onError = { _, _, id in requestID = id }

        // Act
        await router.dispatch(
            json: #"{ "jsonrpc": "2.0", "id": null, "method":"nonexistent.method" }"#,
            isBridgeReady: true
        )

        // Assert
        #expect(requestID == .null)
    }

    @Test
    func test_empty_params_falls_back_to_empty_object() async throws {
        // Arrange
        let router = RPCRouter()
        let called = SendableBox(false)

        router.register(method: NoParamsMethod.self) { _ in
            await called.set(true)
            return nil
        }

        // Act
        await router.dispatch(
            json: #"{ "jsonrpc": "2.0", "method":"agent.noParams" }"#,
            isBridgeReady: true
        )

        // Assert
        #expect(await called.get())
    }

    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let fixtureURL = root.appendingPathComponent("Tests/BridgeContractFixtures/\(name)")
        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }

    private func parseJSONObject(_ json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }
}
