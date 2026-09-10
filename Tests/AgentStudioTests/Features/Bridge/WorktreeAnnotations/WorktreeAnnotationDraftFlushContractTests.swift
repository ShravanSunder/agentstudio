import Foundation
import Testing

@testable import AgentStudioBridge

struct WorktreeAnnotationDraftFlushContractTests {
    @Test(
        "draft flush admits bounded empty bodies without changing their bytes",
        arguments: ["", " \n\t", String(repeating: " ", count: 16 * 1024)])
    func draftFlushAdmitsEmptyBodies(body: String) throws {
        // Arrange
        let operation = flushOperation(body: body)

        // Act
        let decoded = try decodeOperation(operation)

        // Assert
        guard case .flushDraft(let mutation) = decoded else {
            Issue.record("Expected a draft flush")
            return
        }
        #expect(mutation.body == body)
    }

    @Test(
        "draft flush retains body size and Markdown restrictions",
        arguments: [String(repeating: " ", count: 16 * 1024 + 1), "# Heading", "<script>alert(1)</script>"])
    func draftFlushRejectsInvalidBodies(body: String) throws {
        // Arrange
        let operation = flushOperation(body: body)

        // Act / Assert
        #expect(throws: (any Error).self) {
            _ = try decodeOperation(operation)
        }
    }

    @Test("creating a reply still rejects empty bodies", arguments: ["", " \n\t"])
    func replyCreationRejectsEmptyBodies(body: String) throws {
        // Arrange
        let operation: [String: Any] = [
            "kind": "reply.create", "body": body, "editToken": "editor",
            "sessionId": "00000000-0000-7000-8000-000000000011",
            "threadId": "00000000-0000-7000-8000-000000000012",
            "expectedThreadRevision": 1,
        ]

        // Act / Assert
        #expect(throws: (any Error).self) {
            _ = try decodeOperation(operation)
        }
    }

    private func flushOperation(body: String) -> [String: Any] {
        [
            "kind": "draft.flush", "body": body, "editToken": "editor",
            "sessionId": "00000000-0000-7000-8000-000000000011",
            "messageId": "00000000-0000-7000-8000-000000000013",
            "expectedMessageRevision": 1, "expectedDraftRevision": 0,
        ]
    }

    private func decodeOperation(_ operation: [String: Any]) throws -> BridgeProductWorktreeAnnotationOperation {
        try BridgeProductStrictJSON.decode(
            BridgeProductWorktreeAnnotationOperation.self,
            from: JSONSerialization.data(withJSONObject: operation, options: [.sortedKeys]))
    }
}
