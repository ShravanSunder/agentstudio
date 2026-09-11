import Foundation
import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Worktree annotation committed message bounds", .serialized)
struct WorktreeAnnotationCommittedMessageBoundsTests {
    @Test(
        "accepted saved and draft bodies remain serializable as a complete message",
        arguments: ["ordinary", "escaped", "control"]
    )
    func committedBodiesRemainSerializable(bodyKind: String) async throws {
        // Arrange — use real service and SQLite commits, not a fabricated message.
        let harness = try await makeTransportAdapterHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let initial = try await createSavedTransportMessage(harness: harness)
        let sessionID = initial.detail.session.id
        let savedCharacter = bodyKind == "control" ? "\u{0001}" : bodyKind == "escaped" ? "\\" : "a"
        let draftCharacter = bodyKind == "control" ? "\u{0002}" : bodyKind == "escaped" ? "\"" : "b"
        let savedBody = String(repeating: savedCharacter, count: WorktreeAnnotationMessagePolicy.maximumBodyUTF8Bytes)
        let draftBody = String(repeating: draftCharacter, count: WorktreeAnnotationMessagePolicy.maximumBodyUTF8Bytes)
        #expect(try WorktreeAnnotationMessagePolicy.validate(savedBody) == savedBody)
        #expect(try WorktreeAnnotationMessagePolicy.validate(draftBody) == draftBody)
        let initialDraft = try await harness.store.flushDraft(
            .init(
                sessionID: sessionID, messageID: initial.message.id, editToken: "bounds-editor",
                expectedMessageRevision: initial.message.semanticRevision, expectedDraftRevision: nil,
                body: savedBody, now: Date(timeIntervalSince1970: 102)))
        let beforeSave = try #require(initialDraft.detail.threads.first?.messages.first)
        let saved = try await harness.store.saveDraft(
            .init(
                sessionID: sessionID, messageID: initial.message.id, editToken: "bounds-editor",
                expectedMessageRevision: beforeSave.semanticRevision,
                expectedDraftRevision: try #require(beforeSave.draft?.draftRevision),
                now: Date(timeIntervalSince1970: 103)))
        let beforeEdit = try #require(saved.threads.first?.messages.first)

        // Act — both independently valid bodies coexist after a committed edit.
        let edited = try await harness.store.flushDraft(
            .init(
                sessionID: sessionID, messageID: initial.message.id, editToken: "bounds-editor",
                expectedMessageRevision: beforeEdit.semanticRevision, expectedDraftRevision: nil,
                body: draftBody, now: Date(timeIntervalSince1970: 104)))
        let persisted = try await persistedDetail(sessionID: sessionID, harness: harness)
        let thread = try #require(persisted.threads.first)
        let message = try #require(thread.messages.first)

        // Assert — a durable success must not become unreadable during serialization.
        #expect(persisted.session.semanticRevision == edited.detail.session.semanticRevision)
        #expect(message.savedBody == savedBody)
        #expect(message.draft?.body == draftBody)
        let entry = try BridgeProductWorktreeAnnotationMessageEntry(
            message: message, session: persisted.session, thread: thread.thread)
        let encoded = try JSONEncoder().encode(entry)
        #expect(encoded.count <= BridgeProductWireContract.maximumContentDataPayloadBytes)
        let context = try BridgeProductWorktreeAnnotationThreadContext(thread.thread, placement: nil)
        let record = BridgeProductAnnotationProjectionMessageRecord(context: context, message: entry)
        let completeRecord = try JSONEncoder().encode(record)
        #expect(completeRecord.count <= BridgeProductWireContract.maximumContentDataPayloadBytes)
        let capture = BridgeProductAnnotationProjectionCapture(
            worktreeID: persisted.session.worktreeID, recoveryStatus: .available,
            sessions: [persisted.session], details: [persisted], placementsByThreadID: [:],
            projectionRevision: persisted.session.semanticRevision, sourceGeneration: 1)
        let analysis = try BridgeProductAnnotationProjectionRecordAnalysis(capture: capture)
        var cursor = try analysis.makePageCursor(pageOrdinal: 0)
        var decodedMessages: [BridgeProductWorktreeAnnotationMessageEntry] = []
        while let batch = try cursor.nextEncodedBatch() {
            #expect(batch.count <= BridgeProductWireContract.maximumContentDataPayloadBytes)
            for line in batch.split(separator: 0x0A) {
                let decoded = try BridgeProductStrictJSON.decode(
                    BridgeProductAnnotationProjectionRecord.self, from: Data(line))
                if case .message(let record) = decoded { decodedMessages.append(record.message) }
            }
        }
        #expect(decodedMessages.count == 1)
        #expect(decodedMessages.first?.savedBody == savedBody)
        #expect(decodedMessages.first?.draft?.body == draftBody)
        let canonicalReceipt = try BridgeProductWorktreeAnnotationMessageReceiptDTO(
            session: persisted.session, thread: thread.thread, message: message)
        // Exercise the permitted context byte limits independently of the real filesystem fixture.
        var rawReceipt = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(canonicalReceipt)) as? [String: Any])
        var maximumContext = try #require(rawReceipt["context"] as? [String: Any])
        maximumContext["path"] = String(repeating: "\u{0001}", count: 4096)
        maximumContext["sourceIdentity"] = String(repeating: "s", count: 128)
        rawReceipt["context"] = maximumContext
        let receipt = try BridgeProductStrictJSON.decode(
            BridgeProductWorktreeAnnotationMessageReceiptDTO.self,
            from: JSONSerialization.data(withJSONObject: rawReceipt))
        let correlation = try BridgeProductControlCorrelation(
            paneSessionId: String(repeating: "p", count: 128),
            requestId: String(repeating: "r", count: 128),
            requestSequence: BridgeProductWireContract.maximumControlRequestSequence,
            workerInstanceId: String(repeating: "w", count: 128))
        let outcome = BridgeProductWorktreeAnnotationCommandOutcomeDTO(
            .init(requestID: correlation.requestId, surface: .file, sessionID: sessionID, status: .committed),
            receipt: receipt)
        let response = BridgeProductControlResponse.callCompleted(
            .init(correlation: correlation, call: .fileAnnotationsCommand(.completed(outcome))))
        let responseBytes = try JSONEncoder().encode(response)
        #expect(responseBytes.count <= BridgeProductWireContract.maximumRequestBodyBytes)
        #expect(try BridgeProductStrictJSON.decode(BridgeProductControlResponse.self, from: responseBytes) == response)
        print("Canonical full control envelope kind=\(bodyKind) bytes=\(responseBytes.count)")
        print("Annotation envelope kind=\(bodyKind) messageBytes=\(encoded.count) recordBytes=\(completeRecord.count)")
    }
}
