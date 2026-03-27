import AppKit
import os.log

private let registryLogger = Logger(subsystem: "com.agentstudio", category: "ViewRegistry")

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
        return view.mountedContent(as: TerminalPaneMountView.self)?.placeholderViewForTesting
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

    /// Build a renderable SplitTree from a Layout.
    /// Gracefully skips missing views: if one side of a split is missing,
    /// promotes the other side. Returns nil only if ALL views are missing.
    func renderTree(for layout: Layout) -> PaneSplitTree? {
        guard let root = layout.root else { return PaneSplitTree() }
        guard let renderedRoot = renderNode(root) else {
            registryLogger.warning("renderTree failed — all panes missing views")
            return nil
        }
        return PaneSplitTree(root: renderedRoot)
    }

    // MARK: - Private

    private func renderNode(_ node: Layout.Node) -> PaneSplitTree.Node? {
        switch node {
        case .leaf(let paneId):
            guard let view = views[paneId] else {
                registryLogger.warning("No view registered for pane \(paneId) — skipping leaf")
                return nil
            }
            return .leaf(view: view)

        case .split(let split):
            let leftNode = renderNode(split.left)
            let rightNode = renderNode(split.right)

            // Both present → normal split
            if let left = leftNode, let right = rightNode {
                let viewDirection: SplitViewDirection
                switch split.direction {
                case .horizontal: viewDirection = .horizontal
                case .vertical: viewDirection = .vertical
                }
                return .split(
                    PaneSplitTree.Node.Split(
                        id: split.id,
                        direction: viewDirection,
                        ratio: split.ratio,
                        left: left,
                        right: right
                    ))
            }

            // One child missing → promote the surviving side
            if let left = leftNode {
                registryLogger.warning("Split \(split.id): right child missing — promoting left")
                return left
            }
            if let right = rightNode {
                registryLogger.warning("Split \(split.id): left child missing — promoting right")
                return right
            }

            // Both missing
            return nil
        }
    }
}
