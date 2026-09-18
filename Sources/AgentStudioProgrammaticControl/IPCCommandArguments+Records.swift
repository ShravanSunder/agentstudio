import Foundation

package struct IPCWorkspaceWindowCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID

    package init(workspaceWindowId: UUID) {
        self.workspaceWindowId = workspaceWindowId
    }
}

package struct IPCTabCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let tabId: UUID

    package init(workspaceWindowId: UUID, tabId: UUID) {
        self.workspaceWindowId = workspaceWindowId
        self.tabId = tabId
    }
}

package struct IPCRenamedTabCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let tabId: UUID
    package let name: String

    package init(workspaceWindowId: UUID, tabId: UUID, name: String) {
        self.workspaceWindowId = workspaceWindowId
        self.tabId = tabId
        self.name = name
    }
}

package struct IPCNewTabCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let launchDirectory: String?

    package init(workspaceWindowId: UUID, launchDirectory: String?) {
        self.workspaceWindowId = workspaceWindowId
        self.launchDirectory = launchDirectory
    }
}

package struct IPCTabAnchorCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let anchorTabId: UUID

    package init(workspaceWindowId: UUID, anchorTabId: UUID) {
        self.workspaceWindowId = workspaceWindowId
        self.anchorTabId = anchorTabId
    }
}

package struct IPCPaneCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let paneSelector: IPCPaneSelector

    package init(workspaceWindowId: UUID, paneSelector: IPCPaneSelector) {
        self.workspaceWindowId = workspaceWindowId
        self.paneSelector = paneSelector
    }
}

package struct IPCSourcePaneCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let sourcePaneSelector: IPCPaneSelector

    package init(workspaceWindowId: UUID, sourcePaneSelector: IPCPaneSelector) {
        self.workspaceWindowId = workspaceWindowId
        self.sourcePaneSelector = sourcePaneSelector
    }
}

package struct IPCMovePaneToTabCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let sourcePaneSelector: IPCPaneSelector
    package let destinationTabId: UUID

    package init(workspaceWindowId: UUID, sourcePaneSelector: IPCPaneSelector, destinationTabId: UUID) {
        self.workspaceWindowId = workspaceWindowId
        self.sourcePaneSelector = sourcePaneSelector
        self.destinationTabId = destinationTabId
    }
}

package struct IPCArrangementCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let tabId: UUID
    package let arrangementId: UUID

    package init(workspaceWindowId: UUID, tabId: UUID, arrangementId: UUID) {
        self.workspaceWindowId = workspaceWindowId
        self.tabId = tabId
        self.arrangementId = arrangementId
    }
}

package struct IPCNewArrangementCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let tabId: UUID
    package let name: String

    package init(workspaceWindowId: UUID, tabId: UUID, name: String) {
        self.workspaceWindowId = workspaceWindowId
        self.tabId = tabId
        self.name = name
    }
}

package struct IPCRenamedArrangementCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let tabId: UUID
    package let arrangementId: UUID
    package let name: String

    package init(workspaceWindowId: UUID, tabId: UUID, arrangementId: UUID, name: String) {
        self.workspaceWindowId = workspaceWindowId
        self.tabId = tabId
        self.arrangementId = arrangementId
        self.name = name
    }
}

package struct IPCDrawerParentCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let parentPaneSelector: IPCPaneSelector

    package init(workspaceWindowId: UUID, parentPaneSelector: IPCPaneSelector) {
        self.workspaceWindowId = workspaceWindowId
        self.parentPaneSelector = parentPaneSelector
    }
}

package struct IPCDrawerSourcePaneCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let parentPaneSelector: IPCPaneSelector
    package let sourceDrawerPaneSelector: IPCPaneSelector

    package init(
        workspaceWindowId: UUID,
        parentPaneSelector: IPCPaneSelector,
        sourceDrawerPaneSelector: IPCPaneSelector
    ) {
        self.workspaceWindowId = workspaceWindowId
        self.parentPaneSelector = parentPaneSelector
        self.sourceDrawerPaneSelector = sourceDrawerPaneSelector
    }
}

package struct IPCDrawerPaneCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let parentPaneSelector: IPCPaneSelector
    package let drawerPaneSelector: IPCPaneSelector

    package init(
        workspaceWindowId: UUID,
        parentPaneSelector: IPCPaneSelector,
        drawerPaneSelector: IPCPaneSelector
    ) {
        self.workspaceWindowId = workspaceWindowId
        self.parentPaneSelector = parentPaneSelector
        self.drawerPaneSelector = drawerPaneSelector
    }
}

package struct IPCDetachedDrawerPaneCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let drawerPaneSelector: IPCPaneSelector

    package init(workspaceWindowId: UUID, drawerPaneSelector: IPCPaneSelector) {
        self.workspaceWindowId = workspaceWindowId
        self.drawerPaneSelector = drawerPaneSelector
    }
}

package struct IPCDirectoryCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let directoryPath: String

    package init(workspaceWindowId: UUID, directoryPath: String) {
        self.workspaceWindowId = workspaceWindowId
        self.directoryPath = directoryPath
    }
}

package struct IPCRepositoryCommandArguments: Codable, Equatable, Sendable {
    package let repoId: UUID

    package init(repoId: UUID) {
        self.repoId = repoId
    }
}

package struct IPCStandalonePaneCommandArguments: Codable, Equatable, Sendable {
    package let paneSelector: IPCPaneSelector

    package init(paneSelector: IPCPaneSelector) {
        self.paneSelector = paneSelector
    }
}

package struct IPCWorktreeCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let worktreeId: UUID

    package init(workspaceWindowId: UUID, worktreeId: UUID) {
        self.workspaceWindowId = workspaceWindowId
        self.worktreeId = worktreeId
    }
}

package struct IPCWorktreeInPaneCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let worktreeId: UUID
    package let targetPaneSelector: IPCPaneSelector

    package init(workspaceWindowId: UUID, worktreeId: UUID, targetPaneSelector: IPCPaneSelector) {
        self.workspaceWindowId = workspaceWindowId
        self.worktreeId = worktreeId
        self.targetPaneSelector = targetPaneSelector
    }
}

package struct IPCTerminalFromWorktreeCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let worktreeId: UUID
    package let launchDirectory: String?
    package let title: String?

    package init(workspaceWindowId: UUID, worktreeId: UUID, launchDirectory: String?, title: String?) {
        self.workspaceWindowId = workspaceWindowId
        self.worktreeId = worktreeId
        self.launchDirectory = launchDirectory
        self.title = title
    }
}

package struct IPCTerminalFromPaneCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let sourcePaneSelector: IPCPaneSelector
    package let launchDirectory: String?
    package let title: String?

    package init(
        workspaceWindowId: UUID,
        sourcePaneSelector: IPCPaneSelector,
        launchDirectory: String?,
        title: String?
    ) {
        self.workspaceWindowId = workspaceWindowId
        self.sourcePaneSelector = sourcePaneSelector
        self.launchDirectory = launchDirectory
        self.title = title
    }
}

package struct IPCManagementFromMainPaneCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let mainPaneSelector: IPCPaneSelector

    package init(workspaceWindowId: UUID, mainPaneSelector: IPCPaneSelector) {
        self.workspaceWindowId = workspaceWindowId
        self.mainPaneSelector = mainPaneSelector
    }
}

package struct IPCManagementFromDrawerPaneCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let parentPaneSelector: IPCPaneSelector
    package let drawerPaneSelector: IPCPaneSelector

    package init(
        workspaceWindowId: UUID,
        parentPaneSelector: IPCPaneSelector,
        drawerPaneSelector: IPCPaneSelector
    ) {
        self.workspaceWindowId = workspaceWindowId
        self.parentPaneSelector = parentPaneSelector
        self.drawerPaneSelector = drawerPaneSelector
    }
}

package struct IPCFloatingTerminalCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let launchDirectory: String?
    package let title: String?

    package init(workspaceWindowId: UUID, launchDirectory: String?, title: String?) {
        self.workspaceWindowId = workspaceWindowId
        self.launchDirectory = launchDirectory
        self.title = title
    }
}

package struct IPCWebviewCommandArguments: Codable, Equatable, Sendable {
    package let workspaceWindowId: UUID
    package let url: String

    package init(workspaceWindowId: UUID, url: String = "https://github.com") {
        self.workspaceWindowId = workspaceWindowId
        self.url = url
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceWindowId = try container.decode(UUID.self, forKey: .workspaceWindowId)
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? "https://github.com"
    }
}
