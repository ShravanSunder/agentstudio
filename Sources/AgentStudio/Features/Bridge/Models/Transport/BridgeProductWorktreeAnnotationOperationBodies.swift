import Foundation

extension BridgeProductWorktreeAnnotationOperation {
    struct MutationBody: Codable, Equatable, Sendable {
        let body: String
        let editToken: String
        let expectedThreadRevision: Int
        let sessionId: UUID
        let threadId: UUID
    }

    struct DraftMutationBody: Codable, Equatable, Sendable {
        let body: String
        let editToken: String
        let expectedDraftRevision: Int?
        let expectedMessageRevision: Int
        let messageId: UUID
        let sessionId: UUID
    }

    struct DraftRevisionBody: Codable, Equatable, Sendable {
        let editToken: String
        let expectedDraftRevision: Int
        let expectedMessageRevision: Int
        let messageId: UUID
        let sessionId: UUID
    }

    struct ThreadResolutionBody: Codable, Equatable, Sendable {
        let expectedThreadRevision: Int
        let resolution: WorktreeAnnotationThreadResolution
        let sessionId: UUID
        let threadId: UUID
    }

    struct SessionLifecycleBody: Codable, Equatable, Sendable {
        let confirmsUnresolvedWork: Bool
        let expectedOpenThreadCount: Int
        let expectedSessionRevision: Int
        let lifecycle: WorktreeAnnotationSessionLifecycle
        let sessionId: UUID
    }

    enum ContinuityDecision: String, Codable, Equatable, Sendable {
        case acceptCurrentSource
        case keepDetached
    }

    struct ContinuityBody: Codable, Equatable, Sendable {
        let decision: ContinuityDecision
        let expectedSessionRevision: Int
        let sessionId: UUID
    }

    struct SourceRefreshBody: Codable, Equatable, Sendable {
        let sessionId: UUID
        let sourceEpoch: Int
    }
}
