import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@Suite("App AtomRegistry installation preconditions")
struct AppAtomRegistryInstallationExitTests {
    @Test("Core access before App setup fails")
    func accessBeforeSetupFails() async throws {
        let result = try await #require(
            processExitsWith: .failure,
            observing: [\.standardErrorContent]
        ) {
            await MainActor.run {
                _ = CoreAtomScope.store
            }
        }

        let standardError = try #require(
            String(bytes: result.standardErrorContent, encoding: .utf8)
        )
        #expect(
            standardError.contains(
                "CoreAtomScope.store accessed before CoreAtomScope.setUp(_:)"
            )
        )
    }

    @Test("App setup installs its exact Core graph and rejects a second setup")
    func secondSetupFailsAfterExactAppCoreIdentityIsProved() async throws {
        let result = try await #require(
            processExitsWith: .failure,
            observing: [\.standardErrorContent]
        ) {
            await MainActor.run {
                let atomRegistry = AtomRegistry()
                CoreAtomScope.setUp(atomRegistry.core)
                precondition(
                    CoreAtomScope.store === atomRegistry.core,
                    "child-created App root Core identity mismatch"
                )
                CoreAtomScope.setUp(CoreAtoms())
            }
        }

        let standardError = try #require(
            String(bytes: result.standardErrorContent, encoding: .utf8)
        )
        #expect(standardError.contains("CoreAtomScope.setUp(_:) called more than once"))
        #expect(!standardError.contains("child-created App root Core identity mismatch"))
    }
}
