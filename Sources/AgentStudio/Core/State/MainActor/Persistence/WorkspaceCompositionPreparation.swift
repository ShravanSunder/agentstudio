import CoreGraphics
import Foundation

enum WorkspaceCompositionPreparationRejection: Error, Equatable, Sendable {
    case duplicateArrangementID(UUID)
    case duplicateDrawerID(UUID)
    case duplicatePaneID(UUID)
    case duplicateTabID(UUID)
    case paneOwnedByMultipleTabs(paneID: UUID, firstTabID: UUID, secondTabID: UUID)
    case invalidPaneGraph(WorkspacePaneGraphReplacementRejection)
    case tabHasNoArrangements(UUID)
}

enum WorkspaceCompositionPreparationResult: Equatable, Sendable {
    case prepared(PreparedWorkspaceComposition)
    case rejected(WorkspaceCompositionPreparationRejection)
}

struct PreparedWorkspaceCompositionIdentity: Equatable, Sendable {
    let workspaceID: UUID
    let workspaceName: String
    let createdAt: Date
}

struct PreparedWorkspaceCompositionWindowMemory: Equatable, Sendable {
    let sidebarWidth: CGFloat
    let windowFrame: CGRect?
}

struct PreparedWorkspacePaneGraph: Equatable, Sendable {
    let replacement: WorkspacePaneGraphReplacement
}

struct PreparedWorkspaceTabShells: Equatable, Sendable {
    let shells: [TabShell]
    let indexByID: [UUID: Int]
}

struct PreparedWorkspaceTabGraph: Equatable, Sendable {
    let states: [TabGraphState]
    let indexByID: [UUID: Int]
    let tabIDByPaneID: [UUID: UUID]
}

struct PreparedWorkspaceArrangementCursors: Equatable, Sendable {
    let activeArrangementIDsByTabID: [UUID: UUID]
    let paneCursorsByArrangementID: [UUID: ArrangementPaneCursorState]
    let drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState]
}

private struct PreparedWorkspaceCompositionPaneInputs {
    let paneIDs: Set<UUID>
    let normalizedPanes: [Pane]
    let drawerParentPaneIDByDrawerID: [UUID: UUID]
}

/// An immutable, fully validated composition replacement.
///
/// Only `WorkspaceCompositionPreparer` can construct this value. MainActor apply
/// therefore installs precomputed owner projections without repeating fleet
/// validation or consulting repository topology.
struct PreparedWorkspaceComposition: Equatable, Sendable {
    let identity: PreparedWorkspaceCompositionIdentity
    let windowMemory: PreparedWorkspaceCompositionWindowMemory
    let panes: [Pane]
    let tabs: [Tab]
    let activeTabID: UUID?
    let repairReport: WorkspaceTabMembershipRepairReport
    let paneGraph: PreparedWorkspacePaneGraph
    let expandedDrawerID: UUID?
    let tabShells: PreparedWorkspaceTabShells
    let tabGraph: PreparedWorkspaceTabGraph
    let arrangementCursors: PreparedWorkspaceArrangementCursors
    let terminalActivationInput: TerminalActivationInput

    fileprivate init(
        identity: PreparedWorkspaceCompositionIdentity,
        windowMemory: PreparedWorkspaceCompositionWindowMemory,
        panes: [Pane],
        tabs: [Tab],
        activeTabID: UUID?,
        repairReport: WorkspaceTabMembershipRepairReport,
        paneGraph: PreparedWorkspacePaneGraph,
        expandedDrawerID: UUID?,
        tabShells: PreparedWorkspaceTabShells,
        tabGraph: PreparedWorkspaceTabGraph,
        arrangementCursors: PreparedWorkspaceArrangementCursors,
        terminalActivationInput: TerminalActivationInput
    ) {
        self.identity = identity
        self.windowMemory = windowMemory
        self.panes = panes
        self.tabs = tabs
        self.activeTabID = activeTabID
        self.repairReport = repairReport
        self.paneGraph = paneGraph
        self.expandedDrawerID = expandedDrawerID
        self.tabShells = tabShells
        self.tabGraph = tabGraph
        self.arrangementCursors = arrangementCursors
        self.terminalActivationInput = terminalActivationInput
    }
}

enum WorkspaceCompositionPreparer {
    static func prepare(
        _ snapshot: WorkspaceSQLiteSnapshot
    ) -> WorkspaceCompositionPreparationResult {
        let paneInputs: PreparedWorkspaceCompositionPaneInputs
        switch preparePaneInputs(from: snapshot.panes) {
        case .success(let preparedPaneInputs):
            paneInputs = preparedPaneInputs
        case .failure(let rejection):
            return .rejected(rejection)
        }

        let paneIDs = paneInputs.paneIDs
        let normalizedPanes = paneInputs.normalizedPanes
        let drawerParentPaneIDByDrawerID = paneInputs.drawerParentPaneIDByDrawerID

        var tabIDs = Set<UUID>()
        var arrangementIDs = Set<UUID>()
        for tab in snapshot.tabs {
            guard tabIDs.insert(tab.id).inserted else {
                return .rejected(.duplicateTabID(tab.id))
            }
            guard !tab.arrangements.isEmpty else {
                return .rejected(.tabHasNoArrangements(tab.id))
            }
            for arrangement in tab.arrangements where !arrangementIDs.insert(arrangement.id).inserted {
                return .rejected(.duplicateArrangementID(arrangement.id))
            }
        }

        var tabsWithoutTransientPresentation = snapshot.tabs
        for tabIndex in tabsWithoutTransientPresentation.indices {
            tabsWithoutTransientPresentation[tabIndex].zoomedPaneId = nil
        }
        let normalization = WorkspaceTabMembershipNormalizer.normalize(
            tabs: tabsWithoutTransientPresentation,
            validPaneIds: paneIDs,
            activeTabId: snapshot.activeTabId,
            drawerParentPaneIdByDrawerId: drawerParentPaneIDByDrawerID
        )

        var tabIDByPaneID: [UUID: UUID] = [:]
        for tab in normalization.tabs {
            for paneID in tab.allPaneIds {
                if let firstTabID = tabIDByPaneID.updateValue(tab.id, forKey: paneID), firstTabID != tab.id {
                    return .rejected(
                        .paneOwnedByMultipleTabs(
                            paneID: paneID,
                            firstTabID: firstTabID,
                            secondTabID: tab.id
                        ))
                }
            }
        }

        let paneGraph: PreparedWorkspacePaneGraph
        switch makePreparedPaneGraph(from: normalizedPanes) {
        case .success(let preparedPaneGraph):
            paneGraph = preparedPaneGraph
        case .failure(let rejection):
            return .rejected(.invalidPaneGraph(rejection))
        }
        let tabShells = makePreparedTabShells(from: normalization.tabs)
        let tabGraphStates = normalization.tabs.map {
            TabGraphState(
                tabId: $0.id,
                allPaneIds: $0.allPaneIds,
                arrangements: $0.arrangements.map(PaneArrangementGraphState.init)
            )
        }
        let tabGraphIndexByID = Dictionary(
            uniqueKeysWithValues: tabGraphStates.enumerated().map { ($0.element.tabId, $0.offset) }
        )
        let arrangementCursors = makeArrangementCursors(from: normalization.tabs)

        return .prepared(
            PreparedWorkspaceComposition(
                identity: PreparedWorkspaceCompositionIdentity(
                    workspaceID: snapshot.id,
                    workspaceName: snapshot.name,
                    createdAt: snapshot.createdAt
                ),
                windowMemory: PreparedWorkspaceCompositionWindowMemory(
                    sidebarWidth: snapshot.sidebarWidth,
                    windowFrame: snapshot.windowFrame
                ),
                panes: normalizedPanes,
                tabs: normalization.tabs,
                activeTabID: normalization.activeTabId,
                repairReport: normalization.repairReport,
                paneGraph: paneGraph,
                expandedDrawerID: makeExpandedDrawerID(from: normalizedPanes),
                tabShells: tabShells,
                tabGraph: PreparedWorkspaceTabGraph(
                    states: tabGraphStates,
                    indexByID: tabGraphIndexByID,
                    tabIDByPaneID: tabIDByPaneID
                ),
                arrangementCursors: arrangementCursors,
                terminalActivationInput: makeTerminalActivationInput(
                    panes: normalizedPanes,
                    tabs: normalization.tabs,
                    activeTabID: normalization.activeTabId,
                    tabIDByPaneID: tabIDByPaneID
                )
            ))
    }

    private static func preparePaneInputs(
        from panes: [Pane]
    ) -> Result<PreparedWorkspaceCompositionPaneInputs, WorkspaceCompositionPreparationRejection> {
        var paneIDs = Set<UUID>()
        var drawerIDs = Set<UUID>()
        for pane in panes {
            guard paneIDs.insert(pane.id).inserted else {
                return .failure(.duplicatePaneID(pane.id))
            }
            if let drawer = pane.drawer, !drawerIDs.insert(drawer.drawerId).inserted {
                return .failure(.duplicateDrawerID(drawer.drawerId))
            }
        }

        var normalizedPanes = panes
        for paneIndex in normalizedPanes.indices {
            normalizedPanes[paneIndex].withDrawer { drawer in
                drawer.paneIds.removeAll { !paneIDs.contains($0) }
            }
        }
        return .success(
            PreparedWorkspaceCompositionPaneInputs(
                paneIDs: paneIDs,
                normalizedPanes: normalizedPanes,
                drawerParentPaneIDByDrawerID: makeDrawerParentPaneIDsByDrawerID(from: normalizedPanes)
            ))
    }

    private static func makeDrawerParentPaneIDsByDrawerID(from panes: [Pane]) -> [UUID: UUID] {
        Dictionary(
            uniqueKeysWithValues: panes.compactMap { pane in
                pane.drawer.map { ($0.drawerId, pane.id) }
            }
        )
    }

    private static func makeExpandedDrawerID(from panes: [Pane]) -> UUID? {
        panes.compactMap { pane -> UUID? in
            guard let drawer = pane.drawer, drawer.isExpanded else { return nil }
            return drawer.drawerId
        }.last
    }

    private static func makePreparedPaneGraph(
        from panes: [Pane]
    ) -> Result<PreparedWorkspacePaneGraph, WorkspacePaneGraphReplacementRejection> {
        WorkspacePaneGraphReplacement.prepare(
            Dictionary(uniqueKeysWithValues: panes.map { ($0.id, PaneGraphState(pane: $0)) })
        ).map { PreparedWorkspacePaneGraph(replacement: $0) }
    }

    private static func makePreparedTabShells(from tabs: [Tab]) -> PreparedWorkspaceTabShells {
        let shells = tabs.map {
            TabShell(id: $0.id, name: $0.name, colorHex: $0.colorHex)
        }
        return PreparedWorkspaceTabShells(
            shells: shells,
            indexByID: Dictionary(
                uniqueKeysWithValues: shells.enumerated().map { ($0.element.id, $0.offset) }
            )
        )
    }

    private static func makeTerminalActivationInput(
        panes: [Pane],
        tabs: [Tab],
        activeTabID: UUID?,
        tabIDByPaneID: [UUID: UUID]
    ) -> TerminalActivationInput {
        let tabsByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        let panesByID = Dictionary(uniqueKeysWithValues: panes.map { ($0.id, $0) })
        let entries = panes.compactMap { pane -> TerminalActivationDescriptor? in
            guard case .terminal(let terminalState) = pane.content else { return nil }
            guard let tabID = tabIDByPaneID[pane.id], let tab = tabsByID[tabID] else { return nil }
            guard
                let hostPlacement = terminalHostPlacement(
                    for: pane,
                    tabID: tabID,
                    panesByID: panesByID
                )
            else { return nil }

            let visibilityPriority = terminalVisibilityPriority(
                for: pane,
                tab: tab,
                activeTabID: activeTabID,
                panesByID: panesByID
            )
            return TerminalActivationDescriptor(
                paneID: PaneId(uuid: pane.id),
                provider: terminalActivationProvider(from: terminalState),
                launchConfiguration: TerminalActivationLaunchConfiguration(
                    launchDirectory: pane.metadata.launchDirectory.map(TerminalActivationLaunchDirectory.stored)
                        ?? .userHomeDefault,
                    executionBackend: pane.metadata.executionBackend,
                    lifetime: terminalState.lifetime,
                    displayTitle: pane.metadata.title
                ),
                visibilityPriority: visibilityPriority,
                hostPlacement: hostPlacement
            )
        }
        return TerminalActivationInput(entries: entries)
    }

    private static func terminalActivationProvider(
        from terminalState: TerminalState
    ) -> TerminalActivationProvider {
        switch terminalState.provider {
        case .ghostty:
            return .ghostty
        case .zmx:
            return .zmx(sessionID: terminalState.zmxSessionID)
        }
    }

    private static func terminalHostPlacement(
        for pane: Pane,
        tabID: UUID,
        panesByID: [UUID: Pane]
    ) -> TerminalHostPlacementIdentity? {
        switch pane.kind {
        case .layout:
            return .tab(tabID: tabID)
        case .drawerChild(let parentPaneID):
            guard let parentPane = panesByID[parentPaneID], let drawer = parentPane.drawer else { return nil }
            return .drawer(
                tabID: tabID,
                parentPaneID: PaneId(uuid: parentPaneID),
                drawerID: drawer.drawerId
            )
        }
    }

    private static func terminalVisibilityPriority(
        for pane: Pane,
        tab: Tab,
        activeTabID: UUID?,
        panesByID: [UUID: Pane]
    ) -> TerminalActivationVisibilityPriority {
        guard tab.id == activeTabID else { return .hidden }
        let arrangement = tab.activeArrangement
        switch pane.kind {
        case .layout:
            let isVisible =
                arrangement.layout.contains(pane.id)
                && !arrangement.minimizedPaneIds.contains(pane.id)
            guard isVisible else { return .hidden }
            return arrangement.activePaneId == pane.id ? .activeVisible : .visible
        case .drawerChild(let parentPaneID):
            let parentIsVisible =
                arrangement.layout.contains(parentPaneID)
                && !arrangement.minimizedPaneIds.contains(parentPaneID)
            guard parentIsVisible,
                let parentDrawer = panesByID[parentPaneID]?.drawer,
                parentDrawer.isExpanded,
                let drawerView = arrangement.drawerViews[parentDrawer.drawerId],
                drawerView.layout.contains(pane.id),
                !drawerView.minimizedPaneIds.contains(pane.id)
            else { return .hidden }
            return drawerView.activeChildId == pane.id ? .activeVisible : .visible
        }
    }

    private static func makeArrangementCursors(
        from tabs: [Tab]
    ) -> PreparedWorkspaceArrangementCursors {
        var activeArrangementIDsByTabID: [UUID: UUID] = [:]
        var paneCursorsByArrangementID: [UUID: ArrangementPaneCursorState] = [:]
        var drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState] = [:]
        for tab in tabs {
            activeArrangementIDsByTabID[tab.id] = tab.activeArrangementId
            for arrangement in tab.arrangements {
                paneCursorsByArrangementID[arrangement.id] = .init(activePaneId: arrangement.activePaneId)
                for (drawerID, drawerView) in arrangement.drawerViews {
                    drawerCursorsByKey[
                        ArrangementDrawerCursorKey(arrangementId: arrangement.id, drawerId: drawerID)
                    ] = .init(activeChildId: drawerView.activeChildId)
                }
            }
        }
        return PreparedWorkspaceArrangementCursors(
            activeArrangementIDsByTabID: activeArrangementIDsByTabID,
            paneCursorsByArrangementID: paneCursorsByArrangementID,
            drawerCursorsByKey: drawerCursorsByKey
        )
    }
}
