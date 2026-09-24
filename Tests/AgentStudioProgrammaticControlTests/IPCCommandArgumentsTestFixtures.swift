import AgentStudioProgrammaticControl
import Foundation

enum IPCCommandArgumentsTestFixtures {
    static let workspaceWindowId = uuid("01994abc-1000-7000-8000-000000000001")
    static let tabId = uuid("01994abc-1000-7000-8000-000000000002")
    static let destinationTabId = uuid("01994abc-1000-7000-8000-000000000003")
    static let arrangementId = uuid("01994abc-1000-7000-8000-000000000004")
    static let repoId = uuid("01994abc-1000-7000-8000-000000000005")
    static let worktreeId = uuid("01994abc-1000-7000-8000-000000000006")

    static func paneSelector(_ rawValue: String = "pane:3") throws -> IPCPaneSelector {
        try IPCPaneSelector(rawValue: rawValue)
    }

    static func allArguments() throws -> [IPCCommandArguments] {
        try tabArguments()
            + paneAndArrangementArguments()
            + drawerAndRepositoryArguments()
            + creationAndManagementArguments()
    }

    private static func tabArguments() -> [IPCCommandArguments] {
        [
            .noArguments,
            .workspaceWindow(
                IPCWorkspaceWindowCommandArguments(workspaceWindowId: workspaceWindowId)
            ),
            .tab(
                IPCTabCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    tabId: tabId
                )
            ),
            .renamedTab(
                IPCRenamedTabCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    tabId: tabId,
                    name: "Review Queue"
                )
            ),
            .newTab(
                IPCNewTabCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    launchDirectory: nil
                )
            ),
            .tabAnchor(
                IPCTabAnchorCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    anchorTabId: tabId
                )
            ),
        ]
    }

    private static func paneAndArrangementArguments() throws -> [IPCCommandArguments] {
        [
            .pane(
                IPCPaneCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    paneSelector: try paneSelector("self")
                )
            ),
            .sourcePane(
                IPCSourcePaneCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    sourcePaneSelector: try paneSelector()
                )
            ),
            .movePaneToTab(
                IPCMovePaneToTabCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    sourcePaneSelector: try paneSelector(),
                    destinationTabId: destinationTabId
                )
            ),
            .arrangement(
                IPCArrangementCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    tabId: tabId,
                    arrangementId: arrangementId
                )
            ),
            .newArrangement(
                IPCNewArrangementCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    tabId: tabId,
                    name: "Pairing"
                )
            ),
            .renamedArrangement(
                IPCRenamedArrangementCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    tabId: tabId,
                    arrangementId: arrangementId,
                    name: "Launch"
                )
            ),
        ]
    }

    private static func drawerAndRepositoryArguments() throws -> [IPCCommandArguments] {
        [
            .drawerParent(
                IPCDrawerParentCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    parentPaneSelector: try paneSelector("self")
                )
            ),
            .drawerSourcePane(
                IPCDrawerSourcePaneCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    parentPaneSelector: try paneSelector("pane:2"),
                    sourceDrawerPaneSelector: try paneSelector("pane:3")
                )
            ),
            .drawerPane(
                IPCDrawerPaneCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    parentPaneSelector: try paneSelector("pane:2"),
                    drawerPaneSelector: try paneSelector("pane:3")
                )
            ),
            .detachedDrawerPane(
                IPCDetachedDrawerPaneCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    drawerPaneSelector: try paneSelector()
                )
            ),
            .directory(
                IPCDirectoryCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    directoryPath: "/tmp/project"
                )
            ),
            .repository(IPCRepositoryCommandArguments(repoId: repoId)),
            .standalonePane(
                IPCStandalonePaneCommandArguments(paneSelector: try paneSelector("self"))
            ),
        ]
    }

    private static func creationAndManagementArguments() throws -> [IPCCommandArguments] {
        [
            .worktree(
                IPCWorktreeCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    worktreeId: worktreeId
                )
            ),
            .worktreeInPane(
                IPCWorktreeInPaneCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    worktreeId: worktreeId,
                    targetPaneSelector: try paneSelector()
                )
            ),
            .bridgeDocumentInPane(
                IPCBridgeDocumentInPaneCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    targetPaneSelector: try paneSelector(),
                    path: "/tmp/project/notes.md"
                )
            ),
            .terminalFromWorktree(
                IPCTerminalFromWorktreeCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    worktreeId: worktreeId,
                    launchDirectory: "/tmp/project",
                    title: "Build"
                )
            ),
            .terminalFromPane(
                IPCTerminalFromPaneCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    sourcePaneSelector: try paneSelector(),
                    launchDirectory: "/tmp/project",
                    title: "Build"
                )
            ),
            .managementFromMainPane(
                IPCManagementFromMainPaneCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    mainPaneSelector: try paneSelector("self")
                )
            ),
            .managementFromDrawerPane(
                IPCManagementFromDrawerPaneCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    parentPaneSelector: try paneSelector("pane:2"),
                    drawerPaneSelector: try paneSelector("pane:3")
                )
            ),
            .floatingTerminal(
                IPCFloatingTerminalCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    launchDirectory: nil,
                    title: nil
                )
            ),
            .webview(
                IPCWebviewCommandArguments(
                    workspaceWindowId: workspaceWindowId,
                    url: "https://github.com"
                )
            ),
        ]
    }

    static func encodedObject(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private static func uuid(_ rawValue: String) -> UUID {
        guard let identifier = UUID(uuidString: rawValue) else {
            preconditionFailure("Invalid command-argument fixture UUID")
        }
        return identifier
    }
}
