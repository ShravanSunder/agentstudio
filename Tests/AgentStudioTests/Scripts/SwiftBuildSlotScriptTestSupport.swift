import AgentStudioInfrastructure
import AgentStudioTestSupport
import Darwin
import Foundation

struct SwiftBuildSlotFixture: Sendable {
    let rootURL: URL
    let fakeExecutableDirectory: URL
    let openFilesMarkerURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "swift-build-slot-\(UUIDv7.generate().uuidString)")
        fakeExecutableDirectory = rootURL.appending(path: "fake-bin")
        openFilesMarkerURL = rootURL.appending(path: "open-files")
        let scriptsDirectory = rootURL.appending(path: "scripts")
        try FileManager.default.createDirectory(at: fakeExecutableDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)

        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        try FileManager.default.copyItem(
            at: projectRoot.appending(path: "scripts/swift-build-slot.sh"),
            to: scriptsDirectory.appending(path: "swift-build-slot.sh")
        )
        try writeExecutable("ps", contents: Self.fakePS)
        try writeExecutable("lsof", contents: Self.fakeLSOF)
        try writeExecutable("sleep", contents: Self.fakeSleep)
    }

    func run(_ script: String, environment: [String: String] = [:]) async throws -> SwiftBuildSlotResult {
        let fixture = self
        return try await withoutBlockingCooperativePool {
            let process = fixture.makeProcess(script, environment: environment)
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let text = try readOutputToEnd(output.fileHandleForReading)
            process.waitUntilExit()
            return SwiftBuildSlotResult(exitCode: process.terminationStatus, output: text)
        }
    }

    func makeProcess(_ script: String, environment overrides: [String: String] = [:]) -> Process {
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "SWIFT_BUILD_DIR")
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = "\(fakeExecutableDirectory.path):\(existingPath)"
        environment["SWIFT_BUILD_SLOT_FAKE_START"] = "Mon Sep 1 00:00:00 2025"
        environment["SWIFT_BUILD_SLOT_PS_REUSED_START"] = "Tue Sep 2 00:00:00 2025"
        environment["SWIFT_BUILD_SLOT_OPEN_FILES_MARKER"] = openFilesMarkerURL.path
        environment["SWIFT_BUILD_SLOT_FAKE_LSOF_PID"] = "4242"
        environment.merge(overrides, uniquingKeysWith: { _, newValue in newValue })

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        process.currentDirectoryURL = rootURL
        process.environment = environment
        return process
    }

    func createFIFO(at url: URL) throws {
        let status = mkfifo(url.path, mode_t(S_IRUSR | S_IWUSR))
        guard status == 0 else {
            throw SwiftBuildSlotScriptError.fifoCreationFailed(url.path, errno)
        }
    }

    func createClaim(slotDirectory: String, processID: String, startTime: String, task: String) throws {
        let claimDirectory = rootURL.appending(path: "\(slotDirectory)/.slot-claim")
        try FileManager.default.createDirectory(at: claimDirectory, withIntermediateDirectories: true)
        let holder = "\(processID)\t\(startTime)\t\(task)\n"
        try Data(holder.utf8).write(to: claimDirectory.appending(path: "holder"))
    }

    private func writeExecutable(_ name: String, contents: String) throws {
        let executableURL = fakeExecutableDirectory.appending(path: name)
        try Data(contents.utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
    }

    private static let fakePS = """
        #!/bin/sh
        process_id=""
        output_format=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -p) process_id="$2"; shift 2 ;;
            -o) output_format="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        case "$output_format" in
          lstart=)
            if [ "$process_id" = "${SWIFT_BUILD_SLOT_PS_REUSED_PID:-}" ]; then
              printf '%s\\n' "${SWIFT_BUILD_SLOT_PS_REUSED_START:-}"
            else
              printf '%s\\n' "${SWIFT_BUILD_SLOT_FAKE_START:-}"
            fi
            ;;
          command=) printf '%s\\n' 'fixture shell command' ;;
        esac
        """

    private static let fakeLSOF = """
        #!/bin/sh
        target=""
        pid_output=0
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "-t" ]; then pid_output=1; fi
          target="$1"
          shift
        done
        marker="${SWIFT_BUILD_SLOT_OPEN_FILES_MARKER:-}"
        if [ -n "$marker" ] && [ -e "$marker/all" -o -e "$marker/$(basename "$target")" ]; then
          if [ "$pid_output" -eq 1 ]; then printf '%s\\n' "${SWIFT_BUILD_SLOT_FAKE_LSOF_PID:-4242}"; fi
          exit 0
        fi
        exit 1
        """

    private static let fakeSleep = """
        #!/bin/sh
        if [ -n "${SWIFT_BUILD_SLOT_SLEEP_GATE:-}" ]; then
          IFS= read -r _ < "$SWIFT_BUILD_SLOT_SLEEP_GATE"
        else
          /bin/sleep "$@"
        fi
        """
}

struct SwiftBuildSlotResult: Sendable {
    let exitCode: Int32
    let output: String
}

enum SwiftBuildSlotScriptError: Error {
    case missingProcessOutput(String)
    case missingDescendantPID(String)
    case fifoCreationFailed(String, Int32)
    case invalidUTF8Output
    case missingFunction(String)
    case missingTask(String)
}

func readOutput(_ fileHandle: FileHandle, into output: inout String, until marker: String) throws {
    while !output.contains(marker) {
        let data = fileHandle.availableData
        guard !data.isEmpty else {
            throw SwiftBuildSlotScriptError.missingProcessOutput(marker)
        }
        guard let chunk = String(data: data, encoding: .utf8) else {
            throw SwiftBuildSlotScriptError.invalidUTF8Output
        }
        output += chunk
    }
}

func readOutputToEnd(_ fileHandle: FileHandle) throws -> String {
    let data = try fileHandle.readToEnd() ?? Data()
    guard let output = String(data: data, encoding: .utf8) else {
        throw SwiftBuildSlotScriptError.invalidUTF8Output
    }
    return output
}

func writeLine(_ line: String, to fifoURL: URL) throws {
    let fileHandle = try FileHandle(forWritingTo: fifoURL)
    fileHandle.write(Data(line.utf8))
    try fileHandle.close()
}

func swiftBuildSlotShellFunction(named functionName: String, in source: String) throws -> String {
    let marker = "\(functionName)() {"
    guard let start = source.range(of: marker) else {
        throw SwiftBuildSlotScriptError.missingFunction(functionName)
    }
    let tail = source[start.lowerBound...]
    guard let end = tail.range(of: "\n}") else {
        throw SwiftBuildSlotScriptError.missingFunction(functionName)
    }
    return String(tail[..<end.upperBound])
}

func miseTaskBody(named taskName: String, in config: String) throws -> String {
    let marker = "[tasks.\(taskName)]"
    guard let start = config.range(of: marker) else {
        throw SwiftBuildSlotScriptError.missingTask(taskName)
    }
    let tail = config[start.lowerBound...]
    let blockEnd = tail.range(of: "\n[tasks.")?.lowerBound ?? tail.endIndex
    let block = tail[..<blockEnd]
    guard let bodyStart = block.range(of: "run = \"\"\"\n") else {
        throw SwiftBuildSlotScriptError.missingTask(taskName)
    }
    let script = block[bodyStart.upperBound...]
    guard let bodyEnd = script.range(of: "\n\"\"\"")?.lowerBound else {
        throw SwiftBuildSlotScriptError.missingTask(taskName)
    }
    return String(script[..<bodyEnd])
}
