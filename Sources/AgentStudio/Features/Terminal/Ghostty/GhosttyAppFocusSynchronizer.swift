import Foundation
import GhosttyKit
import Observation
import os

@MainActor
protocol GhosttyAppFocusSetting {
    func setAppFocus(_ app: ghostty_app_t, isActive: Bool)
}

@MainActor
private enum LiveGhosttyAppFocusSetter: GhosttyAppFocusSetting {
    case shared

    func setAppFocus(_ app: ghostty_app_t, isActive: Bool) {
        ghostty_app_set_focus(app, isActive)
    }
}

private final class GhosttyAppHandleBits {
    private let lock = OSAllocatedUnfairLock<UInt?>(initialState: nil)

    func update(_ app: ghostty_app_t?) {
        let appHandleBits = app.map { UInt(bitPattern: $0) }
        lock.withLock { $0 = appHandleBits }
    }

    func current() -> UInt? {
        lock.withLock { $0 }
    }
}

extension Ghostty {
    /// Mirrors app-level lifecycle focus into the embedded Ghostty app while
    /// keeping focus observation isolated from callback and action-routing code.
    @MainActor
    final class AppFocusSynchronizer {
        private let focusSetter: any GhosttyAppFocusSetting
        nonisolated(unsafe) private let appHandleBits = GhosttyAppHandleBits()
        private var appLifecycleStore: AppLifecycleStore?
        private var isObservingApplicationLifecycle = false

        init(focusSetter: any GhosttyAppFocusSetting = LiveGhosttyAppFocusSetter.shared) {
            self.focusSetter = focusSetter
        }

        func updateAppHandle(_ app: ghostty_app_t?) {
            appHandleBits.update(app)
        }

        nonisolated func clearAppHandleForDeinit() {
            appHandleBits.update(nil)
        }

        func bindApplicationLifecycleStore(_ appLifecycleStore: AppLifecycleStore) {
            if let existingStore = self.appLifecycleStore {
                guard existingStore !== appLifecycleStore else { return }
                ghosttyLogger.error("Ghostty focus synchronizer rejected lifecycle store rebind")
                return
            }
            self.appLifecycleStore = appLifecycleStore
            syncApplicationFocus()
            observeApplicationLifecycle()
        }

        private func observeApplicationLifecycle() {
            guard !isObservingApplicationLifecycle else { return }
            guard let appLifecycleStore else { return }
            isObservingApplicationLifecycle = true

            withObservationTracking {
                _ = appLifecycleStore.isActive
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isObservingApplicationLifecycle = false
                    self.syncApplicationFocus()
                    self.observeApplicationLifecycle()
                }
            }
        }

        private func syncApplicationFocus() {
            guard let appLifecycleStore else { return }
            let isActive = appLifecycleStore.isActive

            guard
                let appHandleBits = appHandleBits.current(),
                let app = UnsafeMutableRawPointer(bitPattern: appHandleBits)
            else { return }

            focusSetter.setAppFocus(app, isActive: isActive)
            RestoreTrace.log(
                "Ghostty.AppFocusSynchronizer lifecycleStore.isActive=\(isActive) -> ghostty_app_set_focus(\(isActive))"
            )
        }
    }
}
