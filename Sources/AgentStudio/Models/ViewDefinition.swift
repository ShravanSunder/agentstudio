import Foundation

/// A named arrangement of sessions into tabs. Multiple views can reference the same sessions.
struct ViewDefinition: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var kind: ViewKind
    var tabs: [Tab]
    var activeTabId: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        kind: ViewKind,
        tabs: [Tab] = [],
        activeTabId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.tabs = tabs
        self.activeTabId = activeTabId
    }

    // MARK: - Derived

    /// All session IDs across all tabs in this view.
    var allSessionIds: [UUID] { tabs.flatMap(\.sessionIds) }
}

// MARK: - View Kind

/// The kind of view determines its lifecycle and behavior.
enum ViewKind: Codable, Hashable {
    /// Default view, always exists. Cannot be deleted.
    case main
    /// User-persisted layout snapshot.
    case saved
    /// Auto-generated view for a specific worktree.
    case worktree(worktreeId: UUID)
    /// Rule-based view resolved at runtime.
    case dynamic(rule: DynamicViewRule)
}

// MARK: - Dynamic View Rule

/// Rules for dynamically generating views.
enum DynamicViewRule: Codable, Hashable {
    /// All sessions for a specific repo.
    case byRepo(repoId: UUID)
    /// All sessions running a specific agent type.
    case byAgent(AgentType)
    /// Future: user-defined filter.
    case custom(name: String)
}
