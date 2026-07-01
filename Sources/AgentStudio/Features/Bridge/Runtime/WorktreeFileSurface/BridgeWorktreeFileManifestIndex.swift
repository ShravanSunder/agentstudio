import Foundation

/// Single-writer owner of the ordered Worktree/File manifest for one accepted
/// source generation. Enumeration build, watch-event patches, and interest
/// reads all go through this actor; the stateless materializer never owns
/// index state, and interest serving must not re-enumerate the worktree.
/// Contract: performance-demand-lanes.md, manifest index contract.
actor BridgeWorktreeFileManifestIndex {
    let generation: Int
    private var orderedPaths: [String] = []
    private var rowsByPath: [String: BridgeWorktreeTreeRowMetadata] = [:]
    private(set) var enumerationCount = 0
    private(set) var isEnumerationComplete = false

    init(generation: Int) {
        self.generation = generation
    }

    var count: Int {
        orderedPaths.count
    }

    /// Records that a worktree enumeration pass started feeding this index.
    /// The compact proof asserts this stays at 1 across interest updates.
    func beginEnumeration() {
        enumerationCount += 1
    }

    /// Appends enumeration rows in manifest order, deduplicating by path so
    /// repeated feeds never perturb the deterministic enumeration ordering.
    func appendEnumeratedRows(_ rows: [BridgeWorktreeTreeRowMetadata]) {
        for row in rows where rowsByPath[row.path] == nil {
            rowsByPath[row.path] = row
            orderedPaths.append(row.path)
        }
    }

    func markEnumerationComplete() {
        isEnumerationComplete = true
    }

    /// Serves metadata interest membership from the index in O(requested
    /// paths). Freshness stat-truth is applied by the caller before emission;
    /// interest is not discovery, so only manifest members are returned.
    func memberPaths(of paths: Set<String>) -> Set<String> {
        Set(paths.filter { rowsByPath[$0] != nil })
    }

    /// Watch-event stat-truth: updates existing manifest members in place and
    /// appends newly discovered rows at the end of the ordered manifest
    /// (deterministic enumeration ordering governs only the enumeration pass;
    /// watch additions arrive as deltas).
    func upsertRows(_ rows: [BridgeWorktreeTreeRowMetadata]) {
        for row in rows {
            if rowsByPath[row.path] == nil {
                orderedPaths.append(row.path)
            }
            rowsByPath[row.path] = row
        }
    }

    /// Freshness stat-truth: replaces stored rows for paths that still exist
    /// with rebuilt facts. Never inserts new manifest members, so interest
    /// serving cannot perturb enumeration ordering.
    func applyRefreshedRows(_ rows: [BridgeWorktreeTreeRowMetadata]) {
        for row in rows where rowsByPath[row.path] != nil {
            rowsByPath[row.path] = row
        }
    }

    /// Freshness stat-truth: removes paths whose stat failed. Returns the
    /// removed rows so the caller can emit a `removeRows` delta instead of a
    /// stale upsert.
    func removePaths(_ paths: Set<String>) -> [BridgeWorktreeTreeRowMetadata] {
        var removedRows: [BridgeWorktreeTreeRowMetadata] = []
        for path in paths {
            guard let row = rowsByPath.removeValue(forKey: path) else { continue }
            removedRows.append(row)
        }
        if !removedRows.isEmpty {
            let removedPaths = Set(removedRows.map(\.path))
            orderedPaths.removeAll { removedPaths.contains($0) }
        }
        return removedRows
    }

}
