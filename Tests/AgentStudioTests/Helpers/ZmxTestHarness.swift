import Foundation
import XCTest
@testable import AgentStudio

/// Isolated zmx environment for integration tests.
/// Each test run uses a unique ZMX_DIR (temp directory) to prevent cross-test interference.
final class ZmxTestHarness {
    let zmxDir: String
    let zmxPath: String?
    private let executor: DefaultProcessExecutor

    init() {
        let shortId = UUID().uuidString.prefix(8).lowercased()
        self.zmxDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmx-test-\(shortId)").path
        self.executor = DefaultProcessExecutor()

        // Resolve zmx binary: same fallback as SessionConfiguration.findZmx()
        // 1. Well-known PATH locations
        let candidates = [
            "/opt/homebrew/bin/zmx",
            "/usr/local/bin/zmx",
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            self.zmxPath = found
        } else {
            // 2. Fallback: check PATH via which
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = ["zmx"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let path = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    self.zmxPath = (path?.isEmpty == false) ? path : nil
                } else {
                    self.zmxPath = nil
                }
            } catch {
                self.zmxPath = nil
            }
        }
    }

    /// Create a ZmxBackend configured with the test-isolated ZMX_DIR.
    func createBackend() -> ZmxBackend? {
        guard let zmxPath else { return nil }
        return ZmxBackend(executor: executor, zmxPath: zmxPath, zmxDir: zmxDir)
    }

    /// Create a ZmxBackend with a custom executor (for mixed mock/real testing).
    func createBackend(executor: ProcessExecutor) -> ZmxBackend? {
        guard let zmxPath else { return nil }
        return ZmxBackend(executor: executor, zmxPath: zmxPath, zmxDir: zmxDir)
    }

    /// Clean up all sessions in the test ZMX_DIR and remove the temp directory.
    func cleanup() async {
        guard let zmxPath else { return }

        // Kill all sessions in our isolated ZMX_DIR
        do {
            let result = try await executor.execute(
                command: zmxPath,
                args: ["list"],
                cwd: nil,
                environment: ["ZMX_DIR": zmxDir]
            )
            if result.succeeded {
                let sessions = result.stdout
                    .components(separatedBy: "\n")
                    .filter { !$0.isEmpty }
                for session in sessions {
                    // Extract session name (first whitespace-delimited token)
                    if let name = session.components(separatedBy: CharacterSet.whitespaces).first,
                       name.hasPrefix(ZmxBackend.sessionPrefix) {
                        _ = try? await executor.execute(
                            command: zmxPath,
                            args: ["kill", name],
                            cwd: nil,
                            environment: ["ZMX_DIR": zmxDir]
                        )
                    }
                }
            }
        } catch {
            // zmx not found or other error — nothing to clean up
        }

        // Remove the temp directory
        try? FileManager.default.removeItem(atPath: zmxDir)
    }
}
