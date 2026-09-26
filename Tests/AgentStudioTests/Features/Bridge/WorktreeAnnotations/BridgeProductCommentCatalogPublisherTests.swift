import AgentStudioInfrastructure
import AgentStudioTestHarness
import Testing

@testable import AgentStudioBridge

@Suite("Bridge comment N10 current-row publisher")
struct BridgeProductCommentCatalogPublisherTests {
    @Test("wire revisions advance per handle independently of semantic revisions and include deletes")
    func currentRowsDetermineWireUpdates() async throws {
        let sessionID = WorktreeAnnotationSessionID(rawValue: UUIDv7.generate())
        let key = WorktreeAnnotationCatalogKey.session(sessionID)
        let entry = WorktreeAnnotationCatalogEntry.session(
            try .init(sessionID: sessionID, semanticRevision: 0)
        )
        let currentRows = CommentCurrentRowsGate([key: entry])
        let publisher = BridgeProductCommentCatalogPublisher(
            handle: "comment-handle-1",
            readCurrent: { keys in try await currentRows.read(keys) }
        )

        let initial = try await publisher.installSnapshot([entry])
        #expect(initial.handle == "comment-handle-1")
        #expect(initial.targetRevision == 1)
        #expect(initial.puts.first?.revision == 1)
        #expect(initial.puts.first?.entry == entry)
        await publisher.invalidate([key])
        let unchangedSemantic = try #require(await publisher.captureDirty())
        #expect(unchangedSemantic.targetRevision == 2)
        #expect(unchangedSemantic.puts.first?.revision == 2)
        #expect(unchangedSemantic.puts.first?.entry == entry)

        await currentRows.remove(key)
        await publisher.invalidate([key])
        let deleted = try #require(await publisher.captureDirty())
        #expect(deleted.targetRevision == 3)
        #expect(deleted.puts.isEmpty)
        #expect(deleted.deletes == [.init(key: key, revision: 3)])
    }

    @Test("a newer invalidation during a suspended read cannot mint an older row")
    func heldReadKeepsNewestRowDirty() async throws {
        let sessionID = WorktreeAnnotationSessionID(rawValue: UUIDv7.generate())
        let key = WorktreeAnnotationCatalogKey.session(sessionID)
        let oldEntry = WorktreeAnnotationCatalogEntry.session(
            try .init(sessionID: sessionID, semanticRevision: 0)
        )
        let newEntry = WorktreeAnnotationCatalogEntry.session(
            try .init(sessionID: sessionID, semanticRevision: 1)
        )
        let currentRows = CommentCurrentRowsGate([key: oldEntry])
        let publisher = BridgeProductCommentCatalogPublisher(
            handle: "comment-handle-1",
            readCurrent: { keys in try await currentRows.read(keys) }
        )
        _ = try await publisher.installSnapshot([oldEntry])
        let heldRead = HeldStep<[WorktreeAnnotationCatalogKey: WorktreeAnnotationCatalogEntry]>(
            "commentCurrentRows"
        )
        await currentRows.holdNextRead(heldRead)
        await publisher.invalidate([key])
        let firstCapture = Task { try await publisher.captureDirty() }
        let observedRows = try await heldRead.firstArrival()
        #expect(observedRows[key] == oldEntry)

        await currentRows.set(newEntry, for: key)
        await publisher.invalidate([key])
        let concurrentCapture = try await publisher.captureDirty()
        #expect(concurrentCapture == nil)
        heldRead.release()
        let staleCapture = try await firstCapture.value
        #expect(staleCapture == nil)
        let current = try #require(await publisher.captureDirty())
        #expect(current.targetRevision == 2)
        #expect(current.puts.first?.entry == newEntry)
        #expect(current.puts.first?.revision == 2)
    }

    @Test("new handle resets wire revisions and discards prior dirty keys")
    func newHandleResetsWireCursor() async throws {
        let sessionID = WorktreeAnnotationSessionID(rawValue: UUIDv7.generate())
        let key = WorktreeAnnotationCatalogKey.session(sessionID)
        let entry = WorktreeAnnotationCatalogEntry.session(
            try .init(sessionID: sessionID, semanticRevision: 0)
        )
        let currentRows = CommentCurrentRowsGate([key: entry])
        let publisher = BridgeProductCommentCatalogPublisher(
            handle: "old-handle",
            readCurrent: { keys in try await currentRows.read(keys) }
        )
        _ = try await publisher.installSnapshot([entry])
        await publisher.invalidate([key])

        await publisher.replaceHandle("new-handle")
        #expect(await publisher.pendingDirtyKeyCount() == 0)
        let replacement = try await publisher.installSnapshot([entry])
        #expect(replacement.handle == "new-handle")
        #expect(replacement.targetRevision == 1)
        #expect(replacement.puts.first?.revision == 1)
    }

    @Test("a mismatched current row cannot consume a wire revision or dirty key")
    func mismatchedCurrentRowKeepsDirtyKey() async throws {
        let sessionID = WorktreeAnnotationSessionID(rawValue: UUIDv7.generate())
        let otherSessionID = WorktreeAnnotationSessionID(rawValue: UUIDv7.generate())
        let key = WorktreeAnnotationCatalogKey.session(sessionID)
        let entry = WorktreeAnnotationCatalogEntry.session(
            try .init(sessionID: sessionID, semanticRevision: 0)
        )
        let otherEntry = WorktreeAnnotationCatalogEntry.session(
            try .init(sessionID: otherSessionID, semanticRevision: 0)
        )
        let currentRows = CommentCurrentRowsGate([key: otherEntry])
        let publisher = BridgeProductCommentCatalogPublisher(
            handle: "comment-handle-1",
            readCurrent: { keys in try await currentRows.read(keys) }
        )
        _ = try await publisher.installSnapshot([entry])
        await publisher.invalidate([key])

        await #expect(throws: WorktreeAnnotationServiceError.staleSourceEpoch) {
            _ = try await publisher.captureDirty()
        }
        #expect(await publisher.pendingDirtyKeyCount() == 1)
        await currentRows.set(entry, for: key)
        let recovered = try #require(await publisher.captureDirty())
        #expect(recovered.targetRevision == 2)
        #expect(recovered.puts.first?.entry == entry)
    }
}

private actor CommentCurrentRowsGate {
    private var rowsByKey: [WorktreeAnnotationCatalogKey: WorktreeAnnotationCatalogEntry]
    private var heldNextRead: HeldStep<[WorktreeAnnotationCatalogKey: WorktreeAnnotationCatalogEntry]>?

    init(_ rowsByKey: [WorktreeAnnotationCatalogKey: WorktreeAnnotationCatalogEntry]) {
        self.rowsByKey = rowsByKey
    }

    func read(_ keys: Set<WorktreeAnnotationCatalogKey>) async throws -> [WorktreeAnnotationCatalogKey:
        WorktreeAnnotationCatalogEntry]
    {
        let capturedRows = rowsByKey.filter { keys.contains($0.key) }
        if let heldNextRead {
            self.heldNextRead = nil
            try await heldNextRead.arrive(capturedRows)
        }
        return capturedRows
    }

    func holdNextRead(
        _ heldRead: HeldStep<[WorktreeAnnotationCatalogKey: WorktreeAnnotationCatalogEntry]>
    ) { heldNextRead = heldRead }

    func set(_ entry: WorktreeAnnotationCatalogEntry, for key: WorktreeAnnotationCatalogKey) {
        rowsByKey[key] = entry
    }

    func remove(_ key: WorktreeAnnotationCatalogKey) {
        rowsByKey.removeValue(forKey: key)
    }
}
