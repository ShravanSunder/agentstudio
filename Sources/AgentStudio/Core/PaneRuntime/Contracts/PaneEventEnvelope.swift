import Foundation

struct PaneEventEnvelope: Sendable {
    let source: EventSource
    let paneKind: PaneContentType?
    let seq: UInt64
    let commandId: UUID?
    let correlationId: UUID?
    let timestamp: ContinuousClock.Instant
    let epoch: UInt64
    let event: PaneRuntimeEvent
}

enum EventSource: Hashable, Sendable, CustomStringConvertible {
    case pane(PaneId)
    case worktree(WorktreeId)
    case system(SystemSource)

    var description: String {
        switch self {
        case .pane(let paneId): return "pane:\(paneId.uuidString)"
        case .worktree(let worktreeId): return "worktree:\(worktreeId.uuidString)"
        case .system(let source): return "system:\(source.description)"
        }
    }
}

enum SystemSource: Hashable, Sendable, CustomStringConvertible {
    case filesystemWatcher
    case securityBackend
    case coordinator
    case gitForge
    case containerService
    case plugin(String)

    var description: String {
        switch self {
        case .filesystemWatcher:
            return "filesystemWatcher"
        case .securityBackend:
            return "securityBackend"
        case .coordinator:
            return "coordinator"
        case .gitForge:
            return "gitForge"
        case .containerService:
            return "containerService"
        case .plugin(let kind):
            return "plugin:\(kind)"
        }
    }
}
