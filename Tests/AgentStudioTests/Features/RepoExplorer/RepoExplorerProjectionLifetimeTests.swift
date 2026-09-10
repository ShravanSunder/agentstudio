import AgentStudioCore
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

private final class RepoExplorerWeakObjectReference<TObject: AnyObject> {
    weak var value: TObject?

    init(_ value: TObject) {
        self.value = value
    }
}

@MainActor
private func retireDemandedProjection(
    atoms: CoreAtoms
) async -> RepoExplorerWeakObjectReference<RepoExplorerProjectionInputCapture> {
    let store = WorkspaceStore(
        catalogAtom: atoms.workspaceRepositoryTopology,
        graphAtom: atoms.workspacePane,
        interactionAtom: atoms.workspaceTabLayout
    )
    let inputCapture = RepoExplorerProjectionInputCapture(
        store: store,
        preferences: RepoExplorerSidebarPrefsAtom(),
        repoCache: atoms.repoCache,
        sidebarState: atoms.workspaceSidebarState,
        sidebarCache: atoms.sidebarCache,
        coreAtoms: atoms,
        bridgeAttendanceSnapshot: { _ in nil },
        latestPaneMessageSnapshot: { _ in nil }
    )
    let adapter = RepoExplorerProjectionAdapter(inputCapture: inputCapture)
    let host = registerProjectionTestMaterializationHost(adapter: adapter)

    adapter.updateDemand(isVisible: true, query: "")
    let deadline = ContinuousClock.now + .seconds(5)
    while adapter.publishedResult == nil, ContinuousClock.now < deadline {
        await Task.yield()
    }

    #expect(adapter.publishedResult != nil)
    #expect(adapter.observationTokens.contains(.demand))

    await adapter.stopAndDrain()
    host.detach()
    return RepoExplorerWeakObjectReference(inputCapture)
}

@MainActor
@Suite("RepoExplorer projection lifetime", .serialized)
struct RepoExplorerProjectionLifetimeTests {
    @MainActor
    @Test("stopping demanded projection releases its input capture while source atoms remain live")
    func stoppingDemandedProjectionReleasesInputCapture() async {
        await withAsyncTestCoreAtoms { atoms in
            let inputCaptureReference = await retireDemandedProjection(atoms: atoms)

            #expect(inputCaptureReference.value == nil)
            #expect(atoms.workspaceRepositoryTopology.repositoryIdsInOrder.isEmpty)
        }
    }
}
