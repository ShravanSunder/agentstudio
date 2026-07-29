import AgentStudioInfrastructure
import Foundation

@MainActor
func makeSharedComponentsTestOcticonLoader(from testFilePath: String = #filePath) -> OcticonLoader {
    let sourceFileURL = URL(fileURLWithPath: testFilePath)
    let resourceRootURL =
        sourceFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/AgentStudio/Resources", directoryHint: .isDirectory)

    return OcticonLoader(resourceRootURL: resourceRootURL)
}
