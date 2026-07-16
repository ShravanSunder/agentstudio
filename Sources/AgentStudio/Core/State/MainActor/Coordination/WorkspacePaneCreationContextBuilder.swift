import Foundation

enum WorkspacePaneCreationContextCaptureRejection: Equatable, Sendable {
    case tabOwnerAlignment(WorkspaceAlignedTabOwnerIndexRejection)
}

enum WorkspacePaneCreationContextCapture: Equatable, Sendable {
    case captured(WorkspacePaneCreationContext)
    case rejected(WorkspacePaneCreationContextCaptureRejection)
}

@MainActor
protocol WorkspacePaneCreationContextQuerying {
    var activeTabSelection: WorkspaceExistingActiveTabSelection { get }
    var tabShellCount: Int { get }
    var tabGraphCount: Int { get }

    func tabShellContains(_ tabID: UUID) -> Bool
    func tabGraphContains(_ tabID: UUID) -> Bool
    func paneExists(_ paneID: UUID) -> Bool
    func parentPaneID(containingDrawer drawerID: UUID) -> UUID?
    func tabID(containingPane paneID: UUID) -> UUID?
    func tabID(containingArrangement arrangementID: UUID) -> UUID?
    func hasActiveArrangementCursor(tabID: UUID) -> Bool
    func hasPaneCursor(arrangementID: UUID) -> Bool
}

@MainActor
final class WorkspacePaneCreationContextBuilder {
    private let queries: any WorkspacePaneCreationContextQuerying

    init(queries: any WorkspacePaneCreationContextQuerying) {
        self.queries = queries
    }

    convenience init(
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceTabShellAtom: WorkspaceTabShellAtom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    ) {
        self.init(
            queries: WorkspacePaneCreationAtomQueries(
                workspacePaneGraphAtom: workspacePaneGraphAtom,
                workspaceTabShellAtom: workspaceTabShellAtom,
                workspaceTabGraphAtom: workspaceTabGraphAtom,
                workspaceArrangementCursorAtom: workspaceArrangementCursorAtom
            )
        )
    }

    func capture(identities: WorkspaceNewPaneTabIDs) -> WorkspacePaneCreationContextCapture {
        let activeTabSelection = queries.activeTabSelection
        var relevantTabIDs = [identities.tabID]
        if case .selected(let activeTabID) = activeTabSelection,
            activeTabID != identities.tabID
        {
            relevantTabIDs.append(activeTabID)
        }
        let memberships = relevantTabIDs.map { tabID in
            WorkspaceRelevantTabOwnerMembership(
                tabID: tabID,
                shellContains: queries.tabShellContains(tabID),
                graphContains: queries.tabGraphContains(tabID)
            )
        }
        let ownerIndex: WorkspaceAlignedTabOwnerIndex
        switch WorkspaceAlignedTabOwnerIndex.prepareRelevant(
            shellTabCount: queries.tabShellCount,
            graphTabCount: queries.tabGraphCount,
            memberships: memberships
        ) {
        case .validated(let index):
            ownerIndex = index
        case .rejected(let rejection):
            return .rejected(.tabOwnerAlignment(rejection))
        }

        let paneID = identities.paneID.uuid
        let arrangementID = identities.arrangementID
        let paneOwnerByPaneID = queries.tabID(containingPane: paneID).map { [paneID: $0] } ?? [:]
        let existingArrangementIDs: Set<UUID> =
            queries.tabID(containingArrangement: arrangementID) == nil
            ? []
            : [arrangementID]
        let existingActiveArrangementTabIDs: Set<UUID> =
            queries.hasActiveArrangementCursor(
                tabID: identities.tabID
            ) ? [identities.tabID] : []
        let existingActivePaneArrangementIDs: Set<UUID> =
            queries.hasPaneCursor(
                arrangementID: arrangementID
            ) ? [arrangementID] : []

        return .captured(
            WorkspacePaneCreationContext(
                proposedPaneIsOccupied: queries.paneExists(paneID),
                proposedDrawerIsOccupied: queries.parentPaneID(containingDrawer: identities.drawerID) != nil,
                appendTabContext: WorkspaceAppendTabContext(
                    activeTab: activeTabSelection,
                    alignedTabOwners: ownerIndex,
                    panePlacements: WorkspacePanePlacementIndex.prospectiveLayoutPane(
                        paneID: paneID,
                        drawerID: identities.drawerID
                    ),
                    paneOwnerByPaneID: paneOwnerByPaneID,
                    existingArrangementIDs: existingArrangementIDs,
                    existingActiveArrangementTabIDs: existingActiveArrangementTabIDs,
                    existingActivePaneArrangementIDs: existingActivePaneArrangementIDs,
                    existingActiveDrawerChildKeys: []
                )
            )
        )
    }
}

@MainActor
private struct WorkspacePaneCreationAtomQueries: WorkspacePaneCreationContextQuerying {
    let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    let workspaceTabShellAtom: WorkspaceTabShellAtom
    let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom

    var activeTabSelection: WorkspaceExistingActiveTabSelection {
        workspaceTabShellAtom.activeTabId.map(WorkspaceExistingActiveTabSelection.selected)
            ?? .noSelection
    }

    var tabShellCount: Int { workspaceTabShellAtom.tabCount }
    var tabGraphCount: Int { workspaceTabGraphAtom.tabCount }

    func tabShellContains(_ tabID: UUID) -> Bool {
        workspaceTabShellAtom.containsTab(tabID)
    }

    func tabGraphContains(_ tabID: UUID) -> Bool {
        workspaceTabGraphAtom.containsTab(tabID)
    }

    func paneExists(_ paneID: UUID) -> Bool {
        workspacePaneGraphAtom.paneState(paneID) != nil
    }

    func parentPaneID(containingDrawer drawerID: UUID) -> UUID? {
        workspacePaneGraphAtom.parentPaneID(containingDrawer: drawerID)
    }

    func tabID(containingPane paneID: UUID) -> UUID? {
        workspaceTabGraphAtom.tabID(containingPane: paneID)
    }

    func tabID(containingArrangement arrangementID: UUID) -> UUID? {
        workspaceTabGraphAtom.tabID(containingArrangement: arrangementID)
    }

    func hasActiveArrangementCursor(tabID: UUID) -> Bool {
        workspaceArrangementCursorAtom.hasActiveArrangementCursor(tabID: tabID)
    }

    func hasPaneCursor(arrangementID: UUID) -> Bool {
        workspaceArrangementCursorAtom.hasPaneCursor(arrangementID: arrangementID)
    }
}
