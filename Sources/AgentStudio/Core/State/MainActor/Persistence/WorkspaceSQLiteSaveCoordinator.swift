import Foundation

@MainActor
final class WorkspaceSQLiteSaveCoordinator {
    private let identityAtom: WorkspaceIdentityAtom
    private let windowMemoryAtom: WorkspaceWindowMemoryAtom
    private let repositoryTopologyAtom: RepositoryTopologyAtom
    private let workspacePaneAtom: WorkspacePaneAtom
    private let workspaceTabLayoutAtom: WorkspaceTabLayoutAtom
    private let sqliteDatastore: WorkspaceSQLiteDatastore

    init(
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyAtom: RepositoryTopologyAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom,
        sqliteDatastore: WorkspaceSQLiteDatastore
    ) {
        self.identityAtom = identityAtom
        self.windowMemoryAtom = windowMemoryAtom
        self.repositoryTopologyAtom = repositoryTopologyAtom
        self.workspacePaneAtom = workspacePaneAtom
        self.workspaceTabLayoutAtom = workspaceTabLayoutAtom
        self.sqliteDatastore = sqliteDatastore
    }

    func makeSaveBundleResult(persistedAt: Date) -> WorkspaceLiveSQLiteSaveBundleResult {
        WorkspacePersistenceTransformer.makeLiveSQLiteSaveBundleResult(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            workspacePaneAtom: workspacePaneAtom,
            workspaceTabLayoutAtom: workspaceTabLayoutAtom,
            persistedAt: persistedAt
        )
    }

    func save(persistedAt: Date) async throws -> WorkspaceLiveSQLiteSaveBundleResult {
        let result = makeSaveBundleResult(persistedAt: persistedAt)
        try await sqliteDatastore.saveWorkspaceSnapshotBundle(result.bundle)
        return result
    }
}
