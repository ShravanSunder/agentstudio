import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

/// Integration tests that exercise ZmxBackend against a real zmx binary.
/// Each test uses an isolated ZMX_DIR via ZmxTestHarness to prevent cross-test interference.
///
/// Requires zmx to be installed (built from vendor/zmx or on PATH).
extension E2ESerializedTests {
    @Suite(.serialized)
    @MainActor
    struct ZmxBackendIntegrationTests {

        /// Run a test body with a usable backend, skipping if zmx is unavailable.
        private func withBackend(
            _ test: @escaping (ZmxTestHarness, ZmxBackend) async throws -> Void
        ) async throws {
            let harness = await ZmxTestHarness()
            let backend = try #require(
                harness.createBackend(),
                "ZmxTestHarness failed to resolve zmx path for integration test"
            )
            try #require(await backend.isAvailable, "zmx should be available for integration test")
            var bodyError: (any Error)?
            do {
                try await test(harness, backend)
            } catch {
                bodyError = error
            }
            let cleanupOutcome = await harness.cleanup()
            if let bodyError {
                if !cleanupOutcome.succeeded {
                    Issue.record("zmx cleanup also failed: \(cleanupOutcome.diagnostics)")
                }
                throw bodyError
            }
            if !cleanupOutcome.succeeded {
                throw ZmxTestHarness.CleanupError(outcome: cleanupOutcome)
            }
        }

        // MARK: - Create + Verify

        @Test
        func test_createSession_producesValidHandle() async throws {
            try await withBackend { _, backend in
                // Arrange
                let requestedSessionID = ZmxSessionID.generateUUIDv7()

                // Act
                let handle = try await backend.createPaneSession(sessionID: requestedSessionID)

                // Assert — handle is valid (no zmx session actually started, that happens on attach)
                let handleUUID = try #require(UUID(uuidString: handle.id.rawValue))
                #expect(handle.id == requestedSessionID)
                #expect(UUIDv7.isV7(handleUUID))
            }
        }

        // MARK: - Attach Command Format

        @Test
        func test_attachCommand_containsAttachAndSessionId() async throws {
            try await withBackend { harness, backend in
                // Arrange
                let handle = try await backend.createPaneSession(sessionID: .generateUUIDv7())

                // Act
                let cmd = backend.attachCommand(for: handle)

                // Assert
                #expect(!cmd.contains("ZMX_DIR="))
                #expect(cmd.hasPrefix(ZmxBackend.shellEscape(try #require(harness.zmxPath))))
                #expect(cmd.contains("attach"))
                #expect(cmd.contains(handle.id.rawValue))
                #expect(cmd.contains("-i -l"))
            }
        }

        // MARK: - ZMX_DIR Isolation

        @Test
        func test_zmxDir_isolatesFromDefaultDir() async throws {
            try await withBackend { harness, backend in
                // Arrange — create a session in test-isolated dir
                let sessionID = ZmxSessionID.generateUUIDv7()

                // Act
                _ = try await backend.createPaneSession(sessionID: sessionID)

                // Assert — the zmx dir should exist and be in temp
                #expect(
                    harness.zmxDir.hasPrefix("/tmp/zt-")
                )
                #expect(
                    FileManager.default.fileExists(atPath: harness.zmxDir)
                )
            }
        }

        // MARK: - Destroy

        @Test
        func destroySessionByIDReportsOperationFailedForNonzeroKill() async throws {
            let executor = MockProcessExecutor()
            executor.enqueueFailure()
            let sessionID = ZmxSessionID.generateUUIDv7()
            let zmxPath = "/test/zmx"
            let zmxDir = FileManager.default.temporaryDirectory
                .appending(path: "zmx-backend-failure-\(UUIDv7.generate().uuidString)")
                .path
            let backend = ZmxBackend(
                executor: executor,
                zmxPath: zmxPath,
                zmxDir: zmxDir,
                retryPolicy: .singleAttempt,
                retrySleep: { _ in }
            )

            do {
                try await backend.destroySessionByID(sessionID)
                Issue.record("Expected a nonzero zmx kill to report operationFailed")
            } catch let error as SessionBackendError {
                guard case .operationFailed = error else {
                    Issue.record("Expected operationFailed, got \(error)")
                    return
                }
            } catch {
                Issue.record("Expected SessionBackendError.operationFailed, got \(error)")
                return
            }

            #expect(
                executor.calls
                    == [
                        MockProcessExecutor.Call(
                            command: zmxPath,
                            args: ["kill", sessionID.rawValue],
                            environment: ["ZMX_DIR": zmxDir]
                        )
                    ]
            )
        }

        // MARK: - zmx Binary Path Resolution

        @Test
        func test_zmxBinaryPath_resolved() {
            // Act
            let config = SessionConfiguration.detect()

            // Assert — zmxPath should be resolved (zmx may or may not be installed)
            if let path = config.zmxPath {
                #expect(path.hasPrefix("/"))
                #expect(FileManager.default.isExecutableFile(atPath: path))
            }
            // If zmxPath is nil, zmx is not installed — that's fine for CI
        }
    }
}
