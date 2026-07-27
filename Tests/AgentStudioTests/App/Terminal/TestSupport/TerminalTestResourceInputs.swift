import AgentStudioInfrastructure
import AgentStudioTestSupport

@MainActor
func makeTerminalTestOcticonLoader(from testFilePath: String = #filePath) -> OcticonLoader {
    OcticonLoader(
        resourceRootURL: testAgentStudioResourceRootURL(from: testFilePath)
    )
}
