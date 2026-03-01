import Foundation

/// Event routing source identity.
///
/// `.pane` is per-pane routing, `.worktree` is cross-pane worktree routing,
/// and `.system` is process-level system routing.
enum EventSource: Hashable, Sendable, CustomStringConvertible {
    case pane(PaneId)
    case worktree(WorktreeId)
    case system(SystemSource)

    var description: String {
        switch self {
        case .pane(let paneId):
            return "pane:\(paneId.uuidString)"
        case .worktree(let worktreeId):
            return "worktree:\(worktreeId.uuidString)"
        case .system(let source):
            return "system:\(source.description)"
        }
    }
}

/// Three-tier system source hierarchy.
///
/// Description format uses `/` as tier separator to avoid collision with
/// provider names or plugin kinds that may contain `:`.
/// Format: `tier/source` or `tier/source/param`.
enum SystemSource: Hashable, Sendable, CustomStringConvertible {
    case builtin(BuiltinSource)
    case service(ServiceSource)
    case plugin(String)

    var description: String {
        switch self {
        case .builtin(let source):
            return "builtin/\(source.description)"
        case .service(let source):
            return "service/\(source.description)"
        case .plugin(let kind):
            return "plugin/\(kind)"
        }
    }
}

/// Core-implemented system sources.
enum BuiltinSource: Hashable, Sendable, CustomStringConvertible {
    case filesystemWatcher
    case gitWorkingDirectoryProjector
    case securityBackend
    case coordinator

    var description: String {
        switch self {
        case .filesystemWatcher:
            return "filesystemWatcher"
        case .gitWorkingDirectoryProjector:
            return "gitWorkingDirectoryProjector"
        case .securityBackend:
            return "securityBackend"
        case .coordinator:
            return "coordinator"
        }
    }
}

/// Typed service categories with provider names.
enum ServiceSource: Hashable, Sendable, CustomStringConvertible {
    case gitForge(provider: String)
    case containerService(provider: String)

    var description: String {
        switch self {
        case .gitForge(let provider):
            return "gitForge/\(provider)"
        case .containerService(let provider):
            return "containerService/\(provider)"
        }
    }
}
