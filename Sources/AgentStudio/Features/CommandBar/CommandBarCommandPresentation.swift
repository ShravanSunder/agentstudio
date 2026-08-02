import AgentStudioCore

package typealias CommandBarTargetedSpecResolver =
    @Sendable (AppCommand, SearchItemType) -> AppCommandSpec?
package typealias CommandBarCommandSpecResolver = @Sendable (AppCommand) -> AppCommandSpec

package enum CommandBarWorktreeTerminalPlacement: Sendable {
    case currentTabPane
    case newTab
}

/// Catalog-backed admission for command rows owned by non-root Command Bar scopes.
package enum CommandBarCommandPresentation {
    package static let catalogTargetedSpecResolver: CommandBarTargetedSpecResolver = { command, targetType in
        commandBarTargetedSpec(for: command, targetType: targetType)
    }

    package static func contextualSpec(
        for command: AppCommand,
        commandContext: CommandContext
    ) -> AppCommandSpec? {
        let commandSpec = command.definition
        guard commandSpec.targeting.preferredInvocation == .contextual else {
            return nil
        }
        let query = AppCommandPresentationQuery(
            surface: .commandBar,
            subject: .contextual(commandContext)
        )
        return commandSpec.shouldPresent(query) ? commandSpec : nil
    }

    package static func targetedSpec(
        for command: AppCommand,
        targetType: SearchItemType
    ) -> AppCommandSpec? {
        let commandSpec = command.definition
        return commandSpec.targeting.supports(targetType: targetType) ? commandSpec : nil
    }

    package static func commandBarTargetedSpec(
        for command: AppCommand,
        targetType: SearchItemType,
        definitionResolver: CommandBarCommandSpecResolver = { $0.definition }
    ) -> AppCommandSpec? {
        let commandSpec = definitionResolver(command)
        let query = AppCommandPresentationQuery(
            surface: .commandBar,
            subject: .targeted(targetType)
        )
        return commandSpec.shouldPresent(query) ? commandSpec : nil
    }

    package static func targetedWorktreeTerminalSpec(
        for placement: CommandBarWorktreeTerminalPlacement,
        targetedSpecResolver: CommandBarTargetedSpecResolver = catalogTargetedSpecResolver
    ) -> AppCommandSpec? {
        let command =
            switch placement {
            case .currentTabPane:
                AppCommand.openWorktreeInPane
            case .newTab:
                AppCommand.openNewTerminalInTab
            }
        return targetedSpecResolver(command, .worktree)
    }
}
