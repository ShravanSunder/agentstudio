import Foundation

package struct TabArrangementState: Equatable {
    package let tabId: UUID
    package internal(set) var allPaneIds: [UUID]
    package internal(set) var arrangements: [PaneArrangement]
    package internal(set) var activeArrangementId: UUID

    package init(
        tabId: UUID,
        allPaneIds: [UUID],
        arrangements: [PaneArrangement],
        activeArrangementId: UUID
    ) {
        self.tabId = tabId
        self.allPaneIds = allPaneIds
        self.arrangements = arrangements
        self.activeArrangementId = activeArrangementId
    }
}
