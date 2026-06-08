import Foundation
import GRDB

struct DrawerViewValidationContext {
    let workspaceId: UUID
    let tabId: UUID
    let arrangementId: UUID
    let tabPaneIds: Set<UUID>
    let mainLayoutPaneIds: Set<UUID>
}

func validateDrawerView(
    _ database: Database,
    context: DrawerViewValidationContext,
    drawerId: UUID,
    drawerView: WorkspaceCoreRepository.DrawerViewGraphRecord
) throws {
    try validateDrawerViewDividerIdsAreUnique(
        arrangementId: context.arrangementId,
        drawerId: drawerId,
        layout: drawerView.layout
    )
    guard !drawerView.layout.topRow.isEmpty else {
        throw WorkspaceCoreRepositoryError.drawerViewLayoutIsEmpty(
            arrangementId: context.arrangementId,
            drawerId: drawerId
        )
    }
    let drawerPaneIds = try fetchDrawerPaneIds(database, drawerId: drawerId, workspaceId: context.workspaceId)
    var seenPaneIds = Set<UUID>()
    for paneId in drawerView.layout.paneIds {
        guard seenPaneIds.insert(paneId).inserted else {
            throw WorkspaceCoreRepositoryError.drawerViewPaneListedMultipleTimes(
                arrangementId: context.arrangementId,
                paneId: paneId
            )
        }
        guard drawerPaneIds.contains(paneId) else {
            throw WorkspaceCoreRepositoryError.drawerViewPaneNotInDrawer(drawerId: drawerId, paneId: paneId)
        }
        guard !context.mainLayoutPaneIds.contains(paneId) else {
            throw WorkspaceCoreRepositoryError.drawerViewPaneListedMultipleTimes(
                arrangementId: context.arrangementId,
                paneId: paneId
            )
        }
    }
    try validateLayoutPaneIdsBelongToTab(
        tabId: context.tabId,
        arrangementId: context.arrangementId,
        tabPaneIds: context.tabPaneIds,
        paneIds: drawerView.layout.paneIds
    )
    for paneId in drawerView.minimizedPaneIds {
        guard drawerView.layout.contains(paneId) else {
            throw WorkspaceCoreRepositoryError.arrangementMinimizedPaneMissingFromLayout(
                arrangementId: context.arrangementId,
                paneId: paneId
            )
        }
    }
}

private func validateDrawerViewDividerIdsAreUnique(
    arrangementId: UUID,
    drawerId: UUID,
    layout: DrawerGridLayout
) throws {
    var seenDividerIds = Set<UUID>()
    for dividerId in layout.dividerIds where !seenDividerIds.insert(dividerId).inserted {
        throw WorkspaceCoreRepositoryError.drawerViewDividerListedMultipleTimes(
            arrangementId: arrangementId,
            drawerId: drawerId,
            dividerId: dividerId
        )
    }
}

private func fetchDrawerPaneIds(_ database: Database, drawerId: UUID, workspaceId: UUID) throws -> Set<UUID> {
    let rows = try Row.fetchAll(
        database,
        sql: """
            SELECT drawer_pane.pane_id
            FROM drawer_pane
            JOIN pane ON pane.id = drawer_pane.pane_id
            WHERE drawer_pane.drawer_id = ?
            AND pane.workspace_id = ?
            """,
        arguments: [drawerId.uuidString, workspaceId.uuidString]
    )
    return Set(try rows.map { row in try decodePaneId(row["pane_id"]) })
}
