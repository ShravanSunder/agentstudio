import Foundation

public struct IPCSystemIdentifyResult: Codable, Equatable, Sendable {
    public let runtimeId: UUID
    public let accessMode: IPCAccessMode
    public let appVersion: String

    public init(runtimeId: UUID, accessMode: IPCAccessMode, appVersion: String) {
        self.runtimeId = runtimeId
        self.accessMode = accessMode
        self.appVersion = appVersion
    }
}

public struct IPCSystemVersionResult: Codable, Equatable, Sendable {
    public let appVersion: String

    public init(appVersion: String) {
        self.appVersion = appVersion
    }
}

public struct IPCMethodCapability: Codable, Equatable, Sendable {
    public let name: String
    public let privilegeClasses: [IPCPrivilegeClass]
    public let principalAvailability: IPCPrincipalAvailability
    public let executionOwner: IPCExecutionOwner
    public let resultSemantics: IPCResultSemantics

    public init(
        name: String,
        privilegeClasses: [IPCPrivilegeClass],
        principalAvailability: IPCPrincipalAvailability,
        executionOwner: IPCExecutionOwner,
        resultSemantics: IPCResultSemantics
    ) {
        self.name = name
        self.privilegeClasses = privilegeClasses
        self.principalAvailability = principalAvailability
        self.executionOwner = executionOwner
        self.resultSemantics = resultSemantics
    }
}

public struct IPCSystemCapabilitiesResult: Codable, Equatable, Sendable {
    public let methods: [IPCMethodCapability]

    public init(methods: [IPCMethodCapability]) {
        self.methods = methods
    }
}

public struct IPCWindowSummary: Codable, Equatable, Sendable {
    public let id: UUID
    public let ordinal: Int
    public let isKey: Bool
    public let isFocused: Bool
    public let isCurrent: Bool
    public let workspaceId: UUID

    public init(id: UUID, ordinal: Int, isKey: Bool, isFocused: Bool, isCurrent: Bool, workspaceId: UUID) {
        self.id = id
        self.ordinal = ordinal
        self.isKey = isKey
        self.isFocused = isFocused
        self.isCurrent = isCurrent
        self.workspaceId = workspaceId
    }
}

public struct IPCWindowListResult: Codable, Equatable, Sendable {
    public let windows: [IPCWindowSummary]

    public init(windows: [IPCWindowSummary]) {
        self.windows = windows
    }
}

public struct IPCCurrentWindowResult: Codable, Equatable, Sendable {
    public let window: IPCWindowSummary

    public init(window: IPCWindowSummary) {
        self.window = window
    }
}

public struct IPCWorkspaceSummary: Codable, Equatable, Sendable {
    public let id: UUID
    public let ordinal: Int
    public let name: String
    public let tabCount: Int
    public let paneCount: Int
    public let isCurrent: Bool

    public init(id: UUID, ordinal: Int, name: String, tabCount: Int, paneCount: Int, isCurrent: Bool) {
        self.id = id
        self.ordinal = ordinal
        self.name = name
        self.tabCount = tabCount
        self.paneCount = paneCount
        self.isCurrent = isCurrent
    }
}

public struct IPCWorkspaceListResult: Codable, Equatable, Sendable {
    public let workspaces: [IPCWorkspaceSummary]

    public init(workspaces: [IPCWorkspaceSummary]) {
        self.workspaces = workspaces
    }
}

public struct IPCCurrentWorkspaceResult: Codable, Equatable, Sendable {
    public let workspace: IPCWorkspaceSummary

    public init(workspace: IPCWorkspaceSummary) {
        self.workspace = workspace
    }
}

public struct IPCTabSummary: Codable, Equatable, Sendable {
    public let id: UUID
    public let ordinal: Int
    public let name: String
    public let paneIds: [UUID]
    public let activePaneId: UUID?
    public let isActive: Bool

    public init(id: UUID, ordinal: Int, name: String, paneIds: [UUID], activePaneId: UUID?, isActive: Bool) {
        self.id = id
        self.ordinal = ordinal
        self.name = name
        self.paneIds = paneIds
        self.activePaneId = activePaneId
        self.isActive = isActive
    }
}

public enum IPCPaneContentKind: String, Codable, Equatable, Sendable {
    case terminal
    case webview
    case bridgePanel
    case codeViewer
    case unsupported
}

public enum IPCPaneResidency: String, Codable, Equatable, Sendable {
    case active
    case pendingUndo
    case backgrounded
    case orphaned
}

public struct IPCPaneSummary: Codable, Equatable, Sendable {
    public let id: UUID
    public let ordinal: Int
    public let title: String
    public let contentKind: IPCPaneContentKind
    public let residency: IPCPaneResidency
    public let tabId: UUID?
    public let repoId: UUID?
    public let worktreeId: UUID?
    public let isActive: Bool
    public let isDrawerChild: Bool

    public init(
        id: UUID,
        ordinal: Int,
        title: String,
        contentKind: IPCPaneContentKind,
        residency: IPCPaneResidency,
        tabId: UUID?,
        repoId: UUID?,
        worktreeId: UUID?,
        isActive: Bool,
        isDrawerChild: Bool
    ) {
        self.id = id
        self.ordinal = ordinal
        self.title = title
        self.contentKind = contentKind
        self.residency = residency
        self.tabId = tabId
        self.repoId = repoId
        self.worktreeId = worktreeId
        self.isActive = isActive
        self.isDrawerChild = isDrawerChild
    }
}

public struct IPCPaneListResult: Codable, Equatable, Sendable {
    public let panes: [IPCPaneSummary]

    public init(panes: [IPCPaneSummary]) {
        self.panes = panes
    }
}

public struct IPCPaneSnapshotResult: Codable, Equatable, Sendable {
    public let pane: IPCPaneSummary
    public let tab: IPCTabSummary?
    public let workspace: IPCWorkspaceSummary

    public init(pane: IPCPaneSummary, tab: IPCTabSummary?, workspace: IPCWorkspaceSummary) {
        self.pane = pane
        self.tab = tab
        self.workspace = workspace
    }
}

public struct IPCPaneFocusResult: Codable, Equatable, Sendable {
    public let paneId: UUID
    public let focused: Bool

    public init(paneId: UUID, focused: Bool) {
        self.paneId = paneId
        self.focused = focused
    }
}
