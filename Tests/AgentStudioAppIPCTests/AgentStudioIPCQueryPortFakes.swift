import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

struct MethodCapabilitiesQueryPort: AppIPCQueryPort {
    let base: any AppIPCQueryPort
    let methodDefinitions: [IPCMethodDefinition]

    func systemIdentify() throws -> IPCSystemIdentifyResult {
        try base.systemIdentify()
    }

    func systemVersion() throws -> IPCSystemVersionResult {
        try base.systemVersion()
    }

    func systemCapabilities() throws -> IPCSystemCapabilitiesResult {
        IPCSystemCapabilitiesResult(methods: makeMethodCapabilities(from: methodDefinitions))
    }

    func listWindows() throws -> IPCWindowListResult {
        try base.listWindows()
    }

    func currentWindow() throws -> IPCCurrentWindowResult {
        try base.currentWindow()
    }

    func listWorkspaces() throws -> IPCWorkspaceListResult {
        try base.listWorkspaces()
    }

    func currentWorkspace() throws -> IPCCurrentWorkspaceResult {
        try base.currentWorkspace()
    }

    func listPanes() throws -> IPCPaneListResult {
        try base.listPanes()
    }

    func currentPane() throws -> IPCPaneSnapshotResult {
        try base.currentPane()
    }

    func snapshotPane(_ paneId: UUID) throws -> IPCPaneSnapshotResult {
        try base.snapshotPane(paneId)
    }
}

struct FakeQueryPort: AppIPCQueryPort {
    let runtimeId: UUID
    let panes: [IPCPaneSummary]
    let methodDefinitions: [IPCMethodDefinition]

    nonisolated init(
        runtimeId: UUID = UUID(),
        panes: [IPCPaneSummary] = [],
        methodDefinitions: [IPCMethodDefinition] = []
    ) {
        self.runtimeId = runtimeId
        self.panes = panes
        self.methodDefinitions = methodDefinitions
    }

    func systemIdentify() throws -> IPCSystemIdentifyResult {
        IPCSystemIdentifyResult(runtimeId: runtimeId, accessMode: .agentStudioOnly, appVersion: "test")
    }

    func systemVersion() throws -> IPCSystemVersionResult {
        IPCSystemVersionResult(appVersion: "test")
    }

    func systemCapabilities() throws -> IPCSystemCapabilitiesResult {
        IPCSystemCapabilitiesResult(methods: makeMethodCapabilities(from: methodDefinitions))
    }

    func listWindows() throws -> IPCWindowListResult {
        IPCWindowListResult(windows: [])
    }

    func currentWindow() throws -> IPCCurrentWindowResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func listWorkspaces() throws -> IPCWorkspaceListResult {
        IPCWorkspaceListResult(workspaces: [])
    }

    func currentWorkspace() throws -> IPCCurrentWorkspaceResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func listPanes() throws -> IPCPaneListResult {
        IPCPaneListResult(panes: panes)
    }

    func currentPane() throws -> IPCPaneSnapshotResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func snapshotPane(_: UUID) throws -> IPCPaneSnapshotResult {
        throw AppIPCQueryError(reason: .targetNotFound)
    }
}

final class RecordingSnapshotQueryPort: AppIPCQueryPort, @unchecked Sendable {
    let runtimeId: UUID
    let panes: [IPCPaneSummary]
    let methodDefinitions: [IPCMethodDefinition]
    private let lock = NSLock()
    nonisolated(unsafe) private var snapshotPaneIdsStorage: [UUID] = []

    nonisolated init(
        runtimeId: UUID = UUID(),
        panes: [IPCPaneSummary],
        methodDefinitions: [IPCMethodDefinition] = []
    ) {
        self.runtimeId = runtimeId
        self.panes = panes
        self.methodDefinitions = methodDefinitions
    }

    nonisolated var snapshotPaneIds: [UUID] {
        lock.withLock {
            snapshotPaneIdsStorage
        }
    }

    func systemIdentify() throws -> IPCSystemIdentifyResult {
        IPCSystemIdentifyResult(runtimeId: runtimeId, accessMode: .agentStudioOnly, appVersion: "test")
    }

    func systemVersion() throws -> IPCSystemVersionResult {
        IPCSystemVersionResult(appVersion: "test")
    }

    func systemCapabilities() throws -> IPCSystemCapabilitiesResult {
        IPCSystemCapabilitiesResult(methods: makeMethodCapabilities(from: methodDefinitions))
    }

    func listWindows() throws -> IPCWindowListResult {
        IPCWindowListResult(windows: [])
    }

    func currentWindow() throws -> IPCCurrentWindowResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func listWorkspaces() throws -> IPCWorkspaceListResult {
        IPCWorkspaceListResult(workspaces: [])
    }

    func currentWorkspace() throws -> IPCCurrentWorkspaceResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func listPanes() throws -> IPCPaneListResult {
        IPCPaneListResult(panes: panes)
    }

    func currentPane() throws -> IPCPaneSnapshotResult {
        guard let pane = panes.first else {
            throw AppIPCQueryError(reason: .targetNotFound)
        }
        return makePaneSnapshotResult(pane: pane, paneCount: panes.count)
    }

    func snapshotPane(_ paneId: UUID) throws -> IPCPaneSnapshotResult {
        lock.withLock {
            snapshotPaneIdsStorage.append(paneId)
        }
        guard let pane = panes.first(where: { $0.id == paneId }) else {
            throw AppIPCQueryError(reason: .targetNotFound)
        }
        return makePaneSnapshotResult(pane: pane, paneCount: panes.count)
    }
}

private func makeMethodCapabilities(from methodDefinitions: [IPCMethodDefinition]) -> [IPCMethodCapability] {
    methodDefinitions
        .sorted { lhs, rhs in lhs.name < rhs.name }
        .map { definition in
            IPCMethodCapability(
                name: definition.name,
                privilegeClasses: definition.privilegeClasses.sorted { lhs, rhs in lhs.rawValue < rhs.rawValue },
                principalAvailability: definition.principalAvailability,
                executionOwner: definition.executionOwner,
                resultSemantics: definition.resultSemantics
            )
        }
}
