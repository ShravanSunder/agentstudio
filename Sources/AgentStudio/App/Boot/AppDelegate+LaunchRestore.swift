import Foundation
import os.log

private let launchRestoreLogger = Logger(subsystem: "com.agentstudio", category: "AppDelegate")

@MainActor
extension AppDelegate {
    func finishLaunchRestore(
        using restoreBounds: CGRect,
        source: StaticString
    ) async {
        guard !launchRestoreObservationState.didComplete else { return }
        guard !restoreBounds.isEmpty else {
            RestoreTrace.log("launchRestore skipped reason=emptyBounds source=\(source)")
            launchRestoreLogger.error(
                "Launch restore attempted with empty bounds source=\(source, privacy: .public) storeBounds=\(NSStringFromRect(self.windowLifecycleStore.terminalContainerBounds), privacy: .public)"
            )
            launchRestoreObservationState.complete()
            return
        }

        RestoreTrace.log(
            "launchRestore triggered source=\(source) bounds=\(NSStringFromRect(restoreBounds)) windowFrame=\(NSStringFromRect(mainWindowController?.window?.frame ?? .zero)) contentRect=\(NSStringFromRect(mainWindowController?.window?.contentLayoutRect ?? .zero))"
        )
        await paneCoordinator.restoreAllViews(in: restoreBounds)
        mainWindowController?.syncVisibleTerminalGeometry(reason: "postLaunchRestore")
        launchRestoreObservationState.complete()
        RestoreTrace.log("launchRestore end registeredViews=\(viewRegistry.registeredPaneIds.count)")
    }

    func observeLaunchRestoreReadiness() {
        let bridge = WindowRestoreBridge(windowLifecycleStore: windowLifecycleStore)
        windowRestoreBridge = bridge
        launchRestoreObservationState.prepareForObservation()
        launchRestoreObservationTask?.cancel()
        launchRestoreObservationState.installDiagnosticTask(
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch is CancellationError {
                    return
                } catch {
                    launchRestoreLogger.warning("Unexpected error in launch restore diagnostic timer: \(error)")
                    return
                }
                guard !self.launchRestoreObservationState.didComplete else { return }
                launchRestoreLogger.error(
                    "Launch restore timed out — isSettled=\(self.windowLifecycleStore.isLaunchLayoutSettled, privacy: .public) bounds=\(NSStringFromRect(self.windowLifecycleStore.terminalContainerBounds), privacy: .public)"
                )
                let fallbackBounds = self.windowLifecycleStore.terminalContainerBounds
                guard !fallbackBounds.isEmpty else { return }
                launchRestoreLogger.error(
                    "Launch restore timeout recovery: attempting restore with stored bounds \(NSStringFromRect(fallbackBounds), privacy: .public)"
                )
                await self.finishLaunchRestore(
                    using: fallbackBounds,
                    source: "diagnosticTimeoutRecovery"
                )
            }
        )
        launchRestoreObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await bounds in bridge.stream {
                guard !Task.isCancelled else { break }
                let restoreBounds =
                    bounds.isEmpty
                    ? self.windowLifecycleStore.terminalContainerBounds
                    : bounds
                await self.finishLaunchRestore(
                    using: restoreBounds,
                    source: "windowRestoreBridge"
                )
                break
            }
            if !self.launchRestoreObservationState.didComplete {
                launchRestoreLogger.error("Launch restore stream ended without completing restore")
                self.launchRestoreObservationState.cancelDiagnostics()
            }
        }
    }
}
