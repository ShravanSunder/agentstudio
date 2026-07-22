import Darwin
import Foundation

struct LauncherScriptFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-launcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func url(_ relativePath: String) -> URL {
        root.appending(path: relativePath)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    func executable(_ name: String, _ contents: String) throws -> URL {
        let executableURL = url(name)
        try contents.write(to: executableURL, atomically: true, encoding: .utf8)
        chmod(executableURL.path, 0o755)
        return executableURL
    }

    func makeAppBundle(
        name: String,
        releaseChannel: String,
        bundleIdentifier: String = "com.agentstudio.app.beta"
    ) throws -> URL {
        let appURL = url(name)
        let contentsURL = appURL.appending(path: "Contents")
        let macOSURL = contentsURL.appending(path: "MacOS")
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleIdentifier</key>
          <string>\(bundleIdentifier)</string>
          <key>CFBundleShortVersionString</key>
          <string>0.0.0-test</string>
          <key>AgentStudioReleaseChannel</key>
          <string>\(releaseChannel)</string>
        </dict>
        </plist>
        """.write(to: contentsURL.appending(path: "Info.plist"), atomically: true, encoding: .utf8)
        let binaryURL = macOSURL.appending(path: "AgentStudio")
        try "#!/bin/bash\nexit 0\n".write(to: binaryURL, atomically: true, encoding: .utf8)
        chmod(binaryURL.path, 0o755)
        return appURL
    }

    func makeDebugBuildExecutable(_ contents: String) throws -> URL {
        let buildPath = url("debug-build")
        let debugPath = buildPath.appending(path: "debug")
        try FileManager.default.createDirectory(at: debugPath, withIntermediateDirectories: true)
        let binaryURL = debugPath.appending(path: "AgentStudio")
        try contents.write(to: binaryURL, atomically: true, encoding: .utf8)
        chmod(binaryURL.path, 0o755)
        return buildPath
    }

    func runScript(
        _ scriptPath: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> ScriptRunResult {
        let stackHelper = try executable(
            "observability-stack",
            """
            #!/bin/bash
            if [ "${1:-}" = "collector-url" ]; then
              echo "http://127.0.0.1:4318"
            fi
            exit 0
            """
        )
        let curl = try executable(
            "curl",
            """
            #!/bin/bash
            exit 0
            """
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var mergedEnvironment = ProcessInfo.processInfo.environment
        mergedEnvironment["AGENTSTUDIO_OBSERVABILITY_ALLOW_TEST_OVERRIDES"] = "1"
        mergedEnvironment["AI_TOOLS_OBSERVABILITY_STACK_HELPER"] = stackHelper.path
        mergedEnvironment["AI_TOOLS_OBSERVABILITY_COLLECTOR_HEALTH_URL"] = "http://127.0.0.1:13133/"
        mergedEnvironment["AGENTSTUDIO_CURL_BIN"] = curl.path
        mergedEnvironment["AGENTSTUDIO_DEBUG_ARTIFACT_DIR"] = url("debug-app-artifacts").path
        mergedEnvironment["AGENTSTUDIO_DEBUG_BUILD_PATH"] = url("debug-build").path
        for (key, value) in environment {
            mergedEnvironment[key] = value
        }
        process.environment = mergedEnvironment

        return try run(process)
    }

    func runVerifier(
        scriptPath: String = "scripts/verify-beta-observability.sh",
        stateFile: URL,
        environment: [String: String]
    ) throws -> ScriptRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var mergedEnvironment = ProcessInfo.processInfo.environment
        mergedEnvironment["AGENTSTUDIO_OBSERVABILITY_STATE_FILE"] = stateFile.path
        for (key, value) in environment {
            mergedEnvironment[key] = value
        }
        process.environment = mergedEnvironment

        return try run(process)
    }

    func worktreeDebugCode(for rootPath: String = FileManager.default.currentDirectoryPath) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "-c",
            """
            import hashlib, os, sys
            alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
            space = 36 ** 4
            root = os.path.realpath(sys.argv[1])
            value = int.from_bytes(hashlib.sha256(root.encode("utf-8")).digest()[:4], "big") % space
            chars = []
            for _ in range(4):
                value, digit = divmod(value, 36)
                chars.append(alphabet[digit])
            print("".join(reversed(chars)))
            """,
            rootPath,
        ]
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        process.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func waitForFile(_ url: URL, timeoutSeconds: TimeInterval) throws {
        let condition: @Sendable () -> Bool = {
            FileManager.default.fileExists(atPath: url.path)
        }
        guard waitForFileSystemCondition(url, timeoutSeconds: timeoutSeconds, condition: condition) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
    }

    func waitForFile(_ url: URL, containing expectedContent: String, timeoutSeconds: TimeInterval) throws {
        let condition: @Sendable () -> Bool = {
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                return false
            }
            return contents.contains(expectedContent)
        }
        guard waitForFileSystemCondition(url, timeoutSeconds: timeoutSeconds, condition: condition) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
    }

    private func waitForFileSystemCondition(
        _ url: URL,
        timeoutSeconds: TimeInterval,
        condition: @escaping @Sendable () -> Bool
    ) -> Bool {
        let deadline = DispatchTime.now() + .nanoseconds(Int(timeoutSeconds * 1_000_000_000))
        while DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds {
            if condition() {
                return true
            }
            waitForFileSystemChange(affecting: url, until: deadline)
        }
        return condition()
    }

    private func waitForFileSystemChange(affecting url: URL, until deadline: DispatchTime) {
        let watchedURL = FileManager.default.fileExists(atPath: url.path) ? url : url.deletingLastPathComponent()
        let fileDescriptor = open(watchedURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return
        }
        let eventSemaphore = DispatchSemaphore(value: 0)
        let cancelSemaphore = DispatchSemaphore(value: 0)
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        source.setEventHandler {
            eventSemaphore.signal()
        }
        source.setCancelHandler {
            close(fileDescriptor)
            cancelSemaphore.signal()
        }
        source.resume()
        _ = eventSemaphore.wait(timeout: deadline)
        source.cancel()
        cancelSemaphore.wait()
    }

    private func run(_ process: Process) throws -> ScriptRunResult {
        let output = ProcessOutputCapture()
        let stdout = Pipe()
        let stderr = Pipe()
        output.capture(stdout, as: .stdout)
        output.capture(stderr, as: .stderr)
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        output.finish(stdout, as: .stdout)
        output.finish(stderr, as: .stderr)
        return ScriptRunResult(
            exitCode: process.terminationStatus,
            stdout: output.stdout,
            stderr: output.stderr
        )
    }
}

func shellEscapedStateValue(_ value: String) -> String {
    value.replacingOccurrences(of: " ", with: "\\ ")
}

struct ScriptRunResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private final class ProcessOutputCapture: @unchecked Sendable {
    enum Stream {
        case stdout
        case stderr
    }

    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()

    var stdout: String {
        lock.withLock {
            String(data: stdoutData, encoding: .utf8) ?? ""
        }
    }

    var stderr: String {
        lock.withLock {
            String(data: stderrData, encoding: .utf8) ?? ""
        }
    }

    func capture(_ pipe: Pipe, as stream: Stream) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.append(data, to: stream)
        }
    }

    func finish(_ pipe: Pipe, as stream: Stream) {
        pipe.fileHandleForReading.readabilityHandler = nil
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if !data.isEmpty {
            append(data, to: stream)
        }
    }

    private func append(_ data: Data, to stream: Stream) {
        lock.withLock {
            switch stream {
            case .stdout:
                stdoutData.append(data)
            case .stderr:
                stderrData.append(data)
            }
        }
    }
}
