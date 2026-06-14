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
    typealias TransitionStreamProvider = @MainActor () -> AsyncStream<UUID?>

    let focusGainedStream: AsyncStream<UUID>

    private let continuation: AsyncStream<UUID>.Continuation
    private let attendedPane: AttendedPaneAtom
    private let traceQueue: AgentStudioTraceEventQueue?
    private let transitionStreamProvider: TransitionStreamProvider
    private let restartDelay: AsyncDelay
    private let restartDelayDuration: Duration
    private let maxUnexpectedEndRestarts: Int
    private var streamTask: Task<Void, Never>?
    private var isStopped = false
    private var unexpectedEndRestartAttempts = 0

    init(
        attendedPane: AttendedPaneAtom,
        traceRuntime: AgentStudioTraceRuntime? = nil,
        restartClock: (any Clock<Duration> & Sendable)? = nil,
        restartDelay: Duration = .milliseconds(250),
        maxUnexpectedEndRestarts: Int = 3,
        transitionStreamProvider: TransitionStreamProvider? = nil
    ) {
        self.attendedPane = attendedPane
        self.traceQueue = traceRuntime.map(AgentStudioTraceEventQueue.init(traceRuntime:))
        self.transitionStreamProvider = transitionStreamProvider ?? { attendedPane.transitions }
        self.restartDelay = restartClock.map(AsyncDelay.clock) ?? .taskSleep
        self.restartDelayDuration = restartDelay
        self.maxUnexpectedEndRestarts = max(0, maxUnexpectedEndRestarts)
        // `AttendedPaneAtom.transitions` is the single-consumer coordinator feed.
        // If another feature needs the same stream, add fan-out at the atom boundary.
        let (stream, continuation) = AsyncStream.makeStream(of: UUID.self)
        self.focusGainedStream = stream
        self.continuation = continuation

        streamTask = Task { @MainActor [weak self] in
            await self?.consumeTransitionStreams()
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

    private func consumeTransitionStreams() async {
        while !Task.isCancelled, !isStopped {
            for await paneId in transitionStreamProvider() {
                guard !Task.isCancelled, !isStopped else { return }
                unexpectedEndRestartAttempts = 0
                traceAttendedPaneTransition(paneId)
                guard let paneId else { continue }
                continuation.yield(paneId)
            }
            guard !Task.isCancelled, !isStopped else { return }
            guard unexpectedEndRestartAttempts < maxUnexpectedEndRestarts else {
                paneFocusTrackerLogger.error(
                    "Attended-pane transition stream ended after \(self.maxUnexpectedEndRestarts) restart attempts"
                )
                isStopped = true
                streamTask = nil
                continuation.finish()
                return
            }

            unexpectedEndRestartAttempts += 1
            paneFocusTrackerLogger.warning(
                "Attended-pane transition stream ended while pane focus tracker was active; restarting attempt \(self.unexpectedEndRestartAttempts)"
            )
            do {
                try await restartDelay.wait(restartDelayDuration)
            } catch {
                guard !Task.isCancelled, !isStopped else { return }
                paneFocusTrackerLogger.warning(
                    "Pane focus tracker restart delay failed: \(error.localizedDescription)"
                )
            }
        }
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
