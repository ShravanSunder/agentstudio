import AgentStudioCore
import Foundation

@MainActor private var hasInstalledSharedTestCoreAtomScope = false

@MainActor
package func makeInstalledTestCoreAtoms() -> CoreAtoms {
    CoreAtoms(
        workspaceIdentity: WorkspaceIdentityAtom(workspaceId: UUID()),
        applicationEntityRecency: ApplicationEntityRecencyAtom(
            now: { Date(timeIntervalSince1970: 1000) }
        )
    )
}

@MainActor
package func installTestCoreAtomsIfNeeded() {
    guard !hasInstalledSharedTestCoreAtomScope else { return }
    CoreAtomScope.setUp(makeInstalledTestCoreAtoms())
    hasInstalledSharedTestCoreAtomScope = true
}

@MainActor
package func withTestCoreAtoms<T>(
    using coreAtoms: CoreAtoms = makeInstalledTestCoreAtoms(),
    _ body: (CoreAtoms) throws -> T
) rethrows -> T {
    installTestCoreAtomsIfNeeded()
    return try CoreAtomScope.$override.withValue(coreAtoms) {
        try body(coreAtoms)
    }
}

@MainActor
package func withAsyncTestCoreAtoms<T>(
    using coreAtoms: CoreAtoms = makeInstalledTestCoreAtoms(),
    _ body: (CoreAtoms) async throws -> T
) async rethrows -> T {
    installTestCoreAtomsIfNeeded()
    return try await CoreAtomScope.$override.withValue(coreAtoms) {
        try await body(coreAtoms)
    }
}
