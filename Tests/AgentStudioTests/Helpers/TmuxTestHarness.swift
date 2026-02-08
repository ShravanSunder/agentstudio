import Foundation
import XCTest
@testable import AgentStudio

/// Isolated tmux environment for integration tests.
/// Each test run uses a unique socket name to prevent cross-test interference.
final class TmuxTestHarness {
    let socketName: String
    let ghostConfigPath: String
    private let executor: DefaultProcessExecutor

    init() {
        let shortId = UUID().uuidString.prefix(8).lowercased()
        self.socketName = "agentstudio-test-\(shortId)"
        self.executor = DefaultProcessExecutor()

        // Resolve ghost.conf from source tree
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Helpers/
            .deletingLastPathComponent() // AgentStudioTests/
            .deletingLastPathComponent() // Tests/
        let candidate = projectRoot.appendingPathComponent("Sources/AgentStudio/Resources/tmux/ghost.conf")
        if FileManager.default.fileExists(atPath: candidate.path) {
            self.ghostConfigPath = candidate.path
        } else {
            // Fallback for different build layouts
            self.ghostConfigPath = "/tmp/ghost-test.conf"
        }
    }

    /// Create a TmuxBackend configured with the test socket.
    func createBackend() -> TmuxBackend {
        TmuxBackend(executor: executor, ghostConfigPath: ghostConfigPath, socketName: socketName)
    }

    /// Create a TmuxBackend with a custom executor (for mixed mock/real testing).
    func createBackend(executor: ProcessExecutor) -> TmuxBackend {
        TmuxBackend(executor: executor, ghostConfigPath: ghostConfigPath, socketName: socketName)
    }

    /// Clean up all sessions on the test socket.
    /// Retries up to 3 times with 1-second sleep for robustness.
    func cleanup() async {
        for attempt in 0..<3 {
            do {
                let result = try await executor.execute(
                    command: "tmux",
                    args: ["-L", socketName, "kill-server"],
                    cwd: nil,
                    environment: nil
                )
                if result.succeeded || result.stderr.contains("no server running") {
                    return
                }
            } catch {
                // tmux not found or other error — nothing to clean up
                return
            }

            if attempt < 2 {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
