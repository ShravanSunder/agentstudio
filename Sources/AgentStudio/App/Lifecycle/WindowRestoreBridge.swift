import Foundation
import Observation
import os.log

/// Bridges `WindowLifecycleStore` launch-restore readiness into a one-shot async signal.
/// It observes the store using the repo's explicit observation re-registration pattern,
/// yields the current live terminal container bounds once readiness becomes true, and
/// then finishes the stream. `AppDelegate` owns retention and consumption.

@MainActor
final class WindowRestoreBridge {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "WindowRestoreBridge")

    let stream: AsyncStream<CGRect>

    private let continuation: AsyncStream<CGRect>.Continuation
    private let windowLifecycleStore: WindowLifecycleStore
    private var hasFinished = false

    init(windowLifecycleStore: WindowLifecycleStore) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: CGRect.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.stream = stream
        self.continuation = continuation
        self.windowLifecycleStore = windowLifecycleStore
        registerObservation()
        publishIfReady()
    }

    private func registerObservation() {
        guard !hasFinished else { return }
        withObservationTracking {
            _ = windowLifecycleStore.isReadyForLaunchRestore
            _ = windowLifecycleStore.terminalContainerBounds
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.hasFinished else { return }
                self.publishIfReady()
                self.registerObservation()
            }
        }
    }

    private func publishIfReady() {
        guard !hasFinished else { return }
        guard windowLifecycleStore.isReadyForLaunchRestore else {
            RestoreTrace.log(
                "WindowRestoreBridge.publishIfReady skipped bounds=\(NSStringFromRect(windowLifecycleStore.terminalContainerBounds)) settled=\(windowLifecycleStore.isLaunchLayoutSettled) ready=\(windowLifecycleStore.isReadyForLaunchRestore)"
            )
            return
        }

        hasFinished = true
        RestoreTrace.log(
            "WindowRestoreBridge.publishIfReady yield bounds=\(NSStringFromRect(windowLifecycleStore.terminalContainerBounds))"
        )
        continuation.yield(windowLifecycleStore.terminalContainerBounds)
        continuation.finish()
    }

    isolated deinit {
        if !hasFinished {
            Self.logger.error("WindowRestoreBridge deallocated before readiness")
        }
        continuation.finish()
    }
}
