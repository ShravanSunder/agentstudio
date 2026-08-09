import Foundation

// MARK: - Bridge Pane State

/// State for a bridge-backed panel (diff viewer, code review, etc.).
/// Unlike WebviewState, this has no user-visible URL or navigation controls.
/// The panel kind determines which React app/component is loaded, while the
/// source describes what data the panel is displaying.
///
/// Codable for workspace save/restore. Hashable for identity checks.
///
package struct BridgePaneState: Codable, Hashable, Sendable {
    package let panelKind: BridgePanelKind
    package var source: BridgePaneSource?

    package init(panelKind: BridgePanelKind, source: BridgePaneSource?) {
        self.panelKind = panelKind
        self.source = source
    }
}

// MARK: - Bridge Panel Kind

/// The kind of bridge panel. Determines which React app/component is loaded.
///
package enum BridgePanelKind: String, Codable, Hashable, Sendable {
    case diffViewer
    case fileViewer
    // Future: .agentDashboard, .prStatus, etc.
}

// MARK: - Bridge Pane Source

/// What the bridge panel is displaying. Serializable for persistence/restore.
///
/// Each case captures the minimal parameters needed to reconstruct the panel's
/// data query on restore. The bridge panel uses this to fetch and render content.
///
package enum BridgePaneSource: Codable, Hashable, Sendable {
    /// A single commit's diff.
    case commit(sha: String)
    /// Diff between two branches.
    case branchDiff(head: String, base: String)
    /// Working directory changes for one durable comparison intent.
    case workspace(rootPath: String, comparisonIntent: WorkspaceReviewComparisonIntent)
    /// Snapshot from an agent task at a specific point in time.
    case agentSnapshot(taskId: UUID, timestamp: Date)
}

// MARK: - Workspace Review Comparison Intent

/// Durable symbolic intent for a workspace-backed Review surface.
package struct WorkspaceReviewComparisonIntent: Codable, Hashable, Sendable {
    package enum ActiveKind: String, CaseIterable, Codable, Hashable, Sendable {
        case contribution
        case stagedOnly
        case unstagedOnly
    }

    package let activeKind: ActiveKind
    package let contributionTarget: WorkspaceReviewContributionTarget?

    package init(
        activeKind: ActiveKind,
        contributionTarget: WorkspaceReviewContributionTarget?
    ) {
        self.activeKind = activeKind
        self.contributionTarget = contributionTarget
    }
}

/// A symbolic target retained while contribution or a narrow comparison is active.
package enum WorkspaceReviewContributionTarget: Codable, Hashable, Sendable {
    case localDefaultBranch(branchName: String)
    case originDefaultBranch(remoteName: String, branchName: String)
    case branch(name: String)
    case ref(name: String)

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
    }

    package init(from decoder: Decoder) throws {
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
        }
    }

    package func encode(to encoder: Encoder) throws {
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
        }
    }
}

extension BridgePaneSource {
    private enum CodingKeys: String, CodingKey {
        case commit
        case branchDiff
        case workspace
        case agentSnapshot
    }

    private enum CommitCodingKeys: String, CodingKey {
        case sha
    }

    private enum BranchDiffCodingKeys: String, CodingKey {
        case head
        case base
    }

    private enum WorkspaceCodingKeys: String, CodingKey {
        case rootPath
        case comparisonIntent
        case baseline
    }

    private enum AgentSnapshotCodingKeys: String, CodingKey {
        case taskId
        case timestamp
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let sourceKey = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Bridge pane source must contain exactly one recognized case"
                )
            )
        }

        switch sourceKey {
        case .commit:
            let commit = try container.nestedContainer(keyedBy: CommitCodingKeys.self, forKey: .commit)
            self = .commit(sha: try commit.decode(String.self, forKey: .sha))
        case .branchDiff:
            let branchDiff = try container.nestedContainer(
                keyedBy: BranchDiffCodingKeys.self,
                forKey: .branchDiff
            )
            self = .branchDiff(
                head: try branchDiff.decode(String.self, forKey: .head),
                base: try branchDiff.decode(String.self, forKey: .base)
            )
        case .workspace:
            let workspace = try container.nestedContainer(
                keyedBy: WorkspaceCodingKeys.self,
                forKey: .workspace
            )
            let comparisonIntent: WorkspaceReviewComparisonIntent
            if workspace.contains(.comparisonIntent) {
                comparisonIntent = try workspace.decode(
                    WorkspaceReviewComparisonIntent.self,
                    forKey: .comparisonIntent
                )
            } else {
                comparisonIntent = try Self.decodeLegacyComparisonIntent(from: workspace)
            }
            self = .workspace(
                rootPath: try workspace.decode(String.self, forKey: .rootPath),
                comparisonIntent: comparisonIntent
            )
        case .agentSnapshot:
            let snapshot = try container.nestedContainer(
                keyedBy: AgentSnapshotCodingKeys.self,
                forKey: .agentSnapshot
            )
            self = .agentSnapshot(
                taskId: try snapshot.decode(UUID.self, forKey: .taskId),
                timestamp: try snapshot.decode(Date.self, forKey: .timestamp)
            )
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .commit(let sha):
            var commit = container.nestedContainer(keyedBy: CommitCodingKeys.self, forKey: .commit)
            try commit.encode(sha, forKey: .sha)
        case .branchDiff(let head, let base):
            var branchDiff = container.nestedContainer(
                keyedBy: BranchDiffCodingKeys.self,
                forKey: .branchDiff
            )
            try branchDiff.encode(head, forKey: .head)
            try branchDiff.encode(base, forKey: .base)
        case .workspace(let rootPath, let comparisonIntent):
            var workspace = container.nestedContainer(
                keyedBy: WorkspaceCodingKeys.self,
                forKey: .workspace
            )
            try workspace.encode(rootPath, forKey: .rootPath)
            try workspace.encode(comparisonIntent, forKey: .comparisonIntent)
        case .agentSnapshot(let taskId, let timestamp):
            var snapshot = container.nestedContainer(
                keyedBy: AgentSnapshotCodingKeys.self,
                forKey: .agentSnapshot
            )
            try snapshot.encode(taskId, forKey: .taskId)
            try snapshot.encode(timestamp, forKey: .timestamp)
        }
    }

    private static func decodeLegacyComparisonIntent(
        from container: KeyedDecodingContainer<WorkspaceCodingKeys>
    ) throws -> WorkspaceReviewComparisonIntent {
        if let legacyValue = try? container.decode(String.self, forKey: .baseline) {
            return legacySingleValueComparisonIntent(legacyValue)
        }

        let baseline = try container.nestedContainer(
            keyedBy: LegacyBaselineCodingKeys.self,
            forKey: .baseline
        )
        let kind = try baseline.decode(LegacyBaselineKind.self, forKey: .kind)
        return try legacyKeyedComparisonIntent(kind: kind, from: baseline)
    }

    private enum LegacyBaselineCodingKeys: String, CodingKey {
        case kind
        case branchName
        case remoteName
        case name
    }

    private enum LegacyBaselineKind: String, Decodable {
        case localDefaultBranch
        case originDefaultBranch
        case branch
        case ref
        case headMinusOne
        case staged
        case unstaged
    }

    private static func legacyKeyedComparisonIntent(
        kind: LegacyBaselineKind,
        from container: KeyedDecodingContainer<LegacyBaselineCodingKeys>
    ) throws -> WorkspaceReviewComparisonIntent {
        switch kind {
        case .localDefaultBranch:
            _ = try container.decode(String.self, forKey: .branchName)
            return .init(activeKind: .contribution, contributionTarget: nil)
        case .originDefaultBranch:
            return .init(
                activeKind: .contribution,
                contributionTarget: .originDefaultBranch(
                    remoteName: try container.decode(String.self, forKey: .remoteName),
                    branchName: try container.decode(String.self, forKey: .branchName)
                )
            )
        case .branch:
            return .init(
                activeKind: .contribution,
                contributionTarget: .branch(
                    name: try container.decode(String.self, forKey: .name)
                )
            )
        case .headMinusOne:
            return .init(
                activeKind: .contribution,
                contributionTarget: .ref(name: "HEAD~1")
            )
        case .staged:
            return .init(activeKind: .stagedOnly, contributionTarget: nil)
        case .unstaged:
            return .init(activeKind: .unstagedOnly, contributionTarget: nil)
        case .ref:
            return legacyRefIntent(try container.decode(String.self, forKey: .name))
        }
    }

    private static func legacySingleValueComparisonIntent(
        _ value: String
    ) -> WorkspaceReviewComparisonIntent {
        switch value {
        case LegacyBaselineKind.localDefaultBranch.rawValue:
            return .init(activeKind: .contribution, contributionTarget: nil)
        case LegacyBaselineKind.originDefaultBranch.rawValue:
            return .init(
                activeKind: .contribution,
                contributionTarget: .originDefaultBranch(
                    remoteName: "origin",
                    branchName: "main"
                )
            )
        case LegacyBaselineKind.headMinusOne.rawValue:
            return .init(
                activeKind: .contribution,
                contributionTarget: .ref(name: "HEAD~1")
            )
        case LegacyBaselineKind.staged.rawValue:
            return .init(activeKind: .stagedOnly, contributionTarget: nil)
        case LegacyBaselineKind.unstaged.rawValue:
            return .init(activeKind: .unstagedOnly, contributionTarget: nil)
        default:
            return legacyRefIntent(value)
        }
    }

    private static func legacyRefIntent(_ name: String) -> WorkspaceReviewComparisonIntent {
        WorkspaceReviewComparisonIntent(
            activeKind: .contribution,
            contributionTarget: name == "HEAD" ? nil : .ref(name: name)
        )
    }
}
