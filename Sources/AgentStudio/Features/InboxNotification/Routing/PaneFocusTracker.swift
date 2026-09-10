import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation
import Observation
import os.log

private let paneFocusTrackerLogger = Logger(
    subsystem: "com.agentstudio",
    category: "PaneFocusTracker"
)

/// Observes the attended-pane derived read and publishes non-nil focus gains.
@MainActor
package final class PaneFocusTracker {
    let focusGainedStream: AsyncStream<UUID>

    private let continuation: AsyncStream<UUID>.Continuation
    private let attendedPane: AttendedPaneDerived
    private let traceQueue: AgentStudioTraceEventQueue?
    private var lastAttendedPaneId: UUID?
    private var isStopped = false
    private var observationGeneration = 0
    private var pendingDeliveryTask: Task<Void, Never>?

    package init(attendedPane: AttendedPaneDerived, traceRuntime: AgentStudioTraceRuntime? = nil) {
        self.attendedPane = attendedPane
        self.traceQueue = traceRuntime.map(AgentStudioTraceEventQueue.init(traceRuntime:))
        self.lastAttendedPaneId = attendedPane.attendedPaneId
        let (stream, continuation) = AsyncStream.makeStream(of: UUID.self)
        self.focusGainedStream = stream
        self.continuation = continuation
        observeAttendedPane()
    }

    package func stop() async {
        if !isStopped {
            isStopped = true
            observationGeneration += 1
            pendingDeliveryTask?.cancel()
            pendingDeliveryTask = nil
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
        pendingDeliveryTask?.cancel()
        continuation.finish()
        traceQueue?.cancel()
    }

    private func observeAttendedPane() {
        guard !isStopped else { return }
        observationGeneration += 1
        let generation = observationGeneration
        withObservationTracking {
            _ = attendedPane.attendedPaneId
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isStopped, self.observationGeneration == generation else { return }
                self.scheduleSettledDelivery()
            }
        }
    }

    private func scheduleSettledDelivery() {
        guard pendingDeliveryTask == nil else { return }
        pendingDeliveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.pendingDeliveryTask = nil
            guard !Task.isCancelled, !self.isStopped else { return }
            self.observeAttendedPane()
            self.publishTransitionIfNeeded()
        }
    }

    package func waitForPendingDelivery() async {
        await pendingDeliveryTask?.value
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
