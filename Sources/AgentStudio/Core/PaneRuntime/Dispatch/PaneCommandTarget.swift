import Foundation

enum PaneCommandTarget: Sendable, Equatable {
    case pane(PaneId)
    case activePane
    case activePaneInTab(UUID)
}
