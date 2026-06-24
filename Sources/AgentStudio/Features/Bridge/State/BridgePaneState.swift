import Foundation

// MARK: - Bridge Pane State

/// State for a bridge-backed panel (diff viewer, code review, etc.).
/// Unlike WebviewState, this has no user-visible URL or navigation controls.
/// The panel kind determines which React app/component is loaded, while the
/// source describes what data the panel is displaying.
///
/// Codable for workspace save/restore. Hashable for identity checks.
///
struct BridgePaneState: Codable, Hashable, Sendable {
    let panelKind: BridgePanelKind
    var source: BridgePaneSource?
}

// MARK: - Bridge Panel Kind

/// The kind of bridge panel. Determines which React app/component is loaded.
///
enum BridgePanelKind: String, Codable, Hashable, Sendable {
    case diffViewer
    // Future: .agentDashboard, .prStatus, etc.
}

// MARK: - Bridge Pane Source

/// What the bridge panel is displaying. Serializable for persistence/restore.
///
/// Each case captures the minimal parameters needed to reconstruct the panel's
/// data query on restore. The bridge panel uses this to fetch and render content.
///
enum BridgePaneSource: Codable, Hashable, Sendable {
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

/// Baseline reference for workspace review diffs.
///
/// Determines what the current workspace is compared against. Branch/ref cases
/// are resolved by the Git data plane when the review package is built.
enum WorkspaceBaseline: Codable, Hashable, Sendable {
    /// Local default branch, normally `main`.
    case localDefaultBranch(branchName: String)
    /// Remote default branch, normally `origin/main`.
    case originDefaultBranch(remoteName: String, branchName: String)
    /// Named local or remote branch.
    case branch(name: String)
    /// Arbitrary Git ref, tag, or SHA.
    case ref(name: String)
    /// HEAD~1 (last commit).
    case headMinusOne
    /// Staged changes vs HEAD.
    case staged
    /// Unstaged changes vs staged.
    case unstaged

    private enum CodingKeys: String, CodingKey {
        case kind
        case branchName
        case remoteName
        case name
    }

    private enum Kind: String, Codable {
        case localDefaultBranch
        case originDefaultBranch
        case branch
        case ref
        case headMinusOne
        case staged
        case unstaged
    }

    init(from decoder: Decoder) throws {
        if let legacyValue = try? decoder.singleValueContainer().decode(String.self) {
            self = Self.legacyValue(legacyValue)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .localDefaultBranch:
            self = .localDefaultBranch(
                branchName: try container.decode(String.self, forKey: .branchName)
            )
        case .originDefaultBranch:
            self = .originDefaultBranch(
                remoteName: try container.decode(String.self, forKey: .remoteName),
                branchName: try container.decode(String.self, forKey: .branchName)
            )
        case .branch:
            self = .branch(name: try container.decode(String.self, forKey: .name))
        case .ref:
            self = .ref(name: try container.decode(String.self, forKey: .name))
        case .headMinusOne:
            self = .headMinusOne
        case .staged:
            self = .staged
        case .unstaged:
            self = .unstaged
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .localDefaultBranch(let branchName):
            try container.encode(Kind.localDefaultBranch, forKey: .kind)
            try container.encode(branchName, forKey: .branchName)
        case .originDefaultBranch(let remoteName, let branchName):
            try container.encode(Kind.originDefaultBranch, forKey: .kind)
            try container.encode(remoteName, forKey: .remoteName)
            try container.encode(branchName, forKey: .branchName)
        case .branch(let name):
            try container.encode(Kind.branch, forKey: .kind)
            try container.encode(name, forKey: .name)
        case .ref(let name):
            try container.encode(Kind.ref, forKey: .kind)
            try container.encode(name, forKey: .name)
        case .headMinusOne:
            try container.encode(Kind.headMinusOne, forKey: .kind)
        case .staged:
            try container.encode(Kind.staged, forKey: .kind)
        case .unstaged:
            try container.encode(Kind.unstaged, forKey: .kind)
        }
    }

    private static func legacyValue(_ value: String) -> Self {
        switch value {
        case Kind.localDefaultBranch.rawValue:
            .localDefaultBranch(branchName: "main")
        case Kind.originDefaultBranch.rawValue:
            .originDefaultBranch(remoteName: "origin", branchName: "main")
        case Kind.headMinusOne.rawValue:
            .headMinusOne
        case Kind.staged.rawValue:
            .staged
        case Kind.unstaged.rawValue:
            .unstaged
        default:
            .ref(name: value)
        }
    }
}
