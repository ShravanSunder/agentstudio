import AgentStudioRepoExplorer
import Foundation

@testable import AgentStudio
@testable import AgentStudioCommandBar
@testable import AgentStudioCore

@MainActor
final class MockCommandHandler: WorkspaceCommandHandling {
    var executedCommands: [(AppCommand, UUID?, SearchItemType?)] = []
    var quickOpenDirectoryRequests: [(directory: URL, placement: QuickOpenDirectoryPlacement)] = []
    var canExecuteResult: Bool = true
    var targetedCanExecuteResult: Bool?
    var extractedPaneRequests: [(tabId: UUID, paneId: UUID, targetTabIndex: Int?)] = []
    var movePaneRequests: [(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID)] = []
    var repoExplorerCapabilityRequestBatches: [Set<RepoExplorerCommandPresentationRequest>] = []

    func execute(_ command: AppCommand) {
        executedCommands.append((command, nil, nil))
    }

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        executedCommands.append((command, target, targetType))
    }

    func executeQuickOpenDirectory(_ directory: URL, placement: QuickOpenDirectoryPlacement) {
        quickOpenDirectoryRequests.append((directory, placement))
    }

    func canExecute(_ command: AppCommand) -> Bool {
        canExecuteResult
    }

    func canExecute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool {
        _ = command
        _ = target
        _ = targetType
        return targetedCanExecuteResult ?? canExecuteResult
    }

    func repoExplorerCommandCapabilities(
        _ requests: Set<RepoExplorerCommandPresentationRequest>
    ) -> [RepoExplorerCommandPresentationRequest: Bool] {
        repoExplorerCapabilityRequestBatches.append(requests)
        return Dictionary(uniqueKeysWithValues: requests.map { ($0, true) })
    }

    func executeExtractPaneToTab(tabId: UUID, paneId: UUID, targetTabIndex: Int?) {
        extractedPaneRequests.append((tabId, paneId, targetTabIndex))
    }

    func executeMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID) {
        movePaneRequests.append((sourcePaneId, sourceTabId, targetTabId))
    }
}
