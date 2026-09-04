import Foundation
import Testing

@testable import AgentStudioTestSupport

@Suite("Bridge product transport opacity")
struct BridgeProductTransportOpacityTests {
    @Test("generic Swift transport does not interpret application content kinds")
    func genericSwiftTransportDoesNotInterpretApplicationContentKinds() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let contentHeaderSource = try source(
            at: "Sources/AgentStudio/Features/Bridge/Models/Transport/BridgeProductContentHeaders.swift",
            projectRoot: projectRoot
        )
        let contentFrameCodecSource = try source(
            at: "Sources/AgentStudio/Features/Bridge/Models/Transport/BridgeProductContentFrameCodec.swift",
            projectRoot: projectRoot
        )
        let sessionSource = try source(
            at: "Sources/AgentStudio/Features/Bridge/Transport/BridgeProductSession.swift",
            projectRoot: projectRoot
        )

        // Act
        let contentHeaderApplicationSwitch = contentHeaderSource.range(
            of: #"case \.(annotation|fileContent|review)"#,
            options: .regularExpression
        )
        let contentFrameCodecApplicationCheck = contentFrameCodecSource.range(
            of: #"contentKind\s*==\s*\.(annotation|fileContent|review)"#,
            options: .regularExpression
        )
        let closedSessionSurfaceInitialization = sessionSource.range(
            of: #"\.(file|review):\s*0"#,
            options: .regularExpression
        )

        // Assert
        #expect(contentHeaderApplicationSwitch == nil)
        #expect(contentFrameCodecApplicationCheck == nil)
        #expect(closedSessionSurfaceInitialization == nil)
    }

    private func source(at relativePath: String, projectRoot: URL) throws -> String {
        try String(contentsOf: projectRoot.appending(path: relativePath), encoding: .utf8)
    }
}
