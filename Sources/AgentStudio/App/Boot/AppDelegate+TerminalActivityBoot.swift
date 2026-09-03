import AgentStudioCore
import AgentStudioTerminal
import Foundation

extension AppDelegate {
    func bootStartTerminalActivityRouter(bus: EventBus<RuntimeEnvelope>) {
        terminalActivityRouter = TerminalActivityRouter(
            bus: bus,
            activityAtom: atomStore.terminalActivity,
            attendedPane: atomStore.core.attendedPane,
            traceRuntime: traceRuntime,
            startupTraceRecorder: startupTraceRecorder,
            isPaneCurrentlyAttended: { [weak self] paneId in
                self?.isPaneCurrentlyAttendedForTerminalActivity(paneId) ?? false
            },
            isPaneAgentClassified: { [weak self] paneId, paneKind in
                if paneKind == .agent { return true }
                return self?.store.paneAtom.pane(paneId)?.metadata.contentType == .agent
            },
            recordSettledActivityStatus: { [weak self] paneId, lastOutputLine in
                self?.atomStore.core.paneActivityStatus.recordSettledActivity(
                    paneId: paneId,
                    lastOutputLine: lastOutputLine
                )
            },
            clearPaneActivityStatus: { [weak self] paneId in
                self?.atomStore.core.paneActivityStatus.clear(paneId: paneId)
            }
        )
        Task { @MainActor [weak self] in
            await self?.terminalActivityRouter.start()
        }
    }

    private func isPaneCurrentlyAttendedForTerminalActivity(_ paneId: UUID) -> Bool {
        PaneObservationResolver.isPaneCurrentlyAttended(
            paneId: paneId,
            attendedPaneId: atomStore.core.attendedPane.attendedPaneId,
            pane: { store.paneAtom.pane($0) }
        )
    }
}
