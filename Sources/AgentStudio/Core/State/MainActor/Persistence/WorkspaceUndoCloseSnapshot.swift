import Foundation

func decodeValidatedUndoCloseSnapshot(
    version: Int, payload: Data, kind: String, members: [WorkspaceUndoCloseWrite.Member]
) throws -> WorkspaceUndoCloseSnapshot {
    guard version == WorkspaceUndoCloseSnapshot.currentVersion else {
        throw WorkspaceUndoJournalFailure.unsupportedSnapshotVersion(version)
    }
    let snapshot = try JSONDecoder().decode(WorkspaceUndoCloseSnapshot.self, from: payload)
    guard snapshot.kind.rawValue == kind else { throw WorkspaceUndoJournalFailure.snapshotKindMismatch }
    guard Set(members).count == members.count,
        members.count == snapshot.members.count, Set(members) == Set(snapshot.members)
    else { throw WorkspaceUndoJournalFailure.snapshotMembershipMismatch }
    return snapshot
}

/// Versioned value payload for durable undo. It contains no native or observation ownership.
package enum WorkspaceUndoCloseSnapshot: Codable, Equatable, Sendable {
    package static let currentVersion = 1

    case tab(tab: Tab, panes: [Pane], tabIndex: Int)
    case pane(PaneSnapshot)

    package struct PaneSnapshot: Codable, Equatable, Sendable {
        package let pane: Pane
        package let drawerChildPanes: [Pane]
        package let drawerViewsByArrangementID: [UUID: DrawerView]
        package let tabID: UUID
        package let anchorPaneID: UUID?
        package let direction: Layout.SplitDirection
    }

    package var panes: [Pane] {
        switch self {
        case .tab(_, let panes, _):
            panes
        case .pane(let snapshot):
            [snapshot.pane] + snapshot.drawerChildPanes
        }
    }

    package var kind: WorkspaceUndoCloseWrite.Kind {
        switch self {
        case .tab: .tab
        case .pane: .pane
        }
    }

    package var members: [WorkspaceUndoCloseWrite.Member] {
        panes.map { .init(paneID: $0.id, sessionID: $0.terminalState?.zmxSessionID) }
    }

    @MainActor
    package init(entry: WorkspaceMutationCoordinator.CloseEntry) {
        switch entry {
        case .tab(let snapshot):
            self = .tab(tab: snapshot.tab, panes: snapshot.panes, tabIndex: snapshot.tabIndex)
        case .pane(let snapshot):
            self = .pane(
                .init(
                    pane: snapshot.pane,
                    drawerChildPanes: snapshot.drawerChildPanes,
                    drawerViewsByArrangementID: snapshot.drawerViewsByArrangementId,
                    tabID: snapshot.tabId,
                    anchorPaneID: snapshot.anchorPaneId,
                    direction: snapshot.direction
                )
            )
        }
    }

    @MainActor
    package var restoreEntry: WorkspaceMutationCoordinator.CloseEntry {
        switch self {
        case .tab(let tab, let panes, let tabIndex):
            .tab(.init(tab: tab, panes: panes, tabIndex: tabIndex))
        case .pane(let snapshot):
            .pane(
                .init(
                    pane: snapshot.pane,
                    drawerChildPanes: snapshot.drawerChildPanes,
                    drawerViewsByArrangementId: snapshot.drawerViewsByArrangementID,
                    tabId: snapshot.tabID,
                    anchorPaneId: snapshot.anchorPaneID,
                    direction: snapshot.direction
                )
            )
        }
    }
}
