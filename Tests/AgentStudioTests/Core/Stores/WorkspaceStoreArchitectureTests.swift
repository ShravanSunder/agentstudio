import Foundation
import Testing

@Suite("WorkspaceStoreArchitectureTests")
struct WorkspaceStoreArchitectureTests {
    @Test("WorkspaceStore does not depend on action resolver/validator layer")
    func workspaceStore_hasNoActionLayerCoupling() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let storePath = projectRoot.appending(path: "Sources/AgentStudio/Core/Stores/WorkspaceStore.swift")
        let source = try String(contentsOf: storePath, encoding: .utf8)

        #expect(!source.contains("ActionResolver"))
        #expect(!source.contains("ActionValidator"))
        #expect(!source.contains("PaneAction"))
    }
}
