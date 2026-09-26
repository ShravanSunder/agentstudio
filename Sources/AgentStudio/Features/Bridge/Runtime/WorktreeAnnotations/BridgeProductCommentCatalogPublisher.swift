import Foundation

struct BridgeProductCommentCatalogBatch: Equatable, Sendable {
    struct Delete: Equatable, Sendable {
        let key: WorktreeAnnotationCatalogKey
        let revision: Int
    }

    let handle: String
    let targetRevision: Int
    let puts: [BridgeProductCommentCatalogRecord]
    let deletes: [Delete]
}

/// N10's serialized comment minter. Repository reads return current rows in one
/// transaction; invalidations carry keys, never a suspended mutation's payload.
actor BridgeProductCommentCatalogPublisher {
    typealias ReadCurrent =
        @Sendable (Set<WorktreeAnnotationCatalogKey>) async throws ->
        [WorktreeAnnotationCatalogKey: WorktreeAnnotationCatalogEntry]

    private var handle: String
    private let readCurrent: ReadCurrent
    private var dirtyKeys: Set<WorktreeAnnotationCatalogKey> = []
    private var nextWireRevision = 0
    private var captureInProgress = false

    init(handle: String, readCurrent: @escaping ReadCurrent) {
        precondition(!handle.isEmpty)
        self.handle = handle
        self.readCurrent = readCurrent
    }

    func replaceHandle(_ newHandle: String) {
        precondition(!newHandle.isEmpty)
        guard newHandle != handle else { return }
        handle = newHandle
        nextWireRevision = 0
        dirtyKeys.removeAll()
    }

    func invalidate(_ keys: Set<WorktreeAnnotationCatalogKey>) {
        dirtyKeys.formUnion(keys)
    }

    func pendingDirtyKeyCount() -> Int { dirtyKeys.count }

    /// The caller registers for invalidations before its SQLite snapshot read.
    /// Invalidations that arrive during that read remain dirty for the next batch.
    func installSnapshot(_ entries: [WorktreeAnnotationCatalogEntry]) throws
        -> BridgeProductCommentCatalogBatch
    {
        let revision = try mintWireRevision()
        let puts = try entries.map { try BridgeProductCommentCatalogRecord(entry: $0, revision: revision) }
            .sorted { $0.recordKey < $1.recordKey }
        return .init(handle: handle, targetRevision: revision, puts: puts, deletes: [])
    }

    func captureDirty() async throws -> BridgeProductCommentCatalogBatch? {
        guard !captureInProgress, !dirtyKeys.isEmpty else { return nil }
        captureInProgress = true
        defer { captureInProgress = false }
        let capturedHandle = handle
        let requestedKeys = dirtyKeys
        dirtyKeys.subtract(requestedKeys)
        let currentRows: [WorktreeAnnotationCatalogKey: WorktreeAnnotationCatalogEntry]
        do {
            currentRows = try await readCurrent(requestedKeys)
        } catch {
            if handle == capturedHandle { dirtyKeys.formUnion(requestedKeys) }
            throw error
        }
        guard handle == capturedHandle else { return nil }
        // A second commit for one key may have arrived while the read was
        // suspended. Leave it dirty and avoid minting old content over it.
        let settledKeys = requestedKeys.subtracting(dirtyKeys)
        guard !settledKeys.isEmpty else { return nil }
        for key in settledKeys {
            if let entry = currentRows[key], WorktreeAnnotationCatalogKey(entry: entry) != key {
                dirtyKeys.formUnion(settledKeys)
                throw WorktreeAnnotationServiceError.staleSourceEpoch
            }
        }
        let revision = try mintWireRevision()
        var puts: [BridgeProductCommentCatalogRecord] = []
        var deletes: [BridgeProductCommentCatalogBatch.Delete] = []
        for key in settledKeys.sorted(by: { $0.recordKey < $1.recordKey }) {
            if let entry = currentRows[key] {
                puts.append(try BridgeProductCommentCatalogRecord(entry: entry, revision: revision))
            } else {
                deletes.append(.init(key: key, revision: revision))
            }
        }
        return .init(handle: handle, targetRevision: revision, puts: puts, deletes: deletes)
    }

    private func mintWireRevision() throws -> Int {
        guard nextWireRevision < BridgeProductWireContract.maximumSafeInteger else {
            throw WorktreeAnnotationServiceError.unavailable
        }
        nextWireRevision += 1
        return nextWireRevision
    }
}
