import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation projection attention contract")
struct WorktreeAnnotationProjectionAttentionContractTests {
    @Test("domain projection encodes closed human and agent attention pairs")
    func domainProjectionEncodesClosedAuthorAttentionPairs() throws {
        let human = try projectionEntry(message: messageFixture())
        let unseenAgent = try projectionEntry(message: messageFixture(.init(authorKind: .agent)))
        let viewedAgent = try projectionEntry(
            message: messageFixture(.init(authorKind: .agent, viewedSavedRevision: 3))
        )

        #expect(human.authorKind == .human)
        #expect(human.attentionState == .notApplicable)
        #expect(unseenAgent.authorKind == .agent)
        #expect(unseenAgent.attentionState == .new)
        #expect(viewedAgent.authorKind == .agent)
        #expect(viewedAgent.attentionState == .viewed)
        #expect(try encodedObject(human)["authorKind"] as? String == "human")
        #expect(try encodedObject(human)["attentionState"] as? String == "not_applicable")
        #expect(try encodedObject(unseenAgent)["attentionState"] as? String == "new")
        #expect(try encodedObject(viewedAgent)["attentionState"] as? String == "viewed")
    }

    @Test("strict decode rejects missing unknown and invalid author attention combinations")
    func strictDecodeRejectsInvalidAuthorAttentionCombinations() throws {
        let humanObject = try encodedObject(projectionEntry(message: messageFixture()))
        let agentObject = try encodedObject(
            projectionEntry(message: messageFixture(.init(authorKind: .agent)))
        )
        var missingAttention = humanObject
        missingAttention.removeValue(forKey: "attentionState")

        for rejectedObject in [
            missingAttention,
            replacing(humanObject, key: "attentionState", value: "new"),
            replacing(humanObject, key: "authorKind", value: "robot"),
            replacing(agentObject, key: "attentionState", value: "not_applicable"),
            replacing(agentObject, key: "attentionState", value: "unread"),
            replacing(agentObject, key: "handled", value: true),
            replacing(
                agentObject, key: "draft",
                value: [
                    "activeEditToken": NSNull(),
                    "body": "Agent draft",
                    "revision": 1,
                ]),
            replacing(agentObject, key: "savedBody", value: NSNull()),
            replacing(humanObject, key: "unexpectedAttention", value: true),
        ] {
            #expect(throws: (any Error).self) {
                _ = try decodeProjectionEntry(rejectedObject)
            }
        }
    }
}

private struct ProjectionMessageFixtureProps {
    let authorKind: WorktreeAnnotationAuthorKind
    let viewedSavedRevision: Int?

    init(
        authorKind: WorktreeAnnotationAuthorKind = .human,
        viewedSavedRevision: Int? = nil
    ) {
        self.authorKind = authorKind
        self.viewedSavedRevision = viewedSavedRevision
    }
}

private func messageFixture(
    _ props: ProjectionMessageFixtureProps = .init()
) -> WorktreeAnnotationMessage {
    .init(
        id: .generate(),
        threadID: .generate(),
        ordinal: 0,
        semanticRevision: 1,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        savedBody: "Saved annotation",
        savedRevision: 3,
        draft: nil,
        handled: false,
        status: .editable,
        authorKind: props.authorKind,
        viewedSavedRevision: props.viewedSavedRevision
    )
}

private func projectionEntry(
    message: WorktreeAnnotationMessage
) throws -> BridgeProductWorktreeAnnotationMessageEntry {
    let session = WorktreeAnnotationSession(
        id: .generate(),
        repositoryID: "repository",
        worktreeID: "worktree",
        originatingWorkspaceID: nil,
        lifecycle: .living,
        sourceRelationship: .applicable,
        acceptedSourceFingerprint: .init(
            repositoryID: "repository",
            worktreeID: "worktree",
            fileSourceIdentity: "source",
            reviewComparisonOrigin: nil
        ),
        semanticRevision: 2,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        completedAt: nil
    )
    let thread = WorktreeAnnotationThread(
        id: message.threadID,
        sessionID: session.id,
        origin: .session,
        resolution: .open,
        createdOrdinal: 0,
        semanticRevision: 2,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        resolvedAt: nil
    )
    return try .init(message: message, session: session, thread: thread)
}

private func encodedObject(
    _ entry: BridgeProductWorktreeAnnotationMessageEntry
) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
}

private func decodeProjectionEntry(
    _ object: [String: Any]
) throws -> BridgeProductWorktreeAnnotationMessageEntry {
    try BridgeProductStrictJSON.decode(
        BridgeProductWorktreeAnnotationMessageEntry.self,
        from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    )
}

private func replacing(
    _ object: [String: Any],
    key: String,
    value: Any
) -> [String: Any] {
    var replaced = object
    replaced[key] = value
    return replaced
}
