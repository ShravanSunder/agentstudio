import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("WorkspaceStoreArchitectureTests")
struct WorkspaceStoreArchitectureTests {
    @Test("WorkspaceStore does not depend on action resolver/validator layer")
    func workspaceStore_hasNoActionLayerCoupling() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let storePath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift"
        )
        let source = try String(contentsOf: storePath, encoding: .utf8)

        #expect(!source.contains("WorkspaceCommandResolver"))
        #expect(!source.contains("WorkspaceCommandValidator"))
        #expect(!source.contains("WorkspaceActionCommand"))
    }

    @Test("WorkspaceStore does not expose query or mutation facades")
    func workspaceStore_hasNoReadOrForwardingFacadeSurface() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let storePath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift"
        )
        let source = try String(contentsOf: storePath, encoding: .utf8)

        // Intentionally coarse source matching: this is a hard-cutover guardrail,
        // not a parser. Task 7's broader consumer scan complements it.
        #expect(!source.contains("var repos:"))
        #expect(!source.contains("var tabs:"))
        #expect(!source.contains("func pane(_"))
        #expect(!source.contains("func tabContaining("))
        #expect(!source.contains("func createPane("))
        #expect(!source.contains("func appendTab("))
    }

    @Test("repository topology changes do not dirty workspace persistence")
    @MainActor
    func workspaceStore_doesNotObserveRepositoryTopologyForPersistence() {
        let clock = TestPushClock()
        let workspaceIdentity = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())
        let store = WorkspaceStore(
            identityAtom: workspaceIdentity,
            clock: clock,
            startsObserving: true
        )
        let repositoryPath = FileManager.default.temporaryDirectory.appending(
            path: "workspace-store-repository-topology-observation"
        )

        store.mutationCoordinator.addRepo(at: repositoryPath)

        #expect(store.repositoryTopologyAtom.repos.map(\.repoPath) == [repositoryPath.standardizedFileURL])
        #expect(store.isDirty == false)
        #expect(clock.pendingSleepCount == 0)
    }
}
