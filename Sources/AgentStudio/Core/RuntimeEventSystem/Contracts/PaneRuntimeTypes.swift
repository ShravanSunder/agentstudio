import Foundation

package typealias WorktreeId = UUID

package enum PaneContentType: Hashable, Codable, Sendable {
    case terminal
    case browser
    case diff
    case editor
    case review
    case agent
    case codeViewer
    case plugin(String)
}

package enum PaneCapability: Hashable, Sendable {
    case input
    case resize
    case search
    case navigation
    case diffReview
    case editorActions
    case plugin(String)
}

package enum PaneRuntimeLifecycle: Sendable, Equatable {
    case created
    case ready
    case draining
    case terminated
}

package enum ActionPolicy: Sendable, Equatable {
    case critical
    case lossy(consolidationKey: String)
}

package enum ActionResult: Sendable, Equatable {
    case success(commandId: UUID)
    case queued(commandId: UUID, position: Int)
    case failure(ActionError)
}

package enum ActionError: Error, Sendable, Equatable {
    case runtimeNotReady(lifecycle: PaneRuntimeLifecycle)
    case unsupportedCommand(command: String, required: PaneCapability)
    case invalidPayload(description: String)
    case backendUnavailable(backend: String)
    case timeout(commandId: UUID)
}

package struct PaneRuntimeSnapshot: Sendable, Equatable {
    package let paneId: PaneId
    package let metadata: PaneMetadata
    package let lifecycle: PaneRuntimeLifecycle
    package let capabilities: Set<PaneCapability>
    package let lastSeq: UInt64
    package let timestamp: Date

    package init(
        paneId: PaneId,
        metadata: PaneMetadata,
        lifecycle: PaneRuntimeLifecycle,
        capabilities: Set<PaneCapability>,
        lastSeq: UInt64,
        timestamp: Date
    ) {
        self.paneId = paneId
        self.metadata = metadata
        self.lifecycle = lifecycle
        self.capabilities = capabilities
        self.lastSeq = lastSeq
        self.timestamp = timestamp
    }
}
