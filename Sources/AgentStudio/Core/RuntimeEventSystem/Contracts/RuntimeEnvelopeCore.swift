import Foundation

package enum RuntimeEnvelope: Sendable {
    case system(SystemEnvelope)
    case worktree(WorktreeEnvelope)
    case pane(PaneEnvelope)
}

enum RuntimeEnvelopeSchema {
    static let current: UInt16 = 1
}

package enum SystemScopedEvent: Sendable {
    case topology(TopologyEvent)
    case appLifecycle(AppLifecycleEvent)
    case focusChanged(FocusChangeEvent)
    case configChanged(ConfigChangeEvent)
    case workspaceActivity(WorkspaceActivityEvent)
}

package enum LinkedWorktreeInfo: Sendable, Equatable {
    case scanned([URL])
    case notScanned
}

package struct DiscoveredRepoTopologyInfo: Sendable, Equatable {
    package let repoPath: URL
    package let linkedWorktrees: LinkedWorktreeInfo
}

package enum TopologyEvent: Sendable {
    case repoDiscovered(
        repoPath: URL,
        parentPath: URL,
        linkedWorktrees: LinkedWorktreeInfo = .notScanned
    )
    case reposDiscovered(
        parentPath: URL,
        repositories: [DiscoveredRepoTopologyInfo]
    )
    case repoRemoved(repoPath: URL)
    case worktreeRegistered(worktreeId: UUID, repoId: UUID, rootPath: URL)
    case worktreeUnregistered(worktreeId: UUID, repoId: UUID)
}

package enum AppLifecycleEvent: Sendable {
    case appLaunched
    case appTerminating
    case tabSwitched(activeTabId: UUID)
}

package enum FocusChangeEvent: Sendable {
    case activePaneChanged(paneId: PaneId?)
    case activeWorktreeChanged(worktreeId: UUID?)
}

package enum ConfigChangeEvent: Sendable {
    case watchedPathsUpdated(paths: [URL])
    case workspacePersistenceUpdated
}

package enum WorktreeScopedEvent: Sendable {
    case filesystem(FilesystemEvent)
    case gitWorkingDirectory(GitWorkingDirectoryEvent)
    case forge(ForgeEvent)
    case security(SecurityEvent)
}

package enum GitWorkingDirectoryEvent: Sendable {
    case snapshotChanged(snapshot: GitWorkingTreeSnapshot)
    case branchChanged(worktreeId: UUID, repoId: UUID, from: String, to: String)
    case originChanged(repoId: UUID, from: String, to: String)
    case originUnavailable(repoId: UUID)
    case worktreeDiscovered(repoId: UUID, worktreePath: URL, branch: String, isMain: Bool)
    case worktreeRemoved(repoId: UUID, worktreePath: URL)
    case diffAvailable(diffId: UUID, worktreeId: UUID, repoId: UUID)
}

package enum ForgeEvent: Sendable {
    case pullRequestCountsChanged(repoId: UUID, countsByBranch: [String: Int])
    case checksUpdated(repoId: UUID, status: ForgeChecksStatus)
    case refreshFailed(repoId: UUID, error: String)
    case rateLimited(repoId: UUID, retryAfterSeconds: Int)
}

package enum ForgeChecksStatus: String, Sendable {
    case passing
    case failing
    case pending
    case unknown
}

package struct SystemEnvelope: Sendable {
    package let eventId: UUID
    package let source: SystemSource
    package let seq: UInt64
    let timestamp: ContinuousClock.Instant
    let schemaVersion: UInt16
    let correlationId: UUID?
    let causationId: UUID?
    let commandId: UUID?
    package let event: SystemScopedEvent

    package init(
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

package struct WorktreeEnvelope: Sendable {
    package let eventId: UUID
    package let source: EventSource
    package let seq: UInt64
    package let timestamp: ContinuousClock.Instant
    let schemaVersion: UInt16
    package let correlationId: UUID?
    let causationId: UUID?
    package let commandId: UUID?
    package let repoId: UUID
    package let worktreeId: UUID?
    package let event: WorktreeScopedEvent

    package init(
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

package struct PaneEnvelope: Sendable {
    package let eventId: UUID
    package let source: EventSource
    package let seq: UInt64
    package let timestamp: ContinuousClock.Instant
    package let schemaVersion: UInt16
    package let correlationId: UUID?
    package let causationId: UUID?
    package let commandId: UUID?
    package let paneId: PaneId
    package let paneKind: PaneContentType
    package let event: PaneRuntimeEvent

    package init(
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
