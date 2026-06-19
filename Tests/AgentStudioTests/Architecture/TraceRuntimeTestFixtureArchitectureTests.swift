import Foundation
import Testing

@Suite("Trace runtime test fixture architecture")
struct TraceRuntimeTestFixtureArchitectureTests {
    @Test("trace runtime test fixtures choose an explicit backend")
    func traceRuntimeTestFixturesChooseExplicitBackend() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let testRoot = projectRoot.appending(path: "Tests/AgentStudioTests")
        let sourceFiles = try swiftSourceFiles(in: testRoot)
        var violations: [String] = []

        for sourceFile in sourceFiles {
            guard sourceFile.lastPathComponent != "AgentStudioTraceConfigurationTests.swift" else {
                continue
            }

            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            for block in traceConfigurationEnvironmentBlocks(in: source) {
                guard block.contains("\"AGENTSTUDIO_TRACE_TAGS\""),
                    !block.contains("\"AGENTSTUDIO_TRACE_BACKEND\"")
                else {
                    continue
                }
                violations.append(sourceFile.path.replacingOccurrences(of: projectRoot.path + "/", with: ""))
            }
        }

        #expect(
            violations.isEmpty,
            Comment(
                rawValue: "Trace runtime test fixtures must set AGENTSTUDIO_TRACE_BACKEND explicitly: "
                    + violations.sorted().joined(separator: ", ")
            )
        )
    }

    private func swiftSourceFiles(in root: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var sourceFiles: [URL] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true, fileURL.pathExtension == "swift" else {
                continue
            }
            sourceFiles.append(fileURL)
        }
        return sourceFiles
    }

    private func traceConfigurationEnvironmentBlocks(in source: String) -> [String] {
        let pattern = #"AgentStudioTraceConfiguration\.from\(environment:\s*\[(.*?)\]\)"#
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.dotMatchesLineSeparators]
            )
        else {
            return []
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                let blockRange = Range(match.range(at: 1), in: source)
            else {
                return nil
            }
            return String(source[blockRange])
        }
    }
}
