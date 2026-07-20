import Foundation
import Observation
import os.log

private let paneFocusTrackerLogger = Logger(
    subsystem: "com.agentstudio",
    category: "PaneFocusTracker"
)

/// Observes the attended-pane derived read and publishes non-nil focus gains.
@MainActor
final class PaneFocusTracker {
    let focusGainedStream: AsyncStream<UUID>

    private let continuation: AsyncStream<UUID>.Continuation
    private let attendedPane: AttendedPaneDerived
    private let traceQueue: AgentStudioTraceEventQueue?
    private var lastAttendedPaneId: UUID?
    private var isStopped = false

    init(attendedPane: AttendedPaneDerived, traceRuntime: AgentStudioTraceRuntime? = nil) {
        self.attendedPane = attendedPane
        self.traceQueue = traceRuntime.map(AgentStudioTraceEventQueue.init(traceRuntime:))
        self.lastAttendedPaneId = attendedPane.attendedPaneId
        let (stream, continuation) = AsyncStream.makeStream(of: UUID.self)
        self.focusGainedStream = stream
        self.continuation = continuation
        observeAttendedPane()
    }

    func stop() async {
        if !isStopped {
            isStopped = true
            continuation.finish()
        }
        do {
            try await traceQueue?.drain()
        } catch {
            paneFocusTrackerLogger.warning(
                "Pane focus trace drain failed: \(error.localizedDescription)")
        }
    }

    deinit {
        continuation.finish()
        traceQueue?.cancel()
    }

    private func observeAttendedPane() {
        guard !isStopped else { return }
        withObservationTracking {
            _ = attendedPane.attendedPaneId
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isStopped else { return }
                self.publishTransitionIfNeeded()
                self.observeAttendedPane()
            }
        }
    }

    private func publishTransitionIfNeeded() {
        let updatedAttendedPaneId = attendedPane.attendedPaneId
        guard updatedAttendedPaneId != lastAttendedPaneId else { return }
        lastAttendedPaneId = updatedAttendedPaneId
        traceAttendedPaneTransition(updatedAttendedPaneId)
        guard let updatedAttendedPaneId else { return }
        continuation.yield(updatedAttendedPaneId)
    }

    private func traceAttendedPaneTransition(_ paneId: UUID?) {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.app.focus.attended": .bool(paneId != nil),
            "agentstudio.app.focus.source": .string("AttendedPaneDerived"),
        ]
        if let paneId {
            attributes["agentstudio.pane.id"] = .string(paneId.uuidString)
        }
        traceQueue?.record(
            tag: .appFocus,
            body: "app.focus.attendedPaneChanged",
            attributes: attributes
        )
    }
}
