import Foundation

@testable import AgentStudio

extension PaneArrangement {
    init(
        id: UUID = UUID(),
        name: String = "Default",
        isDefault: Bool = true,
        layout: Layout,
        visiblePaneIds _: Set<UUID>,
        minimizedPaneIds: Set<UUID> = []
    ) {
        self.init(
            id: id,
            name: name,
            isDefault: isDefault,
            layout: layout,
            minimizedPaneIds: minimizedPaneIds,
            activePaneId: layout.paneIds.first { !minimizedPaneIds.contains($0) } ?? layout.paneIds.first
        )
    }

    var visiblePaneIds: Set<UUID> {
        Set(layout.paneIds)
    }
}

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
            normalizedArrangements[activeIndex].activePaneId = activePaneId
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

    var visiblePaneIds: [UUID] {
        activePaneIds.filter { !activeMinimizedPaneIds.contains($0) }
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
            normalizedArrangements[activeIndex].activePaneId = activePaneId
        }
        self.init(
            tabId: tabId,
            allPaneIds: allPaneIds,
            arrangements: normalizedArrangements,
            activeArrangementId: activeArrangementId,
            zoomedPaneId: zoomedPaneId
        )
    }

    var activePaneId: UUID? {
        arrangements.first { $0.id == activeArrangementId }?.activePaneId
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
