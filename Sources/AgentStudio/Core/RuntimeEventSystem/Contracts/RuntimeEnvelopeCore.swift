import Foundation

package enum RuntimeEnvelope: Sendable {
    case system(SystemEnvelope)
    case worktree(WorktreeEnvelope)
    case pane(PaneEnvelope)
}

extension EventBusFactTopic {
    package static let systemTopology = Self("system.topology")
    package static let systemAppLifecycle = Self("system.appLifecycle")
    package static let systemFocusChanged = Self("system.focusChanged")
    package static let systemConfigChanged = Self("system.configChanged")
    package static let systemWorkspaceActivity = Self("system.workspaceActivity")
    package static let worktreeFilesystem = Self("worktree.filesystem")
    package static let worktreeGitWorkingDirectory = Self("worktree.gitWorkingDirectory")
    package static let worktreeForge = Self("worktree.forge")
    package static let worktreeSecurity = Self("worktree.security")
    package static let paneLifecycle = Self("pane.lifecycle")
    package static let paneTerminal = Self("pane.terminal")
    package static let paneTerminalActivity = Self("pane.terminalActivity")
    package static let paneBrowser = Self("pane.browser")
    package static let paneDiff = Self("pane.diff")
    package static let paneEditor = Self("pane.editor")
    package static let paneAgentNotificationRequested = Self("pane.agentNotificationRequested")
    package static let panePlugin = Self("pane.plugin")
    package static let paneFilesystemContext = Self("pane.paneFilesystemContext")
    package static let paneFilesystem = Self("pane.filesystem")
    package static let paneArtifact = Self("pane.artifact")
    package static let paneSecurity = Self("pane.security")
    package static let paneError = Self("pane.error")
}

extension RuntimeEnvelope: EventBusFactTopicProviding {
    package var eventBusFactTopic: EventBusFactTopic {
        switch self {
        case .system(let envelope):
            switch envelope.event {
            case .topology: return .systemTopology
            case .appLifecycle: return .systemAppLifecycle
            case .focusChanged: return .systemFocusChanged
            case .configChanged: return .systemConfigChanged
            case .workspaceActivity: return .systemWorkspaceActivity
            }
        case .worktree(let envelope):
            switch envelope.event {
            case .filesystem: return .worktreeFilesystem
            case .gitWorkingDirectory: return .worktreeGitWorkingDirectory
            case .forge: return .worktreeForge
            case .security: return .worktreeSecurity
            }
        case .pane(let envelope):
            switch envelope.event {
            case .lifecycle: return .paneLifecycle
            case .terminal: return .paneTerminal
            case .terminalActivity: return .paneTerminalActivity
            case .browser: return .paneBrowser
            case .diff: return .paneDiff
            case .editor: return .paneEditor
            case .agentNotificationRequested: return .paneAgentNotificationRequested
            case .plugin: return .panePlugin
            case .paneFilesystemContext: return .paneFilesystemContext
            case .filesystem: return .paneFilesystem
            case .artifact: return .paneArtifact
            case .security: return .paneSecurity
            case .error: return .paneError
            }
        }
    }
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

package struct DiscoveredRepoStableIdentity: Sendable, Equatable {
    package let repositoryStableKey: String
    package let worktreeStableKeysByPath: [URL: String]

    package init(repositoryStableKey: String, worktreeStableKeysByPath: [URL: String]) {
        self.repositoryStableKey = repositoryStableKey
        self.worktreeStableKeysByPath = worktreeStableKeysByPath
    }

    package static func prepare(
        repoPath: URL,
        linkedWorktrees: LinkedWorktreeInfo
    ) -> Self {
        let normalizedRepoPath = repoPath.standardizedFileURL
        var paths = [normalizedRepoPath]
        if case .scanned(let linkedPaths) = linkedWorktrees {
            paths.append(contentsOf: linkedPaths.map(\.standardizedFileURL))
        }
        return Self(
            repositoryStableKey: StableKey.fromPath(normalizedRepoPath),
            worktreeStableKeysByPath: Dictionary(
                uniqueKeysWithValues: paths.map { ($0, StableKey.fromPath($0)) }
            )
        )
    }
}

package struct DiscoveredRepoTopologyInfo: Sendable, Equatable {
    package let repoPath: URL
    package let linkedWorktrees: LinkedWorktreeInfo
    package let stableIdentity: DiscoveredRepoStableIdentity

    package init(
        repoPath: URL,
        linkedWorktrees: LinkedWorktreeInfo,
        stableIdentity: DiscoveredRepoStableIdentity? = nil
    ) {
        self.repoPath = repoPath
        self.linkedWorktrees = linkedWorktrees
        self.stableIdentity =
            stableIdentity
            ?? .prepare(repoPath: repoPath, linkedWorktrees: linkedWorktrees)
    }
}

package enum TopologyEvent: Sendable {
    case repoDiscovered(
        repoPath: URL,
        parentPath: URL,
        linkedWorktrees: LinkedWorktreeInfo = .notScanned,
        stableIdentity: DiscoveredRepoStableIdentity? = nil
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
    case statusOutcome(GitStatusOutcomeFact)
    case snapshotChanged(snapshot: GitWorkingTreeSnapshot)
    case branchChanged(worktreeId: UUID, repoId: UUID, from: String, to: String)
    case originChanged(repoId: UUID, from: String, to: String)
    case originUnavailable(repoId: UUID)
    case worktreeDiscovered(repoId: UUID, worktreePath: URL, branch: String, isMain: Bool)
    case worktreeRemoved(repoId: UUID, worktreePath: URL)
    case diffAvailable(diffId: UUID, worktreeId: UUID, repoId: UUID)
}

package struct GitStatusOutcomeFact: Sendable, Equatable {
    package let worktreeId: UUID
    package let repoId: UUID
    package let outcome: GitStatusOutcome
    package let reason: GitWorkingTreeStatusUnavailableReason?
    package let consecutiveFailureCount: Int

    package init(
        worktreeId: UUID,
        repoId: UUID,
        outcome: GitStatusOutcome,
        reason: GitWorkingTreeStatusUnavailableReason?,
        consecutiveFailureCount: Int
    ) {
        self.worktreeId = worktreeId
        self.repoId = repoId
        self.outcome = outcome
        self.reason = reason
        self.consecutiveFailureCount = consecutiveFailureCount
    }
}

package enum GitStatusOutcome: String, Sendable, Equatable {
    case completed
    case timeout
    case unavailable
}

package enum PullRequestStablePresentation: Equatable, Sendable {
    case unknown
    case ready(confirmedFactsByBranch: [String: PullRequestFacts])
    case unavailable(previousConfirmedFactsByBranch: [String: PullRequestFacts]?)
}

package enum PullRequestRepositoryProjection: Equatable, Sendable {
    case stable(PullRequestStablePresentation)
    case loading(
        baseline: PullRequestStablePresentation,
        requestIdentity: UInt64
    )
}

package enum ForgeEvent: Sendable {
    case pullRequestRepositoryProjectionChanged(
        repoId: UUID,
        projection: PullRequestRepositoryProjection,
        invalidatedBranches: Set<String>
    )
    case checksUpdated(repoId: UUID, status: ForgeChecksStatus)
    case refreshFailed(repoId: UUID, error: String)
    case rateLimited(repoId: UUID, retryAfterSeconds: Int?)
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
