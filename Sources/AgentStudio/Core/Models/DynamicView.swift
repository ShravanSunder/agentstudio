import Foundation

/// The facet type for grouping panes into dynamic view tabs.
enum DynamicViewType: String, Codable, CaseIterable, Hashable {
    /// One tab per repository.
    case byRepo
    /// One tab per worktree.
    case byWorktree
    /// One tab per distinct CWD.
    case byCWD
    /// One tab per agent type.
    case byAgentType
    /// One tab per parent folder of repos.
    case byParentFolder

    var displayName: String {
        switch self {
        case .byRepo: return "By Repo"
        case .byWorktree: return "By Worktree"
        case .byCWD: return "By CWD"
        case .byAgentType: return "By Agent Type"
        case .byParentFolder: return "By Parent Folder"
        }
    }
}

/// A single group in a dynamic view projection — represents one virtual tab.
struct DynamicViewGroup: Identifiable, Hashable {
    /// Stable identity derived from the group key (e.g., repo ID, worktree ID).
    let id: String
    /// Display name for this group tab.
    let name: String
    /// Pane IDs in this group, sorted by insertion order.
    let paneIds: [UUID]
    /// Auto-tiled layout for display.
    let layout: Layout
}

/// Result of projecting workspace state through a dynamic view.
struct DynamicViewProjection: Hashable {
    /// The view type used for this projection.
    let viewType: DynamicViewType
    /// The generated groups (virtual tabs), sorted alphabetically by name.
    let groups: [DynamicViewGroup]
}
