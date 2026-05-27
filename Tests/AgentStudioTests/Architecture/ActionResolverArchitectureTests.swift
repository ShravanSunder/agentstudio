import Foundation
import Testing

@testable import AgentStudio

@Suite("ActionResolverArchitectureTests")
struct ActionResolverArchitectureTests {
    @Test("workspace command resolver switch is exhaustive")
    func workspaceCommandResolverSwitchIsExhaustive() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let resolverPath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/Actions/ActionResolver.swift"
        )
        let source = try String(contentsOf: resolverPath, encoding: .utf8)

        #expect(source.range(of: #"default\s*:\s*return\s+nil"#, options: .regularExpression) == nil)
    }
}
