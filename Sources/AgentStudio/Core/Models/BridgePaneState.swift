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
    /// Working directory changes relative to a baseline.
    ///
    /// A nil baseline means the initial contribution target still needs to be
    /// designated. Staged and unstaged remain the pre-existing narrow modes.
    case workspace(rootPath: String, baseline: WorkspaceBaseline?)
    /// Snapshot from an agent task at a specific point in time.
    case agentSnapshot(taskId: UUID, timestamp: Date)
}

// MARK: - Workspace Review Contribution Target

/// A symbolic target accepted by the complete-worktree contribution path.
package enum WorkspaceReviewContributionTarget: Codable, Hashable, Sendable {
    case localDefaultBranch(branchName: String)
    case originDefaultBranch(remoteName: String, branchName: String)
    case branch(name: String)
    case commit(oid: String)
    case ref(name: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case branchName
        case remoteName
        case name
        case oid
    }

    private enum Kind: String, Codable {
        case localDefaultBranch
        case originDefaultBranch
        case branch
        case commit
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
        case .commit:
            self = .commit(
                oid: try decodeExactGitCommitOID(from: container, forKey: .oid, decoder: decoder)
            )
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
        case .commit(let oid):
            try container.encode(Kind.commit, forKey: .kind)
            try container.encode(oid, forKey: .oid)
        case .ref(let name):
            try container.encode(Kind.ref, forKey: .kind)
            try container.encode(name, forKey: .name)
        }
    }
}

// MARK: - Workspace Baseline

/// Persisted workspace review baseline.
///
/// Target-bearing cases select a complete-worktree contribution comparison.
/// Staged and unstaged retain their pre-existing narrow meanings.
package enum WorkspaceBaseline: Codable, Hashable, Sendable {
    case localDefaultBranch(branchName: String)
    case originDefaultBranch(remoteName: String, branchName: String)
    case branch(name: String)
    case commit(oid: String)
    case ref(name: String)
    case headMinusOne
    case staged
    case unstaged

    private enum CodingKeys: String, CodingKey {
        case kind
        case branchName
        case remoteName
        case name
        case oid
    }

    private enum Kind: String, Codable {
        case localDefaultBranch
        case originDefaultBranch
        case branch
        case commit
        case ref
        case headMinusOne
        case staged
        case unstaged
    }

    package init(from decoder: Decoder) throws {
        if let legacyValue = try? decoder.singleValueContainer().decode(String.self) {
            self = Self.legacyValue(legacyValue)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
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
        case .commit:
            self = .commit(
                oid: try decodeExactGitCommitOID(from: container, forKey: .oid, decoder: decoder)
            )
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
        case .commit(let oid):
            try container.encode(Kind.commit, forKey: .kind)
            try container.encode(oid, forKey: .oid)
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

    package init(contributionTarget: WorkspaceReviewContributionTarget) {
        switch contributionTarget {
        case .localDefaultBranch(let branchName):
            self = .localDefaultBranch(branchName: branchName)
        case .originDefaultBranch(let remoteName, let branchName):
            self = .originDefaultBranch(remoteName: remoteName, branchName: branchName)
        case .branch(let name):
            self = .branch(name: name)
        case .commit(let oid):
            self = .commit(oid: oid)
        case .ref(let name):
            self = .ref(name: name)
        }
    }

    package var contributionTarget: WorkspaceReviewContributionTarget? {
        switch self {
        case .localDefaultBranch(let branchName):
            .localDefaultBranch(branchName: branchName)
        case .originDefaultBranch(let remoteName, let branchName):
            .originDefaultBranch(remoteName: remoteName, branchName: branchName)
        case .branch(let name):
            .branch(name: name)
        case .commit(let oid):
            .commit(oid: oid)
        case .ref(let name):
            .ref(name: name)
        case .headMinusOne:
            .ref(name: "HEAD~1")
        case .staged, .unstaged:
            nil
        }
    }

    private static func legacyValue(_ value: String) -> Self {
        switch value {
        case Kind.localDefaultBranch.rawValue, "main":
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

private func decodeExactGitCommitOID<CodingKeyType: CodingKey>(
    from container: KeyedDecodingContainer<CodingKeyType>,
    forKey key: CodingKeyType,
    decoder: Decoder
) throws -> String {
    let oid = try container.decode(String.self, forKey: key)
    let utf8 = oid.utf8
    guard utf8.count == 40 || utf8.count == 64,
        utf8.allSatisfy({ byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 70)
                || (byte >= 97 && byte <= 102)
        })
    else {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath + [key],
                debugDescription: "Commit OID must contain exactly 40 or 64 hexadecimal characters"
            )
        )
    }
    return oid
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
        case baseline
        case comparisonTarget
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
            let baseline: WorkspaceBaseline?
            if workspace.contains(.comparisonTarget) {
                baseline = WorkspaceBaseline(
                    contributionTarget: try workspace.decode(
                        WorkspaceReviewContributionTarget.self,
                        forKey: .comparisonTarget
                    )
                )
            } else if let legacyBaseline = try workspace.decodeIfPresent(
                WorkspaceBaseline.self,
                forKey: .baseline
            ) {
                baseline = Self.canonicalBaseline(fromLegacy: legacyBaseline)
            } else {
                baseline = nil
            }
            self = .workspace(
                rootPath: try workspace.decode(String.self, forKey: .rootPath),
                baseline: baseline
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
        case .workspace(let rootPath, let baseline):
            var workspace = container.nestedContainer(
                keyedBy: WorkspaceCodingKeys.self,
                forKey: .workspace
            )
            try workspace.encode(rootPath, forKey: .rootPath)
            switch baseline {
            case .staged, .unstaged, .headMinusOne:
                try workspace.encode(baseline, forKey: .baseline)
            case .localDefaultBranch, .originDefaultBranch, .branch, .commit, .ref:
                try workspace.encode(
                    baseline?.contributionTarget,
                    forKey: .comparisonTarget
                )
            case nil:
                break
            }
        case .agentSnapshot(let taskId, let timestamp):
            var snapshot = container.nestedContainer(
                keyedBy: AgentSnapshotCodingKeys.self,
                forKey: .agentSnapshot
            )
            try snapshot.encode(taskId, forKey: .taskId)
            try snapshot.encode(timestamp, forKey: .timestamp)
        }
    }

    private static func canonicalBaseline(
        fromLegacy baseline: WorkspaceBaseline
    ) -> WorkspaceBaseline? {
        switch baseline {
        case .localDefaultBranch:
            nil
        case .ref(let name) where name == "HEAD":
            nil
        case .originDefaultBranch, .branch, .commit, .ref, .headMinusOne, .staged, .unstaged:
            baseline
        }
    }

}
