import Foundation

package func testAgentStudioResourceRootURL(from testFilePath: String = #filePath) -> URL {
    URL(
        fileURLWithPath: TestPathResolver.projectRoot(from: testFilePath),
        isDirectory: true
    )
    .appending(path: "Sources/AgentStudio/Resources", directoryHint: .isDirectory)
}

package func testBridgeAppRootURL(from testFilePath: String = #filePath) -> URL {
    testAgentStudioResourceRootURL(from: testFilePath)
        .appending(path: "BridgeWeb/app", directoryHint: .isDirectory)
}
