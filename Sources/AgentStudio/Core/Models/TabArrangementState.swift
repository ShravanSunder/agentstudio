import Foundation

struct TabArrangementState: Equatable {
    let tabId: UUID
    var allPaneIds: [UUID]
    var arrangements: [PaneArrangement]
    var activeArrangementId: UUID
    var transientState: TabTransientState

    var zoomedPaneId: UUID? {
        get { transientState.zoomedPaneId }
        set { transientState.zoomedPaneId = newValue }
    }

    init(
        tabId: UUID,
        allPaneIds: [UUID],
        arrangements: [PaneArrangement],
        activeArrangementId: UUID,
        transientState: TabTransientState = TabTransientState()
    ) {
        precondition(!arrangements.isEmpty, "TabArrangementState must have at least one arrangement")
        precondition(
            arrangements.filter(\.isDefault).count == 1,
            "TabArrangementState must have exactly one default arrangement"
        )
        precondition(
            arrangements.contains { $0.id == activeArrangementId },
            "TabArrangementState activeArrangementId must resolve"
        )
        self.tabId = tabId
        self.allPaneIds = allPaneIds
        self.arrangements = arrangements
        self.activeArrangementId = activeArrangementId
        self.transientState = transientState
    }
}
