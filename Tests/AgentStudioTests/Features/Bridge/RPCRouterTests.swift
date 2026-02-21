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

    // MARK: - Dispatch

    @Test
    func test_dispatches_to_registered_handler() async throws {
        // Arrange
        let router = RPCRouter()
        var receivedFileId: String?

        router.register(method: DiffRequestFileContentsMethod.self) { params in
            receivedFileId = params.fileId
            return nil
        }

        // Act
        let fixture = try loadFixture("valid/rpc-command-notification.json")
        try await router.dispatch(json: fixture)

        // Assert
        #expect(receivedFileId == "abc123")
    }

    // MARK: - Unknown method

    @Test
    func test_unknown_method_reports_32601() async throws {
        // Arrange
        let router = RPCRouter()
        var errorCode: Int?

        router.onError = { code, _, _ in errorCode = code }

        // Act
        try await router.dispatch(
            json: """
                    {"jsonrpc":"2.0","method":"nonexistent.method","params":{}}
                """)

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
        try await router.dispatch(json: fixture)

        // Assert
        #expect(errorCode == -32_600)
    }

    @Test
    func test_invalid_jsonrpc_version_reports_32600() async throws {
        // Arrange
        let router = RPCRouter()
        var errorCode: Int?
        router.onError = { code, _, _ in errorCode = code }

        // Act
        try await router.dispatch(
            json: """
                {"jsonrpc":"1.0","method":"diff.requestFileContents","params":{"fileId":"abc123"}}
                """
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
        try await router.dispatch(
            json: """
                {"jsonrpc":"2.0","id":true,"method":"diff.requestFileContents","params":{"fileId":"abc123"}}
                """
        )

        // Assert
        #expect(errorCode == -32_600)
    }

    // MARK: - Invalid params

    @Test
    func test_missing_params_reports_32602() async throws {
        // Arrange
        let router = RPCRouter()
        var errorCode: Int?
        var requestedFileId: String?

        router.register(method: DiffRequestFileContentsMethod.self) { params in
            requestedFileId = params.fileId
            return nil
        }

        router.onError = { code, _, _ in errorCode = code }

        // Act
        let fixture = #"{"jsonrpc":"2.0","method":"diff.requestFileContents"}"#
        try await router.dispatch(json: fixture)

        // Assert
        #expect(errorCode == -32_602)
        #expect(requestedFileId == nil)
    }

    @Test
    func test_wrong_params_shape_reports_32602() async throws {
        // Arrange
        let router = RPCRouter()
        var errorCode: Int?

        router.register(method: DiffRequestFileContentsMethod.self) { _ in
            return nil
        }

        router.onError = { code, _, _ in errorCode = code }

        // Act
        try await router.dispatch(
            json: """
                {"jsonrpc":"2.0","method":"diff.requestFileContents","params":"abc"}
                """
        )

        // Assert
        #expect(errorCode == -32_602)
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
        try await router.dispatch(json: fixture)

        // Assert
        #expect(errorCode == -32_600)
    }

    // MARK: - Malformed JSON parse error

    @Test
    func test_malformed_json_reports_32700() async throws {
        // Arrange
        let router = RPCRouter()
        var errorCode: Int?
        router.onError = { code, _, _ in errorCode = code }

        // Act
        try await router.dispatch(json: "{ not valid json !!!")

        // Assert
        #expect(errorCode == -32_700, "Malformed JSON should report parse error -32700, not -32600")
    }

    // MARK: - Duplicate commandId idempotency

    @Test
    func test_duplicate_commandId_is_idempotent() async throws {
        // Arrange
        let router = RPCRouter()
        var callCount = 0

        router.register(method: DiffRequestFileContentsMethod.self) { _ in
            callCount += 1
            return nil
        }

        // Act
        let fixture = try loadFixture("edge/rpc-duplicate-commandId.json")
        try await router.dispatch(json: fixture)
        try await router.dispatch(json: fixture)

        // Assert
        #expect(callCount == 1, "Duplicate commandId should not execute twice")
    }

    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let fixtureURL = root.appendingPathComponent("Tests/BridgeContractFixtures/\(name)")
        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }
}
