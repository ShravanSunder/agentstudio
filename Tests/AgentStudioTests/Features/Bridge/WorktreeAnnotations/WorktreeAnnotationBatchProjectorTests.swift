import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation batch projector")
struct WorktreeAnnotationBatchProjectorTests {
    @Test("new v2 snapshot order, authors, and Markdown are deterministic")
    func deterministicExactV2SnapshotAndMarkdown() throws {
        let fixture = makeBatchFixture()
        let snapshot = try WorktreeAnnotationBatchProjector.makeSnapshot(
            fixture.input(selectedMessages: fixture.selections.reversed())
        )

        #expect(snapshot.schema == "agentstudio.worktree-annotations.batch")
        #expect(snapshot.formatVersion == 2)
        #expect(snapshot.entries.map(\.batchOrdinal) == [0, 1])
        #expect(snapshot.entries.map(\.origin.path) == ["Sources/A.swift", "Sources/B.swift"])
        #expect(snapshot.entries.map(\.bodyMarkdown) == ["## Request A", "## Request B"])
        #expect(snapshot.entries.map(\.message.author.kind.rawValue) == ["human", "agent"])

        let markdown = try #require(
            String(
                data: WorktreeAnnotationBatchProjector.markdownData(
                    for: snapshot,
                    presentation: .init(
                        worktreeLabel: "agent-studio.review-comments",
                        comparisonLabel: nil
                    )
                ),
                encoding: .utf8
            )
        )
        #expect(markdown.split(separator: "\n").filter { $0.hasPrefix("# ") }.count == 1)
        #expect(markdown.contains("Worktree: `agent-studio.review-comments`"))
        #expect(markdown.contains("File: `Sources/A.swift`"))
        #expect(markdown.contains("10 │ let a = 1"))
        #expect(markdown.contains("Author: Human\n\nMessage:\n\n## Request A"))
        #expect(markdown.contains("Author: Agent\n\nMessage:\n\n## Request B"))
    }

    @Test("exact v2 JSON round trips and rejects closed-contract violations")
    func exactV2JSONRoundTripAndRejection() throws {
        let fixture = makeBatchFixture()
        let snapshot = try WorktreeAnnotationBatchProjector.makeSnapshot(
            fixture.input(selectedMessages: fixture.selections)
        )
        let json = try WorktreeAnnotationBatchProjector.jsonData(for: snapshot)
        let decoded = try WorktreeAnnotationBatchProjector.decodeJSON(json)
        #expect(decoded == snapshot)
        #expect(try WorktreeAnnotationBatchProjector.jsonData(for: decoded) == json)

        let jsonString = try #require(String(data: json, encoding: .utf8))
        let unknownField = Data(
            jsonString.replacingOccurrences(of: "{", with: "{\"unexpected\":true,", maxReplacements: 1).utf8
        )
        let unsupportedVersion = Data(
            jsonString.replacingOccurrences(of: "\"formatVersion\":2", with: "\"formatVersion\":3").utf8
        )
        let invalidSchema = Data(
            jsonString.replacingOccurrences(
                of: "agentstudio.worktree-annotations.batch",
                with: "agentstudio.invalid"
            ).utf8
        )
        let inconsistentOrder = try mutateEntries(in: json) { $0.swapAt(0, 1) }
        let duplicateMessage = try mutateEntries(in: json) { entries in
            var second = try #require(entries[1] as? [String: Any])
            let first = try #require(entries[0] as? [String: Any])
            var secondMessage = try #require(second["message"] as? [String: Any])
            let firstMessage = try #require(first["message"] as? [String: Any])
            secondMessage["messageId"] = firstMessage["messageId"]
            second["message"] = secondMessage
            entries[1] = second
        }
        let unknownAuthor = Data(
            jsonString.replacingOccurrences(
                of: "\"kind\":\"agent\"",
                with: "\"kind\":\"automation\""
            ).utf8
        )

        for rejected in [
            unknownField,
            unsupportedVersion,
            invalidSchema,
            inconsistentOrder,
            duplicateMessage,
            unknownAuthor,
        ] {
            #expect(throws: (any Error).self) {
                try WorktreeAnnotationBatchProjector.decodeJSON(rejected)
            }
        }
    }

    @Test("stored v1 remains strict and byte-stable under persisted-version dispatch")
    func storedV1StrictIdentityAndVersionDispatch() throws {
        let fixture = makeBatchFixture()
        let v2 = try WorktreeAnnotationBatchProjector.makeSnapshot(
            fixture.input(selectedMessages: fixture.selections)
        )
        let v2JSON = try WorktreeAnnotationBatchProjector.jsonData(for: v2)
        let v2JSONString = try #require(String(data: v2JSON, encoding: .utf8))
        let v1JSON = Data(
            v2JSONString
                .replacingOccurrences(of: "\"formatVersion\":2", with: "\"formatVersion\":1")
                .replacingOccurrences(of: "\"kind\":\"agent\"", with: "\"kind\":\"human\"")
                .utf8
        )

        let stored = try WorktreeAnnotationStoredBatchDocument.decodeJSON(
            v1JSON,
            persistedFormatVersion: 1
        )
        #expect(stored.formatVersion == 1)
        #expect(try stored.jsonData() == v1JSON)

        let v1JSONString = try #require(String(data: v1JSON, encoding: .utf8))
        let v1WithAgent = Data(
            v1JSONString.replacingOccurrences(of: "\"kind\":\"human\"", with: "\"kind\":\"agent\"").utf8
        )
        let v1WithUnknownAuthor = Data(
            v1JSONString.replacingOccurrences(
                of: "\"kind\":\"human\"",
                with: "\"kind\":\"automation\""
            ).utf8
        )
        for rejected in [v1WithAgent, v1WithUnknownAuthor] {
            #expect(throws: (any Error).self) {
                try WorktreeAnnotationStoredBatchDocument.decodeJSON(
                    rejected,
                    persistedFormatVersion: 1
                )
            }
        }
        #expect(throws: (any Error).self) {
            try WorktreeAnnotationStoredBatchDocument.decodeJSON(v1JSON, persistedFormatVersion: 2)
        }
        #expect(throws: (any Error).self) {
            try WorktreeAnnotationStoredBatchDocument.decodeJSON(v2JSON, persistedFormatVersion: 1)
        }
        #expect(throws: (any Error).self) {
            try WorktreeAnnotationStoredBatchDocument.decodeJSON(v1JSON, persistedFormatVersion: 3)
        }
    }

    @Test("selection requires the current saved revision and located origin")
    func selectionRequiresCurrentSavedRevisionAndLocatedOrigin() throws {
        let fixture = makeBatchFixture()
        let selection = try #require(fixture.selections.first)
        #expect(throws: WorktreeAnnotationBatchProjectorError.savedMessageNotFound) {
            try WorktreeAnnotationBatchProjector.makeSnapshot(
                fixture.input(
                    selectedMessages: [
                        .init(messageID: selection.messageID, expectedSavedRevision: 99)
                    ]
                )
            )
        }
        #expect(throws: WorktreeAnnotationBatchProjectorError.duplicateSelection) {
            try WorktreeAnnotationBatchProjector.makeSnapshot(
                fixture.input(selectedMessages: [selection, selection])
            )
        }
    }

    @Test("selected trailing blank source line remains part of the output origin")
    func selectedTrailingBlankSourceLineRemainsPartOfOutputOrigin() throws {
        let fixture = makeBatchFixture(trailingBlankLineInFirstOrigin: true)

        let snapshot = try WorktreeAnnotationBatchProjector.makeSnapshot(
            fixture.input(selectedMessages: fixture.selections)
        )

        let firstOrigin = try #require(snapshot.entries.first?.origin)
        #expect(firstOrigin.startLine == 10)
        #expect(firstOrigin.endLine == 11)
        #expect(firstOrigin.excerpt.map(\.lineNumber) == [10, 11])
        #expect(firstOrigin.excerpt.map(\.text) == ["let a = 1", ""])
    }
}

private struct BatchFixture {
    let sessionDetail: WorktreeAnnotationSessionDetail
    let selections: [WorktreeAnnotationSQLiteRepository.OutputMessageSelection]
    let placements: [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection]

    func input(
        selectedMessages: some Sequence<WorktreeAnnotationSQLiteRepository.OutputMessageSelection>
    ) -> WorktreeAnnotationBatchProjector.Input {
        .init(
            batchID: .init(rawValue: batchTestUUID(90)),
            createdAt: Date(timeIntervalSince1970: 1_723_833_720),
            sessionDetail: sessionDetail,
            selectedMessages: Array(selectedMessages),
            placementsByThreadID: placements,
            sessionLabel: "Review current implementation",
            worktreeLabel: "agent-studio.review-comments",
            comparisonLabel: nil
        )
    }
}

private func makeBatchFixture(trailingBlankLineInFirstOrigin: Bool = false) -> BatchFixture {
    let sessionID = WorktreeAnnotationSessionID(rawValue: batchTestUUID(1))
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
            fileSourceIdentity: "file-source",
            reviewComparisonOrigin: nil
        ),
        semanticRevision: 1,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1),
        completedAt: nil
    )
    let specifications = [
        (
            path: "Sources/B.swift",
            line: 20,
            body: "## Request B",
            number: 2,
            authorKind: WorktreeAnnotationAuthorKind.agent
        ),
        (
            path: "Sources/A.swift",
            line: 10,
            body: "## Request A",
            number: 1,
            authorKind: WorktreeAnnotationAuthorKind.human
        ),
    ]
    var details: [WorktreeAnnotationThreadDetail] = []
    var selections: [WorktreeAnnotationSQLiteRepository.OutputMessageSelection] = []
    var placements: [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection] = [:]
    for specification in specifications {
        let threadID = WorktreeAnnotationThreadID(rawValue: batchTestUUID(10 + specification.number))
        let messageID = WorktreeAnnotationMessageID(rawValue: batchTestUUID(20 + specification.number))
        let sourceIdentity = "source-\(specification.number)"
        let includesTrailingBlankLine = trailingBlankLineInFirstOrigin && specification.number == 1
        let origin = WorktreeAnnotationLocatedOrigin(
            repositoryRelativePath: specification.path,
            startLine: specification.line,
            endLine: specification.line + (includesTrailingBlankLine ? 1 : 0),
            sourceRole: .file,
            diffSide: nil,
            sourceIdentity: sourceIdentity,
            selectedExcerpt:
                "let \(specification.number == 1 ? "a" : "b") = \(specification.number)"
                + (includesTrailingBlankLine ? "\n" : ""),
            contextBefore: nil,
            contextAfter: nil
        )
        let thread = WorktreeAnnotationThread(
            id: threadID,
            sessionID: sessionID,
            origin: .located(origin),
            resolution: .open,
            createdOrdinal: specification.number,
            semanticRevision: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            resolvedAt: nil
        )
        let message = WorktreeAnnotationMessage(
            id: messageID,
            threadID: threadID,
            ordinal: 0,
            semanticRevision: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            savedBody: specification.body,
            savedRevision: 1,
            draft: nil,
            handled: false,
            status: specification.authorKind == .human ? .editable : .locked,
            authorKind: specification.authorKind
        )
        details.append(.init(thread: thread, messages: [message]))
        selections.append(.init(messageID: messageID, expectedSavedRevision: 1))
        placements[threadID] = .init(
            placement: .exact,
            currentPath: specification.path,
            currentStartLine: specification.line,
            currentEndLine: specification.line + (includesTrailingBlankLine ? 1 : 0),
            currentSourceIdentity: sourceIdentity
        )
    }
    return .init(
        sessionDetail: .init(session: session, threads: details),
        selections: selections,
        placements: placements
    )
}

private func mutateEntries(
    in data: Data,
    mutation: (inout [Any]) throws -> Void
) throws -> Data {
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var entries = try #require(object["entries"] as? [Any])
    try mutation(&entries)
    object["entries"] = entries
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func batchTestUUID(_ suffix: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-7000-8000-%012d", suffix))!
}

extension String {
    fileprivate func replacingOccurrences(
        of target: String,
        with replacement: String,
        maxReplacements: Int
    ) -> String {
        guard maxReplacements > 0, let range = range(of: target) else { return self }
        return replacingCharacters(in: range, with: replacement)
    }
}
