import Foundation
import Observation

struct DrawerViewGraphState: Equatable, Hashable, Sendable {
    var layout: DrawerGridLayout
    var minimizedPaneIds: Set<UUID>

    init(layout: DrawerGridLayout = DrawerGridLayout(), minimizedPaneIds: Set<UUID> = []) {
        self.layout = layout
        self.minimizedPaneIds = minimizedPaneIds.intersection(layout.paneIds)
    }

    init(_ drawerView: DrawerView) {
        self.init(layout: drawerView.layout, minimizedPaneIds: drawerView.minimizedPaneIds)
    }
}

struct PaneArrangementGraphState: Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var isDefault: Bool
    var layout: Layout
    var minimizedPaneIds: Set<UUID>
    var showsMinimizedPanes: Bool
    var drawerViews: [UUID: DrawerViewGraphState]

    init(
        id: UUID,
        name: String,
        isDefault: Bool,
        layout: Layout,
        minimizedPaneIds: Set<UUID>,
        showsMinimizedPanes: Bool,
        drawerViews: [UUID: DrawerViewGraphState]
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.layout = layout
        self.minimizedPaneIds = minimizedPaneIds.intersection(layout.paneIds)
        self.showsMinimizedPanes = showsMinimizedPanes
        self.drawerViews = drawerViews
    }

    init(_ arrangement: PaneArrangement) {
        self.init(
            id: arrangement.id,
            name: arrangement.name,
            isDefault: arrangement.isDefault,
            layout: arrangement.layout,
            minimizedPaneIds: arrangement.minimizedPaneIds,
            showsMinimizedPanes: arrangement.showsMinimizedPanes,
            drawerViews: arrangement.drawerViews.mapValues(DrawerViewGraphState.init)
        )
    }
}

struct TabGraphState: Equatable, Hashable, Sendable {
    let tabId: UUID
    var allPaneIds: [UUID]
    var arrangements: [PaneArrangementGraphState]

    init(tabId: UUID, allPaneIds: [UUID], arrangements: [PaneArrangementGraphState]) {
        self.tabId = tabId
        self.allPaneIds = allPaneIds
        self.arrangements = arrangements
    }

    init(_ state: TabArrangementState) {
        self.init(
            tabId: state.tabId,
            allPaneIds: state.allPaneIds,
            arrangements: state.arrangements.map(PaneArrangementGraphState.init)
        )
    }
}

@MainActor
@Observable
final class WorkspaceTabGraphAtom {
    private(set) var tabStates: [TabGraphState] = []
    private var tabIndexByID: [UUID: Int] = [:]
    private var tabIDByPaneID: [UUID: UUID] = [:]
    private var tabIDByArrangementID: [UUID: UUID] = [:]

    var tabCount: Int {
        tabStates.count
    }

    func containsTab(_ id: UUID) -> Bool {
        tabIndexByID[id] != nil
    }

    func replaceStates(_ states: [TabGraphState]) {
        replaceTabStates(states)
    }

    func replaceTabStates(_ states: [TabGraphState]) {
        let indexes = Self.makeIndexes(states)
        guard tabStates != states else { return }
        tabStates = states
        tabIndexByID = indexes.tabIndexByID
        tabIDByPaneID = indexes.tabIDByPaneID
        tabIDByArrangementID = indexes.tabIDByArrangementID
    }

    func tabState(_ tabId: UUID) -> TabGraphState? {
        tabIndexByID[tabId].map { tabStates[$0] }
    }

    func tabIndex(for tabID: UUID) -> Int? {
        tabIndexByID[tabID]
    }

    func tabID(containingPane paneID: UUID) -> UUID? {
        tabIDByPaneID[paneID]
    }

    func tabID(containingArrangement arrangementID: UUID) -> UUID? {
        tabIDByArrangementID[arrangementID]
    }

    func insertTabState(_ state: TabGraphState, at index: Int) {
        precondition(
            (0...tabStates.count).contains(index),
            "tab graph insertion index must be within the exact insertion boundary"
        )
        precondition(tabIndexByID[state.tabId] == nil, "tab graph identity must be absent before insertion")
        for paneID in state.allPaneIds {
            precondition(
                tabIDByPaneID[paneID] == nil,
                "pane identity must be absent from the tab graph before insertion"
            )
        }
        var insertedArrangementIDs: Set<UUID> = []
        for arrangement in state.arrangements {
            precondition(
                insertedArrangementIDs.insert(arrangement.id).inserted,
                "arrangement identity must be unique within an inserted tab graph"
            )
            precondition(
                tabIDByArrangementID[arrangement.id] == nil,
                "arrangement identity must be absent from the tab graph before insertion"
            )
        }

        tabStates.insert(state, at: index)
        for indexedTab in tabStates[index...].enumerated() {
            tabIndexByID[indexedTab.element.tabId] = index + indexedTab.offset
        }
        for paneID in state.allPaneIds {
            tabIDByPaneID[paneID] = state.tabId
        }
        for arrangement in state.arrangements {
            tabIDByArrangementID[arrangement.id] = state.tabId
        }
    }

    func replaceTabStatePreservingIdentity(_ replacement: TabGraphState) {
        guard let index = tabIndexByID[replacement.tabId] else {
            preconditionFailure("tab graph identity must exist before keyed replacement")
        }
        let previous = tabStates[index]
        precondition(
            previous.allPaneIds == replacement.allPaneIds,
            "identity-preserving tab graph replacement cannot change pane ownership"
        )
        precondition(
            previous.arrangements.map(\.id) == replacement.arrangements.map(\.id),
            "identity-preserving tab graph replacement cannot change arrangement ownership"
        )
        guard previous != replacement else { return }
        tabStates[index] = replacement
    }

    func replaceTabStateAndOwnership(_ replacement: TabGraphState) {
        guard let index = tabIndexByID[replacement.tabId] else {
            preconditionFailure("tab graph identity must exist before keyed replacement")
        }
        let previous = tabStates[index]
        precondition(
            previous.arrangements.map(\.id) == replacement.arrangements.map(\.id),
            "pane residency replacement cannot change arrangement identity"
        )
        for paneID in replacement.allPaneIds {
            let currentOwner = tabIDByPaneID[paneID]
            precondition(
                currentOwner == nil || currentOwner == replacement.tabId,
                "pane identity cannot be assigned to multiple tab graphs"
            )
        }
        for paneID in previous.allPaneIds {
            tabIDByPaneID.removeValue(forKey: paneID)
        }
        for paneID in replacement.allPaneIds {
            tabIDByPaneID[paneID] = replacement.tabId
        }
        guard previous != replacement else { return }
        tabStates[index] = replacement
    }

    func replaceTabStateAndArrangementOwnership(_ replacement: TabGraphState) {
        guard let index = tabIndexByID[replacement.tabId] else {
            preconditionFailure("tab graph identity must exist before arrangement ownership replacement")
        }
        let previous = tabStates[index]
        precondition(
            previous.allPaneIds == replacement.allPaneIds,
            "arrangement ownership replacement cannot change pane ownership"
        )
        var replacementArrangementIDs: Set<UUID> = []
        for arrangement in replacement.arrangements {
            precondition(
                replacementArrangementIDs.insert(arrangement.id).inserted,
                "arrangement identity must be unique within a tab graph"
            )
            let currentOwner = tabIDByArrangementID[arrangement.id]
            precondition(
                currentOwner == nil || currentOwner == replacement.tabId,
                "arrangement identity cannot be assigned to multiple tab graphs"
            )
        }
        for arrangement in previous.arrangements {
            tabIDByArrangementID.removeValue(forKey: arrangement.id)
        }
        for arrangement in replacement.arrangements {
            tabIDByArrangementID[arrangement.id] = replacement.tabId
        }
        guard previous != replacement else { return }
        tabStates[index] = replacement
    }

    func removeTabState(_ tabID: UUID) {
        guard let index = tabIndexByID.removeValue(forKey: tabID) else {
            preconditionFailure("tab graph identity must exist before keyed removal")
        }
        let removed = tabStates.remove(at: index)
        for paneID in removed.allPaneIds {
            tabIDByPaneID.removeValue(forKey: paneID)
        }
        for arrangement in removed.arrangements {
            tabIDByArrangementID.removeValue(forKey: arrangement.id)
        }
        for shiftedIndex in index..<tabStates.count {
            tabIndexByID[tabStates[shiftedIndex].tabId] = shiftedIndex
        }
    }

    private static func makeIndexes(
        _ states: [TabGraphState]
    ) -> (
        tabIndexByID: [UUID: Int],
        tabIDByPaneID: [UUID: UUID],
        tabIDByArrangementID: [UUID: UUID]
    ) {
        var tabIndexByID: [UUID: Int] = [:]
        var tabIDByPaneID: [UUID: UUID] = [:]
        var tabIDByArrangementID: [UUID: UUID] = [:]
        for (index, state) in states.enumerated() {
            precondition(
                tabIndexByID.updateValue(index, forKey: state.tabId) == nil,
                "tab graph identity must be unique"
            )
            for paneID in state.allPaneIds {
                if let firstTabID = tabIDByPaneID.updateValue(state.tabId, forKey: paneID),
                    firstTabID != state.tabId
                {
                    preconditionFailure(
                        "pane \(paneID) cannot belong to tab \(firstTabID) and tab \(state.tabId)"
                    )
                }
            }
            for arrangement in state.arrangements {
                guard tabIDByArrangementID.updateValue(state.tabId, forKey: arrangement.id) == nil else {
                    preconditionFailure("arrangement \(arrangement.id) must have one tab owner")
                }
            }
        }
        return (tabIndexByID, tabIDByPaneID, tabIDByArrangementID)
    }
}
