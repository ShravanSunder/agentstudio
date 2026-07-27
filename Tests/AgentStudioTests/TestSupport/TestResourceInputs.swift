import Foundation

@testable import AgentStudio

@MainActor
func makeTestOcticonLoader(from testFilePath: String = #filePath) -> OcticonLoader {
    OcticonLoader(
        resourceRootURL: testAgentStudioResourceRootURL(from: testFilePath)
    )
}

func testAgentStudioResourceRootURL(from testFilePath: String = #filePath) -> URL {
    URL(
        fileURLWithPath: TestPathResolver.projectRoot(from: testFilePath),
        isDirectory: true
    )
    .appending(path: "Sources/AgentStudio/Resources", directoryHint: .isDirectory)
}

func testBridgeAppRootURL(from testFilePath: String = #filePath) -> URL {
    testAgentStudioResourceRootURL(from: testFilePath)
        .appending(path: "BridgeWeb/app", directoryHint: .isDirectory)
}
