import Foundation

@testable import AgentStudio

@MainActor
final class FakeAppCommandDispatcher: AppCommandDispatching {
    var availableCommands = Set(AppCommand.allCases)
    var dispatchedCommands: [AppCommand] = []
    var targetedDispatches: [(command: AppCommand, target: UUID, targetType: SearchItemType)] = []
    var bridgeTargetsByWorktreeId: [UUID: BridgePaneCommandTarget] = [:]
    var movePaneDispatches: [(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID)] = []

    func dispatch(_ command: AppCommand) {
        dispatchedCommands.append(command)
    }

    func dispatch(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        targetedDispatches.append((command, target, targetType))
    }

    func canDispatch(_ command: AppCommand) -> Bool {
        availableCommands.contains(command)
    }

    func canDispatch(_ command: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        availableCommands.contains(command)
    }

    func bridgePaneCommandTarget(worktreeId: UUID) -> BridgePaneCommandTarget? {
        bridgeTargetsByWorktreeId[worktreeId]
    }

    func dispatchMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID) {
        movePaneDispatches.append((sourcePaneId, sourceTabId, targetTabId))
    }
}
