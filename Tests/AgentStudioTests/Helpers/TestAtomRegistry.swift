@testable import AgentStudio

@MainActor private var hasInstalledSharedTestCoreAtomScope = false

@MainActor
func makeInstalledTestCoreAtoms() -> CoreAtoms {
    CoreAtoms(
        workspaceIdentity: WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())
    )
}

@MainActor
func installTestCoreAtomsIfNeeded() {
    guard !hasInstalledSharedTestCoreAtomScope else { return }
    CoreAtomScope.setUp(makeInstalledTestCoreAtoms())
    hasInstalledSharedTestCoreAtomScope = true
}

@MainActor
func withTestCoreAtoms<T>(
    using coreAtoms: CoreAtoms = makeInstalledTestCoreAtoms(),
    _ body: (CoreAtoms) throws -> T
) rethrows -> T {
    installTestCoreAtomsIfNeeded()
    return try CoreAtomScope.$override.withValue(coreAtoms) {
        try body(coreAtoms)
    }
}

@MainActor
func withAsyncTestCoreAtoms<T>(
    using coreAtoms: CoreAtoms = makeInstalledTestCoreAtoms(),
    _ body: (CoreAtoms) async throws -> T
) async rethrows -> T {
    installTestCoreAtomsIfNeeded()
    return try await CoreAtomScope.$override.withValue(coreAtoms) {
        try await body(coreAtoms)
    }
}

@MainActor
func makeTestAtomRegistry() -> AtomRegistry {
    AtomRegistry(core: makeInstalledTestCoreAtoms())
}
