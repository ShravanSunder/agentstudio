import Foundation

enum RuntimeEnvelope: Sendable {
    case system(SystemEnvelope)
    case worktree(WorktreeEnvelope)
    case pane(PaneEnvelope)
}

enum RuntimeEnvelopeSchema {
    static let current: UInt16 = 1
}

enum SystemScopedEvent: Sendable {
    case topology(TopologyEvent)
    case appLifecycle(AppLifecycleEvent)
    case focusChanged(FocusChangeEvent)
    case configChanged(ConfigChangeEvent)
}

enum TopologyEvent: Sendable {
    case repoDiscovered(repoPath: URL, parentPath: URL)
    case repoRemoved(repoPath: URL)
    case worktreeRegistered(worktreeId: UUID, repoId: UUID, rootPath: URL)
    case worktreeUnregistered(worktreeId: UUID, repoId: UUID)
}

enum AppLifecycleEvent: Sendable {
    case appLaunched
    case appTerminating
    case tabSwitched(activeTabId: UUID)
}

enum FocusChangeEvent: Sendable {
    case activePaneChanged(paneId: PaneId?)
    case activeWorktreeChanged(worktreeId: UUID?)
}

enum ConfigChangeEvent: Sendable {
    case watchedPathsUpdated(paths: [URL])
    case workspacePersistenceUpdated
}

enum WorktreeScopedEvent: Sendable {
    case filesystem(FilesystemEvent)
    case gitWorkingDirectory(GitWorkingDirectoryEvent)
    case forge(ForgeEvent)
    case security(SecurityEvent)
}

enum GitWorkingDirectoryEvent: Sendable {
    case snapshotChanged(snapshot: GitWorkingTreeSnapshot)
    case branchChanged(worktreeId: UUID, repoId: UUID, from: String, to: String)
    case originChanged(repoId: UUID, from: String, to: String)
    case worktreeDiscovered(repoId: UUID, worktreePath: URL, branch: String, isMain: Bool)
    case worktreeRemoved(repoId: UUID, worktreePath: URL)
    case diffAvailable(diffId: UUID, worktreeId: UUID, repoId: UUID)
}

enum ForgeEvent: Sendable {
    case pullRequestCountsChanged(repoId: UUID, countsByBranch: [String: Int])
    case checksUpdated(repoId: UUID, status: ForgeChecksStatus)
    case refreshFailed(repoId: UUID, error: String)
    case rateLimited(repoId: UUID, retryAfterSeconds: Int)
}

enum ForgeChecksStatus: String, Sendable {
    case passing
    case failing
    case pending
    case unknown
}

struct SystemEnvelope: Sendable {
    let eventId: UUID
    let source: SystemSource
    let seq: UInt64
    let timestamp: ContinuousClock.Instant
    let schemaVersion: UInt16
    let correlationId: UUID?
    let causationId: UUID?
    let commandId: UUID?
    let event: SystemScopedEvent

    init(
        eventId: UUID = UUID(),
        source: SystemSource,
        seq: UInt64,
        timestamp: ContinuousClock.Instant,
        schemaVersion: UInt16 = RuntimeEnvelopeSchema.current,
        correlationId: UUID? = nil,
        causationId: UUID? = nil,
        commandId: UUID? = nil,
        event: SystemScopedEvent
    ) {
        self.eventId = eventId
        self.source = source
        self.seq = seq
        self.timestamp = timestamp
        self.schemaVersion = schemaVersion
        self.correlationId = correlationId
        self.causationId = causationId
        self.commandId = commandId
        self.event = event
    }
}

struct WorktreeEnvelope: Sendable {
    let eventId: UUID
    let source: EventSource
    let seq: UInt64
    let timestamp: ContinuousClock.Instant
    let schemaVersion: UInt16
    let correlationId: UUID?
    let causationId: UUID?
    let commandId: UUID?
    let repoId: UUID
    let worktreeId: UUID?
    let event: WorktreeScopedEvent

    init(
        eventId: UUID = UUID(),
        source: EventSource,
        seq: UInt64,
        timestamp: ContinuousClock.Instant,
        schemaVersion: UInt16 = RuntimeEnvelopeSchema.current,
        correlationId: UUID? = nil,
        causationId: UUID? = nil,
        commandId: UUID? = nil,
        repoId: UUID,
        worktreeId: UUID? = nil,
        event: WorktreeScopedEvent
    ) {
        self.eventId = eventId
        self.source = source
        self.seq = seq
        self.timestamp = timestamp
        self.schemaVersion = schemaVersion
        self.correlationId = correlationId
        self.causationId = causationId
        self.commandId = commandId
        self.repoId = repoId
        self.worktreeId = worktreeId
        self.event = event
    }
}

struct PaneEnvelope: Sendable {
    let eventId: UUID
    let source: EventSource
    let seq: UInt64
    let timestamp: ContinuousClock.Instant
    let schemaVersion: UInt16
    let correlationId: UUID?
    let causationId: UUID?
    let commandId: UUID?
    let paneId: PaneId
    let paneKind: PaneContentType
    let event: PaneRuntimeEvent

    init(
        eventId: UUID = UUID(),
        source: EventSource,
        seq: UInt64,
        timestamp: ContinuousClock.Instant,
        schemaVersion: UInt16 = RuntimeEnvelopeSchema.current,
        correlationId: UUID? = nil,
        causationId: UUID? = nil,
        commandId: UUID? = nil,
        paneId: PaneId,
        paneKind: PaneContentType,
        event: PaneRuntimeEvent
    ) {
        self.eventId = eventId
        self.source = source
        self.seq = seq
        self.timestamp = timestamp
        self.schemaVersion = schemaVersion
        self.correlationId = correlationId
        self.causationId = causationId
        self.commandId = commandId
        self.paneId = paneId
        self.paneKind = paneKind
        self.event = event
    }
}
