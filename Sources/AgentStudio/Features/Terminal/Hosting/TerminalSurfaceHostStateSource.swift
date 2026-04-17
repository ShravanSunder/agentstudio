import AppKit

@MainActor
protocol TerminalSurfaceHostStateSource: AnyObject {
    var hostScrollbarState: ScrollbarState? { get }
    var hostConfigSnapshot: GhosttyHostConfigSnapshot { get }
    var reportedCellSize: NSSize? { get }
    var onHostScrollbarStateChanged: (@MainActor @Sendable (ScrollbarState) -> Void)? { get set }
}

extension Ghostty.SurfaceView: TerminalSurfaceHostStateSource {}
