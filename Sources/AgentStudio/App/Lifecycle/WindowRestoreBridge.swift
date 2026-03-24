import Foundation
import Observation

@MainActor
final class WindowRestoreBridge {
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
                self?.publishIfReady()
                self?.registerObservation()
            }
        }
    }

    private func publishIfReady() {
        guard !hasFinished else { return }
        guard windowLifecycleStore.isReadyForLaunchRestore else { return }

        hasFinished = true
        continuation.yield(windowLifecycleStore.terminalContainerBounds)
        continuation.finish()
    }

    isolated deinit {
        continuation.finish()
    }
}
