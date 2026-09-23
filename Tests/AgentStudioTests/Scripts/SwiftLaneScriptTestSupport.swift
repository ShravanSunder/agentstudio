import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation

/// The outcome of one bash command run by a Swift lane runner test.
struct LaneScriptBashResult: Sendable {
    let exitCode: Int32
    let output: String
}

/// Runs one bash command from the repository root with stdout and stderr merged.
///
/// The child is awaited off the cooperative pool: on a 3-core CI runner a
/// blocking wait here would starve every other suite's tasks.
func runLaneScriptBash(_ command: String) async throws -> LaneScriptBashResult {
    try await withoutBlockingCooperativePool {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "swift-lane-runner-output-\(UUIDv7.generate().uuidString).log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        process.standardOutput = outputHandle
        process.standardError = outputHandle
        try process.run()
        process.waitUntilExit()
        try outputHandle.close()
        return LaneScriptBashResult(
            exitCode: process.terminationStatus,
            output: try String(contentsOf: outputURL, encoding: .utf8)
        )
    }
}

/// The body of one `name() {` shell function, up to its closing brace.
func laneScriptShellFunction(named functionName: String, in script: String) throws -> String {
    try laneScriptNamedBlock(startingWith: "\(functionName)() {", endingBefore: "\n}\n", in: script)
}

/// The text from `marker` up to (not including) the next `terminator`, or to the end.
func laneScriptNamedBlock(startingWith marker: String, endingBefore terminator: String, in text: String) throws
    -> String
{
    guard let startRange = text.range(of: marker) else {
        throw LaneScriptTestError.missingBlock(marker)
    }
    let tail = text[startRange.lowerBound...]
    guard let endRange = tail.range(of: terminator, range: tail.index(after: startRange.lowerBound)..<tail.endIndex)
    else {
        return String(tail)
    }
    return String(tail[..<endRange.lowerBound])
}

enum LaneScriptTestError: Error {
    case missingBlock(String)
}
