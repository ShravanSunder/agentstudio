import AgentStudioInfrastructure
import Foundation

struct BridgeProductCommentCatalogBatch: Equatable, Sendable {
    struct Delete: Equatable, Sendable {
        let key: WorktreeAnnotationCatalogKey
        let revision: Int
    }

    let handle: String
    let scopeRevision: Int
    let baseRevision: Int
    let targetRevision: Int
    let puts: [BridgeProductCommentCatalogRecord]
    let deletes: [Delete]
}

enum WorktreeAnnotationCatalogRange: Hashable, Sendable {
    case worktree
    case session(WorktreeAnnotationSessionID)
}

/// N10 owns canonical installed membership. A range read certifies every row
/// inside that range, including absence after a SQLite cascade deletion.
actor BridgeProductCommentCatalogPublisher {
    typealias ReadCurrent =
        @Sendable (WorktreeAnnotationCatalogRange) async throws ->
        [WorktreeAnnotationCatalogKey: WorktreeAnnotationCatalogEntry]

    private var handle: String
    private let readCurrent: ReadCurrent
    private var scopeRevision: Int
    private var dirtyRanges: Set<WorktreeAnnotationCatalogRange> = []
    private var installedEntries: [WorktreeAnnotationCatalogKey: WorktreeAnnotationCatalogEntry] = [:]
    private var installedSessionByKey: [WorktreeAnnotationCatalogKey: WorktreeAnnotationSessionID] = [:]
    private var nextWireRevision = 0
    private var activeCaptureID: UUID?
    private var isRetired = false

    init(
        handle: String,
        scopeRevision: Int,
        readCurrent: @escaping ReadCurrent
    ) {
        precondition(!handle.isEmpty)
        self.handle = handle
        self.scopeRevision = scopeRevision
        self.readCurrent = readCurrent
    }

    func acceptScope(revision: Int) -> Bool {
        guard !isRetired, revision > scopeRevision else { return false }
        scopeRevision = revision
        return true
    }

    func retire() { isRetired = true }

    func replaceHandle(_ newHandle: String) {
        precondition(!newHandle.isEmpty)
        guard newHandle != handle else { return }
        handle = newHandle
        nextWireRevision = 0
        dirtyRanges.removeAll()
        installedEntries.removeAll()
        installedSessionByKey.removeAll()
        activeCaptureID = nil
    }

    func invalidate(_ range: WorktreeAnnotationCatalogRange) {
        dirtyRanges.insert(range)
    }

    func pendingDirtyRangeCount() -> Int { dirtyRanges.count }

    /// Registers for invalidations before the read. The captured handle must
    /// still be current when the complete read installs its diff and revision.
    func captureSnapshot() async throws -> BridgeProductCommentCatalogBatch? {
        guard !isRetired, let captureID = beginCapture() else { return nil }
        defer { endCapture(captureID) }
        let capturedHandle = handle
        let rows = try await readCurrent(.worktree)
        guard !isRetired, handle == capturedHandle else {
            return nil
        }
        return try install(rows, in: .worktree)
    }

    func captureDirty() async throws -> BridgeProductCommentCatalogBatch? {
        guard !isRetired, let range = nextDirtyRange(),
            let captureID = beginCapture()
        else { return nil }
        defer { endCapture(captureID) }
        let capturedHandle = handle
        dirtyRanges.remove(range)
        let rows: [WorktreeAnnotationCatalogKey: WorktreeAnnotationCatalogEntry]
        do {
            rows = try await readCurrent(range)
        } catch {
            if handle == capturedHandle { dirtyRanges.insert(range) }
            throw error
        }
        guard !isRetired, handle == capturedHandle else {
            return nil
        }
        // A second invalidation during the read remains dirty for another
        // pass. This complete read still installs, so continuous edits cannot
        // starve publication.
        do {
            return try install(rows, in: range)
        } catch {
            dirtyRanges.insert(range)
            throw error
        }
    }

    private func beginCapture() -> UUID? {
        guard activeCaptureID == nil else { return nil }
        let captureID = UUIDv7.generate()
        activeCaptureID = captureID
        return captureID
    }

    private func endCapture(_ captureID: UUID) {
        if activeCaptureID == captureID { activeCaptureID = nil }
    }

    private func nextDirtyRange() -> WorktreeAnnotationCatalogRange? {
        if dirtyRanges.contains(.worktree) { return .worktree }
        return dirtyRanges.compactMap { range -> WorktreeAnnotationSessionID? in
            if case .session(let id) = range { return id }
            return nil
        }.min { $0.rawValue.uuidString < $1.rawValue.uuidString }
            .map(WorktreeAnnotationCatalogRange.session)
    }

    private func install(
        _ rows: [WorktreeAnnotationCatalogKey: WorktreeAnnotationCatalogEntry],
        in range: WorktreeAnnotationCatalogRange
    ) throws -> BridgeProductCommentCatalogBatch {
        guard nextWireRevision < BridgeProductWireContract.maximumSafeInteger else {
            throw WorktreeAnnotationServiceError.unavailable
        }
        let baseRevision = nextWireRevision
        let revision = baseRevision + 1
        let membership = try sessionMembership(for: rows)
        if case .session(let sessionID) = range,
            membership.values.contains(where: { $0 != sessionID })
        {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        let previousKeys: Set<WorktreeAnnotationCatalogKey> =
            switch range {
            case .worktree: Set(installedEntries.keys)
            case .session(let sessionID):
                Set(
                    installedSessionByKey.compactMap { key, owner in
                        owner == sessionID ? key : nil
                    })
            }
        let currentKeys = Set(rows.keys)
        let puts = try rows.keys.sorted { $0.recordKey < $1.recordKey }.map { key in
            guard let entry = rows[key] else { preconditionFailure("A selected catalog row disappeared") }
            return try BridgeProductCommentCatalogRecord(entry: entry, revision: revision)
        }
        let deletes = previousKeys.subtracting(currentKeys)
            .sorted { $0.recordKey < $1.recordKey }
            .map { BridgeProductCommentCatalogBatch.Delete(key: $0, revision: revision) }

        for key in previousKeys.subtracting(currentKeys) {
            installedEntries.removeValue(forKey: key)
            installedSessionByKey.removeValue(forKey: key)
        }
        for (key, entry) in rows {
            installedEntries[key] = entry
            installedSessionByKey[key] = membership[key]
        }
        nextWireRevision = revision
        return .init(
            handle: handle,
            scopeRevision: scopeRevision,
            baseRevision: baseRevision,
            targetRevision: revision,
            puts: puts,
            deletes: deletes
        )
    }

    private func sessionMembership(
        for rows: [WorktreeAnnotationCatalogKey: WorktreeAnnotationCatalogEntry]
    ) throws -> [WorktreeAnnotationCatalogKey: WorktreeAnnotationSessionID] {
        var membership: [WorktreeAnnotationCatalogKey: WorktreeAnnotationSessionID] = [:]
        for (key, entry) in rows {
            guard WorktreeAnnotationCatalogKey(entry: entry) == key else {
                throw WorktreeAnnotationServiceError.staleSourceEpoch
            }
            switch entry {
            case .session(let session): membership[key] = session.sessionID
            case .thread(let thread): membership[key] = thread.sessionID
            case .message: break
            }
        }
        for (key, entry) in rows {
            guard case .message(let message) = entry else { continue }
            guard let sessionID = membership[.thread(message.threadID)] else {
                throw WorktreeAnnotationServiceError.staleSourceEpoch
            }
            membership[key] = sessionID
        }
        return membership
    }
}
