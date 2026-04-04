import Foundation

extension RuntimeEnvelope {
    var source: EventSource {
        switch self {
        case .system(let envelope):
            return .system(envelope.source)
        case .worktree(let envelope):
            return envelope.source
        case .pane(let envelope):
            return envelope.source
        }
    }

    var seq: UInt64 {
        switch self {
        case .system(let envelope):
            return envelope.seq
        case .worktree(let envelope):
            return envelope.seq
        case .pane(let envelope):
            return envelope.seq
        }
    }

    var timestamp: ContinuousClock.Instant {
        switch self {
        case .system(let envelope):
            return envelope.timestamp
        case .worktree(let envelope):
            return envelope.timestamp
        case .pane(let envelope):
            return envelope.timestamp
        }
    }

    var actionPolicy: ActionPolicy {
        switch self {
        case .pane(let envelope):
            return envelope.event.actionPolicy
        case .system, .worktree:
            return .critical
        }
    }

    var commandId: UUID? {
        switch self {
        case .system(let envelope):
            return envelope.commandId
        case .worktree(let envelope):
            return envelope.commandId
        case .pane(let envelope):
            return envelope.commandId
        }
    }

    var correlationId: UUID? {
        switch self {
        case .system(let envelope):
            return envelope.correlationId
        case .worktree(let envelope):
            return envelope.correlationId
        case .pane(let envelope):
            return envelope.correlationId
        }
    }

    var causationId: UUID? {
        switch self {
        case .system(let envelope):
            return envelope.causationId
        case .worktree(let envelope):
            return envelope.causationId
        case .pane(let envelope):
            return envelope.causationId
        }
    }
}
