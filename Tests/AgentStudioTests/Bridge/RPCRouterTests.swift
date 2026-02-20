import XCTest
@testable import AgentStudio

/// Tests for RPCRouter dispatch, error handling, batch rejection, and commandId dedup.
///
/// The RPC router is the command channel entry point (design doc §5.1, §9.2).
/// React sends JSON-RPC 2.0 notifications via postMessage → bridge world →
/// RPCMessageHandler → RPCRouter. The router dispatches to registered handlers,
/// deduplicates by __commandId (sliding window of 100), and rejects batch requests.
/// Error codes follow JSON-RPC 2.0 standard (§5.3).
@MainActor
final class RPCRouterTests: XCTestCase {

    // MARK: - Dispatch

    func test_dispatches_to_registered_handler() async throws {
        // Arrange
        let router = RPCRouter()
        var receivedFileId: String?

        router.register("diff.requestFileContents") { params in
            receivedFileId = params["fileId"] as? String
        }

        // Act
        let fixture = try loadFixture("valid/rpc-command-notification.json")
        try await router.dispatch(json: fixture)

        // Assert
        XCTAssertEqual(receivedFileId, "abc123")
    }

    // MARK: - Unknown method

    func test_unknown_method_reports_32601() async throws {
        // Arrange
        let router = RPCRouter()
        var errorCode: Int?

        router.onError = { code, _, _ in errorCode = code }

        // Act
        try await router.dispatch(json: """
            {"jsonrpc":"2.0","method":"nonexistent.method","params":{}}
        """)

        // Assert
        XCTAssertEqual(errorCode, -32601)
    }

    // MARK: - Missing method field

    func test_missing_method_reports_32600() async throws {
        // Arrange
        let router = RPCRouter()
        var errorCode: Int?

        router.onError = { code, _, _ in errorCode = code }

        // Act
        let fixture = try loadFixture("invalid/rpc-missing-method.json")
        try await router.dispatch(json: fixture)

        // Assert
        XCTAssertEqual(errorCode, -32600)
    }

    // MARK: - Batch rejection (§5.5)

    func test_batch_array_reports_32600() async throws {
        // Arrange
        let router = RPCRouter()
        var errorCode: Int?

        router.onError = { code, _, _ in errorCode = code }

        // Act
        let fixture = try loadFixture("invalid/rpc-batch-array.json")
        try await router.dispatch(json: fixture)

        // Assert
        XCTAssertEqual(errorCode, -32600)
    }

    // MARK: - Duplicate commandId idempotency

    func test_duplicate_commandId_is_idempotent() async throws {
        // Arrange
        let router = RPCRouter()
        var callCount = 0

        router.register("diff.requestFileContents") { _ in callCount += 1 }

        // Act
        let fixture = try loadFixture("edge/rpc-duplicate-commandId.json")
        try await router.dispatch(json: fixture)
        try await router.dispatch(json: fixture)

        // Assert
        XCTAssertEqual(callCount, 1, "Duplicate commandId should not execute twice")
    }

    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Bridge/
            .deletingLastPathComponent() // AgentStudioTests/
            .deletingLastPathComponent() // Tests/
        let fixtureURL = root.appendingPathComponent("BridgeContractFixtures/\(name)")
        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }
}
