import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class RPCRouterIdentifierTests {
    private struct NoResponse: Codable, Sendable {}

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
    func test_parse_request_id_double_is_preserved() async throws {
        // Arrange
        let router = RPCRouter()
        var requestID: RPCIdentifier?

        router.onError = { _, _, id in requestID = id }

        // Act
        await router.dispatch(
            json: #"{ "jsonrpc": "2.0", "id": 12.5, "method":"nonexistent.method" }"#,
            isBridgeReady: true
        )

        // Assert
        #expect(requestID == .double(12.5))
    }

    @Test
    func test_error_response_round_trips_double_id() async throws {
        // Arrange
        let router = RPCRouter()
        let responseJSON = SendableBox<String?>(nil)
        router.onResponse = { json in
            await responseJSON.set(json)
        }

        // Act
        await router.dispatch(
            json: #"{ "jsonrpc":"2.0", "id": 12.5, "method":"nonexistent.method" }"#,
            isBridgeReady: true
        )

        // Assert
        let envelope = try parseJSONObject(try #require(await responseJSON.get()))
        #expect((envelope["id"] as? NSNumber)?.doubleValue == 12.5)
        let error = envelope["error"] as? [String: Any]
        #expect((error?["code"] as? NSNumber)?.intValue == -32_601)
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

    private func parseJSONObject(_ json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }
}
