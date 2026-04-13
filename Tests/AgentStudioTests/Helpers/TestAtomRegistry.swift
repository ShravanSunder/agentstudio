@testable import AgentStudio

@MainActor
private var hasInstalledSharedTestAtomScope = false

@MainActor
func installTestAtomRegistryIfNeeded() {
    guard !hasInstalledSharedTestAtomScope else { return }
    AtomScope.setUp(AtomRegistry())
    hasInstalledSharedTestAtomScope = true
}

@MainActor
func withTestAtomRegistry<T>(
    _ body: (AtomRegistry) throws -> T
) rethrows -> T {
    installTestAtomRegistryIfNeeded()
    let atoms = AtomRegistry()
    return try AtomScope.$override.withValue(atoms) {
        try body(atoms)
    }
}
