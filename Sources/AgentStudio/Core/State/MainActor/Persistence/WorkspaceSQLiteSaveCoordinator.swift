import Foundation
import os.log

private let workspaceSQLiteSavePreparationLogger = Logger(
    subsystem: "com.agentstudio",
    category: "WorkspaceSQLiteSavePreparation"
)

enum WorkspaceSQLiteSaveCoordinatorFailure: Error, Equatable, Sendable {
    case compositionRejected(WorkspaceCompositionPreparationRejection)
    case datastore(WorkspaceSQLiteDatastoreFailure)
}

struct WorkspaceSQLiteSaveCapture: Sendable {
    let workspaceID: UUID
    let workspaceName: String
    let paneStatesByID: [UUID: PaneGraphState]
    let expandedDrawerID: UUID?
    let tabShells: [TabShell]
    let tabGraphStates: [TabGraphState]
    let activeArrangementIDsByTabID: [UUID: UUID]
    let paneCursorsByArrangementID: [UUID: ArrangementPaneCursorState]
    let drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState]
    let zoomedPaneIDsByTabID: [UUID: UUID]
    let activeTabID: UUID?
    let sidebarWidth: CGFloat
    let windowFrame: CGRect?
    let createdAt: Date
    let persistedAt: Date
}

enum WorkspaceSQLiteSavePreparation {
    @concurrent nonisolated static func prepareOffMain(
        _ capture: WorkspaceSQLiteSaveCapture
    ) async -> WorkspaceSQLiteSaveBundle {
        let panes = capture.paneStatesByID.values.compactMap { paneState -> Pane? in
            guard !paneState.residency.isPendingUndo else { return nil }
            return paneState.pane(isDrawerExpanded: paneState.drawer?.drawerId == capture.expandedDrawerID)
        }
        let tabGraphStatesByID = Dictionary(
            uniqueKeysWithValues: capture.tabGraphStates.map { ($0.tabId, $0) }
        )
        let tabs = capture.tabShells.compactMap { shell -> Tab? in
            guard let graphState = tabGraphStatesByID[shell.id] else {
                workspaceSQLiteSavePreparationLogger.warning(
                    "tabs: missing graph state for shell \(shell.id)"
                )
                return nil
            }
            let arrangements = graphState.arrangements.map { graphArrangement in
                var arrangement = PaneArrangement(
                    id: graphArrangement.id,
                    name: graphArrangement.name,
                    isDefault: graphArrangement.isDefault,
                    layout: graphArrangement.layout,
                    minimizedPaneIds: graphArrangement.minimizedPaneIds,
                    showsMinimizedPanes: graphArrangement.showsMinimizedPanes,
                    activePaneId: capture.paneCursorsByArrangementID[graphArrangement.id]?.activePaneId,
                    drawerViews: Dictionary(
                        uniqueKeysWithValues: graphArrangement.drawerViews.map { drawerID, drawerGraphState in
                            let cursorKey = ArrangementDrawerCursorKey(
                                arrangementId: graphArrangement.id,
                                drawerId: drawerID
                            )
                            let activeChildID = capture.drawerCursorsByKey[cursorKey]?.activeChildId
                            var drawerView = DrawerView(
                                layout: drawerGraphState.layout,
                                activeChildId: activeChildID,
                                minimizedPaneIds: drawerGraphState.minimizedPaneIds
                            )
                            // Preserve an explicitly empty cursor after DrawerView normalization.
                            drawerView.activeChildId = activeChildID
                            return (drawerID, drawerView)
                        }
                    )
                )
                // Preserve an explicitly empty cursor after PaneArrangement normalization.
                arrangement.activePaneId = capture.paneCursorsByArrangementID[graphArrangement.id]?.activePaneId
                return arrangement
            }
            let activeArrangementID =
                capture.activeArrangementIDsByTabID[graphState.tabId]
                ?? arrangements.first(where: \.isDefault)?.id
                ?? arrangements.first?.id
                // No arrangement is invalid and is rejected before SQLite I/O.
                // Use existing identity as the rejection sentinel; saving must not mint identity.
                ?? graphState.tabId
            return Tab(
                id: shell.id,
                name: shell.name,
                allPaneIds: graphState.allPaneIds,
                arrangements: arrangements,
                activeArrangementId: activeArrangementID,
                colorHex: shell.colorHex,
                zoomedPaneId: capture.zoomedPaneIDsByTabID[graphState.tabId]
            )
        }
        return WorkspaceSQLiteSaveBundle(
            workspace: .init(
                id: capture.workspaceID,
                name: capture.workspaceName,
                panes: panes,
                tabs: tabs,
                activeTabId: capture.activeTabID,
                sidebarWidth: capture.sidebarWidth,
                windowFrame: capture.windowFrame,
                createdAt: capture.createdAt,
                updatedAt: capture.persistedAt
            )
        )
    }
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

    func captureCurrentSaveState(persistedAt: Date) -> WorkspaceSQLiteSaveCapture {
        let arrangementAtom = workspaceTabLayoutAtom.arrangementAtom
        return WorkspaceSQLiteSaveCapture(
            workspaceID: identityAtom.workspaceId,
            workspaceName: identityAtom.workspaceName,
            paneStatesByID: workspacePaneAtom.graphAtom.paneStates,
            expandedDrawerID: workspacePaneAtom.drawerCursorAtom.expandedDrawerId,
            tabShells: workspaceTabLayoutAtom.shellAtom.tabShells,
            tabGraphStates: arrangementAtom.graphAtom.tabStates,
            activeArrangementIDsByTabID: arrangementAtom.cursorAtom.activeArrangementIdsByTabId,
            paneCursorsByArrangementID: arrangementAtom.cursorAtom.paneCursorsByArrangementId,
            drawerCursorsByKey: arrangementAtom.cursorAtom.drawerCursorsByKey,
            zoomedPaneIDsByTabID: arrangementAtom.presentationAtom.zoomedPaneIdsByTabId,
            activeTabID: workspaceTabLayoutAtom.activeTabId,
            sidebarWidth: windowMemoryAtom.sidebarWidth,
            windowFrame: windowMemoryAtom.windowFrame,
            createdAt: identityAtom.createdAt,
            persistedAt: persistedAt
        )
    }

    func captureCurrentSaveBundle(persistedAt: Date) async -> WorkspaceSQLiteSaveBundle {
        await WorkspaceSQLiteSavePreparation.prepareOffMain(
            captureCurrentSaveState(persistedAt: persistedAt)
        )
    }

    func save(
        persistedAt: Date
    ) async throws(WorkspaceSQLiteSaveCoordinatorFailure) -> WorkspaceSQLiteSaveBundle {
        let bundle = await captureCurrentSaveBundle(persistedAt: persistedAt)
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
