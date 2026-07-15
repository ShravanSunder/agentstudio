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

    func replaceStates(_ states: [TabGraphState]) {
        guard tabStates != states else { return }
        tabStates = states
    }

    func tabState(_ tabId: UUID) -> TabGraphState? {
        tabStates.first { $0.tabId == tabId }
    }
}
