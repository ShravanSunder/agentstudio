import Foundation

// MARK: - Bridge Pane State

/// State for a bridge-backed panel (diff viewer, code review, etc.).
/// Unlike WebviewState, this has no user-visible URL or navigation controls.
/// The panel kind determines which React app/component is loaded, while the
/// source describes what data the panel is displaying.
///
/// Codable for workspace save/restore. Hashable for identity checks.
///
/// Design doc S15.2 line 3001-3006.
struct BridgePaneState: Codable, Hashable {
    let panelKind: BridgePanelKind
    var source: BridgePaneSource?
}

// MARK: - Bridge Panel Kind

/// The kind of bridge panel. Determines which React app/component is loaded.
///
/// Design doc S15.2 line 3008-3011.
enum BridgePanelKind: String, Codable, Hashable {
    case diffViewer
    // Future: .agentDashboard, .prStatus, etc.
}

// MARK: - Bridge Pane Source

/// What the bridge panel is displaying. Serializable for persistence/restore.
///
/// Each case captures the minimal parameters needed to reconstruct the panel's
/// data query on restore. The bridge panel uses this to fetch and render content.
///
/// Design doc S15.2 line 3013-3019.
enum BridgePaneSource: Codable, Hashable {
    /// A single commit's diff.
    case commit(sha: String)
    /// Diff between two branches.
    case branchDiff(head: String, base: String)
    /// Working directory changes relative to a baseline.
    case workspace(rootPath: String, baseline: WorkspaceBaseline)
    /// Snapshot from an agent task at a specific point in time.
    case agentSnapshot(taskId: UUID, timestamp: Date)
}

// MARK: - Workspace Baseline

/// Baseline reference for workspace diffs.
///
/// Determines what the working directory changes are compared against.
enum WorkspaceBaseline: String, Codable, Hashable {
    /// HEAD~1 (last commit).
    case headMinusOne
    /// Staged changes vs HEAD.
    case staged
    /// Unstaged changes vs staged.
    case unstaged
}
