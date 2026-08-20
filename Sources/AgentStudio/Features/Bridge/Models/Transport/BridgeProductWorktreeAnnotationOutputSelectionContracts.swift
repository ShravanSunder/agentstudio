import Foundation

extension BridgeProductWorktreeAnnotationOperation {
    enum OutputKind: String, Codable, Equatable, Sendable {
        case clipboardMarkdown
        case jsonFile
    }

    enum OutputScope: String, Codable, Equatable, Sendable {
        case new
        case all
    }

    struct OutputScopeCommitBody: Codable, Equatable, Sendable {
        let displayedProjectionRevision: Int
        let expectedSessionRevision: Int
        let outputKind: OutputKind
        let scope: OutputScope
        let sessionId: UUID
        let sourceGeneration: Int
    }

    struct OutputHandledClearBody: Codable, Equatable, Sendable {
        let attemptId: UUID
        let expectedSessionRevision: Int
    }
}
