import AgentStudioTestHarness
import Foundation
import Testing

@Suite("Real test tool resolution")
struct TestRealToolResolverTests {
    @Test("test launchers do not invoke the shared system tool aliases")
    func launchersAvoidSystemAliases() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let files = try #require(
            FileManager.default.enumerator(
                at: root.appending(path: "Tests"), includingPropertiesForKeys: nil))
        var violations: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            // Architecture assertions mention prohibited spellings; the resolver
            // itself stats the aliases for its identity receipt, never launches them.
            guard !file.path.contains("/Architecture/"),
                file.lastPathComponent != "ResolvedTestTools.swift"
            else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            for (offset, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if line.contains("/usr/bin/" + "git") || line.contains("/usr/bin/" + "python3") {
                    violations.append("\(file.path):\(offset + 1)")
                }
            }
        }
        #expect(violations.isEmpty, Comment(rawValue: violations.joined(separator: "\n")))
    }
}
