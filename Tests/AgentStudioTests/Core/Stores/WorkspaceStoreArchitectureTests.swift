import Foundation
import Testing

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

    @Test("WorkspaceStore does not observe, hydrate, or serialize repository topology")
    func workspaceStore_hasNoRepositoryTopologyPersistenceOwnership() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let storePath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift"
        )
        let source = try String(contentsOf: storePath, encoding: .utf8)

        #expect(!source.contains("_ = repositoryTopologyAtom.repos"))
        #expect(!source.contains("_ = repositoryTopologyAtom.watchedPaths"))
        #expect(!source.contains("_ = repositoryTopologyAtom.unavailableRepoIds"))
        #expect(
            !source.contains(
                "makeLiveSQLiteSnapshotResult(\n                    identityAtom: identityAtom,\n                    windowMemoryAtom: windowMemoryAtom,\n                    repositoryTopologyAtom: repositoryTopologyAtom"
            ))
        #expect(
            !source.contains(
                "makePersistableState(\n                identityAtom: identityAtom,\n                windowMemoryAtom: windowMemoryAtom,\n                repositoryTopologyAtom: repositoryTopologyAtom"
            ))
        #expect(
            !source.contains(
                "WorkspacePersistenceTransformer.hydrate(\n            state,\n            identityAtom: identityAtom,\n            windowMemoryAtom: windowMemoryAtom,\n            repositoryTopologyAtom: repositoryTopologyAtom"
            ))
        #expect(!source.contains("loadWorkspaceSnapshot(preferredWorkspaceId: identityAtom.workspaceId)"))
        #expect(source.contains("resolveWorkspaceRestoreContext(preferredWorkspaceId: identityAtom.workspaceId)"))
        #expect(source.contains("repositoryTopologyStore.restoreTopology(from: context)"))
    }
}
