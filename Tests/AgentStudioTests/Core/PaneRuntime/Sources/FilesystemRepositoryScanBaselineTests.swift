import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("Filesystem canonical scan baseline")
struct FilesystemRepositoryScanBaselineTests {
    @Test("a newer baseline drops collected checkout paths and rejects stale snapshots")
    func canonicalBaselineKeepsRevisionAndRetainedLocationsTogether() async {
        let root = URL(fileURLWithPath: "/tmp/repository-scan-baseline")
        let repositoryID = UUIDv7.generate()
        let main = Worktree(
            id: UUIDv7.generate(), repoId: repositoryID, name: "main", path: root.appending(path: "main"))
        let linked = Worktree(
            id: UUIDv7.generate(), repoId: repositoryID, name: "linked", path: root.appending(path: "linked"))
        let original = Repo(
            id: repositoryID, name: "family", repoPath: main.path, worktrees: [main, linked])
        let collectedMain = Repo(
            id: repositoryID, name: "family", repoPath: main.path, worktrees: [linked])
        let filesystem = FilesystemActor(
            bus: EventBus<RuntimeEnvelope>(), fseventStreamClient: ControllableFSEventStreamClient())

        #expect(await filesystem.updateRepositoryScanBaseline([original], membershipRevision: 3))
        #expect(await filesystem.updateRepositoryScanBaseline([collectedMain], membershipRevision: 4))
        #expect(await filesystem.updateRepositoryScanBaseline([original], membershipRevision: 3) == false)
        let baseline = await filesystem.watchedFolderScanState.repositoryScanBaseline
        #expect(baseline.membershipRevision == 4)
        #expect(baseline.checkoutPaths.map(\.path) == [linked.path.path])

        // A stale full refresh cannot reintroduce the older inventory or authorize its watched root.
        _ = await filesystem.refreshWatchedFolders(
            [WatchedPath(path: root)], restoring: [original], membershipRevision: 3)
        let registrations = await filesystem.watchedFolderScanState.registrationsBySourceID
        #expect(registrations.isEmpty)
        #expect(await filesystem.watchedFolderScanState.repositoryScanBaseline.membershipRevision == 4)
        await filesystem.shutdown()
    }
}
