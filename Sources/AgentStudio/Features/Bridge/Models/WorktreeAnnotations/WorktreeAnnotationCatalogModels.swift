struct WorktreeAnnotationCatalogSessionRow: Equatable, Sendable {
    let sessionID: WorktreeAnnotationSessionID
    let semanticRevision: Int
}

struct WorktreeAnnotationCatalogThreadRow: Equatable, Sendable {
    let threadID: WorktreeAnnotationThreadID
    let sessionID: WorktreeAnnotationSessionID
    let scope: WorktreeAnnotationThreadScope
    let createdOrdinal: Int
}

struct WorktreeAnnotationCatalogMessageRow: Equatable, Sendable {
    let messageID: WorktreeAnnotationMessageID
    let threadID: WorktreeAnnotationThreadID
    let ordinal: Int
}

struct WorktreeAnnotationCatalogCapture: Equatable, Sendable {
    let worktreeID: String
    let sessions: [WorktreeAnnotationCatalogSessionRow]
    let threads: [WorktreeAnnotationCatalogThreadRow]
    let messages: [WorktreeAnnotationCatalogMessageRow]
}
