import Foundation

@testable import AgentStudio

extension Tab {
    init(
        id: UUID = UUID(),
        name: String = "Tab",
        allPaneIds: [UUID],
        arrangements: [PaneArrangement],
        activeArrangementId: UUID,
        activePaneId: UUID?,
        zoomedPaneId: UUID? = nil
    ) {
        var normalizedArrangements = arrangements
        if let activeIndex = normalizedArrangements.firstIndex(where: { $0.id == activeArrangementId }) {
            normalizedArrangements[activeIndex].activePaneId = activePaneId.map(MainPaneId.init)
        }
        self.init(
            id: id,
            name: name,
            allPaneIds: allPaneIds,
            arrangements: normalizedArrangements,
            activeArrangementId: activeArrangementId,
            zoomedPaneId: zoomedPaneId
        )
    }

    init(
        id: UUID = UUID(),
        name: String = "Tab",
        panes: [UUID],
        arrangements: [PaneArrangement],
        activeArrangementId: UUID,
        activePaneId: UUID?,
        zoomedPaneId: UUID? = nil
    ) {
        self.init(
            id: id,
            name: name,
            allPaneIds: panes,
            arrangements: arrangements,
            activeArrangementId: activeArrangementId,
            activePaneId: activePaneId,
            zoomedPaneId: zoomedPaneId
        )
    }

}

extension TabArrangementState {
    init(
        tabId: UUID,
        allPaneIds: [UUID],
        arrangements: [PaneArrangement],
        activeArrangementId: UUID,
        activePaneId: UUID?,
        zoomedPaneId: UUID?
    ) {
        var normalizedArrangements = arrangements
        if let activeIndex = normalizedArrangements.firstIndex(where: { $0.id == activeArrangementId }) {
            normalizedArrangements[activeIndex].activePaneId = activePaneId.map(MainPaneId.init)
        }
        self.init(
            tabId: tabId,
            allPaneIds: allPaneIds,
            arrangements: normalizedArrangements,
            activeArrangementId: activeArrangementId,
            transientState: TabTransientState(zoomedPaneId: zoomedPaneId)
        )
    }

    init(
        tabId: UUID,
        allPaneIds: [UUID],
        arrangements: [PaneArrangement],
        activeArrangementId: UUID,
        activePaneId: UUID?,
        transientState: TabTransientState
    ) {
        var normalizedArrangements = arrangements
        if let activeIndex = normalizedArrangements.firstIndex(where: { $0.id == activeArrangementId }) {
            normalizedArrangements[activeIndex].activePaneId = activePaneId.map(MainPaneId.init)
        }
        self.init(
            tabId: tabId,
            allPaneIds: allPaneIds,
            arrangements: normalizedArrangements,
            activeArrangementId: activeArrangementId,
            transientState: transientState
        )
    }

    var activePaneId: UUID? {
        arrangements.first { $0.id == activeArrangementId }?.activePaneId?.rawValue
    }
}

extension Drawer {
    init(
        paneIds: [UUID] = [],
        isExpanded: Bool = false
    ) {
        self.init(parentPaneId: UUID(), paneIds: paneIds, isExpanded: isExpanded)
    }
}
