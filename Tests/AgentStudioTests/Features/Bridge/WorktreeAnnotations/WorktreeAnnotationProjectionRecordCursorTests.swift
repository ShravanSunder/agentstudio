import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation finite projection record cursor")
struct WorktreeAnnotationProjectionRecordCursorTests {
    @Test("canonical projection hash is deterministic")
    func canonicalProjectionHashIsDeterministic() throws {
        // Arrange
        let capture = makeProjectionCapture(messageBodies: ["first", "second"])
        let differentlyOrderedCapture = BridgeProductAnnotationProjectionCapture(
            worktreeID: capture.worktreeID,
            recoveryStatus: capture.recoveryStatus,
            sessions: Array(capture.sessions.reversed()),
            details: capture.details.reversed().map { detail in
                WorktreeAnnotationSessionDetail(
                    session: detail.session,
                    threads: detail.threads.reversed().map { threadDetail in
                        WorktreeAnnotationThreadDetail(
                            thread: threadDetail.thread,
                            messages: Array(threadDetail.messages.reversed())
                        )
                    }
                )
            },
            placementsByThreadID: capture.placementsByThreadID,
            projectionRevision: capture.projectionRevision,
            sourceGeneration: capture.sourceGeneration
        )

        // Act
        let first = try BridgeProductAnnotationProjectionRecordAnalysis(capture: capture)
        let second = try BridgeProductAnnotationProjectionRecordAnalysis(capture: differentlyOrderedCapture)

        // Assert
        #expect(first.aggregateSHA256 == second.aggregateSHA256)
        #expect(first.aggregateSHA256.count == 64)
        #expect(first.expectedSessionCount == 1)
        #expect(first.expectedThreadCount == 1)
        #expect(first.expectedMessageCount == 2)
    }

    @Test("a maximum body remains one complete record")
    func maximumBodyRemainsOneCompleteRecord() throws {
        // Arrange
        let maximumBody = String(
            repeating: "a",
            count: WorktreeAnnotationMessagePolicy.maximumBodyUTF8Bytes
        )
        let analysis = try BridgeProductAnnotationProjectionRecordAnalysis(
            capture: makeProjectionCapture(messageBodies: [maximumBody])
        )
        var cursor = try analysis.makePageCursor(pageOrdinal: 0)

        // Act
        let batches = try collectBatches(cursor: &cursor)
        let records = try batches.flatMap(decodeRecords)

        // Assert
        #expect(records.count == 2)
        guard case .message(let messageRecord) = records[1] else {
            Issue.record("Expected one complete message record")
            return
        }
        #expect(messageRecord.message.savedBody == maximumBody)
        #expect(messageRecord.message.handled == false)
    }

    @Test("header excludes command outcomes and output history")
    func headerExcludesCommandOutcomesAndOutputHistory() throws {
        // Arrange
        let analysis = try BridgeProductAnnotationProjectionRecordAnalysis(
            capture: makeProjectionCapture(messageBodies: ["body"])
        )
        var cursor = try analysis.makePageCursor(pageOrdinal: 0)

        // Act
        let firstBatchOrNil = try cursor.nextEncodedBatch()
        let firstBatch = try #require(firstBatchOrNil)
        let encoded = try #require(String(data: firstBatch, encoding: .utf8))

        // Assert
        #expect(!encoded.contains("commandOutcome"))
        #expect(!encoded.contains("outputHistory"))
    }

    @Test("projection timestamps use explicit Unix-millisecond wire members")
    func projectionTimestampsUseUnixMilliseconds() throws {
        // Arrange
        let analysis = try BridgeProductAnnotationProjectionRecordAnalysis(
            capture: makeProjectionCapture(messageBodies: ["body"])
        )
        var cursor = try analysis.makePageCursor(pageOrdinal: 0)

        // Act
        let encoded = try collectBatches(cursor: &cursor)
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined()

        // Assert
        #expect(encoded.contains(#""createdAtUnixMilliseconds":978307300000"#))
        #expect(encoded.contains(#""updatedAtUnixMilliseconds":978307300000"#))
        #expect(encoded.contains(#""completedAtUnixMilliseconds":null"#))
        #expect(!encoded.contains(#""createdAt":"#))
        #expect(!encoded.contains(#""updatedAt":"#))
        #expect(!encoded.contains(#""completedAt":"#))
    }

    @Test("page boundaries occur only between whole records")
    func pageBoundariesOccurOnlyBetweenWholeRecords() throws {
        // Arrange
        let capture = makeProjectionCapture(
            messageBodies: (0..<8).map { index in
                "message-\(index)-" + String(repeating: "b", count: 5000)
            }
        )
        let analysis = try BridgeProductAnnotationProjectionRecordAnalysis(
            capture: capture,
            maximumPageBytes: 18_000,
            maximumFrameBytes: BridgeProductWireContract.maximumContentDataPayloadBytes
        )

        // Act
        var transportedMessageIDs = Set<UUID>()
        for pageOrdinal in 0..<analysis.pageCount {
            var cursor = try analysis.makePageCursor(pageOrdinal: pageOrdinal)
            for batch in try collectBatches(cursor: &cursor) {
                for record in try decodeRecords(batch) {
                    if case .message(let messageRecord) = record {
                        #expect(transportedMessageIDs.insert(messageRecord.message.messageId).inserted)
                    }
                }
            }
        }

        // Assert
        #expect(analysis.pageCount > 1)
        #expect(transportedMessageIDs.count == 8)
    }

    @Test("every emitted physical batch stays within the 128 KiB ceiling")
    func emittedBatchesRespectPhysicalFrameCeiling() throws {
        // Arrange
        let capture = makeProjectionCapture(
            messageBodies: (0..<24).map { index in
                "message-\(index)-" + String(repeating: "c", count: 8000)
            }
        )
        let analysis = try BridgeProductAnnotationProjectionRecordAnalysis(capture: capture)

        // Act / Assert
        for pageOrdinal in 0..<analysis.pageCount {
            var cursor = try analysis.makePageCursor(pageOrdinal: pageOrdinal)
            for batch in try collectBatches(cursor: &cursor) {
                #expect(batch.count <= BridgeProductWireContract.maximumContentDataPayloadBytes)
                _ = try decodeRecords(batch)
            }
        }
    }

    @Test("a singleton record that cannot fit fails closed")
    func singletonRecordThatCannotFitFailsClosed() {
        // Arrange
        let capture = makeProjectionCapture(
            messageBodies: [
                String(
                    repeating: "d",
                    count: WorktreeAnnotationMessagePolicy.maximumBodyUTF8Bytes
                )
            ]
        )

        // Act / Assert
        #expect(throws: BridgeProductAnnotationProjectionRecordCursorError.self) {
            _ = try BridgeProductAnnotationProjectionRecordAnalysis(
                capture: capture,
                maximumFrameBytes: 8 * 1024
            )
        }
    }

    @Test("a body beyond 16 KiB is rejected before projection encoding")
    func oversizedBodyFailsClosed() {
        // Arrange
        let oversizedBody = String(
            repeating: "x",
            count: WorktreeAnnotationMessagePolicy.maximumBodyUTF8Bytes + 1
        )

        // Act / Assert
        #expect(throws: BridgeProductAnnotationProjectionRecordCursorError.invalidCapture) {
            _ = try BridgeProductAnnotationProjectionRecordAnalysis(
                capture: makeProjectionCapture(messageBodies: [oversizedBody])
            )
        }
    }
}

private func collectBatches(
    cursor: inout BridgeProductAnnotationProjectionPageRecordCursor
) throws -> [Data] {
    var batches: [Data] = []
    while let batch = try cursor.nextEncodedBatch() {
        batches.append(batch)
    }
    return batches
}

private func decodeRecords(_ batch: Data) throws -> [BridgeProductAnnotationProjectionRecord] {
    try batch.split(separator: 0x0A).map { line in
        try BridgeProductStrictJSON.decode(
            BridgeProductAnnotationProjectionRecord.self,
            from: Data(line)
        )
    }
}

private func makeProjectionCapture(messageBodies: [String]) -> BridgeProductAnnotationProjectionCapture {
    let sessionID = WorktreeAnnotationSessionID(
        rawValue: UUID(uuidString: "01890abc-def0-7abc-8def-0123456789ab")!
    )
    let threadID = WorktreeAnnotationThreadID(
        rawValue: UUID(uuidString: "01890abc-def0-7abc-8def-0123456789ac")!
    )
    let createdAt = Date(timeIntervalSinceReferenceDate: 100)
    let session = WorktreeAnnotationSession(
        id: sessionID,
        repositoryID: "repository-1",
        worktreeID: "worktree-1",
        originatingWorkspaceID: nil,
        lifecycle: .living,
        sourceRelationship: .applicable,
        acceptedSourceFingerprint: .init(
            repositoryID: "repository-1",
            worktreeID: "worktree-1",
            fileSourceIdentity: "source-1",
            reviewComparisonOrigin: nil
        ),
        semanticRevision: 7,
        createdAt: createdAt,
        updatedAt: createdAt,
        completedAt: nil
    )
    let thread = WorktreeAnnotationThread(
        id: threadID,
        sessionID: sessionID,
        origin: .located(
            .init(
                repositoryRelativePath: "Sources/Feature.swift",
                startLine: 10,
                endLine: 12,
                sourceRole: .file,
                diffSide: nil,
                sourceIdentity: "source-1",
                selectedExcerpt: "let value = 1",
                contextBefore: nil,
                contextAfter: nil
            )
        ),
        resolution: .open,
        createdOrdinal: 1,
        semanticRevision: 5,
        createdAt: createdAt,
        updatedAt: createdAt,
        resolvedAt: nil
    )
    let messages = messageBodies.enumerated().map { index, body in
        WorktreeAnnotationMessage(
            id: WorktreeAnnotationMessageID(
                rawValue: UUID(uuidString: String(format: "01890abc-def0-7abc-8def-%012x", index + 100))!
            ),
            threadID: threadID,
            ordinal: index,
            semanticRevision: index + 1,
            createdAt: createdAt.addingTimeInterval(TimeInterval(index)),
            updatedAt: createdAt.addingTimeInterval(TimeInterval(index)),
            savedBody: body,
            savedRevision: 1,
            draft: nil,
            handled: false,
            status: .editable
        )
    }
    return BridgeProductAnnotationProjectionCapture(
        worktreeID: "worktree-1",
        recoveryStatus: .available,
        sessions: [session],
        details: [.init(session: session, threads: [.init(thread: thread, messages: messages)])],
        placementsByThreadID: [
            threadID: .init(
                placement: .exact,
                currentPath: "Sources/Feature.swift",
                currentStartLine: 10,
                currentEndLine: 12,
                currentSourceIdentity: "source-1"
            )
        ],
        projectionRevision: 11,
        sourceGeneration: 3
    )
}
