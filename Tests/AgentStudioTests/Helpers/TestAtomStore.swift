@testable import AgentStudio

@MainActor
private var hasInstalledSharedTestAtomScope = false

@MainActor
func installTestAtomScopeIfNeeded() {
    guard !hasInstalledSharedTestAtomScope else { return }
    AtomScope.setUp(AtomStore())
    hasInstalledSharedTestAtomScope = true
}

@MainActor
func withTestAtomStore<T>(
    _ body: (AtomStore) throws -> T
) rethrows -> T {
    installTestAtomScopeIfNeeded()
    let atoms = AtomStore()
    return try AtomScope.$override.withValue(atoms) {
        try body(atoms)
    }
}
