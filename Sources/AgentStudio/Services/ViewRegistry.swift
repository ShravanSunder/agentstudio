import AppKit
import os.log

private let registryLogger = Logger(subsystem: "com.agentstudio", category: "ViewRegistry")

/// Maps session IDs to live AgentStudioTerminalView instances.
/// Runtime only — not persisted. Collaborator of WorkspaceStore.
@MainActor
final class ViewRegistry {
    private var views: [UUID: AgentStudioTerminalView] = [:]

    /// Monotonically increasing counter, bumped on every register/unregister.
    /// Consumers can compare against a cached epoch to detect registry changes
    /// without subscribing to Combine or notifications.
    private(set) var epoch: Int = 0

    /// Register a view for a session.
    func register(_ view: AgentStudioTerminalView, for sessionId: UUID) {
        views[sessionId] = view
        epoch += 1
    }

    /// Unregister a view for a session.
    func unregister(_ sessionId: UUID) {
        views.removeValue(forKey: sessionId)
        epoch += 1
    }

    /// Get the view for a session, if registered.
    func view(for sessionId: UUID) -> AgentStudioTerminalView? {
        views[sessionId]
    }

    /// All currently registered session IDs.
    var registeredSessionIds: Set<UUID> {
        Set(views.keys)
    }

    /// Build a renderable SplitTree from a Layout.
    /// Gracefully skips missing views: if one side of a split is missing,
    /// promotes the other side. Returns nil only if ALL views are missing.
    func renderTree(for layout: Layout) -> TerminalSplitTree? {
        guard let root = layout.root else { return TerminalSplitTree() }
        guard let renderedRoot = renderNode(root) else {
            registryLogger.warning("renderTree failed — all sessions missing views")
            return nil
        }
        return TerminalSplitTree(root: renderedRoot)
    }

    // MARK: - Private

    private func renderNode(_ node: Layout.Node) -> TerminalSplitTree.Node? {
        switch node {
        case .leaf(let sessionId):
            guard let view = views[sessionId] else {
                registryLogger.warning("No view registered for session \(sessionId) — skipping leaf")
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
