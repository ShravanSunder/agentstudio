@testable import AgentStudio

@MainActor
private var hasInstalledSharedTestAtomScope = false

@MainActor
func makeInstalledTestAtomRegistry() -> AtomRegistry {
    AtomRegistry(
        workspaceIdentity: WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())
    )
}

@MainActor
func installTestAtomRegistryIfNeeded() {
    guard !hasInstalledSharedTestAtomScope else { return }
    AtomScope.setUp(makeInstalledTestAtomRegistry())
    hasInstalledSharedTestAtomScope = true
}

@MainActor
func withTestAtomRegistry<T>(
    _ body: (AtomRegistry) throws -> T
) rethrows -> T {
    installTestAtomRegistryIfNeeded()
    let atoms = makeInstalledTestAtomRegistry()
    return try AtomScope.$override.withValue(atoms) {
        try body(atoms)
    }
}

@MainActor
func withAsyncTestAtomRegistry<T>(
    _ body: (AtomRegistry) async throws -> T
) async rethrows -> T {
    installTestAtomRegistryIfNeeded()
    let atoms = makeInstalledTestAtomRegistry()
    return try await AtomScope.$override.withValue(atoms) {
        try await body(atoms)
    }
}
