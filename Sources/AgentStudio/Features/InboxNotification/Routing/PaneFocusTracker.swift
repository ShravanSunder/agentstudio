import Foundation

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
    private var streamTask: Task<Void, Never>?
    private var isStopped = false

    init(attendedPane: AttendedPaneAtom) {
        self.attendedPane = attendedPane
        let (stream, continuation) = AsyncStream.makeStream(of: UUID.self)
        self.focusGainedStream = stream
        self.continuation = continuation

        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await paneId in self.attendedPane.transitions {
                guard !Task.isCancelled, !self.isStopped else { return }
                guard let paneId else { continue }
                self.continuation.yield(paneId)
            }
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        streamTask?.cancel()
        streamTask = nil
        continuation.finish()
    }

    deinit {
        streamTask?.cancel()
        continuation.finish()
    }
}
