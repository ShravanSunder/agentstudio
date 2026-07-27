import Foundation

package struct FilesystemProjectionTopologyEntry: Sendable, Equatable {
    package let repoId: UUID
    package let worktreeId: UUID
    package let rootPath: URL
    package let isUnavailable: Bool

    package init(repoId: UUID, worktreeId: UUID, rootPath: URL, isUnavailable: Bool) {
        self.repoId = repoId
        self.worktreeId = worktreeId
        self.rootPath = rootPath
        self.isUnavailable = isUnavailable
    }
}

package struct FilesystemProjectionPaneEntry: Sendable, Equatable {
    package let paneId: UUID
    package let paneKind: PaneContentType
    package let repoId: UUID?
    package let worktreeId: UUID?
    package let cwd: URL?

    package init(
        paneId: UUID,
        paneKind: PaneContentType,
        repoId: UUID?,
        worktreeId: UUID?,
        cwd: URL?
    ) {
        self.paneId = paneId
        self.paneKind = paneKind
        self.repoId = repoId
        self.worktreeId = worktreeId
        self.cwd = cwd
    }
}

package struct FilesystemProjectionPaneUpdate: Sendable, Equatable {
    package enum Kind: Sendable, Equatable {
        case upsert(FilesystemProjectionPaneEntry)
        case remove(paneId: UUID)
    }

    package let requestGeneration: UInt64
    package let kind: Kind

    package init(requestGeneration: UInt64, kind: Kind) {
        self.requestGeneration = requestGeneration
        self.kind = kind
    }
}

package struct FilesystemSourceSyncRequest: Sendable, Equatable {
    package let requestGeneration: UInt64
    package let paneContextGeneration: UInt64
    package let topologyEntries: [FilesystemProjectionTopologyEntry]
    package let paneEntries: [FilesystemProjectionPaneEntry]
    package let appliedContextsByWorktreeId: [UUID: WorktreeFilesystemContext]
    package let appliedActivityByWorktreeId: [UUID: Bool]
    package let activePaneWorktreeId: UUID?
    package let appliedActivePaneWorktreeId: UUID?
    package let sidebarVisibleWorktreeIds: Set<UUID>
    package let appliedSidebarVisibleWorktreeIds: Set<UUID>

    package init(
        requestGeneration: UInt64,
        paneContextGeneration: UInt64,
        topologyEntries: [FilesystemProjectionTopologyEntry],
        paneEntries: [FilesystemProjectionPaneEntry],
        appliedContextsByWorktreeId: [UUID: WorktreeFilesystemContext] = [:],
        appliedActivityByWorktreeId: [UUID: Bool],
        activePaneWorktreeId: UUID?,
        appliedActivePaneWorktreeId: UUID?,
        sidebarVisibleWorktreeIds: Set<UUID> = [],
        appliedSidebarVisibleWorktreeIds: Set<UUID> = []
    ) {
        self.requestGeneration = requestGeneration
        self.paneContextGeneration = paneContextGeneration
        self.topologyEntries = topologyEntries
        self.paneEntries = paneEntries
        self.appliedContextsByWorktreeId = appliedContextsByWorktreeId
        self.appliedActivityByWorktreeId = appliedActivityByWorktreeId
        self.activePaneWorktreeId = activePaneWorktreeId
        self.appliedActivePaneWorktreeId = appliedActivePaneWorktreeId
        self.sidebarVisibleWorktreeIds = sidebarVisibleWorktreeIds
        self.appliedSidebarVisibleWorktreeIds = appliedSidebarVisibleWorktreeIds
    }
}

package struct FilesystemSourceSyncDiff: Sendable, Equatable {
    package struct Registration: Sendable, Equatable {
        package let worktreeId: UUID
        package let repoId: UUID
        package let rootPath: URL

        package init(worktreeId: UUID, repoId: UUID, rootPath: URL) {
            self.worktreeId = worktreeId
            self.repoId = repoId
            self.rootPath = rootPath
        }
    }

    package struct ActivityUpdate: Sendable, Equatable {
        package let worktreeId: UUID
        package let isActiveInApp: Bool

        package init(worktreeId: UUID, isActiveInApp: Bool) {
            self.worktreeId = worktreeId
            self.isActiveInApp = isActiveInApp
        }
    }

    package let requestGeneration: UInt64
    package let contextsByWorktreeId: [UUID: WorktreeFilesystemContext]
    package let unregisterWorktreeIds: [UUID]
    package let registerWorktrees: [Registration]
    package let activityUpdates: [ActivityUpdate]
    package let activityByWorktreeId: [UUID: Bool]
    package let activePaneWorktreeId: UUID?
    package let shouldUpdateActivePaneWorktree: Bool
    package let sidebarVisibleWorktreeIds: Set<UUID>
    package let shouldUpdateSidebarVisibleWorktrees: Bool
    package let validPaneIds: Set<UUID>
    package let validWorktreeIds: Set<UUID>

    package init(
        requestGeneration: UInt64,
        contextsByWorktreeId: [UUID: WorktreeFilesystemContext],
        unregisterWorktreeIds: [UUID],
        registerWorktrees: [Registration],
        activityUpdates: [ActivityUpdate],
        activityByWorktreeId: [UUID: Bool],
        activePaneWorktreeId: UUID?,
        shouldUpdateActivePaneWorktree: Bool,
        sidebarVisibleWorktreeIds: Set<UUID>,
        shouldUpdateSidebarVisibleWorktrees: Bool,
        validPaneIds: Set<UUID>,
        validWorktreeIds: Set<UUID>
    ) {
        self.requestGeneration = requestGeneration
        self.contextsByWorktreeId = contextsByWorktreeId
        self.unregisterWorktreeIds = unregisterWorktreeIds
        self.registerWorktrees = registerWorktrees
        self.activityUpdates = activityUpdates
        self.activityByWorktreeId = activityByWorktreeId
        self.activePaneWorktreeId = activePaneWorktreeId
        self.shouldUpdateActivePaneWorktree = shouldUpdateActivePaneWorktree
        self.sidebarVisibleWorktreeIds = sidebarVisibleWorktreeIds
        self.shouldUpdateSidebarVisibleWorktrees = shouldUpdateSidebarVisibleWorktrees
        self.validPaneIds = validPaneIds
        self.validWorktreeIds = validWorktreeIds
    }
}

package struct PaneFilesystemProjectionRequest: Sendable {
    package let requestGeneration: UInt64
    package let paneContextGeneration: UInt64
    package let topologyGeneration: UInt64
    package let envelope: RuntimeEnvelope

    package init(
        requestGeneration: UInt64,
        paneContextGeneration: UInt64,
        topologyGeneration: UInt64,
        envelope: RuntimeEnvelope
    ) {
        self.requestGeneration = requestGeneration
        self.paneContextGeneration = paneContextGeneration
        self.topologyGeneration = topologyGeneration
        self.envelope = envelope
    }
}

package struct PaneFilesystemProjectionResult: Sendable {
    package let requestGeneration: UInt64
    package let paneContextGeneration: UInt64
    package let topologyGeneration: UInt64
    package let intents: [PaneFilesystemProjectionIntent]
    package let worktreeCount: Int
    package let paneCount: Int

    package init(
        requestGeneration: UInt64,
        paneContextGeneration: UInt64,
        topologyGeneration: UInt64,
        intents: [PaneFilesystemProjectionIntent],
        worktreeCount: Int,
        paneCount: Int
    ) {
        self.requestGeneration = requestGeneration
        self.paneContextGeneration = paneContextGeneration
        self.topologyGeneration = topologyGeneration
        self.intents = intents
        self.worktreeCount = worktreeCount
        self.paneCount = paneCount
    }
}

package struct PaneFilesystemCWDSubtreeProjection: Sendable {
    package let paneId: UUID
    package let paneKind: PaneContentType
    package let context: PaneFilesystemContext
    package let paths: [String]
    package let batchSequence: UInt64
    package let timestamp: ContinuousClock.Instant
    package let correlationId: UUID?
    package let commandId: UUID?

    package init(
        paneId: UUID,
        paneKind: PaneContentType,
        context: PaneFilesystemContext,
        paths: [String],
        batchSequence: UInt64,
        timestamp: ContinuousClock.Instant,
        correlationId: UUID?,
        commandId: UUID?
    ) {
        self.paneId = paneId
        self.paneKind = paneKind
        self.context = context
        self.paths = paths
        self.batchSequence = batchSequence
        self.timestamp = timestamp
        self.correlationId = correlationId
        self.commandId = commandId
    }
}

package struct PaneFilesystemGitProjection: Sendable {
    package let paneId: UUID
    package let paneKind: PaneContentType
    package let context: PaneFilesystemContext
    package let summary: GitWorkingTreeSummary
    package let timestamp: ContinuousClock.Instant
    package let correlationId: UUID?
    package let commandId: UUID?

    package init(
        paneId: UUID,
        paneKind: PaneContentType,
        context: PaneFilesystemContext,
        summary: GitWorkingTreeSummary,
        timestamp: ContinuousClock.Instant,
        correlationId: UUID?,
        commandId: UUID?
    ) {
        self.paneId = paneId
        self.paneKind = paneKind
        self.context = context
        self.summary = summary
        self.timestamp = timestamp
        self.correlationId = correlationId
        self.commandId = commandId
    }
}

package enum PaneFilesystemProjectionIntent: Sendable {
    case cwdSubtreeChanged(PaneFilesystemCWDSubtreeProjection)
    case gitWorkingTreeInCwd(PaneFilesystemGitProjection)
}
