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
        case .system(let source): return "system:\(source.rawValue)"
        }
    }
}

enum SystemSource: String, Hashable, Sendable {
    case filesystemWatcher
    case securityBackend
    case coordinator
}
