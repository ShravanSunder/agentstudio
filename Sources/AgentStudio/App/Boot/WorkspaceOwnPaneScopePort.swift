import AgentStudioAppIPC
import AgentStudioCore
import Foundation

/// Reads an agent's own pane from the current pane graph: the bound pane and,
/// when it is a main-layout pane, its drawer children. A drawer terminal owns
/// only itself. One pane lookup per request; no I/O. Each decision's duration
/// goes to the performance recorder as `performance.ipc.agent_authorization`.
@MainActor
final class WorkspaceOwnPaneScopePort: AppIPCOwnPaneScopePort, @unchecked Sendable {
    private let workspaceStore: WorkspaceStore
    private nonisolated let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?

    init(workspaceStore: WorkspaceStore, performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?) {
        self.workspaceStore = workspaceStore
        self.performanceTraceRecorder = performanceTraceRecorder
    }

    nonisolated func recordAgentAuthorization(elapsed: Duration, outcome: AppIPCAgentAuthorizationOutcome) {
        performanceTraceRecorder?.recordDuration(
            .ipcAgentAuthorization,
            duration: elapsed,
            attributes: ["agentstudio.performance.ipc.agent_authorization.outcome": .string(outcome.rawValue)]
        )
    }

    func ownPaneScope(boundPaneId: UUID) -> AppIPCOwnPaneScope? {
        guard let pane = workspaceStore.paneAtom.pane(boundPaneId) else { return nil }
        return AppIPCOwnPaneScope(
            boundPaneId: boundPaneId,
            isDrawerTerminal: pane.isDrawerChild,
            drawerChildPaneIds: Set(pane.drawer?.paneIds ?? [])
        )
    }
}
