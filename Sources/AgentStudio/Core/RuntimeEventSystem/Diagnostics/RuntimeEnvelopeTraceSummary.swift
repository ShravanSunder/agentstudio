import Foundation

struct RuntimeEnvelopeTraceSummary: Sendable, Equatable {
    enum Scope: String, Sendable {
        case pane
        case system
        case worktree
    }

    let scope: Scope
    let eventId: UUID
    let sequence: UInt64
    let schemaVersion: UInt16
    let eventName: String
    let actionPolicy: String?
    let correlationId: UUID?
    let causationId: UUID?
    let commandId: UUID?
    let paneId: UUID?
    let paneKind: String?
    let repoId: UUID?
    let worktreeId: UUID?

    init(_ envelope: RuntimeEnvelope) {
        switch envelope {
        case .pane(let paneEnvelope):
            self.init(paneEnvelope)
        case .system(let systemEnvelope):
            self.init(systemEnvelope)
        case .worktree(let worktreeEnvelope):
            self.init(worktreeEnvelope)
        }
    }

    init(_ envelope: PaneEnvelope) {
        self.scope = .pane
        self.eventId = envelope.eventId
        self.sequence = envelope.seq
        self.schemaVersion = envelope.schemaVersion
        self.eventName = envelope.event.traceEventName
        self.actionPolicy = envelope.event.actionPolicy.traceName
        self.correlationId = envelope.correlationId
        self.causationId = envelope.causationId
        self.commandId = envelope.commandId
        self.paneId = envelope.paneId.uuid
        self.paneKind = envelope.paneKind.traceName
        self.repoId = nil
        self.worktreeId = nil
    }

    init(_ envelope: SystemEnvelope) {
        self.scope = .system
        self.eventId = envelope.eventId
        self.sequence = envelope.seq
        self.schemaVersion = envelope.schemaVersion
        self.eventName = envelope.event.traceEventName
        self.actionPolicy = nil
        self.correlationId = envelope.correlationId
        self.causationId = envelope.causationId
        self.commandId = envelope.commandId
        self.paneId = nil
        self.paneKind = nil
        self.repoId = nil
        self.worktreeId = nil
    }

    init(_ envelope: WorktreeEnvelope) {
        self.scope = .worktree
        self.eventId = envelope.eventId
        self.sequence = envelope.seq
        self.schemaVersion = envelope.schemaVersion
        self.eventName = envelope.event.traceEventName
        self.actionPolicy = nil
        self.correlationId = envelope.correlationId
        self.causationId = envelope.causationId
        self.commandId = envelope.commandId
        self.paneId = nil
        self.paneKind = nil
        self.repoId = envelope.repoId
        self.worktreeId = envelope.worktreeId
    }

    func attributes(
        eventBusName: String,
        consumerName: String
    ) -> [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.eventbus.consumer": .string(consumerName),
            "agentstudio.eventbus.name": .string(eventBusName),
            "agentstudio.envelope.event_id": .string(eventId.uuidString),
            "agentstudio.envelope.scope": .string(scope.rawValue),
            "agentstudio.envelope.schema_version": .int(Int(schemaVersion)),
            "agentstudio.envelope.seq": .int(Int(sequence)),
            "agentstudio.runtime.event": .string(eventName),
        ]
        if let actionPolicy {
            attributes["agentstudio.runtime.action_policy"] = .string(actionPolicy)
        }
        if let correlationId {
            attributes["agentstudio.envelope.correlation_id"] = .string(correlationId.uuidString)
        }
        if let causationId {
            attributes["agentstudio.envelope.causation_id"] = .string(causationId.uuidString)
        }
        if let commandId {
            attributes["agentstudio.command.id"] = .string(commandId.uuidString)
        }
        if let paneId {
            attributes["agentstudio.pane.id"] = .string(paneId.uuidString)
        }
        if let paneKind {
            attributes["agentstudio.pane.kind"] = .string(paneKind)
        }
        if let repoId {
            attributes["agentstudio.repo.id"] = .string(repoId.uuidString)
        }
        if let worktreeId {
            attributes["agentstudio.worktree.id"] = .string(worktreeId.uuidString)
        }
        return attributes
    }
}

extension RuntimeEnvelopeTraceSummary {
    static func isHighVolumeActivityOnly(_ event: PaneRuntimeEvent) -> Bool {
        switch event {
        case .terminal(.scrollbarChanged),
            .terminal(.cwdChanged),
            .terminal(.titleChanged),
            .terminal(.tabTitleChanged),
            .terminal(.cellSizeChanged),
            .terminal(.mouseShapeChanged),
            .terminal(.mouseVisibilityChanged),
            .terminal(.mouseLinkHovered),
            .terminal(.keySequenceChanged),
            .terminal(.keyTableChanged),
            .terminal(.searchMatchesUpdated),
            .terminal(.searchSelectionChanged):
            return true
        case .browser(.consoleMessage),
            .editor(.diagnosticsUpdated):
            return true
        case .paneFilesystemContext(.gitWorkingTreeInCwd):
            return true
        default:
            return false
        }
    }
}

extension ActionPolicy {
    var traceName: String {
        switch self {
        case .critical:
            return "critical"
        case .lossy(let consolidationKey):
            return "lossy:\(consolidationKey)"
        }
    }
}

extension PaneContentType {
    var traceName: String {
        switch self {
        case .terminal:
            return "terminal"
        case .browser:
            return "browser"
        case .diff:
            return "diff"
        case .editor:
            return "editor"
        case .review:
            return "review"
        case .agent:
            return "agent"
        case .codeViewer:
            return "codeViewer"
        case .plugin(let name):
            return "plugin:\(name)"
        }
    }
}

extension PaneRuntimeEvent {
    var traceEventName: String {
        switch self {
        case .terminal(let event):
            return event.traceEventName
        case .terminalActivity(let event):
            return event.traceEventName
        case .browser(let event):
            return event.traceEventName
        case .diff(let event):
            return event.traceEventName
        case .editor(let event):
            return event.traceEventName
        case .agentNotificationRequested:
            return "agent.notificationRequested"
        case .plugin(_, let event):
            return "plugin.\(event.eventName.rawValue)"
        case .paneFilesystemContext(let event):
            return event.traceEventName
        case .lifecycle(let event):
            return event.traceName
        case .filesystem(let event):
            return event.traceName
        case .artifact(let event):
            return event.traceName
        case .security(let event):
            return event.traceName
        case .error(let event):
            return event.traceName
        }
    }
}

extension TerminalActivityEvent {
    var traceEventName: String {
        switch self {
        case .unseenActivitySettled:
            return "terminalActivity.unseenActivitySettled"
        }
    }
}

extension GhosttyEvent {
    var traceEventName: String {
        "terminal.\(eventName.rawValue)"
    }
}

extension BrowserEvent {
    var traceEventName: String {
        "browser.\(eventName.rawValue)"
    }
}

extension DiffEvent {
    var traceEventName: String {
        "diff.\(eventName.rawValue)"
    }
}

extension EditorEvent {
    var traceEventName: String {
        "editor.\(eventName.rawValue)"
    }
}

extension PaneFilesystemContextEvent {
    var traceEventName: String {
        "paneFilesystemContext.\(eventName.rawValue)"
    }
}

extension PaneLifecycleEvent {
    var traceName: String {
        switch self {
        case .surfaceCreated:
            return "lifecycle.surfaceCreated"
        case .sizeObserved:
            return "lifecycle.sizeObserved"
        case .sizeStabilized:
            return "lifecycle.sizeStabilized"
        case .attachStarted:
            return "lifecycle.attachStarted"
        case .attachSucceeded:
            return "lifecycle.attachSucceeded"
        case .attachFailed:
            return "lifecycle.attachFailed"
        case .paneClosed:
            return "lifecycle.paneClosed"
        case .activePaneChanged:
            return "lifecycle.activePaneChanged"
        case .drawerExpanded:
            return "lifecycle.drawerExpanded"
        case .drawerCollapsed:
            return "lifecycle.drawerCollapsed"
        case .tabSwitched:
            return "lifecycle.tabSwitched"
        }
    }
}

extension FilesystemEvent {
    var traceName: String {
        switch self {
        case .worktreeRegistered:
            return "filesystem.worktreeRegistered"
        case .worktreeUnregistered:
            return "filesystem.worktreeUnregistered"
        case .filesChanged:
            return "filesystem.filesChanged"
        case .gitSnapshotChanged:
            return "filesystem.gitSnapshotChanged"
        case .diffAvailable:
            return "filesystem.diffAvailable"
        case .branchChanged:
            return "filesystem.branchChanged"
        }
    }
}

extension ArtifactEvent {
    var traceName: String {
        switch self {
        case .diffProduced:
            return "artifact.diffProduced"
        case .approvalRequested:
            return "artifact.approvalRequested"
        case .approvalDecided:
            return "artifact.approvalDecided"
        }
    }
}

extension SecurityEvent {
    var traceName: String {
        switch self {
        case .networkEgressBlocked:
            return "security.networkEgressBlocked"
        case .filesystemAccessDenied:
            return "security.filesystemAccessDenied"
        case .secretAccessed:
            return "security.secretAccessed"
        case .processSpawnBlocked:
            return "security.processSpawnBlocked"
        case .sandboxStarted:
            return "security.sandboxStarted"
        case .sandboxStopped:
            return "security.sandboxStopped"
        case .sandboxHealthChanged:
            return "security.sandboxHealthChanged"
        }
    }
}

extension RuntimeErrorEvent {
    var traceName: String {
        switch self {
        case .surfaceCrashed:
            return "error.surfaceCrashed"
        case .commandTimeout:
            return "error.commandTimeout"
        case .commandDispatchFailed:
            return "error.commandDispatchFailed"
        case .adapterError:
            return "error.adapterError"
        case .resourceExhausted:
            return "error.resourceExhausted"
        case .internalStateCorrupted:
            return "error.internalStateCorrupted"
        }
    }
}

extension SystemScopedEvent {
    var traceEventName: String {
        switch self {
        case .topology(let event):
            return event.traceName
        case .appLifecycle(let event):
            return event.traceName
        case .focusChanged(let event):
            return event.traceName
        case .configChanged(let event):
            return event.traceName
        case .workspaceActivity(let event):
            return event.traceName
        }
    }
}

extension TopologyEvent {
    var traceName: String {
        switch self {
        case .repoDiscovered:
            return "topology.repoDiscovered"
        case .reposDiscovered:
            return "topology.reposDiscovered"
        case .repoRemoved:
            return "topology.repoRemoved"
        case .worktreeRegistered:
            return "topology.worktreeRegistered"
        case .worktreeUnregistered:
            return "topology.worktreeUnregistered"
        }
    }
}

extension AppLifecycleEvent {
    var traceName: String {
        switch self {
        case .appLaunched:
            return "appLifecycle.appLaunched"
        case .appTerminating:
            return "appLifecycle.appTerminating"
        case .tabSwitched:
            return "appLifecycle.tabSwitched"
        }
    }
}

extension FocusChangeEvent {
    var traceName: String {
        switch self {
        case .activePaneChanged:
            return "focusChanged.activePaneChanged"
        case .activeWorktreeChanged:
            return "focusChanged.activeWorktreeChanged"
        }
    }
}

extension ConfigChangeEvent {
    var traceName: String {
        switch self {
        case .watchedPathsUpdated:
            return "configChanged.watchedPathsUpdated"
        case .workspacePersistenceUpdated:
            return "configChanged.workspacePersistenceUpdated"
        }
    }
}

extension WorkspaceActivityEvent {
    var traceName: String {
        switch self {
        case .recentTargetOpened:
            return "workspaceActivity.recentTargetOpened"
        case .folderScanFinished:
            return "workspaceActivity.folderScanFinished"
        }
    }
}

extension WorktreeScopedEvent {
    var traceEventName: String {
        switch self {
        case .filesystem(let event):
            return event.traceName
        case .gitWorkingDirectory(let event):
            return event.traceName
        case .forge(let event):
            return event.traceName
        case .security(let event):
            return event.traceName
        }
    }
}

extension GitWorkingDirectoryEvent {
    var traceName: String {
        switch self {
        case .snapshotChanged:
            return "gitWorkingDirectory.snapshotChanged"
        case .branchChanged:
            return "gitWorkingDirectory.branchChanged"
        case .originChanged:
            return "gitWorkingDirectory.originChanged"
        case .originUnavailable:
            return "gitWorkingDirectory.originUnavailable"
        case .worktreeDiscovered:
            return "gitWorkingDirectory.worktreeDiscovered"
        case .worktreeRemoved:
            return "gitWorkingDirectory.worktreeRemoved"
        case .diffAvailable:
            return "gitWorkingDirectory.diffAvailable"
        }
    }
}

extension ForgeEvent {
    var traceName: String {
        switch self {
        case .pullRequestCountsChanged:
            return "forge.pullRequestCountsChanged"
        case .checksUpdated:
            return "forge.checksUpdated"
        case .refreshFailed:
            return "forge.refreshFailed"
        case .rateLimited:
            return "forge.rateLimited"
        }
    }
}
