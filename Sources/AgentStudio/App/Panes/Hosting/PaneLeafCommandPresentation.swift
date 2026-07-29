import AgentStudioCore
import Foundation

@MainActor
struct PaneLeafCommandPresentation {
    let spec: AppCommandSpec
    let isEnabled: Bool

    private let targetPaneId: UUID
    private let targetType: SearchItemType
    private let dispatcher: any AppCommandDispatching

    static func resolve(
        command: AppCommand,
        surface: AppCommandSurface,
        targetPaneId: UUID,
        targetType: SearchItemType = .pane,
        dispatcher: any AppCommandDispatching
    ) -> Self? {
        let spec = command.definition
        guard
            spec.shouldPresent(
                AppCommandPresentationQuery(
                    surface: surface,
                    subject: .targeted(targetType)
                )
            )
        else {
            return nil
        }

        return Self(
            spec: spec,
            isEnabled: dispatcher.canDispatch(
                command,
                target: targetPaneId,
                targetType: targetType
            ),
            targetPaneId: targetPaneId,
            targetType: targetType,
            dispatcher: dispatcher
        )
    }

    func perform() {
        guard
            dispatcher.canDispatch(
                spec.command,
                target: targetPaneId,
                targetType: targetType
            )
        else {
            return
        }
        dispatcher.dispatch(
            spec.command,
            target: targetPaneId,
            targetType: targetType
        )
    }

    func movePane(sourceTabId: UUID?, targetTabId: UUID) {
        guard
            spec.command == .movePaneToTab,
            targetType == .pane,
            dispatcher.canDispatch(
                spec.command,
                target: targetPaneId,
                targetType: targetType
            )
        else {
            return
        }
        dispatcher.dispatchMovePaneToTab(
            sourcePaneId: targetPaneId,
            sourceTabId: sourceTabId,
            targetTabId: targetTabId
        )
    }
}
