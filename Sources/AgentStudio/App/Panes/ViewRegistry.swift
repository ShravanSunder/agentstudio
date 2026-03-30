import AppKit

/// Maps pane IDs to live PaneHostView instances.
/// Runtime only — not persisted. Collaborator of WorkspaceStore.
///
/// NOT @Observable — views should not re-render based on surface registration.
/// Store mutations (via @Observable WorkspaceStore) trigger SwiftUI re-renders;
/// ViewRegistry provides the NSView instances to display during those renders.
@MainActor
final class ViewRegistry {
    private var views: [UUID: PaneHostView] = [:]

    /// Register a view for a pane.
    func register(_ view: PaneHostView, for paneId: UUID) {
        views[paneId] = view
    }

    /// Unregister a view for a pane.
    func unregister(_ paneId: UUID) {
        views.removeValue(forKey: paneId)
    }

    /// Get the view for a pane, if registered.
    func view(for paneId: UUID) -> PaneHostView? {
        views[paneId]
    }

    /// Get the terminal view for a pane, if it is a terminal.
    func terminalView(for paneId: UUID) -> TerminalPaneMountView? {
        guard let view = views[paneId] else { return nil }
        return view.mountedContent(as: TerminalPaneMountView.self)
    }

    /// Get the terminal status placeholder view for a pane, if it is present.
    func terminalStatusPlaceholderView(for paneId: UUID) -> TerminalStatusPlaceholderView? {
        guard let view = views[paneId] else { return nil }
        return view.mountedContent(as: TerminalPaneMountView.self)?.currentPlaceholderView
    }

    /// Get the webview for a pane, if it is a webview.
    func webviewView(for paneId: UUID) -> WebviewPaneMountView? {
        guard let view = views[paneId] else { return nil }
        return view.mountedContent(as: WebviewPaneMountView.self)
    }

    /// All registered webview pane views, keyed by pane ID.
    var allWebviewViews: [UUID: WebviewPaneMountView] {
        views.compactMapValues { view in
            view.mountedContent(as: WebviewPaneMountView.self)
        }
    }

    /// All registered terminal pane views, keyed by pane ID.
    var allTerminalViews: [UUID: TerminalPaneMountView] {
        views.compactMapValues { view in
            view.mountedContent(as: TerminalPaneMountView.self)
        }
    }

    /// All currently registered pane IDs.
    var registeredPaneIds: Set<UUID> {
        Set(views.keys)
    }
}
