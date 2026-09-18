import Foundation

package struct IPCWorkspaceQueryMethodDescriptors: Sendable {
    package let windowList: IPCMethodDescriptor<IPCEmptyParams, IPCWindowListResult>
    package let windowCurrent: IPCMethodDescriptor<IPCEmptyParams, IPCCurrentWindowResult>
    package let workspaceList: IPCMethodDescriptor<IPCEmptyParams, IPCWorkspaceListResult>
    package let workspaceCurrent: IPCMethodDescriptor<IPCEmptyParams, IPCCurrentWorkspaceResult>
    package let paneList: IPCMethodDescriptor<IPCEmptyParams, IPCPaneListResult>
    package let paneCurrent: IPCMethodDescriptor<IPCEmptyParams, IPCPaneSnapshotResult>
    package let paneSnapshot: IPCMethodDescriptor<IPCPaneSelectorParams, IPCPaneSnapshotResult>

    init(examples: IPCBuiltInMethodExampleContext) throws {
        let window = IPCWindowSummary(
            id: examples.windowId,
            ordinal: 1,
            isKey: true,
            isFocused: true,
            isCurrent: true,
            workspaceId: examples.workspaceId
        )
        let worktree = IPCWorkspaceWorktreeSummary(
            id: examples.worktreeId,
            repoId: examples.repositoryId,
            name: "main",
            path: "/example/repository",
            isMainWorktree: true
        )
        let repository = IPCWorkspaceRepositorySummary(
            id: examples.repositoryId,
            name: "example-repository",
            path: "/example/repository",
            worktrees: [worktree]
        )
        let workspace = IPCWorkspaceSummary(
            id: examples.workspaceId,
            ordinal: 1,
            name: "Example Workspace",
            tabCount: 1,
            paneCount: 1,
            repositories: [repository],
            isCurrent: true
        )
        let tab = IPCTabSummary(
            id: examples.tabId,
            ordinal: 1,
            name: "Main",
            paneIds: [examples.paneId],
            activePaneId: examples.paneId,
            isActive: true
        )
        let pane = IPCPaneSummary(
            id: examples.paneId,
            ordinal: 1,
            contentKind: .terminal,
            residency: .active,
            tabId: examples.tabId,
            repoId: examples.repositoryId,
            worktreeId: examples.worktreeId,
            isActive: true,
            isDrawerChild: false
        )
        let paneResult = IPCPaneSnapshotResult(pane: pane, tab: tab, workspace: workspace)

        windowList = try Self.query(
            "window.list", "List workspace windows.", IPCWindowListResult(windows: [window]), .workspaceRead,
            .unspecified)
        windowCurrent = try Self.query(
            "window.current", "Read the current workspace window.", IPCCurrentWindowResult(window: window),
            .workspaceRead, .unspecified)
        workspaceList = try Self.query(
            "workspace.list", "List available workspaces.", IPCWorkspaceListResult(workspaces: [workspace]),
            .workspaceRead, .unspecified)
        workspaceCurrent = try Self.query(
            "workspace.current", "Read the current workspace.", IPCCurrentWorkspaceResult(workspace: workspace),
            .workspaceRead, .unspecified)
        paneList = try Self.query(
            "pane.list", "List panes in the selected runtime.", IPCPaneListResult(panes: [pane]),
            .paneContextRead, .paneContext)
        paneCurrent = try Self.query(
            "pane.current", "Read the current pane and its workspace context.", paneResult,
            .paneContextRead, .paneContext)
        paneSnapshot = try IPCBuiltInDescriptorSupport.read(
            name: "pane.snapshot",
            description: "Read one explicit pane and its workspace context.",
            parameters: IPCPaneSelectorParams(handle: "self"),
            result: paneResult,
            privilege: .paneContextRead,
            dataScope: .paneContext,
            targetKinds: [.pane],
            errors: [IPCBuiltInDescriptorSupport.invalidParams, IPCBuiltInDescriptorSupport.targetNotFound]
        )
    }

    private static func query<Result: IPCSchemaProviding>(
        _ name: String,
        _ description: String,
        _ result: Result,
        _ privilege: IPCPrivilegeClass,
        _ dataScope: IPCDataScope
    ) throws -> IPCMethodDescriptor<IPCEmptyParams, Result> {
        try IPCBuiltInDescriptorSupport.read(
            name: name,
            description: description,
            parameters: IPCEmptyParams(),
            result: result,
            privilege: privilege,
            dataScope: dataScope,
            errors: [IPCBuiltInDescriptorSupport.unavailable]
        )
    }

    var erased: [IPCAnyMethodDescriptor] {
        get throws {
            try [
                IPCAnyMethodDescriptor(erasing: windowList),
                IPCAnyMethodDescriptor(erasing: windowCurrent),
                IPCAnyMethodDescriptor(erasing: workspaceList),
                IPCAnyMethodDescriptor(erasing: workspaceCurrent),
                IPCAnyMethodDescriptor(erasing: paneList),
                IPCAnyMethodDescriptor(erasing: paneCurrent),
                IPCAnyMethodDescriptor(erasing: paneSnapshot),
            ]
        }
    }
}
