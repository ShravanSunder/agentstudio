import AppKit
import os.log

private let registryLogger = Logger(subsystem: "com.agentstudio", category: "ViewRegistry")

/// Maps session IDs to live AgentStudioTerminalView instances.
/// Runtime only — not persisted. Collaborator of WorkspaceStore.
@MainActor
final class ViewRegistry {
    private var views: [UUID: AgentStudioTerminalView] = [:]

    /// Register a view for a session.
    func register(_ view: AgentStudioTerminalView, for sessionId: UUID) {
        views[sessionId] = view
    }

    /// Unregister a view for a session.
    func unregister(_ sessionId: UUID) {
        views.removeValue(forKey: sessionId)
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
    /// Returns nil if any session in the layout lacks a registered view.
    func renderTree(for layout: Layout) -> TerminalSplitTree? {
        guard let root = layout.root else { return TerminalSplitTree() }
        guard let renderedRoot = renderNode(root) else {
            registryLogger.warning("renderTree failed — some sessions missing views")
            return nil
        }
        return TerminalSplitTree(root: renderedRoot)
    }

    // MARK: - Private

    private func renderNode(_ node: Layout.Node) -> TerminalSplitTree.Node? {
        switch node {
        case .leaf(let sessionId):
            guard let view = views[sessionId] else {
                registryLogger.warning("No view registered for session \(sessionId)")
                return nil
            }
            return .leaf(view: view)

        case .split(let split):
            guard let leftNode = renderNode(split.left),
                  let rightNode = renderNode(split.right) else {
                return nil
            }
            // Bridge Layout.SplitDirection → SplitViewDirection
            let viewDirection: SplitViewDirection
            switch split.direction {
            case .horizontal: viewDirection = .horizontal
            case .vertical: viewDirection = .vertical
            }
            return .split(TerminalSplitTree.Node.Split(
                id: split.id,
                direction: viewDirection,
                ratio: split.ratio,
                left: leftNode,
                right: rightNode
            ))
        }
    }
}
