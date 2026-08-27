import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation metadata event contracts")
struct WorktreeAnnotationMetadataEventContractTests {
    @Test("catalog session and control events round trip through the strict wire contract")
    func eventVariantsRoundTrip() throws {
        // Arrange
        let authority = try BridgeProductWorktreeAnnotationEvent.Authority(
            worktreeID: "worktree-1",
            applicationSourceGeneration: 7
        )
        let sessionID = WorktreeAnnotationSessionID(rawValue: UUIDv7.generate())
        let threadID = WorktreeAnnotationThreadID(rawValue: UUIDv7.generate())
        let messageID = WorktreeAnnotationMessageID(rawValue: UUIDv7.generate())
        let transferID = UUIDv7.generate().uuidString.lowercased()
        let events: [BridgeProductWorktreeAnnotationEvent] = [
            .catalog(
                try .init(
                    authority: authority,
                    transfer: .window(
                        transferID: transferID,
                        catalogRevision: 7,
                        windowOrdinal: 0,
                        entries: [
                            .session(try .init(sessionID: sessionID, semanticRevision: 0)),
                            .thread(
                                try .init(
                                    threadID: threadID,
                                    sessionID: sessionID,
                                    scope: .wholeFile,
                                    createdOrdinal: 0
                                )
                            ),
                            .message(
                                try .init(messageID: messageID, threadID: threadID, ordinal: 0)
                            ),
                        ]
                    )
                )
            ),
            .sessionChanged(
                try .init(authority: authority, sessionID: sessionID, semanticRevision: 3)
            ),
            .controlChanged(.init(authority: authority, reason: .recovery)),
        ]

        // Act / Assert
        for event in events {
            let encoded = try JSONEncoder.bridgeProductSorted.encode(event)
            #expect(
                try decodeAnnotationMetadataEvent(from: encoded) == event
            )
            #expect(event.sourceGeneration == 7)
        }
    }

    @Test("event entry and authority unions reject unknown or mismatched schema")
    func strictSchemasRejectUnknownAndMismatchedMembers() throws {
        // Arrange
        let sessionID = UUIDv7.generate().uuidString.lowercased()
        let threadID = UUIDv7.generate().uuidString.lowercased()
        let transferID = UUIDv7.generate().uuidString.lowercased()
        let invalidBodies = [
            """
            {"authority":{"applicationSourceGeneration":7,"worktreeId":"worktree-1"},"kind":"annotation.unknown","reason":"recovery"}
            """,
            """
            {"authority":{"applicationSourceGeneration":7,"unknown":true,"worktreeId":"worktree-1"},"kind":"annotation.controlChanged","reason":"recovery"}
            """,
            """
            {"authority":{"applicationSourceGeneration":7,"worktreeId":"worktree-1"},"kind":"annotation.controlChanged","reason":"unsupported"}
            """,
            """
            {"authority":{"applicationSourceGeneration":7,"worktreeId":"worktree-1"},"kind":"annotation.sessionChanged","semanticRevision":3,"sessionId":"\(sessionID)","unknown":true}
            """,
            """
            {"authority":{"applicationSourceGeneration":7,"worktreeId":"worktree-1"},"kind":"annotation.catalog","transfer":{"catalogRevision":7,"entries":[{"createdOrdinal":0,"kind":"thread","scope":"located","sessionId":"\(sessionID)","threadId":"\(threadID)","unknown":true}],"kind":"catalog.window","transferId":"\(transferID)","windowOrdinal":0}}
            """,
            """
            {"authority":{"applicationSourceGeneration":7,"worktreeId":"worktree-1"},"kind":"annotation.catalog","transfer":{"catalogRevision":7,"entries":[{"createdOrdinal":0,"kind":"thread","scope":"unsupported","sessionId":"\(sessionID)","threadId":"\(threadID)"}],"kind":"catalog.window","transferId":"\(transferID)","windowOrdinal":0}}
            """,
            """
            {"authority":{"applicationSourceGeneration":7,"worktreeId":"worktree-1"},"kind":"annotation.catalog","transfer":{"catalogRevision":8,"expectedEntryCount":0,"kind":"catalog.begin","transferId":"\(transferID)"}}
            """,
        ]

        // Act / Assert
        for body in invalidBodies {
            #expect(throws: (any Error).self) {
                _ = try decodeAnnotationMetadataEvent(from: Data(body.utf8))
            }
        }
    }

    @Test("event numeric and identity fields enforce application wire ranges")
    func numericAndIdentityFieldsEnforceWireRanges() throws {
        // Arrange
        let sessionID = UUIDv7.generate().uuidString.lowercased()
        let threadID = UUIDv7.generate().uuidString.lowercased()
        let messageID = UUIDv7.generate().uuidString.lowercased()
        let transferID = UUIDv7.generate().uuidString.lowercased()
        let excessiveInteger = BridgeProductWireContract.maximumSafeInteger + 1
        let invalidBodies = [
            """
            {"authority":{"applicationSourceGeneration":-1,"worktreeId":"worktree-1"},"kind":"annotation.controlChanged","reason":"discovery"}
            """,
            """
            {"authority":{"applicationSourceGeneration":\(excessiveInteger),"worktreeId":"worktree-1"},"kind":"annotation.controlChanged","reason":"discovery"}
            """,
            """
            {"authority":{"applicationSourceGeneration":1,"worktreeId":""},"kind":"annotation.controlChanged","reason":"discovery"}
            """,
            """
            {"authority":{"applicationSourceGeneration":1,"worktreeId":"worktree-1"},"kind":"annotation.sessionChanged","semanticRevision":0,"sessionId":"\(sessionID)"}
            """,
            """
            {"authority":{"applicationSourceGeneration":1,"worktreeId":"worktree-1"},"kind":"annotation.sessionChanged","semanticRevision":\(excessiveInteger),"sessionId":"\(sessionID)"}
            """,
            """
            {"authority":{"applicationSourceGeneration":1,"worktreeId":"worktree-1"},"kind":"annotation.catalog","transfer":{"catalogRevision":1,"entries":[{"kind":"session","semanticRevision":-1,"sessionId":"\(sessionID)"}],"kind":"catalog.window","transferId":"\(transferID)","windowOrdinal":0}}
            """,
            """
            {"authority":{"applicationSourceGeneration":1,"worktreeId":"worktree-1"},"kind":"annotation.catalog","transfer":{"catalogRevision":1,"entries":[{"createdOrdinal":-1,"kind":"thread","scope":"located","sessionId":"\(sessionID)","threadId":"\(threadID)"}],"kind":"catalog.window","transferId":"\(transferID)","windowOrdinal":0}}
            """,
            """
            {"authority":{"applicationSourceGeneration":1,"worktreeId":"worktree-1"},"kind":"annotation.catalog","transfer":{"catalogRevision":1,"entries":[{"kind":"message","messageId":"\(messageID)","ordinal":-1,"threadId":"\(threadID)"}],"kind":"catalog.window","transferId":"\(transferID)","windowOrdinal":0}}
            """,
            """
            {"authority":{"applicationSourceGeneration":1,"worktreeId":"worktree-1"},"kind":"annotation.catalog","transfer":{"catalogRevision":1,"entries":[{"kind":"session","semanticRevision":\(excessiveInteger),"sessionId":"\(sessionID)"}],"kind":"catalog.window","transferId":"\(transferID)","windowOrdinal":0}}
            """,
            """
            {"authority":{"applicationSourceGeneration":1,"worktreeId":"worktree-1"},"kind":"annotation.catalog","transfer":{"catalogRevision":1,"entries":[{"createdOrdinal":\(excessiveInteger),"kind":"thread","scope":"located","sessionId":"\(sessionID)","threadId":"\(threadID)"}],"kind":"catalog.window","transferId":"\(transferID)","windowOrdinal":0}}
            """,
            """
            {"authority":{"applicationSourceGeneration":1,"worktreeId":"worktree-1"},"kind":"annotation.catalog","transfer":{"catalogRevision":1,"entries":[{"kind":"message","messageId":"\(messageID)","ordinal":\(excessiveInteger),"threadId":"\(threadID)"}],"kind":"catalog.window","transferId":"\(transferID)","windowOrdinal":0}}
            """,
        ]

        // Act / Assert
        for body in invalidBodies {
            #expect(throws: (any Error).self) {
                _ = try decodeAnnotationMetadataEvent(from: Data(body.utf8))
            }
        }
    }

    @Test("registered annotation event generation must match the generic frame")
    func registryRejectsGenerationMismatch() throws {
        // Arrange
        let registration = AnyBridgeProductMetadataApplicationProtocol(
            BridgeProductFileAnnotationsMetadataApplication.self
        )
        let event = BridgeProductWorktreeAnnotationEvent.controlChanged(
            .init(
                authority: try .init(
                    worktreeID: "worktree-1",
                    applicationSourceGeneration: 7
                ),
                reason: .discovery
            )
        )
        let encoded = try JSONEncoder.bridgeProductSorted.encode(event)

        // Act / Assert
        #expect(try registration.validateEvent(encoded, frameSourceGeneration: 7) == encoded)
        #expect(throws: BridgeProductMetadataApplicationRegistryError.sourceGenerationMismatch) {
            _ = try registration.validateEvent(encoded, frameSourceGeneration: 8)
        }
    }
}

private func decodeAnnotationMetadataEvent(
    from data: Data
) throws -> BridgeProductWorktreeAnnotationEvent {
    try BridgeProductStrictJSON.validate(data)
    return try JSONDecoder().decode(BridgeProductWorktreeAnnotationEvent.self, from: data)
}
