import Foundation

enum BridgeWorktreeFileManifestRemovalResult: Sendable {
    case applied([BridgeWorktreeTreeRowMetadata])
    case rejected
}

/// Single-writer owner of the ordered Worktree/File manifest for one accepted
/// source generation. Enumeration build, watch-event patches, and interest
/// reads all go through this actor; the stateless materializer never owns
/// index state, and interest serving must not re-enumerate the worktree.
/// Contract: performance-demand-lanes.md, manifest index contract.
actor BridgeWorktreeFileManifestIndex {
    let generation: Int
    private let owningProductAdmission: BridgeProductAdmissionContext
    private var orderedPaths: [String] = []
    private var rowsByPath: [String: BridgeWorktreeTreeRowMetadata] = [:]
    private(set) var enumerationCount = 0
    private(set) var isEnumerationComplete = false

    init(
        generation: Int,
        productAdmission: BridgeProductAdmissionContext
    ) {
        self.generation = generation
        self.owningProductAdmission = productAdmission
    }

    var count: Int {
        orderedPaths.count
    }

    /// Records that a worktree enumeration pass started feeding this index.
    /// The compact proof asserts this stays at 1 across interest updates.
    @discardableResult
    func beginEnumeration(productAdmission: BridgeProductAdmissionContext) -> Bool {
        guard owningProductAdmission.matches(productAdmission) else { return false }
        return productAdmission.withValidAdmission { () -> Bool in
            enumerationCount += 1
            return true
        } ?? false
    }

    /// Appends enumeration rows in manifest order, deduplicating by path so
    /// repeated feeds never perturb the deterministic enumeration ordering.
    @discardableResult
    func appendEnumeratedRows(
        _ rows: [BridgeWorktreeTreeRowMetadata],
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        guard owningProductAdmission.matches(productAdmission) else { return false }
        return productAdmission.withValidAdmission { () -> Bool in
            for row in rows where rowsByPath[row.path] == nil {
                rowsByPath[row.path] = row
                orderedPaths.append(row.path)
            }
            return true
        } ?? false
    }

    @discardableResult
    func markEnumerationComplete(productAdmission: BridgeProductAdmissionContext) -> Bool {
        guard owningProductAdmission.matches(productAdmission) else { return false }
        return productAdmission.withValidAdmission { () -> Bool in
            isEnumerationComplete = true
            return true
        } ?? false
    }

    /// Serves metadata interest membership from the index in O(requested
    /// paths). Freshness stat-truth is applied by the caller before emission;
    /// interest is not discovery, so only manifest members are returned.
    func memberPaths(of paths: Set<String>) -> Set<String> {
        Set(paths.filter { rowsByPath[$0] != nil })
    }

    /// A bounded slice of the ordered manifest paths. Used by proof harnesses
    /// to select known manifest members (for example, continuation rows past
    /// the startup window) without re-enumerating the worktree.
    func orderedPaths(startIndex: Int, limit: Int) -> [String] {
        guard startIndex < orderedPaths.count, limit > 0 else {
            return []
        }
        let endIndex = min(startIndex + limit, orderedPaths.count)
        return Array(orderedPaths[startIndex..<endIndex])
    }

    /// Watch-event stat-truth: updates existing manifest members in place and
    /// appends newly discovered rows at the end of the ordered manifest
    /// (deterministic enumeration ordering governs only the enumeration pass;
    /// watch additions arrive as deltas).
    @discardableResult
    func upsertRows(
        _ rows: [BridgeWorktreeTreeRowMetadata],
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        guard owningProductAdmission.matches(productAdmission) else { return false }
        return productAdmission.withValidAdmission { () -> Bool in
            for row in rows {
                if rowsByPath[row.path] == nil {
                    orderedPaths.append(row.path)
                }
                rowsByPath[row.path] = row
            }
            return true
        } ?? false
    }

    /// Freshness stat-truth: replaces stored rows for paths that still exist
    /// with rebuilt facts. Never inserts new manifest members, so interest
    /// serving cannot perturb enumeration ordering.
    @discardableResult
    func applyRefreshedRows(
        _ rows: [BridgeWorktreeTreeRowMetadata],
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        guard owningProductAdmission.matches(productAdmission) else { return false }
        return productAdmission.withValidAdmission { () -> Bool in
            for row in rows where rowsByPath[row.path] != nil {
                rowsByPath[row.path] = row
            }
            return true
        } ?? false
    }

    /// Freshness stat-truth: removes paths whose stat failed. Returns the
    /// removed rows so the caller can emit a `removeRows` delta instead of a
    /// stale upsert.
    func removePaths(
        _ paths: Set<String>,
        productAdmission: BridgeProductAdmissionContext
    ) -> BridgeWorktreeFileManifestRemovalResult {
        guard owningProductAdmission.matches(productAdmission) else { return .rejected }
        return productAdmission.withValidAdmission {
            () -> BridgeWorktreeFileManifestRemovalResult in
            var removedRows: [BridgeWorktreeTreeRowMetadata] = []
            for path in paths {
                guard let row = rowsByPath.removeValue(forKey: path) else { continue }
                removedRows.append(row)
            }
            if !removedRows.isEmpty {
                let removedPaths = Set(removedRows.map(\.path))
                orderedPaths.removeAll { removedPaths.contains($0) }
            }
            return .applied(removedRows)
        } ?? .rejected
    }

}
