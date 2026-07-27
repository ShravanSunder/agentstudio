@testable import AgentStudio
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
func makeTestAtomRegistry() -> AtomRegistry {
    AtomRegistry(core: makeInstalledTestCoreAtoms())
}

@MainActor
func makeTestOcticonLoader(from testFilePath: String = #filePath) -> OcticonLoader {
    OcticonLoader(
        resourceRootURL: testAgentStudioResourceRootURL(from: testFilePath)
    )
}
