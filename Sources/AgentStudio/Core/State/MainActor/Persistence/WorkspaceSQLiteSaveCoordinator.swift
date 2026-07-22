import Foundation

enum WorkspaceSQLiteSaveCoordinatorFailure: Error, Equatable, Sendable {
    case compositionRejected(WorkspaceCompositionPreparationRejection)
    case datastore(WorkspaceSQLiteDatastoreFailure)
}

@MainActor
final class WorkspaceSQLiteSaveCoordinator {
    private let identityAtom: WorkspaceIdentityAtom
    private let windowMemoryAtom: WorkspaceWindowMemoryAtom
    private let workspacePaneAtom: WorkspacePaneAtom
    private let workspaceTabLayoutAtom: WorkspaceTabLayoutAtom
    private let sqliteDatastore: WorkspaceSQLiteDatastore

    init(
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom,
        sqliteDatastore: WorkspaceSQLiteDatastore
    ) {
        self.identityAtom = identityAtom
        self.windowMemoryAtom = windowMemoryAtom
        self.workspacePaneAtom = workspacePaneAtom
        self.workspaceTabLayoutAtom = workspaceTabLayoutAtom
        self.sqliteDatastore = sqliteDatastore
    }

    func captureCurrentSaveBundle(persistedAt: Date) -> WorkspaceSQLiteSaveBundle {
        let panes = workspacePaneAtom.graphAtom.paneStates.values.map { paneState in
            let drawerID = paneState.drawer?.drawerId
            return paneState.pane(
                isDrawerExpanded: drawerID.map {
                    workspacePaneAtom.drawerCursorAtom.isExpanded(drawerId: $0)
                } ?? false
            )
        }
        return WorkspaceSQLiteSaveBundle(
            workspace: .init(
                id: identityAtom.workspaceId,
                name: identityAtom.workspaceName,
                panes: panes,
                tabs: workspaceTabLayoutAtom.tabs,
                activeTabId: workspaceTabLayoutAtom.activeTabId,
                sidebarWidth: windowMemoryAtom.sidebarWidth,
                windowFrame: windowMemoryAtom.windowFrame,
                createdAt: identityAtom.createdAt,
                updatedAt: persistedAt
            )
        )
    }

    func save(
        persistedAt: Date
    ) async throws(WorkspaceSQLiteSaveCoordinatorFailure) -> WorkspaceSQLiteSaveBundle {
        let bundle = captureCurrentSaveBundle(persistedAt: persistedAt)
        switch await WorkspaceCompositionPreparer.prepareOffMain(bundle.workspace) {
        case .prepared:
            break
        case .rejected(let rejection):
            throw .compositionRejected(rejection)
        }
        do {
            try await sqliteDatastore.saveWorkspaceSnapshotBundle(bundle)
        } catch {
            throw .datastore(.init(error))
        }
        return bundle
    }
}
