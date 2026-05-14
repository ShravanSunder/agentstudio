import Foundation

enum RuntimeCommandTarget: Sendable, Equatable {
    case pane(PaneId)
    case activePane
    case activePaneInTab(UUID)
}
