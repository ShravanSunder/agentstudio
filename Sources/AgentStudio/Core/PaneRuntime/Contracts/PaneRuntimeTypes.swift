import Foundation

typealias PaneId = UUID
typealias WorktreeId = UUID

enum PaneContentType: Hashable, Codable, Sendable {
    case terminal
    case browser
    case diff
    case editor
    case plugin(String)
}

enum PaneCapability: Hashable, Sendable {
    case input
    case resize
    case search
    case navigation
    case diffReview
    case editorActions
    case plugin(String)
}

enum PaneRuntimeLifecycle: Sendable, Equatable {
    case created
    case ready
    case draining
    case terminated
}

enum ActionPolicy: Sendable, Equatable {
    case critical
    case lossy(consolidationKey: String)
}

enum ActionResult: Sendable, Equatable {
    case success(commandId: UUID)
    case queued(commandId: UUID, position: Int)
    case failure(ActionError)
}

enum ActionError: Error, Sendable, Equatable {
    case runtimeNotReady(lifecycle: PaneRuntimeLifecycle)
    case unsupportedCommand(command: String, required: PaneCapability)
    case invalidPayload(description: String)
    case backendUnavailable(backend: String)
    case timeout(commandId: UUID)
}

struct PaneRuntimeSnapshot: Sendable, Equatable {
    let paneId: PaneId
    let metadata: PaneMetadata
    let lifecycle: PaneRuntimeLifecycle
    let capabilities: Set<PaneCapability>
    let lastSeq: UInt64
    let timestamp: Date
}
