import Foundation

/// Transport envelope for all runtime events.
///
/// Routing identity is carried in `source`; domain payload is carried in `event`.
/// Ordering, idempotency, and replay are handled by `(seq, epoch, timestamp)`.
struct PaneEventEnvelope: Sendable {
    let source: EventSource
    let sourceFacets: PaneContextFacets
    let paneKind: PaneContentType?
    let seq: UInt64
    let commandId: UUID?
    let correlationId: UUID?
    let timestamp: ContinuousClock.Instant
    let epoch: UInt64
    let event: PaneRuntimeEvent

    init(
        source: EventSource,
        sourceFacets: PaneContextFacets = .empty,
        paneKind: PaneContentType?,
        seq: UInt64,
        commandId: UUID?,
        correlationId: UUID?,
        timestamp: ContinuousClock.Instant,
        epoch: UInt64,
        event: PaneRuntimeEvent
    ) {
        self.source = source
        self.sourceFacets = sourceFacets
        self.paneKind = paneKind
        self.seq = seq
        self.commandId = commandId
        self.correlationId = correlationId
        self.timestamp = timestamp
        self.epoch = epoch
        self.event = event
    }
}

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
        case .pane(let paneId): return "pane:\(paneId.uuidString)"
        case .worktree(let worktreeId): return "worktree:\(worktreeId.uuidString)"
        case .system(let source): return "system:\(source.description)"
        }
    }
}

/// Three-tier system source hierarchy (see D9 in pane_runtime_architecture.md).
///
/// Description format uses `/` as tier separator to avoid collision with
/// provider names or plugin kinds that may contain `:`.
/// Format: "tier/source" or "tier/source/param" — unambiguous parse at first `/`.
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

/// Core-implemented system sources. Closed set.
enum BuiltinSource: Hashable, Sendable, CustomStringConvertible {
    case filesystemWatcher
    case securityBackend
    case coordinator

    var description: String {
        switch self {
        case .filesystemWatcher: return "filesystemWatcher"
        case .securityBackend: return "securityBackend"
        case .coordinator: return "coordinator"
        }
    }
}

/// Typed service categories with plugin-provided backends.
/// Description uses `/` separator between category and provider
/// for unambiguous consolidation keys.
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
