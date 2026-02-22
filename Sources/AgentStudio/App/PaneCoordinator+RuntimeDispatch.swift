import Foundation

@MainActor
extension PaneCoordinator {
    func dispatchRuntimeCommand(
        _ command: PaneCommand,
        target: PaneCommandTarget,
        correlationId: UUID? = nil
    ) async -> ActionResult {
        guard let paneId = paneTargetResolver.resolve(target) else {
            return .failure(.invalidPayload(description: "Unable to resolve pane target"))
        }

        guard let runtime = runtimeRegistry.runtime(for: paneId) else {
            return .failure(.backendUnavailable(backend: "RuntimeRegistry"))
        }

        let envelope = PaneCommandEnvelope(
            commandId: UUID(),
            correlationId: correlationId,
            targetPaneId: paneId,
            command: command,
            timestamp: runtimeCommandClock.now
        )
        return await runtime.handleCommand(envelope)
    }
}
