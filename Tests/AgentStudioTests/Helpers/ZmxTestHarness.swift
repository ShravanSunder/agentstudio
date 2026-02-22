import Darwin
import Foundation

@testable import AgentStudio

/// Isolated zmx environment for integration tests.
/// Each test run uses a unique ZMX_DIR (temp directory) to prevent cross-test interference.
final class ZmxTestHarness: @unchecked Sendable {
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
        // Keep zmx subprocess calls short in tests; backend-level retry handles transient failures.
        self.executor = DefaultProcessExecutor(timeout: 0.5)

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
        // Always attempt process + directory cleanup, even when zmx isn't available.
        defer {
            try? FileManager.default.removeItem(atPath: zmxDir)
        }

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

        // Remove the temp directory in defer.
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
        let projectRoot = TestPathResolver.projectRoot(from: #filePath)
        let candidate = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent("vendor/zmx/zig-out/bin/zmx")
            .path
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
        let parentProcessGroup = getpid() > 0 ? processGroupID(for: getpid()) : nil

        for entry in spawnedProcesses {
            if entry.processID <= 0 {
                continue
            }

            if let processGroup = processGroupID(for: entry.processID),
                let parentGroup = parentProcessGroup,
                processGroup > 0,
                processGroup != parentGroup
            {
                terminateProcess(-processGroup, signal: SIGKILL)
            } else {
                let descendants = collectDescendantProcessIDs(
                    of: entry.processID
                )
                for pid in ([entry.processID] + descendants).reversed() {
                    if pid > 0 {
                        terminateProcess(pid, signal: SIGKILL)
                    }
                }
            }

            if entry.process.isRunning {
                entry.process.terminate()
            }
        }

        spawnedProcesses.removeAll()
    }

    private func processGroupID(for pid: pid_t) -> pid_t? {
        let pgid = getpgid(pid)
        return pgid > 0 ? pgid : nil
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
        let pgrepPath = "/usr/bin/pgrep"
        guard FileManager.default.isExecutableFile(atPath: pgrepPath) else {
            logError("pgrep is not executable at \(pgrepPath); cannot enumerate child processes")
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pgrepPath)
        process.arguments = ["-P", "\(parentPID)"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            let outputData = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
            let errorData = try errorPipe.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()

            switch process.terminationStatus {
            case 0:
                guard let output = String(data: outputData, encoding: .utf8) else {
                    logError("pgrep produced non-UTF8 output for parent PID \(parentPID)")
                    return []
                }
                return
                    output
                    .split(whereSeparator: \.isNewline)
                    .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .map { pid_t($0) }

            case 1:
                return []

            default:
                let stderr = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let details = stderr.map { " stderr=\($0)" } ?? ""
                logError(
                    "pgrep failed for parent PID \(parentPID) with exit status \(process.terminationStatus).\(details)")
                return []
            }
        } catch {
            logError("pgrep invocation failed for parent PID \(parentPID): \(error)")
            return []
        }
    }

    private func terminateProcess(_ pid: pid_t, signal: Int32) {
        guard pid != 0 else { return }
        let result = Darwin.kill(pid, signal)
        if result == 0 { return }

        let code = errno
        let message = String(cString: strerror(code))
        if code == ESRCH {
            return
        }

        if code == EPERM {
            logError("kill permission denied for pid \(pid) with signal \(signal): \(message) (errno \(code))")
            return
        }

        logError("failed to kill pid \(pid) with signal \(signal): \(message) (errno \(code))")
    }

    private func logError(_ message: String) {
        let data = Data("[ZmxTestHarness] \(message)\n".utf8)
        if !data.isEmpty {
            FileHandle.standardError.write(data)
        }
    }

}
