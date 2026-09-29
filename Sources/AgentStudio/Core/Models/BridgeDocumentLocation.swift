import AgentStudioInfrastructure
import Foundation

/// The canonical local file location of a document retained by a receiving
/// Bridge.
///
/// The path is absolute, normalized and symlink-resolved by admission before a
/// location is constructed; this value never touches the filesystem itself and
/// never lowercases paths to invent identity. Two locations are the same
/// document exactly when their canonical paths are equal.
package struct BridgeDocumentLocation: Hashable, Sendable, Comparable {
    package let canonicalPath: String

    package init?(canonicalPath: String) {
        guard canonicalPath.hasPrefix("/"), canonicalPath.count > 1,
            !canonicalPath.hasSuffix("/")
        else {
            return nil
        }
        self.canonicalPath = canonicalPath
    }

    package var fileURL: URL {
        URL(fileURLWithPath: canonicalPath, isDirectory: false)
    }

    package var displayName: String {
        (canonicalPath as NSString).lastPathComponent
    }

    /// Canonical containment: the document lies inside `rootCanonicalPath`.
    /// Both sides must already be canonical; this is grouping evidence only,
    /// never proof of Git identity.
    package func isContained(inCanonicalRoot rootCanonicalPath: String) -> Bool {
        guard !rootCanonicalPath.isEmpty else { return false }
        if rootCanonicalPath == "/" { return true }
        return canonicalPath.hasPrefix(rootCanonicalPath + "/")
    }

    /// The path of this document relative to a containing canonical root.
    package func relativePath(inCanonicalRoot rootCanonicalPath: String) -> String? {
        guard isContained(inCanonicalRoot: rootCanonicalPath) else { return nil }
        if rootCanonicalPath == "/" { return String(canonicalPath.dropFirst()) }
        return String(canonicalPath.dropFirst(rootCanonicalPath.count + 1))
    }

    package static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.canonicalPath < rhs.canonicalPath
    }
}

/// Source evidence recorded when a document was admitted from inside an
/// already-known worktree. It is not a second mutable repository catalog and
/// never implies that the file's repository was registered by opening it.
package struct BridgeKnownWorktreeProvenance: Hashable, Sendable {
    package let repoId: UUID
    package let worktreeId: UUID
    package let relativePath: String

    package init(repoId: UUID, worktreeId: UUID, relativePath: String) {
        self.repoId = repoId
        self.worktreeId = worktreeId
        self.relativePath = relativePath
    }
}

/// One value of a receiver's location-keyed opened-document inventory.
/// The sort key is minted off-main at admission and stays stable on re-show.
package struct BridgeOpenedDocumentEntry: Hashable, Sendable {
    package let provenance: BridgeKnownWorktreeProvenance?
    /// Optional one-based line to use when this Open files row is activated.
    package let openedLine: Int?
    package let sortKey: UUID

    package init(
        provenance: BridgeKnownWorktreeProvenance?,
        openedLine: Int? = nil,
        sortKey: UUID
    ) {
        self.provenance = provenance
        if let openedLine { precondition(openedLine > 0) }
        self.openedLine = openedLine
        precondition(UUIDv7.isV7(sortKey))
        self.sortKey = sortKey
    }
}

/// Where a document belongs in the Files collection, derived from its canonical
/// location and the receiver's member roots — never from how it was opened.
package enum BridgeDocumentGrouping: Hashable, Sendable {
    /// Inside exactly one deepest member root.
    case member(worktreeId: UUID)
    /// Physically outside every member root.
    case loose
    /// Two members share the deepest containing root; Git provenance is not guessed.
    case ambiguous(worktreeIds: [UUID])
}
