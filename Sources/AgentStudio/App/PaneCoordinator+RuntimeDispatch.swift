import Foundation

@MainActor
extension PaneCoordinator {
    func dispatchRuntimeCommand(
        _ command: RuntimeCommand,
        target: RuntimeCommandTarget,
        correlationId: UUID? = nil
    ) async -> ActionResult {
        guard let paneId = runtimeTargetResolver.resolve(target) else {
            return .failure(.invalidPayload(description: "Unable to resolve pane target"))
        }

        guard let runtime = runtimeRegistry.runtime(for: paneId) else {
            return .failure(.backendUnavailable(backend: "RuntimeRegistry"))
        }

        guard runtime.lifecycle == .ready else {
            return .failure(.runtimeNotReady(lifecycle: runtime.lifecycle))
        }

        if case .diff(let diffCommand) = command,
            case .loadDiff(let artifact) = diffCommand
        {
            guard runtime.metadata.worktreeId == artifact.worktreeId else {
                return .failure(
                    .invalidPayload(
                        description: "Diff artifact worktree does not match runtime worktree context"
                    )
                )
            }
        }

        if let requiredCapability = requiredCapability(for: command),
            !runtime.capabilities.contains(requiredCapability)
        {
            return .failure(
                .unsupportedCommand(
                    command: String(describing: command),
                    required: requiredCapability
                )
            )
        }

        let envelope = RuntimeCommandEnvelope(
            commandId: UUID(),
            correlationId: correlationId,
            targetPaneId: paneId,
            command: command,
            timestamp: runtimeCommandClock.now
        )
        return await runtime.handleCommand(envelope)
    }

    private func requiredCapability(for command: RuntimeCommand) -> PaneCapability? {
        switch command {
        case .activate, .deactivate, .prepareForClose, .requestSnapshot:
            return nil
        case .terminal(let terminalCommand):
            switch terminalCommand {
            case .sendInput, .clearScrollback:
                return .input
            case .resize:
                return .resize
            }
        case .browser:
            return .navigation
        case .diff:
            return .diffReview
        case .editor:
            return .editorActions
        case .plugin:
            return nil
        }
    }
}
