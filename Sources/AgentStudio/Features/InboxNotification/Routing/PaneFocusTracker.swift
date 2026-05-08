import Foundation
import os.log

private let paneFocusTrackerLogger = Logger(
    subsystem: "com.agentstudio",
    category: "PaneFocusTracker"
)

/// Narrows attended-pane transitions down to non-nil focus-gained pane ids.
///
/// `AttendedPaneAtom` owns the composite "what pane is currently attended?" model.
/// The router only needs gained pane ids for auto-dismiss behavior, so this bridge
/// keeps that feature concern local without re-deriving attention semantics.
@MainActor
final class PaneFocusTracker {
    let focusGainedStream: AsyncStream<UUID>

    private let continuation: AsyncStream<UUID>.Continuation
    private let attendedPane: AttendedPaneAtom
    private let traceQueue: AgentStudioTraceEventQueue?
    private var streamTask: Task<Void, Never>?
    private var isStopped = false

    init(attendedPane: AttendedPaneAtom, traceRuntime: AgentStudioTraceRuntime? = nil) {
        self.attendedPane = attendedPane
        self.traceQueue = traceRuntime.map(AgentStudioTraceEventQueue.init(traceRuntime:))
        // `AttendedPaneAtom.transitions` is the single-consumer coordinator feed.
        // If another feature needs the same stream, add fan-out at the atom boundary.
        let (stream, continuation) = AsyncStream.makeStream(of: UUID.self)
        self.focusGainedStream = stream
        self.continuation = continuation

        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await paneId in self.attendedPane.transitions {
                guard !Task.isCancelled, !self.isStopped else { return }
                self.traceAttendedPaneTransition(paneId)
                guard let paneId else { continue }
                self.continuation.yield(paneId)
            }
            guard !Task.isCancelled, !self.isStopped else { return }
            paneFocusTrackerLogger.warning(
                "Attended-pane transition stream ended while pane focus tracker was active"
            )
            self.isStopped = true
            self.streamTask = nil
            self.continuation.finish()
        }
    }

    func stop() async {
        if !isStopped {
            isStopped = true
            streamTask?.cancel()
            streamTask = nil
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
        streamTask?.cancel()
        continuation.finish()
        traceQueue?.cancel()
    }

    private func traceAttendedPaneTransition(_ paneId: UUID?) {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.app.focus.attended": .bool(paneId != nil),
            "agentstudio.app.focus.source": .string("AttendedPaneAtom"),
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
