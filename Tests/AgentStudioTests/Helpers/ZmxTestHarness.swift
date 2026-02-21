import Darwin
import Foundation

@testable import AgentStudio

/// Isolated zmx environment for integration tests.
/// Each test run uses a unique ZMX_DIR (temp directory) to prevent cross-test interference.
final class ZmxTestHarness {
    private struct SpawnedProcess {
        let process: Process
        let processID: pid_t
    }

    let zmxDir: String
    let zmxPath: String?
    private let executor: DefaultProcessExecutor
    private var spawnedProcesses: [SpawnedProcess] = []

    init() {
        let shortId = UUID().uuidString.prefix(8).lowercased()
        // Use /tmp directly (not NSTemporaryDirectory) to keep socket paths under
        // the 104-byte Unix domain socket limit. Session IDs are 65 chars, so
        // ZMX_DIR must be short: /tmp/zt-<8chars>/ = 16 chars + 65 = 81 < 104.
        self.zmxDir = "/tmp/zt-\(shortId)"
        self.executor = DefaultProcessExecutor()

        // Resolve zmx binary: check vendored build first, then system PATH
        // 1. Vendored binary (built by scripts/build-zmx.sh or zig build)
        let vendoredPath = Self.findVendoredZmx()
        if let vendored = vendoredPath {
            self.zmxPath = vendored
        } else if let found = ["/opt/homebrew/bin/zmx", "/usr/local/bin/zmx"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        {
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
                    // Parse both full list output (`session_name=<id> ...`) and short output (`<id>`).
                    if let name = Self.extractSessionName(from: session),
                        name.hasPrefix(ZmxBackend.sessionPrefix)
                    {
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

        terminateSpawnedProcesses()

        // Remove the temp directory
        try? FileManager.default.removeItem(atPath: zmxDir)
    }

    /// Spawn a zmx attach command against a real zmx daemon.
    ///
    /// The returned process must be awaited by callers through `cleanup()`.
    func spawnZmxSession(
        zmxPath: String,
        sessionId: String,
        commandArgs: [String]
    ) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: zmxPath)
        process.arguments = ["attach", sessionId] + commandArgs
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = Pipe()
        var env = ProcessInfo.processInfo.environment
        env["ZMX_DIR"] = zmxDir
        process.environment = env
        try process.run()

        let processID = process.processIdentifier
        spawnedProcesses.append(
            SpawnedProcess(
                process: process,
                processID: processID
            ))

        return process
    }

    /// Walk up from the test binary to find vendor/zmx/zig-out/bin/zmx.
    private static func findVendoredZmx() -> String? {
        // The test binary is deep inside .build/; walk up to find the project root.
        var dir = URL(fileURLWithPath: #filePath)  // .../Tests/AgentStudioTests/Helpers/ZmxTestHarness.swift
        for _ in 0..<4 { dir = dir.deletingLastPathComponent() }  // → project root
        let candidate = dir.appendingPathComponent("vendor/zmx/zig-out/bin/zmx").path
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
    }

    static func extractSessionName(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace)
        for token in tokens {
            if token.hasPrefix("session_name=") {
                let value = token.dropFirst("session_name=".count)
                return value.isEmpty ? nil : String(value)
            }
        }

        // Fallback for short output: first token is the raw session id.
        guard let first = tokens.first, !first.contains("=") else { return nil }
        return String(first)
    }

    private func terminateSpawnedProcesses() {
        for entry in spawnedProcesses {
            if entry.processID <= 0 {
                continue
            }

            let descendants = collectDescendantProcessIDs(
                of: entry.processID
            )
            for pid in ([entry.processID] + descendants).reversed() {
                if pid > 0 {
                    let _ = Darwin.kill(pid, SIGKILL)
                }
            }

            if entry.process.isRunning {
                entry.process.terminate()
            }
        }

        spawnedProcesses.removeAll()
    }

    private func collectDescendantProcessIDs(of pid: pid_t) -> [pid_t] {
        var descendants: [pid_t] = []
        var queue: [pid_t] = [pid]

        while let current = queue.popLast() {
            let children = childProcessIDs(of: current)
            descendants.append(contentsOf: children)
            queue.append(contentsOf: children)
        }

        return descendants
    }

    private func childProcessIDs(of parentPID: pid_t) -> [pid_t] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", "\(parentPID)"]
        process.standardOutput = Pipe()
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }

            guard
                let outputData = (process.standardOutput as? Pipe)?
                    .fileHandleForReading
                    .readDataToEndOfFile(),
                let output = String(data: outputData, encoding: .utf8)
            else {
                return []
            }

            return
                output
                .split(whereSeparator: \.isNewline)
                .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .map { pid_t($0) }
        } catch {
            return []
        }
    }

}
