import Foundation
import Testing

@Suite("RepositoryTopologyStoreArchitectureTests")
struct RepositoryTopologyStoreArchitectureTests {
    @Test("RepositoryTopologyStore exists and uses the SQLite datastore boundary")
    func repositoryTopologyStoreUsesDatastoreBoundary() throws {
        let source = try projectSource(
            "Sources/AgentStudio/Core/State/MainActor/Persistence/RepositoryTopologyStore.swift"
        )

        #expect(source.contains("final class RepositoryTopologyStore"))
        #expect(source.contains("RepositoryTopologyAtom"))
        #expect(source.contains("WorkspaceSQLiteDatastore"))
        #expect(!source.contains("WorkspaceCoreRepository"))
        #expect(!source.contains("WorkspaceSQLiteStoreBackend"))
    }

    @Test("RepositoryTopologyStore does not own filesystem or process authority")
    func repositoryTopologyStoreHasNoFilesystemOrProcessAuthority() throws {
        let source = try projectSource(
            "Sources/AgentStudio/Core/State/MainActor/Persistence/RepositoryTopologyStore.swift"
        )

        #expect(!source.contains("FileManager.default"))
        #expect(!source.contains("Process("))
        #expect(!source.contains("ProcessExecutor"))
        #expect(!source.contains("GitWorkingTreeStatusProvider"))
        #expect(!source.contains("ForgeActor"))
    }

    @Test("RepositoryTopologyAtom stays free of persistence and external authority")
    func repositoryTopologyAtomHasNoPersistenceOrExternalAuthority() throws {
        let source = try projectSource(
            "Sources/AgentStudio/Core/State/MainActor/Atoms/RepositoryTopologyAtom.swift"
        )

        #expect(source.contains("final class RepositoryTopologyAtom"))
        #expect(!source.contains("WorkspaceStore"))
        #expect(!source.contains("WorkspaceCoreRepository"))
        #expect(!source.contains("WorkspaceSQLiteDatastore"))
        #expect(!source.contains("FileManager.default"))
        #expect(!source.contains("Process("))
        #expect(!source.contains("GitWorkingTreeStatusProvider"))
        #expect(!source.contains("ForgeActor"))
    }

    private func projectSource(_ relativePath: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try String(contentsOf: projectRoot.appending(path: relativePath), encoding: .utf8)
    }
}
