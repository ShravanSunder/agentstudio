import Foundation

package struct TabArrangementState: Equatable {
    package let tabId: UUID
    package internal(set) var allPaneIds: [UUID]
    package internal(set) var arrangements: [PaneArrangement]
    package internal(set) var activeArrangementId: UUID
    package internal(set) var zoomedPaneId: UUID?

    package init(
        tabId: UUID,
        allPaneIds: [UUID],
        arrangements: [PaneArrangement],
        activeArrangementId: UUID,
        zoomedPaneId: UUID?
    ) {
        self.tabId = tabId
        self.allPaneIds = allPaneIds
        self.arrangements = arrangements
        self.activeArrangementId = activeArrangementId
        self.zoomedPaneId = zoomedPaneId
    }
}
