import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Topology runtime scope feedback", .serialized)
struct TopologyRuntimeScopeFeedbackTests {
    enum Scenario: CaseIterable, Sendable {
        case unregisterHiddenCheckout
        case registerRemovedCheckout
    }

    @Test("watcher facts cannot delete retained topology or recreate removed topology", arguments: Scenario.allCases)
    func watcherFactsHaveNoCanonicalMutationAuthority(_ scenario: Scenario) async throws {
        try await withAsyncTestCoreAtoms { _ in
            let root = FileManager.default.temporaryDirectory.appending(path: "scope-feedback-\(UUIDv7.generate())")
            let linkedPath = root.appending(path: "linked")
            try FileManager.default.createDirectory(at: linkedPath, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let bus = EventBus<RuntimeEnvelope>()
            let store = WorkspaceStore()
            let cache = RepoCacheAtom()
            let filesystem = FilesystemActor(bus: bus, fseventStreamClient: ControllableFSEventStreamClient())
            let coordinator = WorkspaceCacheCoordinator(
                bus: bus, workspaceStore: store, repoCache: cache, scopeSyncHandler: { _ in }
            )
            await coordinator.startConsuming()
            do {
                let repo = store.addRepo(at: root)
                let checkout = Worktree(id: UUIDv7.generate(), repoId: repo.id, name: "linked", path: linkedPath)
                _ = store.mutationCoordinator.reconcileDiscoveredWorktrees(
                    repo.id, worktrees: repo.worktrees + [checkout])
                switch scenario {
                case .unregisterHiddenCheckout:
                    await filesystem.register(worktreeId: checkout.id, repoId: repo.id, rootPath: linkedPath)
                    #expect(
                        store.mutationCoordinator.recordWorktreeAbsence(
                            checkout.id,
                            at: .init(
                                utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1
                            )
                        ))
                    await filesystem.unregister(worktreeId: checkout.id)
                case .registerRemovedCheckout:
                    _ = store.mutationCoordinator.unregisterWorktree(checkout.id, from: repo.id)
                    await filesystem.register(worktreeId: checkout.id, repoId: repo.id, rootPath: linkedPath)
                }
                // A later ordered topology fact acknowledges the coordinator passed the watcher fact.
                _ = await bus.post(
                    .system(
                        SystemEnvelope(
                            source: .builtin(.coordinator), seq: 100, timestamp: ContinuousClock().now,
                            event: .topology(
                                .repoDiscovered(
                                    repoPath: root, parentPath: root.deletingLastPathComponent(),
                                    linkedWorktrees: .notScanned))
                        )))
                await assertEventuallyMain("ordered coordinator acknowledgement should be observable") {
                    cache.repoEnrichment(for: repo.id) != nil
                }
                switch scenario {
                case .unregisterHiddenCheckout:
                    #expect(store.repositoryTopologyAtom.worktree(checkout.id) != nil)
                    #expect(store.repositoryTopologyAtom.isWorktreeUnavailable(checkout.id))
                    #expect(store.repositoryTopologyAtom.absenceRecords.worktrees[checkout.id] != nil)
                case .registerRemovedCheckout:
                    #expect(store.repositoryTopologyAtom.worktree(checkout.id) == nil)
                }
                await coordinator.shutdown()
                await filesystem.shutdown()
            } catch {
                await coordinator.shutdown()
                await filesystem.shutdown()
                throw error
            }
        }
    }
}
