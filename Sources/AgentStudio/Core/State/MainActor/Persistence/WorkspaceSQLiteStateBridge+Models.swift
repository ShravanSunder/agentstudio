import Foundation

extension WorkspaceSQLiteStateBridge {
    static func paneArrangement(
        from record: WorkspaceCoreRepository.TabArrangementGraphRecord,
        cursorState: WorkspaceLocalRepository.CursorStateRecord
    ) -> PaneArrangement {
        .init(
            id: record.id,
            name: record.name,
            isDefault: record.isDefault,
            layout: record.layout,
            minimizedPaneIds: record.minimizedPaneIds,
            showsMinimizedPanes: record.showsMinimizedPanes,
            activePaneId: cursorState.activePaneIdsByArrangementId[record.id],
            drawerViews: record.drawerViews.map { drawerId, drawerView in
                let key = WorkspaceLocalRepository.ArrangementDrawerCursorKey(
                    arrangementId: record.id,
                    drawerId: drawerId
                )
                return (
                    drawerId,
                    DrawerView(
                        layout: drawerView.layout,
                        activeChildId: cursorState.activeChildIdsByArrangementDrawer[key],
                        minimizedPaneIds: drawerView.minimizedPaneIds
                    )
                )
            }.reduce(into: [:]) { partialResult, pair in
                partialResult[pair.0] = pair.1
            }
        )
    }

    static func canonicalRepo(from record: WorkspaceCoreRepository.RepoRecord) -> CanonicalRepo {
        .init(
            id: record.id,
            name: record.name,
            repoPath: record.repoPath,
            createdAt: record.createdAt,
            tags: record.tags
        )
    }

    static func canonicalWorktree(from record: WorkspaceCoreRepository.WorktreeRecord) -> CanonicalWorktree {
        .init(
            id: record.id,
            repoId: record.repoId,
            name: record.name,
            path: record.path,
            isMainWorktree: record.isMainWorktree,
            tags: record.tags
        )
    }

    static func watchedPath(from record: WorkspaceCoreRepository.WatchedPathRecord) -> WatchedPath {
        .init(id: record.id, path: record.path, addedAt: record.addedAt)
    }
}

enum WorkspaceSQLiteStateBridgeError: Error, Equatable, Sendable {
    case invalidPayloadJSON
    case layoutPaneMissingDrawer(UUID)
}
