import Testing

@testable import AgentStudio

@MainActor
struct AtomScopeTests {
    @Test
    func overrideStore_winsWithinScopedBlock_only() async throws {
        installTestAtomScopeIfNeeded()
        let production = AtomScope.store
        let override = AtomStore()
        #expect(AtomScope.store === production)

        AtomScope.$override.withValue(override) {
            #expect(AtomScope.store === override)
        }

        #expect(AtomScope.store === production)
    }
}
