import Foundation
import GRDB

func validatePaneGraph(
    _ database: Database,
    workspaceId: UUID,
    graph: WorkspaceCoreRepository.PaneGraphRecord
) throws {
    try validateUniquePaneIds(graph.panes)
    try validateUniqueDrawerIds(graph.panes)
    let panesById = Dictionary(uniqueKeysWithValues: graph.panes.map { ($0.id, $0) })
    let drawerMemberships = try makeDrawerMemberships(graph.panes)

    for pane in graph.panes {
        try validateExistingPaneBelongsToWorkspace(database, workspaceId: workspaceId, paneId: pane.id)
        if let drawer = pane.drawer {
            try validateExistingDrawerBelongsToWorkspace(database, workspaceId: workspaceId, drawerId: drawer.drawerId)
        }
        try validatePaneContentRoute(pane)
        try validatePaneContentTypeIsStable(database, workspaceId: workspaceId, pane: pane)
        try validatePanePlacement(pane, panesById: panesById, drawerMemberships: drawerMemberships)
        try validatePaneDrawer(pane, panesById: panesById)
    }
}

private func validateUniquePaneIds(_ panes: [WorkspaceCoreRepository.PaneRecord]) throws {
    var seenIds = Set<UUID>()
    for pane in panes where !seenIds.insert(pane.id).inserted {
        throw WorkspaceCoreRepositoryError.duplicatePaneId(pane.id)
    }
}

private func validateUniqueDrawerIds(_ panes: [WorkspaceCoreRepository.PaneRecord]) throws {
    var seenIds = Set<UUID>()
    for drawer in panes.compactMap(\.drawer) where !seenIds.insert(drawer.drawerId).inserted {
        throw WorkspaceCoreRepositoryError.duplicateDrawerId(drawer.drawerId)
    }
}

private func validatePaneContentRoute(_ pane: WorkspaceCoreRepository.PaneRecord) throws {
    guard case .payload(let contentType, _, _) = pane.content else { return }
    guard isPayloadBackedContentType(contentType) else {
        throw WorkspaceCoreRepositoryError.panePayloadContentTypeUnsupported(
            paneId: pane.id,
            contentType: contentType
        )
    }
}

private func validatePaneContentTypeIsStable(
    _ database: Database,
    workspaceId: UUID,
    pane: WorkspaceCoreRepository.PaneRecord
) throws {
    guard
        let existingContentTypeString = try String.fetchOne(
            database,
            sql: """
                SELECT content_type
                FROM pane
                WHERE id = ?
                AND workspace_id = ?
                """,
            arguments: [pane.id.uuidString, workspaceId.uuidString]
        )
    else {
        return
    }
    let existingContentType = try decodePaneContentType(existingContentTypeString)
    let newContentType = pane.content.contentType
    guard existingContentType == newContentType else {
        throw WorkspaceCoreRepositoryError.paneContentTypeIsImmutable(
            paneId: pane.id,
            oldContentType: existingContentType,
            newContentType: newContentType
        )
    }
}

private func validatePanePlacement(
    _ pane: WorkspaceCoreRepository.PaneRecord,
    panesById: [UUID: WorkspaceCoreRepository.PaneRecord],
    drawerMemberships: [UUID: UUID]
) throws {
    guard case .drawerChild(let parentPaneId) = pane.placement else { return }
    guard panesById[parentPaneId] != nil else {
        throw WorkspaceCoreRepositoryError.drawerChildMissingParent(childPaneId: pane.id, parentPaneId: parentPaneId)
    }
    if let drawer = pane.drawer {
        throw WorkspaceCoreRepositoryError.drawerChildCannotOwnDrawer(childPaneId: pane.id, drawerId: drawer.drawerId)
    }
    guard drawerMemberships[pane.id] != nil else {
        throw WorkspaceCoreRepositoryError.drawerChildMembershipMissing(
            childPaneId: pane.id,
            parentPaneId: parentPaneId
        )
    }
}

private func validatePaneDrawer(
    _ pane: WorkspaceCoreRepository.PaneRecord,
    panesById: [UUID: WorkspaceCoreRepository.PaneRecord]
) throws {
    guard let drawer = pane.drawer else { return }
    guard drawer.parentPaneId == pane.id else {
        throw WorkspaceCoreRepositoryError.drawerParentMismatch(
            drawerId: drawer.drawerId,
            expectedParentPaneId: pane.id,
            actualParentPaneId: drawer.parentPaneId
        )
    }
    guard panesById[drawer.parentPaneId] != nil else {
        throw WorkspaceCoreRepositoryError.drawerParentPaneMissing(
            drawerId: drawer.drawerId,
            parentPaneId: drawer.parentPaneId
        )
    }
    for childPaneId in drawer.childPaneIds {
        try validateDrawerChild(drawer: drawer, childPaneId: childPaneId, panesById: panesById)
    }
}

private func validateDrawerChild(
    drawer: WorkspaceCoreRepository.DrawerRecord,
    childPaneId: UUID,
    panesById: [UUID: WorkspaceCoreRepository.PaneRecord]
) throws {
    guard let childPane = panesById[childPaneId] else {
        throw WorkspaceCoreRepositoryError.drawerChildPaneMissing(drawerId: drawer.drawerId, childPaneId: childPaneId)
    }
    guard case .drawerChild(let actualParentPaneId) = childPane.placement else {
        throw WorkspaceCoreRepositoryError.drawerChildPaneMissing(drawerId: drawer.drawerId, childPaneId: childPaneId)
    }
    guard actualParentPaneId == drawer.parentPaneId else {
        throw WorkspaceCoreRepositoryError.drawerChildParentMismatch(
            childPaneId: childPaneId,
            expectedParentPaneId: drawer.parentPaneId,
            actualParentPaneId: actualParentPaneId
        )
    }
}

private func makeDrawerMemberships(
    _ panes: [WorkspaceCoreRepository.PaneRecord]
) throws -> [UUID: UUID] {
    var memberships: [UUID: UUID] = [:]
    for drawer in panes.compactMap(\.drawer) {
        for childPaneId in drawer.childPaneIds {
            guard memberships[childPaneId] == nil else {
                throw WorkspaceCoreRepositoryError.drawerChildListedMultipleTimes(childPaneId: childPaneId)
            }
            memberships[childPaneId] = drawer.parentPaneId
        }
    }
    return memberships
}

private func validateExistingPaneBelongsToWorkspace(
    _ database: Database,
    workspaceId: UUID,
    paneId: UUID
) throws {
    guard
        let actualWorkspaceId = try fetchPaneWorkspaceId(database, paneId: paneId),
        actualWorkspaceId != workspaceId
    else {
        return
    }
    throw WorkspaceCoreRepositoryError.paneBelongsToDifferentWorkspace(
        paneId: paneId,
        expectedWorkspaceId: workspaceId,
        actualWorkspaceId: actualWorkspaceId
    )
}

private func validateExistingDrawerBelongsToWorkspace(
    _ database: Database,
    workspaceId: UUID,
    drawerId: UUID
) throws {
    guard
        let actualWorkspaceId = try fetchDrawerWorkspaceId(database, drawerId: drawerId),
        actualWorkspaceId != workspaceId
    else {
        return
    }
    throw WorkspaceCoreRepositoryError.drawerBelongsToDifferentWorkspace(
        drawerId: drawerId,
        expectedWorkspaceId: workspaceId,
        actualWorkspaceId: actualWorkspaceId
    )
}

private func fetchPaneWorkspaceId(_ database: Database, paneId: UUID) throws -> UUID? {
    guard
        let workspaceIdString = try String.fetchOne(
            database,
            sql: """
                SELECT workspace_id
                FROM pane
                WHERE id = ?
                """,
            arguments: [paneId.uuidString]
        )
    else {
        return nil
    }
    guard let workspaceId = UUID(uuidString: workspaceIdString) else {
        throw WorkspaceCoreRepositoryError.malformedWorkspaceId(workspaceIdString)
    }
    return workspaceId
}

private func fetchDrawerWorkspaceId(_ database: Database, drawerId: UUID) throws -> UUID? {
    guard
        let workspaceIdString = try String.fetchOne(
            database,
            sql: """
                SELECT pane.workspace_id
                FROM drawer
                JOIN pane ON pane.id = drawer.parent_pane_id
                WHERE drawer.id = ?
                """,
            arguments: [drawerId.uuidString]
        )
    else {
        return nil
    }
    guard let workspaceId = UUID(uuidString: workspaceIdString) else {
        throw WorkspaceCoreRepositoryError.malformedWorkspaceId(workspaceIdString)
    }
    return workspaceId
}

private func isPayloadBackedContentType(_ contentType: PaneContentType) -> Bool {
    switch contentType {
    case .diff, .editor, .review, .agent, .plugin:
        true
    case .terminal, .browser, .codeViewer:
        false
    }
}
