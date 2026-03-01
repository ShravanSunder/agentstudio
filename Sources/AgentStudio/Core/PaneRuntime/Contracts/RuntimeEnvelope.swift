import Foundation
import os

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

extension SystemEnvelope {
    static func test(
        event: SystemScopedEvent,
        source: SystemSource = .builtin(.coordinator),
        seq: UInt64 = 1,
        timestamp: ContinuousClock.Instant = ContinuousClock().now,
        schemaVersion: UInt16 = RuntimeEnvelopeSchema.current,
        eventId: UUID = UUID(),
        correlationId: UUID? = nil,
        causationId: UUID? = nil,
        commandId: UUID? = nil
    ) -> Self {
        Self(
            eventId: eventId,
            source: source,
            seq: seq,
            timestamp: timestamp,
            schemaVersion: schemaVersion,
            correlationId: correlationId,
            causationId: causationId,
            commandId: commandId,
            event: event
        )
    }
}

extension WorktreeEnvelope {
    static func test(
        event: WorktreeScopedEvent,
        repoId: UUID = UUID(),
        worktreeId: UUID? = UUID(),
        source: EventSource? = nil,
        seq: UInt64 = 1,
        timestamp: ContinuousClock.Instant = ContinuousClock().now,
        schemaVersion: UInt16 = RuntimeEnvelopeSchema.current,
        eventId: UUID = UUID(),
        correlationId: UUID? = nil,
        causationId: UUID? = nil,
        commandId: UUID? = nil
    ) -> Self {
        let resolvedSource = source ?? .worktree(worktreeId ?? repoId)
        return Self(
            eventId: eventId,
            source: resolvedSource,
            seq: seq,
            timestamp: timestamp,
            schemaVersion: schemaVersion,
            correlationId: correlationId,
            causationId: causationId,
            commandId: commandId,
            repoId: repoId,
            worktreeId: worktreeId,
            event: event
        )
    }
}

extension PaneEnvelope {
    static func test(
        event: PaneRuntimeEvent,
        paneId: PaneId = PaneId(),
        paneKind: PaneContentType = .terminal,
        source: EventSource? = nil,
        seq: UInt64 = 1,
        timestamp: ContinuousClock.Instant = ContinuousClock().now,
        schemaVersion: UInt16 = RuntimeEnvelopeSchema.current,
        eventId: UUID = UUID(),
        correlationId: UUID? = nil,
        causationId: UUID? = nil,
        commandId: UUID? = nil
    ) -> Self {
        let resolvedSource = source ?? .pane(paneId)
        return Self(
            eventId: eventId,
            source: resolvedSource,
            seq: seq,
            timestamp: timestamp,
            schemaVersion: schemaVersion,
            correlationId: correlationId,
            causationId: causationId,
            commandId: commandId,
            paneId: paneId,
            paneKind: paneKind,
            event: event
        )
    }
}

extension RuntimeEnvelope {
    private static let bridgeLogger = Logger(subsystem: "com.agentstudio", category: "RuntimeEnvelopeBridge")

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

    static func fromLegacy(_ legacy: PaneEventEnvelope) -> RuntimeEnvelope {
        if let systemEnvelope = systemEnvelope(from: legacy) {
            return .system(systemEnvelope)
        }

        if let worktreeScopedEvent = worktreeScopedEvent(from: legacy.event) {
            let resolvedWorktreeId = legacy.sourceFacets.worktreeId ?? worktreeId(from: legacy.event)
            let resolvedRepoId: UUID
            if let explicitRepoId = legacy.sourceFacets.repoId
                ?? repoId(from: legacy.event)
                ?? resolvedWorktreeId
            {
                resolvedRepoId = explicitRepoId
            } else {
                // Deterministic fallback preserves idempotency when source facts are incomplete.
                resolvedRepoId = legacy.eventId
                bridgeLogger.warning(
                    """
                    Missing repoId while adapting legacy pane envelope to WorktreeEnvelope; \
                    fallbackRepoId=\(resolvedRepoId.uuidString, privacy: .public) \
                    source=\(legacy.source.description, privacy: .public)
                    """
                )
            }
            return .worktree(
                WorktreeEnvelope(
                    eventId: legacy.eventId,
                    source: legacy.source,
                    seq: legacy.seq,
                    timestamp: legacy.timestamp,
                    schemaVersion: legacy.schemaVersion,
                    correlationId: legacy.correlationId,
                    causationId: legacy.causationId,
                    commandId: legacy.commandId,
                    repoId: resolvedRepoId,
                    worktreeId: resolvedWorktreeId,
                    event: worktreeScopedEvent
                )
            )
        }

        return .pane(
            PaneEnvelope(
                eventId: legacy.eventId,
                source: legacy.source,
                seq: legacy.seq,
                timestamp: legacy.timestamp,
                schemaVersion: legacy.schemaVersion,
                correlationId: legacy.correlationId,
                causationId: legacy.causationId,
                commandId: legacy.commandId,
                paneId: resolvePaneId(from: legacy),
                paneKind: legacy.paneKind ?? inferredPaneKind(from: legacy.event) ?? .agent,
                event: legacy.event
            )
        )
    }

    func toLegacy() -> PaneEventEnvelope? {
        switch self {
        case .pane(let envelope):
            return PaneEventEnvelope(
                eventId: envelope.eventId,
                source: envelope.source,
                sourceFacets: Self.legacySourceFacets(from: envelope),
                paneKind: Self.legacyPaneKind(from: envelope),
                seq: envelope.seq,
                schemaVersion: envelope.schemaVersion,
                commandId: envelope.commandId,
                correlationId: envelope.correlationId,
                causationId: envelope.causationId,
                timestamp: envelope.timestamp,
                epoch: 0,
                event: envelope.event
            )
        case .worktree(let envelope):
            guard let legacyEvent = Self.legacyPaneRuntimeEvent(from: envelope.event) else {
                return nil
            }
            return PaneEventEnvelope(
                eventId: envelope.eventId,
                source: envelope.source,
                sourceFacets: PaneContextFacets.from(worktreeEnvelope: envelope),
                paneKind: Self.inferredPaneKind(from: legacyEvent),
                seq: envelope.seq,
                schemaVersion: envelope.schemaVersion,
                commandId: envelope.commandId,
                correlationId: envelope.correlationId,
                causationId: envelope.causationId,
                timestamp: envelope.timestamp,
                epoch: 0,
                event: legacyEvent
            )
        case .system:
            guard let legacyEvent = Self.legacyPaneRuntimeEvent(fromSystem: self) else {
                return nil
            }
            guard case .system(let envelope) = self else { return nil }
            return PaneEventEnvelope(
                eventId: envelope.eventId,
                source: .system(envelope.source),
                sourceFacets: Self.legacySourceFacets(from: envelope),
                paneKind: nil,
                seq: envelope.seq,
                schemaVersion: envelope.schemaVersion,
                commandId: envelope.commandId,
                correlationId: envelope.correlationId,
                causationId: envelope.causationId,
                timestamp: envelope.timestamp,
                epoch: 0,
                event: legacyEvent
            )
        }
    }

    private static func systemEnvelope(from legacy: PaneEventEnvelope) -> SystemEnvelope? {
        guard case .filesystem(let filesystemEvent) = legacy.event else { return nil }

        let topologyEvent: TopologyEvent?
        switch filesystemEvent {
        case .worktreeRegistered(let worktreeId, let repoId, let rootPath):
            topologyEvent = .worktreeRegistered(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        case .worktreeUnregistered(let worktreeId, let repoId):
            topologyEvent = .worktreeUnregistered(worktreeId: worktreeId, repoId: repoId)
        case .filesChanged, .gitSnapshotChanged, .diffAvailable, .branchChanged:
            topologyEvent = nil
        }

        guard let topologyEvent else { return nil }

        let systemSource: SystemSource
        switch legacy.source {
        case .system(let source):
            systemSource = source
        case .pane, .worktree:
            systemSource = .builtin(.coordinator)
        }

        return SystemEnvelope(
            eventId: legacy.eventId,
            source: systemSource,
            seq: legacy.seq,
            timestamp: legacy.timestamp,
            schemaVersion: legacy.schemaVersion,
            correlationId: legacy.correlationId,
            causationId: legacy.causationId,
            commandId: legacy.commandId,
            event: .topology(topologyEvent)
        )
    }

    private static func worktreeScopedEvent(from event: PaneRuntimeEvent) -> WorktreeScopedEvent? {
        switch event {
        case .filesystem(let filesystemEvent):
            if let compatibilityEvent = filesystemEvent.compatibilityWorktreeScopedEvent {
                return compatibilityEvent
            }
            return nil
        case .security(let securityEvent):
            return .security(securityEvent)
        case .lifecycle, .terminal, .browser, .diff, .editor, .plugin, .artifact, .error:
            return nil
        }
    }

    private static func legacyPaneRuntimeEvent(from event: WorktreeScopedEvent) -> PaneRuntimeEvent? {
        switch event {
        case .filesystem(let filesystemEvent):
            return .filesystem(filesystemEvent)
        case .gitWorkingDirectory(let gitEvent):
            guard let filesystemEvent = gitEvent.compatibilityFilesystemEvent else {
                return nil
            }
            return .filesystem(filesystemEvent)
        case .security(let securityEvent):
            return .security(securityEvent)
        case .forge:
            return nil
        }
    }

    private static func legacyPaneRuntimeEvent(fromSystem envelope: RuntimeEnvelope) -> PaneRuntimeEvent? {
        guard case .system(let systemEnvelope) = envelope else { return nil }
        switch systemEnvelope.event {
        case .topology(let topologyEvent):
            switch topologyEvent {
            case .worktreeRegistered(let worktreeId, let repoId, let rootPath):
                return .filesystem(
                    .worktreeRegistered(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
                )
            case .worktreeUnregistered(let worktreeId, let repoId):
                return .filesystem(
                    .worktreeUnregistered(worktreeId: worktreeId, repoId: repoId)
                )
            case .repoDiscovered, .repoRemoved:
                return nil
            }
        case .appLifecycle, .focusChanged, .configChanged:
            return nil
        }
    }

    private static func legacySourceFacets(from envelope: PaneEnvelope) -> PaneContextFacets {
        var sourceFacets = PaneContextFacets.empty
        switch envelope.source {
        case .worktree(let worktreeId):
            sourceFacets.worktreeId = worktreeId
        case .pane, .system:
            break
        }

        switch envelope.event {
        case .filesystem(let filesystemEvent):
            sourceFacets.repoId = repoId(from: .filesystem(filesystemEvent)) ?? sourceFacets.repoId
            sourceFacets.worktreeId = worktreeId(from: .filesystem(filesystemEvent)) ?? sourceFacets.worktreeId
            switch filesystemEvent {
            case .worktreeRegistered(_, _, let rootPath):
                sourceFacets.cwd = rootPath
            case .filesChanged(let changeset):
                sourceFacets.cwd = changeset.rootPath
            case .worktreeUnregistered, .gitSnapshotChanged, .diffAvailable, .branchChanged:
                break
            }
        case .terminal(.cwdChanged(let cwdPath)):
            sourceFacets.cwd = URL(fileURLWithPath: cwdPath)
        case .lifecycle, .terminal, .browser, .diff, .editor, .plugin, .artifact, .security, .error:
            break
        }

        return sourceFacets
    }

    private static func legacyPaneKind(from envelope: PaneEnvelope) -> PaneContentType? {
        switch envelope.source {
        case .pane:
            return envelope.paneKind
        case .system, .worktree:
            return inferredPaneKind(from: envelope.event)
        }
    }

    private static func legacySourceFacets(from envelope: SystemEnvelope) -> PaneContextFacets {
        switch envelope.event {
        case .topology(let topologyEvent):
            switch topologyEvent {
            case .worktreeRegistered(let worktreeId, let repoId, let rootPath):
                return PaneContextFacets(repoId: repoId, worktreeId: worktreeId, cwd: rootPath)
            case .worktreeUnregistered(let worktreeId, let repoId):
                return PaneContextFacets(repoId: repoId, worktreeId: worktreeId)
            case .repoDiscovered(let repoPath, _):
                return PaneContextFacets(cwd: repoPath)
            case .repoRemoved(let repoPath):
                return PaneContextFacets(cwd: repoPath)
            }
        case .appLifecycle, .focusChanged, .configChanged:
            return .empty
        }
    }

    private static func resolvePaneId(from legacy: PaneEventEnvelope) -> PaneId {
        switch legacy.source {
        case .pane(let paneId):
            return paneId
        case .worktree, .system:
            return PaneId()
        }
    }

    private static func inferredPaneKind(from event: PaneRuntimeEvent) -> PaneContentType? {
        switch event {
        case .lifecycle, .terminal:
            return .terminal
        case .browser:
            return .browser
        case .diff:
            return .diff
        case .editor:
            return .editor
        case .plugin(let kind, _):
            return kind
        case .filesystem, .artifact, .security, .error:
            return nil
        }
    }

    private static func worktreeId(from event: PaneRuntimeEvent) -> UUID? {
        guard case .filesystem(let filesystemEvent) = event else { return nil }
        switch filesystemEvent {
        case .worktreeRegistered(let worktreeId, _, _):
            return worktreeId
        case .worktreeUnregistered(let worktreeId, _):
            return worktreeId
        case .filesChanged(let changeset):
            return changeset.worktreeId
        case .gitSnapshotChanged(let snapshot):
            return snapshot.worktreeId
        case .diffAvailable(_, let worktreeId, _):
            return worktreeId
        case .branchChanged(let worktreeId, _, _, _):
            return worktreeId
        }
    }

    private static func repoId(from event: PaneRuntimeEvent) -> UUID? {
        guard case .filesystem(let filesystemEvent) = event else { return nil }
        switch filesystemEvent {
        case .worktreeRegistered(_, let repoId, _):
            return repoId
        case .worktreeUnregistered(_, let repoId):
            return repoId
        case .filesChanged(let changeset):
            return changeset.repoId
        case .gitSnapshotChanged(let snapshot):
            return snapshot.repoId
        case .diffAvailable(_, _, let repoId):
            return repoId
        case .branchChanged(_, let repoId, _, _):
            return repoId
        }
    }
}

private extension GitWorkingDirectoryEvent {
    var compatibilityFilesystemEvent: FilesystemEvent? {
        switch self {
        case .snapshotChanged(let snapshot):
            return .gitSnapshotChanged(snapshot: snapshot)
        case .branchChanged(let worktreeId, let repoId, let from, let to):
            return .branchChanged(worktreeId: worktreeId, repoId: repoId, from: from, to: to)
        case .diffAvailable(let diffId, let worktreeId, let repoId):
            return .diffAvailable(diffId: diffId, worktreeId: worktreeId, repoId: repoId)
        case .originChanged, .worktreeDiscovered, .worktreeRemoved:
            return nil
        }
    }
}
