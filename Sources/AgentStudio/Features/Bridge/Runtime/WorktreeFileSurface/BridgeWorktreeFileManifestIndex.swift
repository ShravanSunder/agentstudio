import AgentStudioInfrastructure
import Foundation

enum BridgeWorktreeFileManifestRemovalResult: Sendable {
    case applied([BridgeWorktreeTreeRowMetadata])
    case rejected
}

struct BridgeWorktreeFileKeyedRecord: Equatable, Sendable {
    let key: String
    let revision: Int
    let row: BridgeWorktreeTreeRowMetadata
    let descriptorOutcome: BridgeProductFileDescriptorReadyPayload?
}

struct BridgeWorktreeFileDescriptorAttempt: Sendable {
    let canonicalKey: String
    let contentGeneration: Int
    let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    let indexGeneration: Int
    let interestRevision: Int
    let invalidationGeneration: Int
    let memberIncarnation: String
    let path: String
    let productAdmission: BridgeProductAdmissionContext
    let source: BridgeProductFileSourceIdentity
    let token: UUID
}

struct BridgeWorktreeFileRetainedDescriptorLease: Sendable {
    let id: UUID
    let descriptor: BridgeProductFileContentDescriptor
}

struct BridgeWorktreeFileKeyedSnapshot: Equatable, Sendable {
    let records: [BridgeWorktreeFileKeyedRecord]
    let targetRevision: Int
    let tombstoneRevisionByKey: [String: Int]
    let absenceFloorRevisionByRange: [String: Int]
}

/// Single-writer owner of the ordered Worktree/File manifest for one accepted
/// source generation. Enumeration build, watch-event patches, and interest
/// reads all go through this actor; the stateless materializer never owns
/// index state, and interest serving must not re-enumerate the worktree.
/// Contract: performance-demand-lanes.md, manifest index contract.
actor BridgeWorktreeFileManifestIndex {
    let generation: Int
    private let owningProductAdmission: BridgeProductAdmissionContext
    private let canonicalRootURL: URL
    private var orderedPaths: [String] = []
    private var rowsByPath: [String: BridgeWorktreeTreeRowMetadata] = [:]
    private var canonicalLocationByPath: [String: String] = [:]
    private var revisionByPath: [String: Int] = [:]
    private var newestDescriptorOutcomeByKey: [String: BridgeProductFileDescriptorReadyPayload] = [:]
    private var contentGenerationByKey: [String: Int] = [:]
    private var invalidationGenerationByKey: [String: Int] = [:]
    private var descriptorAttemptTokenByKey: [String: UUID] = [:]
    private var descriptorInterestRevisionByKey: [String: Int] = [:]
    private var retainedDescriptorByLeaseId: [UUID: BridgeProductFileDescriptorReadyPayload] = [:]
    private let memberIncarnation: String
    private var tombstoneRevisionByKey: [String: Int] = [:]
    private var nextRevision = 0
    private var absenceFloorRevisionByRange: [String: Int] = [:]
    private(set) var enumerationCount = 0
    private(set) var isEnumerationComplete = false

    init(
        generation: Int,
        rootURL: URL,
        productAdmission: BridgeProductAdmissionContext,
        memberIncarnation: String = "default"
    ) {
        self.generation = generation
        self.canonicalRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        self.owningProductAdmission = productAdmission
        self.memberIncarnation = memberIncarnation
    }

    /// A snapshot freezes records and its target in the same actor turn.
    func captureKeyedSnapshot() -> BridgeWorktreeFileKeyedSnapshot {
        let records = orderedPaths.compactMap { path -> BridgeWorktreeFileKeyedRecord? in
            guard let row = rowsByPath[path],
                let key = canonicalLocationByPath[path],
                let revision = revisionByPath[path]
            else { return nil }
            return .init(
                key: key,
                revision: revision,
                row: row,
                descriptorOutcome: newestDescriptorOutcomeByKey[key]
            )
        }
        return .init(
            records: records,
            targetRevision: nextRevision,
            tombstoneRevisionByKey: tombstoneRevisionByKey,
            absenceFloorRevisionByRange: absenceFloorRevisionByRange
        )
    }

    /// Reserves one attempt against the current row, interest and pane admission.
    /// A newer reservation for the same key fences its predecessor before either
    /// materialization returns.
    func reserveDescriptorAttempt(
        for path: String,
        source: BridgeProductFileSourceIdentity,
        memberIncarnation requestedMemberIncarnation: String,
        interestRevision: Int,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) -> BridgeWorktreeFileDescriptorAttempt? {
        guard owningProductAdmission.matches(productAdmission),
            requestedMemberIncarnation == memberIncarnation,
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            productAdmission.withValidAdmission({ true }) == true,
            rowsByPath[path] != nil,
            let canonicalKey = canonicalLocationByPath[path],
            let contentGeneration = contentGenerationByKey[canonicalKey],
            let invalidationGeneration = invalidationGenerationByKey[canonicalKey],
            interestRevision >= (descriptorInterestRevisionByKey[canonicalKey] ?? 0)
        else { return nil }
        let token = UUIDv7.generate()
        descriptorAttemptTokenByKey[canonicalKey] = token
        descriptorInterestRevisionByKey[canonicalKey] = interestRevision
        return .init(
            canonicalKey: canonicalKey,
            contentGeneration: contentGeneration,
            foregroundWorkAdmission: foregroundWorkAdmission,
            indexGeneration: generation,
            interestRevision: interestRevision,
            invalidationGeneration: invalidationGeneration,
            memberIncarnation: memberIncarnation,
            path: path,
            productAdmission: productAdmission,
            source: source,
            token: token
        )
    }

    /// Accepts success and unavailable through the same guard. Descriptor and
    /// wire revision change in this actor turn; no delivery acknowledgement can
    /// roll the accepted outcome back.
    @discardableResult
    func acceptDescriptorOutcome(
        _ outcome: BridgeProductFileDescriptorReadyPayload,
        for attempt: BridgeWorktreeFileDescriptorAttempt
    ) -> Bool {
        guard owningProductAdmission.matches(attempt.productAdmission),
            attempt.indexGeneration == generation,
            attempt.memberIncarnation == memberIncarnation,
            attempt.foregroundWorkAdmission.withValidAdmission({ true }) == true,
            attempt.productAdmission.withValidAdmission({ true }) == true,
            outcome.path == attempt.path,
            outcome.source == attempt.source,
            canonicalLocationByPath[attempt.path] == attempt.canonicalKey,
            rowsByPath[attempt.path] != nil,
            contentGenerationByKey[attempt.canonicalKey] == attempt.contentGeneration,
            invalidationGenerationByKey[attempt.canonicalKey] == attempt.invalidationGeneration,
            descriptorInterestRevisionByKey[attempt.canonicalKey] == attempt.interestRevision,
            descriptorAttemptTokenByKey[attempt.canonicalKey] == attempt.token
        else { return false }
        descriptorAttemptTokenByKey.removeValue(forKey: attempt.canonicalKey)
        guard newestDescriptorOutcomeByKey[attempt.canonicalKey] != outcome else { return true }
        newestDescriptorOutcomeByKey[attempt.canonicalKey] = outcome
        revisionByPath[attempt.path] = mintRevision()
        return true
    }

    @discardableResult
    func invalidateDescriptor(
        for path: String,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        guard owningProductAdmission.matches(productAdmission) else { return false }
        return productAdmission.withValidAdmission { () -> Bool in
            guard let canonicalKey = canonicalLocationByPath[path], rowsByPath[path] != nil else {
                return false
            }
            invalidationGenerationByKey[canonicalKey, default: 0] += 1
            descriptorAttemptTokenByKey.removeValue(forKey: canonicalKey)
            newestDescriptorOutcomeByKey.removeValue(forKey: canonicalKey)
            revisionByPath[path] = mintRevision()
            return true
        } ?? false
    }

    func retainCurrentDescriptor(
        for canonicalKey: String,
        productAdmission: BridgeProductAdmissionContext
    ) -> BridgeWorktreeFileRetainedDescriptorLease? {
        guard owningProductAdmission.matches(productAdmission),
            productAdmission.withValidAdmission({ true }) == true,
            let outcome = newestDescriptorOutcomeByKey[canonicalKey],
            case .available(let descriptor) = outcome.availability
        else { return nil }
        let lease = BridgeWorktreeFileRetainedDescriptorLease(id: UUIDv7.generate(), descriptor: descriptor)
        retainedDescriptorByLeaseId[lease.id] = outcome
        return lease
    }

    func issuedDescriptorOutcome(
        matching descriptor: BridgeProductFileContentDescriptor,
        productAdmission: BridgeProductAdmissionContext
    ) -> BridgeProductFileDescriptorReadyPayload? {
        guard owningProductAdmission.matches(productAdmission),
            productAdmission.withValidAdmission({ true }) == true
        else { return nil }
        for outcome in newestDescriptorOutcomeByKey.values {
            if case .available(let current) = outcome.availability, current == descriptor {
                return outcome
            }
        }
        for outcome in retainedDescriptorByLeaseId.values {
            if case .available(let retained) = outcome.availability, retained == descriptor {
                return outcome
            }
        }
        return nil
    }

    func releaseRetainedDescriptor(_ lease: BridgeWorktreeFileRetainedDescriptorLease) {
        retainedDescriptorByLeaseId.removeValue(forKey: lease.id)
    }

    func revokeRetainedDescriptors() {
        retainedDescriptorByLeaseId.removeAll(keepingCapacity: false)
    }

    var retainedDescriptorLeaseCount: Int { retainedDescriptorByLeaseId.count }

    var count: Int {
        orderedPaths.count
    }

    /// Records that a worktree enumeration pass started feeding this index.
    /// The compact proof asserts this stays at 1 across interest updates.
    @discardableResult
    func beginEnumeration(
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) -> Bool {
        guard owningProductAdmission.matches(productAdmission) else { return false }
        return foregroundWorkAdmission.withValidAdmission {
            productAdmission.withValidAdmission { () -> Bool in
                enumerationCount += 1
                return true
            } ?? false
        } ?? false
    }

    /// Appends enumeration rows in manifest order, deduplicating by path so
    /// repeated feeds never perturb the deterministic enumeration ordering.
    @discardableResult
    func appendEnumeratedRows(
        _ rows: [BridgeWorktreeTreeRowMetadata],
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) -> Bool {
        guard owningProductAdmission.matches(productAdmission) else { return false }
        return foregroundWorkAdmission.withValidAdmission {
            productAdmission.withValidAdmission { () -> Bool in
                for row in rows where rowsByPath[row.path] == nil {
                    upsert(row)
                }
                return true
            } ?? false
        } ?? false
    }

    @discardableResult
    func markEnumerationComplete(
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) -> Bool {
        guard owningProductAdmission.matches(productAdmission) else { return false }
        return foregroundWorkAdmission.withValidAdmission {
            productAdmission.withValidAdmission { () -> Bool in
                isEnumerationComplete = true
                return true
            } ?? false
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
                upsert(row)
            }
            return true
        } ?? false
    }

    /// Watch-refresh mutation guarded by both pane lifetime and current
    /// foreground activity. Initial source enumeration uses `upsertRows`; only
    /// invalidation-driven refreshes require this additional activity epoch.
    @discardableResult
    func upsertRowsForForegroundRefresh(
        _ rows: [BridgeWorktreeTreeRowMetadata],
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) -> Bool {
        guard owningProductAdmission.matches(productAdmission) else { return false }
        return foregroundWorkAdmission.withValidAdmission {
            productAdmission.withValidAdmission { () -> Bool in
                for row in rows {
                    upsert(row)
                }
                return true
            } ?? false
        } ?? false
    }

    /// Freshness stat-truth: replaces stored rows for paths that still exist
    /// with rebuilt facts. Never inserts new manifest members, so interest
    /// serving cannot perturb enumeration ordering.
    @discardableResult
    func applyRefreshedRows(
        _ rows: [BridgeWorktreeTreeRowMetadata],
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) -> Bool {
        guard owningProductAdmission.matches(productAdmission) else { return false }
        return foregroundWorkAdmission.withValidAdmission {
            productAdmission.withValidAdmission { () -> Bool in
                for row in rows where rowsByPath[row.path] != nil {
                    upsert(row)
                }
                return true
            } ?? false
        } ?? false
    }

    /// Freshness stat-truth: removes paths whose stat failed. Returns the
    /// removed rows so the caller can emit a `removeRows` delta instead of a
    /// stale upsert.
    func removePaths(
        _ paths: Set<String>,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) -> BridgeWorktreeFileManifestRemovalResult {
        guard owningProductAdmission.matches(productAdmission) else { return .rejected }
        return foregroundWorkAdmission.withValidAdmission {
            productAdmission.withValidAdmission {
                () -> BridgeWorktreeFileManifestRemovalResult in
                var removedRows: [BridgeWorktreeTreeRowMetadata] = []
                for path in paths {
                    guard let row = remove(path: path) else { continue }
                    removedRows.append(row)
                }
                if !removedRows.isEmpty {
                    let removedPaths = Set(removedRows.map(\.path))
                    orderedPaths.removeAll { removedPaths.contains($0) }
                }
                return .applied(removedRows)
            } ?? .rejected
        } ?? .rejected
    }

    func removePathsForForegroundRefresh(
        _ paths: Set<String>,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) -> BridgeWorktreeFileManifestRemovalResult {
        guard owningProductAdmission.matches(productAdmission) else { return .rejected }
        return foregroundWorkAdmission.withValidAdmission {
            productAdmission.withValidAdmission {
                () -> BridgeWorktreeFileManifestRemovalResult in
                var removedRows: [BridgeWorktreeTreeRowMetadata] = []
                for path in paths {
                    guard let row = remove(path: path) else { continue }
                    removedRows.append(row)
                }
                if !removedRows.isEmpty {
                    let removedPaths = Set(removedRows.map(\.path))
                    orderedPaths.removeAll { removedPaths.contains($0) }
                }
                return .applied(removedRows)
            } ?? .rejected
        } ?? .rejected
    }

    /// A complete certified snapshot permits deletion history to compact to
    /// one range-wide floor. A later snapshot may still contain newer writes.
    func certifyCompleteAbsence(in canonicalRange: String, upTo targetRevision: Int) -> Bool {
        guard isEnumerationComplete,
            isWithinRoot(canonicalRange),
            targetRevision >= (absenceFloorRevisionByRange[canonicalRange] ?? 0),
            targetRevision <= nextRevision
        else { return false }
        absenceFloorRevisionByRange[canonicalRange] = targetRevision
        tombstoneRevisionByKey = tombstoneRevisionByKey.filter { key, revision in
            revision > targetRevision || !Self.isWithin(key, range: canonicalRange)
        }
        return true
    }

    func acceptsExistingRevision(_ revision: Int, for canonicalKey: String) -> Bool {
        let floor = absenceFloorRevisionByRange.reduce(0) { current, entry in
            Self.isWithin(canonicalKey, range: entry.key) ? max(current, entry.value) : current
        }
        return revision > max(floor, tombstoneRevisionByKey[canonicalKey] ?? 0)
    }

    private func isWithinRoot(_ canonicalRange: String) -> Bool {
        Self.isWithin(canonicalRange, range: canonicalRootURL.path)
    }

    private static func isWithin(_ canonicalKey: String, range: String) -> Bool {
        canonicalKey == range || canonicalKey.hasPrefix(range == "/" ? "/" : range + "/")
    }

    private func upsert(_ row: BridgeWorktreeTreeRowMetadata) {
        let canonicalLocation = canonicalRootURL.appending(path: row.path)
            .standardizedFileURL.resolvingSymlinksInPath().path
        if rowsByPath[row.path] == row,
            canonicalLocationByPath[row.path] == canonicalLocation
        {
            return
        }
        if let previousLocation = canonicalLocationByPath[row.path],
            previousLocation != canonicalLocation
        {
            tombstoneRevisionByKey[previousLocation] = mintRevision()
            newestDescriptorOutcomeByKey.removeValue(forKey: previousLocation)
            descriptorAttemptTokenByKey.removeValue(forKey: previousLocation)
        }
        if rowsByPath[row.path] == nil {
            orderedPaths.append(row.path)
        }
        rowsByPath[row.path] = row
        canonicalLocationByPath[row.path] = canonicalLocation
        contentGenerationByKey[canonicalLocation, default: 0] += 1
        invalidationGenerationByKey[canonicalLocation, default: 0] += 1
        descriptorAttemptTokenByKey.removeValue(forKey: canonicalLocation)
        newestDescriptorOutcomeByKey.removeValue(forKey: canonicalLocation)
        revisionByPath[row.path] = mintRevision()
        tombstoneRevisionByKey.removeValue(forKey: canonicalLocation)
    }

    private func remove(path: String) -> BridgeWorktreeTreeRowMetadata? {
        guard let row = rowsByPath.removeValue(forKey: path) else { return nil }
        revisionByPath.removeValue(forKey: path)
        if let canonicalLocation = canonicalLocationByPath.removeValue(forKey: path) {
            tombstoneRevisionByKey[canonicalLocation] = mintRevision()
            contentGenerationByKey[canonicalLocation, default: 0] += 1
            invalidationGenerationByKey[canonicalLocation, default: 0] += 1
            descriptorAttemptTokenByKey.removeValue(forKey: canonicalLocation)
            newestDescriptorOutcomeByKey.removeValue(forKey: canonicalLocation)
        }
        return row
    }

    private func mintRevision() -> Int {
        precondition(nextRevision < BridgeProductWireContract.maximumSafeInteger)
        nextRevision += 1
        return nextRevision
    }

}
