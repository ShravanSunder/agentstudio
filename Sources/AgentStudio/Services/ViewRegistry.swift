import AppKit
import os.log

private let registryLogger = Logger(subsystem: "com.agentstudio", category: "ViewRegistry")

/// Maps pane IDs to live AgentStudioTerminalView instances.
/// Runtime only — not persisted. Collaborator of WorkspaceStore.
@MainActor
final class ViewRegistry {
    private var views: [UUID: AgentStudioTerminalView] = [:]

    /// Monotonically increasing counter, bumped on every register/unregister.
    /// Consumers can compare against a cached epoch to detect registry changes
    /// without subscribing to Combine or notifications.
    private(set) var epoch: Int = 0

    /// Register a view for a pane.
    func register(_ view: AgentStudioTerminalView, for paneId: UUID) {
        views[paneId] = view
        epoch += 1
    }

    /// Unregister a view for a pane.
    func unregister(_ paneId: UUID) {
        views.removeValue(forKey: paneId)
        epoch += 1
    }

    /// Get the view for a pane, if registered.
    func view(for paneId: UUID) -> AgentStudioTerminalView? {
        views[paneId]
    }

    /// All currently registered pane IDs.
    var registeredPaneIds: Set<UUID> {
        Set(views.keys)
    }

    /// Build a renderable SplitTree from a Layout.
    /// Gracefully skips missing views: if one side of a split is missing,
    /// promotes the other side. Returns nil only if ALL views are missing.
    func renderTree(for layout: Layout) -> TerminalSplitTree? {
        guard let root = layout.root else { return TerminalSplitTree() }
        guard let renderedRoot = renderNode(root) else {
            registryLogger.warning("renderTree failed — all panes missing views")
            return nil
        }
        return TerminalSplitTree(root: renderedRoot)
    }

    // MARK: - Private

    private func renderNode(_ node: Layout.Node) -> TerminalSplitTree.Node? {
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
                return .split(TerminalSplitTree.Node.Split(
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
