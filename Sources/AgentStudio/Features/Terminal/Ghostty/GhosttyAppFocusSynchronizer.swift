import Foundation
import GhosttyKit
import Observation
import os

protocol GhosttyAppFocusSetting: Sendable {
    func setAppFocus(_ app: ghostty_app_t, isActive: Bool)
}

private enum LiveGhosttyAppFocusSetter: GhosttyAppFocusSetting {
    case shared

    func setAppFocus(_ app: ghostty_app_t, isActive: Bool) {
        ghostty_app_set_focus(app, isActive)
    }
}

final class GhosttyAppHandleBits: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<UInt?>(initialState: nil)

    func update(_ app: ghostty_app_t?) {
        let appHandleBits = app.map { UInt(bitPattern: $0) }
        lock.withLock { $0 = appHandleBits }
    }

    @MainActor
    @discardableResult
    func withCurrent(_ body: @Sendable (ghostty_app_t) -> Void) -> Bool {
        lock.withLock { appHandleBits in
            guard
                let appHandleBits,
                let app = UnsafeMutableRawPointer(bitPattern: appHandleBits)
            else { return false }

            body(app)
            return true
        }
    }
}

extension Ghostty {
    /// Mirrors app-level lifecycle focus into the embedded Ghostty app while
    /// keeping focus observation isolated from callback and action-routing code.
    @MainActor
    final class AppFocusSynchronizer {
        private let focusSetter: any GhosttyAppFocusSetting
        private let appHandleBits = GhosttyAppHandleBits()
        private var appLifecycleStore: AppLifecycleAtom?
        private var isObservingApplicationLifecycle = false

        init(focusSetter: any GhosttyAppFocusSetting = LiveGhosttyAppFocusSetter.shared) {
            self.focusSetter = focusSetter
        }

        func updateAppHandle(_ app: ghostty_app_t?) {
            appHandleBits.update(app)
        }

        nonisolated func clearAppHandleForDeinit() {
            // Must run before Ghostty.AppHandle deinit frees ghostty_app_t.
            appHandleBits.update(nil)
        }

        func bindApplicationLifecycleStore(_ appLifecycleStore: AppLifecycleAtom) {
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

            let didSync = appHandleBits.withCurrent { app in
                // Vendored Ghostty implements ghostty_app_set_focus as a wrapper
                // around App.focusEvent: redundant-state guard, debug log, boolean
                // assignment. Keep this lock body to that verified app-focus call.
                focusSetter.setAppFocus(app, isActive: isActive)
            }
            guard didSync else { return }

            RestoreTrace.log(
                "Ghostty.AppFocusSynchronizer lifecycleStore.isActive=\(isActive) -> ghostty_app_set_focus(\(isActive))"
            )
        }
    }
}
