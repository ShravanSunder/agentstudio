import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceInteractionAtom {
    var draggingTabId: UUID?
    var dropTargetIndex: Int?
    var tabFrames: [UUID: CGRect] = [:]
    var isSplitResizing: Bool = false

    func setDraggingTabId(_ draggingTabId: UUID?) {
        self.draggingTabId = draggingTabId
    }

    func setDropTargetIndex(_ dropTargetIndex: Int?) {
        self.dropTargetIndex = dropTargetIndex
    }

    func setTabFrames(_ tabFrames: [UUID: CGRect]) {
        self.tabFrames = tabFrames
    }

    func setIsSplitResizing(_ isSplitResizing: Bool) {
        self.isSplitResizing = isSplitResizing
    }
}
