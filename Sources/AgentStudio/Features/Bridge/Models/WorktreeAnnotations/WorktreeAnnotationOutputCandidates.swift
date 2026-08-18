import Foundation

enum WorktreeAnnotationOutputCandidateLocation: String, Codable, Equatable, Sendable {
    case current
    case original
}

enum WorktreeAnnotationOutputCandidateState: String, Codable, Equatable, Sendable {
    case eligible
}

struct WorktreeAnnotationOutputCandidateCursor: Equatable, Sendable {
    let flatOrdinal: Int
    let messageID: WorktreeAnnotationMessageID
}

struct WorktreeAnnotationOutputCandidate: Equatable, Sendable {
    let messageID: WorktreeAnnotationMessageID
    let threadID: WorktreeAnnotationThreadID
    let flatOrdinal: Int
    let path: String
    let startLine: Int
    let endLine: Int
    let location: WorktreeAnnotationOutputCandidateLocation
    let placement: WorktreeAnnotationPlacement
    let authoredAt: Date
    let state: WorktreeAnnotationOutputCandidateState
    let excerpt: String
}

struct WorktreeAnnotationOutputCandidatePage: Equatable, Sendable {
    let sessionID: WorktreeAnnotationSessionID
    let sessionRevision: Int
    let candidates: [WorktreeAnnotationOutputCandidate]
    let nextCursor: WorktreeAnnotationOutputCandidateCursor?
    let eligibleMessageCount: Int
    let eligibleWithoutInlinePlacementCount: Int
}

struct WorktreeAnnotationRepositoryOutputCandidate: Equatable, Sendable {
    let messageID: WorktreeAnnotationMessageID
    let threadID: WorktreeAnnotationThreadID
    let flatOrdinal: Int
    let originalPath: String
    let originalStartLine: Int
    let originalEndLine: Int
    let authoredAt: Date
    let savedBodyPrefix: String
}

struct WorktreeAnnotationRepositoryOutputCandidatePage: Equatable, Sendable {
    let sessionRevision: Int
    let candidates: [WorktreeAnnotationRepositoryOutputCandidate]
    let nextCursor: WorktreeAnnotationOutputCandidateCursor?
    let eligibleMessageCount: Int
}
