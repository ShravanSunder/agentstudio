import Foundation

enum PaneRuntimeEvent: Sendable {
    case lifecycle(PaneLifecycleEvent)
    case terminal(GhosttyEvent)
    case browser(BrowserEvent)
    case diff(DiffEvent)
    case editor(EditorEvent)
    case plugin(kind: PaneContentType, event: any PaneKindEvent)
    case filesystem(FilesystemEvent)
    case artifact(ArtifactEvent)
    case security(SecurityEvent)
    case error(RuntimeErrorEvent)
}

extension PaneRuntimeEvent {
    var actionPolicy: ActionPolicy {
        switch self {
        case .terminal(let event): return event.actionPolicy
        case .browser(let event): return event.actionPolicy
        case .diff(let event): return event.actionPolicy
        case .editor(let event): return event.actionPolicy
        case .plugin(_, let event): return event.actionPolicy
        case .lifecycle, .filesystem, .artifact, .security, .error:
            return .critical
        }
    }
}

enum PaneLifecycleEvent: Sendable {
    case surfaceCreated
    case sizeObserved(cols: Int, rows: Int)
    case sizeStabilized
    case attachStarted
    case attachSucceeded
    case attachFailed(error: AttachError)
    case paneClosed
    case activePaneChanged
    case drawerExpanded
    case drawerCollapsed
    case tabSwitched(activeTabId: UUID)
}

enum AttachError: Error, Sendable, Equatable {
    case surfaceNotFound
    case surfaceAlreadyAttached
    case backendUnavailable(reason: String)
    case timeout
}

enum FilesystemEvent: Sendable {
    case filesChanged(changeset: FileChangeset)
    case gitStatusChanged(summary: GitStatusSummary)
    case diffAvailable(diffId: UUID)
    case branchChanged(from: String, to: String)
}

struct FileChangeset: Sendable {
    let worktreeId: WorktreeId
    let paths: Set<String>
    let timestamp: ContinuousClock.Instant
    let batchSeq: UInt64
}

struct GitStatusSummary: Sendable {
    let changed: Int
    let staged: Int
    let untracked: Int
}

enum ArtifactEvent: Sendable {
    case diffProduced(worktreeId: UUID, artifact: DiffArtifact)
    case approvalRequested(request: ApprovalRequest)
    case approvalDecided(decision: ApprovalDecision)
}

struct DiffArtifact: Sendable {
    let diffId: UUID
    let worktreeId: UUID
    let patchData: Data
}

struct ApprovalRequest: Sendable {
    let id: UUID
    let summary: String
}

struct ApprovalDecision: Sendable {
    let requestId: UUID
    let approved: Bool
}

enum SecurityEvent: Sendable {
    case networkEgressBlocked(destination: String, rule: String)
    case filesystemAccessDenied(path: String, operation: String)
    case secretAccessed(secretId: String, consumerId: String)
    case processSpawnBlocked(command: String, rule: String)
    case sandboxStarted(backend: ExecutionBackend, policy: String)
    case sandboxStopped(reason: String)
    case sandboxHealthChanged(healthy: Bool)
}

enum ExecutionBackend: Sendable, Equatable, Hashable, Codable {
    case local
    case docker(image: String)
    case gondolin(policyId: String)
    case remote(host: String)
}

enum RuntimeErrorEvent: Error, Sendable {
    case surfaceCrashed(reason: String)
    case commandTimeout(commandId: UUID)
    case commandDispatchFailed(command: String, underlyingDescription: String)
    case adapterError(String)
    case resourceExhausted(resource: String)
    case internalStateCorrupted
}

enum GhosttyEvent: PaneKindEvent, Sendable {
    case titleChanged(String)
    case cwdChanged(String)
    case commandFinished(exitCode: Int, duration: UInt64)
    case bellRang
    case scrollbarChanged(ScrollbarState)
    case unhandled(tag: UInt32)

    var actionPolicy: ActionPolicy {
        switch self {
        case .scrollbarChanged:
            return .lossy(consolidationKey: "scroll")
        case .titleChanged, .cwdChanged, .commandFinished, .bellRang, .unhandled:
            return .critical
        }
    }

    var eventName: EventIdentifier {
        switch self {
        case .titleChanged: return .titleChanged
        case .cwdChanged: return .cwdChanged
        case .commandFinished: return .commandFinished
        case .bellRang: return .bellRang
        case .scrollbarChanged: return .scrollbarChanged
        case .unhandled: return .unhandled
        }
    }
}

struct ScrollbarState: Sendable, Equatable {
    let top: Int
    let bottom: Int
    let total: Int
}

enum BrowserEvent: PaneKindEvent, Sendable {
    case navigationCompleted(url: URL, statusCode: Int?)
    case pageLoaded(url: URL)
    case consoleMessage(level: ConsoleLevel, message: String)

    var actionPolicy: ActionPolicy {
        switch self {
        case .consoleMessage:
            return .lossy(consolidationKey: "console")
        case .navigationCompleted, .pageLoaded:
            return .critical
        }
    }

    var eventName: EventIdentifier {
        switch self {
        case .navigationCompleted: return .navigationCompleted
        case .pageLoaded: return .pageLoaded
        case .consoleMessage: return .consoleMessage
        }
    }
}

enum ConsoleLevel: String, Sendable {
    case log
    case warn
    case error
    case debug
    case info
}

enum DiffEvent: PaneKindEvent, Sendable {
    case diffLoaded(stats: DiffStats)
    case hunkApproved(hunkId: String)
    case allApproved

    var actionPolicy: ActionPolicy {
        switch self {
        case .diffLoaded:
            return .critical
        case .hunkApproved, .allApproved:
            return .critical
        }
    }

    var eventName: EventIdentifier {
        switch self {
        case .diffLoaded: return .diffLoaded
        case .hunkApproved: return .hunkApproved
        case .allApproved: return .allApproved
        }
    }
}

struct DiffStats: Sendable, Equatable {
    let filesChanged: Int
    let insertions: Int
    let deletions: Int
}

enum EditorEvent: PaneKindEvent, Sendable {
    case contentSaved(path: String)
    case fileOpened(path: String, language: String?)
    case diagnosticsUpdated(path: String, errors: Int, warnings: Int)

    var actionPolicy: ActionPolicy {
        switch self {
        case .contentSaved, .fileOpened:
            return .critical
        case .diagnosticsUpdated:
            return .lossy(consolidationKey: "diagnostics")
        }
    }

    var eventName: EventIdentifier {
        switch self {
        case .contentSaved: return .contentSaved
        case .fileOpened: return .fileOpened
        case .diagnosticsUpdated: return .diagnosticsUpdated
        }
    }
}
