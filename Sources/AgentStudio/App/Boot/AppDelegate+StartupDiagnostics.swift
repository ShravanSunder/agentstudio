import Foundation

@MainActor
extension AppDelegate {
    func runStartupDiagnosticActionIfRequested() {
        guard let action = AgentStudioStartupDiagnosticAction.fromEnvironment() else { return }
        startupTraceRecorder.recordAppStartup(
            "app.startup_diagnostic_action.requested",
            phase: "startup_diagnostic_action",
            attributes: startupDiagnosticTraceAttributes(for: action)
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            self.startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.dispatched",
                phase: "startup_diagnostic_action",
                attributes: self.startupDiagnosticTraceAttributes(for: action)
            )
            switch action.kind {
            case .newTab:
                CommandDispatcher.shared.dispatch(.newTab)
            case .commandBarRepoFilter:
                CommandDispatcher.shared.dispatch(.showCommandBarEverything)
                await Task.yield()
                self.commandBarController.state.rawInput = "# repo"
            case .addWatchFolder:
                guard let folderURL = AgentStudioStartupDiagnosticAction.watchFolderURL() else {
                    self.startupTraceRecorder.recordAppStartup(
                        "app.startup_diagnostic_action.skipped",
                        phase: "startup_diagnostic_action",
                        attributes: self.startupDiagnosticTraceAttributes(for: action).merging([
                            "agentstudio.startup_diagnostic.skip_reason": .string("missing_watch_folder")
                        ]) { _, newValue in newValue }
                    )
                    return
                }
                await self.handleWatchFolderRequested(startingAt: folderURL)
            }
        }
    }

    private func startupDiagnosticTraceAttributes(
        for action: AgentStudioStartupDiagnosticAction
    ) -> [String: AgentStudioTraceValue] {
        [
            "agentstudio.command.source": .string("startup_diagnostic"),
            "agentstudio.command.name": .string(action.commandName),
            "agentstudio.startup_diagnostic.action": .string(action.kind.rawValue),
        ]
    }
}
