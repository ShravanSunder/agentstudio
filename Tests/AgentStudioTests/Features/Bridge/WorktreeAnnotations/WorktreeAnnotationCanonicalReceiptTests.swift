import Foundation
import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Worktree annotation canonical command receipts", .serialized)
struct WorktreeAnnotationCanonicalReceiptTests {
    @Test("canonical wire rejects legacy, mismatched, partial, and placement-bearing receipts")
    func canonicalWireRejectsInvalidReceipts() async throws {
        // Arrange — derive the wire fixture from the real canonical native encoder.
        let harness = try await makeTransportAdapterHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let saved = try await createSavedTransportMessage(harness: harness)
        let thread = try #require(saved.detail.threads.first)
        let receipt = try BridgeProductWorktreeAnnotationMessageReceiptDTO(
            session: saved.detail.session, thread: thread.thread, message: saved.message)
        let outcome = BridgeProductWorktreeAnnotationCommandOutcomeDTO(
            .init(
                requestID: "canonical-strict", surface: .file, sessionID: saved.detail.session.id, status: .committed),
            receipt: receipt)
        let valid = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(outcome)) as? [String: Any])
        let validReceipt = try #require(valid["receipt"] as? [String: Any])
        let validMessage = try #require(validReceipt["message"] as? [String: Any])
        let validContext = try #require(validReceipt["context"] as? [String: Any])
        var partialMessage = validMessage
        partialMessage.removeValue(forKey: "savedBody")
        var placementContext = validContext
        placementContext["placement"] = "exact"
        var mismatchedContext = validContext
        mismatchedContext["threadId"] = WorktreeAnnotationThreadID.generate().rawValue.uuidString.lowercased()
        let invalidReceipts: [[String: Any]] = [
            ["kind": "message", "messageId": saved.message.id.rawValue.uuidString.lowercased(), "messageRevision": 1],
            ["kind": "message", "context": validContext, "message": partialMessage],
            ["kind": "message", "context": placementContext, "message": validMessage],
            ["kind": "message", "context": mismatchedContext, "message": validMessage],
        ]

        // Act / Assert
        #expect(
            try BridgeProductStrictJSON.decode(
                BridgeProductWorktreeAnnotationCommandOutcomeDTO.self, from: JSONEncoder().encode(outcome)) == outcome)
        for invalidReceipt in invalidReceipts {
            let invalid = valid.merging(["receipt": invalidReceipt]) { _, next in next }
            #expect(throws: (any Error).self) {
                _ = try BridgeProductStrictJSON.decode(
                    BridgeProductWorktreeAnnotationCommandOutcomeDTO.self,
                    from: JSONSerialization.data(withJSONObject: invalid))
            }
        }
        var failedOutcome = valid
        failedOutcome["status"] = ["kind": "failed", "code": "conflict"]
        var mismatchedOutcome = valid
        mismatchedOutcome["sessionId"] = WorktreeAnnotationSessionID.generate().rawValue.uuidString.lowercased()
        for invalid in [failedOutcome, mismatchedOutcome] {
            #expect(throws: (any Error).self) {
                _ = try BridgeProductStrictJSON.decode(
                    BridgeProductWorktreeAnnotationCommandOutcomeDTO.self,
                    from: JSONSerialization.data(withJSONObject: invalid))
            }
        }
    }

    @Test("edit ownership and saved Revert return complete current messages")
    func editOwnershipAndSavedRevertReturnCanonicalMessages() async throws {
        // Arrange — existing saved message, no projection used to complete commands.
        let harness = try await makeTransportAdapterHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let saved = try await createSavedTransportMessage(harness: harness)
        var messageRevision = saved.message.semanticRevision
        var draftRevision: Int?
        var editToken = "canonical-editor"

        // Act — flush, relinquish, reacquire, and revert against exact returned fences.
        for kind in ["draft.flush", "draft.edit.release", "draft.edit.acquire", "draft.revert"] {
            if kind == "draft.edit.acquire" { editToken = "canonical-editor-reacquired" }
            var operation: [String: Any] = [
                "kind": kind, "sessionId": saved.detail.session.id.rawValue.uuidString.lowercased(),
                "messageId": saved.message.id.rawValue.uuidString.lowercased(), "editToken": editToken,
                "expectedMessageRevision": messageRevision,
                "expectedDraftRevision": draftRevision.map { $0 as Any } ?? NSNull(),
            ]
            if kind == "draft.flush" { operation["body"] = "Canonical changed draft" }
            let outcome = await harness.adapter.apply(
                try canonicalReceiptCommand(operation), surface: .file,
                correlation: try makeAnnotationCorrelation(requestID: "canonical-\(kind)"),
                productAdmission: harness.productAdmission)

            // Assert — canonical body and edit state are command-owned, not local guesses.
            #expect(outcome.status == .committed)
            guard case .message(let context, let message) = try #require(outcome.receipt) else {
                Issue.record("Expected a complete message receipt for \(kind)")
                return
            }
            #expect(message.messageId == saved.message.id.rawValue)
            #expect(context.threadId == message.threadId)
            #expect(message.messageRevision > messageRevision)
            #expect(message.savedBody == saved.message.savedBody)
            if kind == "draft.revert" {
                #expect(message.draft == nil)
            } else {
                #expect(message.draft?.body == "Canonical changed draft")
                #expect(message.draft?.activeEditToken == (kind == "draft.edit.release" ? nil : editToken))
            }
            let bytes = try JSONEncoder().encode(outcome)
            #expect(
                try BridgeProductStrictJSON.decode(BridgeProductWorktreeAnnotationCommandOutcomeDTO.self, from: bytes)
                    == outcome)
            messageRevision = message.messageRevision
            draftRevision = message.draft?.revision
        }
    }

    @Test(
        "removing a never-saved draft returns its exact committed tombstone", arguments: ["root", "reply"],
        ["draft.flush", "draft.revert"])
    func removedDraftReturnsCanonicalTombstone(targetKind: String, operationKind: String) async throws {
        // Arrange — real SQLite mutations, with no projection read after command completion.
        let harness = try await makeTransportAdapterHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let editToken = "canonical-removal-editor"
        var createOperation: [String: Any] = ["body": "Discard this unsaved draft", "editToken": editToken]
        if targetKind == "reply" {
            let saved = try await createSavedTransportMessage(harness: harness)
            let thread = try #require(saved.detail.threads.first)
            createOperation["kind"] = "reply.create"
            createOperation["sessionId"] = saved.detail.session.id.rawValue.uuidString.lowercased()
            createOperation["threadId"] = thread.thread.id.rawValue.uuidString.lowercased()
            createOperation["expectedThreadRevision"] = thread.thread.semanticRevision
        } else {
            createOperation["kind"] = "root.create"
            createOperation["admission"] = ["kind": "implicitOrSingle"]
            createOperation["origin"] = [
                "kind": "located", "path": "Sources/Example.swift", "sourceIdentity": "file-source-1",
                "sourceRole": "file", "diffSide": NSNull(), "startLine": 2, "endLine": 3,
            ]
        }
        let created = await harness.adapter.apply(
            try canonicalReceiptCommand(createOperation),
            surface: .file,
            correlation: try makeAnnotationCorrelation(requestID: "canonical-removal-create"),
            productAdmission: harness.productAdmission
        )
        #expect(created.status == .committed)
        let sessionID = WorktreeAnnotationSessionID(rawValue: try #require(created.sessionId))
        let before = try await persistedDetail(sessionID: sessionID, harness: harness)
        let thread = try #require(before.threads.last)
        let message = try #require(thread.messages.last)
        var removal: [String: Any] = [
            "kind": operationKind,
            "sessionId": sessionID.rawValue.uuidString.lowercased(),
            "messageId": message.id.rawValue.uuidString.lowercased(),
            "editToken": editToken,
            "expectedMessageRevision": message.semanticRevision,
            "expectedDraftRevision": try #require(message.draft?.draftRevision),
        ]
        if operationKind == "draft.flush" { removal["body"] = "" }

        // Act
        let outcome = await harness.adapter.apply(
            try canonicalReceiptCommand(removal),
            surface: .file,
            correlation: try makeAnnotationCorrelation(requestID: "canonical-removal-commit"),
            productAdmission: harness.productAdmission
        )

        // Assert — identity is returned by the command, not reconstructed by UI.
        #expect(outcome.status == .committed)
        let encoded = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(outcome)) as? [String: Any])
        let receipt = try #require(encoded["receipt"] as? [String: Any])
        #expect(receipt["kind"] as? String == "message_removed")
        #expect(receipt["messageId"] as? String == message.id.rawValue.uuidString.lowercased())
        #expect(receipt["threadId"] as? String == thread.thread.id.rawValue.uuidString.lowercased())
        #expect(receipt["sessionId"] as? String == sessionID.rawValue.uuidString.lowercased())
        #expect(receipt["removedMessageRevision"] as? Int == message.semanticRevision)
        #expect((receipt["sessionRevision"] as? Int ?? -1) > before.session.semanticRevision)
        if targetKind == "root" {
            #expect(receipt["threadRevision"] is NSNull)
        } else {
            #expect(receipt["threadRevision"] as? Int == thread.thread.semanticRevision)
        }
        #expect(receipt["message"] == nil)
        let wire = try JSONEncoder().encode(outcome)
        #expect(
            try BridgeProductStrictJSON.decode(BridgeProductWorktreeAnnotationCommandOutcomeDTO.self, from: wire)
                == outcome)
        let after = try await persistedDetail(sessionID: sessionID, harness: harness)
        #expect(!after.threads.flatMap(\.messages).contains { $0.id == message.id })
    }
}

private func canonicalReceiptCommand(_ operation: [String: Any]) throws -> BridgeProductWorktreeAnnotationCommandRequest
{
    try BridgeProductStrictJSON.decode(
        BridgeProductWorktreeAnnotationCommandRequest.self,
        from: JSONSerialization.data(withJSONObject: ["operation": operation], options: [.sortedKeys]))
}
