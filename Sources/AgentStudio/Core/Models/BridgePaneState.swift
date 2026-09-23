import Foundation

// MARK: - Bridge Pane State

/// Durable core payload of a standalone Bridge pane: which React app the pane
/// loads. What the pane reads — members, opened documents, Files and Review
/// selections — is the pane's receiver navigation record in local UX memory,
/// never this payload. The retired `source` field is read only by the ordered
/// legacy conversion (`LegacyBridgePaneSourceDTO`).
package struct BridgePaneState: Codable, Hashable, Sendable {
    package let panelKind: BridgePanelKind

    package init(panelKind: BridgePanelKind) {
        self.panelKind = panelKind
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

// MARK: - Workspace Review Contribution Target

package enum WorkspaceReviewComparisonBasis: String, Codable, Hashable, Sendable {
    case commonCommit
    case branchTip
}

/// A symbolic target accepted by the complete-worktree contribution path.
package enum WorkspaceReviewContributionTarget: Codable, Hashable, Sendable {
    case localDefaultBranch(
        branchName: String,
        basis: WorkspaceReviewComparisonBasis = .commonCommit
    )
    case originDefaultBranch(
        remoteName: String,
        branchName: String,
        basis: WorkspaceReviewComparisonBasis = .commonCommit
    )
    case branch(name: String, basis: WorkspaceReviewComparisonBasis = .commonCommit)
    case commit(oid: String)
    case ref(name: String, basis: WorkspaceReviewComparisonBasis = .commonCommit)

    private enum CodingKeys: String, CodingKey {
        case kind
        case branchName
        case remoteName
        case name
        case oid
        case basis
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
                branchName: try container.decode(String.self, forKey: .branchName),
                basis: try Self.decodeBasis(from: container, decoder: decoder)
            )
        case .originDefaultBranch:
            self = .originDefaultBranch(
                remoteName: try container.decode(String.self, forKey: .remoteName),
                branchName: try container.decode(String.self, forKey: .branchName),
                basis: try Self.decodeBasis(from: container, decoder: decoder)
            )
        case .branch:
            self = .branch(
                name: try container.decode(String.self, forKey: .name),
                basis: try Self.decodeBasis(from: container, decoder: decoder)
            )
        case .commit:
            self = .commit(
                oid: try decodeExactGitCommitOID(from: container, forKey: .oid, decoder: decoder)
            )
        case .ref:
            self = .ref(
                name: try container.decode(String.self, forKey: .name),
                basis: try Self.decodeBasis(from: container, decoder: decoder)
            )
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .localDefaultBranch(let branchName, let basis):
            try container.encode(Kind.localDefaultBranch, forKey: .kind)
            try container.encode(branchName, forKey: .branchName)
            try container.encode(basis, forKey: .basis)
        case .originDefaultBranch(let remoteName, let branchName, let basis):
            try container.encode(Kind.originDefaultBranch, forKey: .kind)
            try container.encode(remoteName, forKey: .remoteName)
            try container.encode(branchName, forKey: .branchName)
            try container.encode(basis, forKey: .basis)
        case .branch(let name, let basis):
            try container.encode(Kind.branch, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(basis, forKey: .basis)
        case .commit(let oid):
            try container.encode(Kind.commit, forKey: .kind)
            try container.encode(oid, forKey: .oid)
        case .ref(let name, let basis):
            try container.encode(Kind.ref, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(basis, forKey: .basis)
        }
    }

    private static func decodeBasis(
        from container: KeyedDecodingContainer<CodingKeys>,
        decoder: Decoder
    ) throws -> WorkspaceReviewComparisonBasis {
        try container.decodeIfPresent(WorkspaceReviewComparisonBasis.self, forKey: .basis)
            ?? .commonCommit
    }
}

// MARK: - Workspace Baseline

/// Persisted workspace review baseline.
///
/// Target-bearing cases select a complete-worktree contribution comparison.
/// Staged and unstaged retain their pre-existing narrow meanings.
package enum WorkspaceBaseline: Codable, Hashable, Sendable {
    case localDefaultBranch(
        branchName: String,
        basis: WorkspaceReviewComparisonBasis = .commonCommit
    )
    case originDefaultBranch(
        remoteName: String,
        branchName: String,
        basis: WorkspaceReviewComparisonBasis = .commonCommit
    )
    case branch(name: String, basis: WorkspaceReviewComparisonBasis = .commonCommit)
    case commit(oid: String)
    case ref(name: String, basis: WorkspaceReviewComparisonBasis = .commonCommit)
    case headMinusOne
    case staged
    case unstaged

    private enum CodingKeys: String, CodingKey {
        case kind
        case branchName
        case remoteName
        case name
        case oid
        case basis
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
                branchName: try container.decode(String.self, forKey: .branchName),
                basis: try Self.decodeBasis(from: container)
            )
        case .originDefaultBranch:
            self = .originDefaultBranch(
                remoteName: try container.decode(String.self, forKey: .remoteName),
                branchName: try container.decode(String.self, forKey: .branchName),
                basis: try Self.decodeBasis(from: container)
            )
        case .branch:
            self = .branch(
                name: try container.decode(String.self, forKey: .name),
                basis: try Self.decodeBasis(from: container)
            )
        case .commit:
            self = .commit(
                oid: try decodeExactGitCommitOID(from: container, forKey: .oid, decoder: decoder)
            )
        case .ref:
            self = .ref(
                name: try container.decode(String.self, forKey: .name),
                basis: try Self.decodeBasis(from: container)
            )
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
        case .localDefaultBranch(let branchName, let basis):
            try container.encode(Kind.localDefaultBranch, forKey: .kind)
            try container.encode(branchName, forKey: .branchName)
            try container.encode(basis, forKey: .basis)
        case .originDefaultBranch(let remoteName, let branchName, let basis):
            try container.encode(Kind.originDefaultBranch, forKey: .kind)
            try container.encode(remoteName, forKey: .remoteName)
            try container.encode(branchName, forKey: .branchName)
            try container.encode(basis, forKey: .basis)
        case .branch(let name, let basis):
            try container.encode(Kind.branch, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(basis, forKey: .basis)
        case .commit(let oid):
            try container.encode(Kind.commit, forKey: .kind)
            try container.encode(oid, forKey: .oid)
        case .ref(let name, let basis):
            try container.encode(Kind.ref, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(basis, forKey: .basis)
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
        case .localDefaultBranch(let branchName, let basis):
            self = .localDefaultBranch(branchName: branchName, basis: basis)
        case .originDefaultBranch(let remoteName, let branchName, let basis):
            self = .originDefaultBranch(remoteName: remoteName, branchName: branchName, basis: basis)
        case .branch(let name, let basis):
            self = .branch(name: name, basis: basis)
        case .commit(let oid):
            self = .commit(oid: oid)
        case .ref(let name, let basis):
            self = .ref(name: name, basis: basis)
        }
    }

    package var contributionTarget: WorkspaceReviewContributionTarget? {
        switch self {
        case .localDefaultBranch(let branchName, let basis):
            .localDefaultBranch(branchName: branchName, basis: basis)
        case .originDefaultBranch(let remoteName, let branchName, let basis):
            .originDefaultBranch(remoteName: remoteName, branchName: branchName, basis: basis)
        case .branch(let name, let basis):
            .branch(name: name, basis: basis)
        case .commit(let oid):
            .commit(oid: oid)
        case .ref(let name, let basis):
            .ref(name: name, basis: basis)
        case .headMinusOne:
            .ref(name: "HEAD~1", basis: .commonCommit)
        case .staged, .unstaged:
            nil
        }
    }

    private static func legacyValue(_ value: String) -> Self {
        switch value {
        case Kind.localDefaultBranch.rawValue, "main":
            .localDefaultBranch(branchName: "main", basis: .commonCommit)
        case Kind.originDefaultBranch.rawValue:
            .originDefaultBranch(remoteName: "origin", branchName: "main", basis: .commonCommit)
        case Kind.headMinusOne.rawValue:
            .headMinusOne
        case Kind.staged.rawValue:
            .staged
        case Kind.unstaged.rawValue:
            .unstaged
        default:
            .ref(name: value, basis: .commonCommit)
        }
    }

    private static func decodeBasis(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> WorkspaceReviewComparisonBasis {
        try container.decodeIfPresent(WorkspaceReviewComparisonBasis.self, forKey: .basis)
            ?? .commonCommit
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
