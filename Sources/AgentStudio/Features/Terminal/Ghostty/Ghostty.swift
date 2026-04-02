import AppKit
import Foundation
import GhosttyKit
import os

/// Logger for Ghostty-related operations
let ghosttyLogger = Logger(subsystem: "com.agentstudio", category: "Ghostty")

/// Namespace for all Ghostty-related types
enum Ghostty {
    /// The shared Ghostty app instance
    @MainActor private static var sharedApp: App?

    /// Access the shared Ghostty app
    @MainActor
    static var shared: App {
        guard let app = sharedApp else {
            fatalError("Ghostty not initialized. Call Ghostty.initialize() first.")
        }
        return app
    }

    /// Check if Ghostty has been initialized
    @MainActor
    static var isInitialized: Bool {
        sharedApp != nil
    }

    /// Initialize the shared Ghostty app. @MainActor-isolated.
    @MainActor
    @discardableResult
    static func initialize() -> Bool {
        if let sharedApp {
            return sharedApp.app != nil
        }
        let app = App()
        guard app.app != nil else { return false }
        sharedApp = app
        return true
    }

    @MainActor
    static func bindApplicationLifecycleStore(_ appLifecycleStore: AppLifecycleStore) {
        sharedApp?.bindApplicationLifecycleStore(appLifecycleStore)
    }
}

extension Ghostty {
    /// Thin composition root for the embedded Ghostty host subsystem.
    final class App: @unchecked Sendable {
        /// The raw Ghostty app lifetime owner.
        private var appHandle: AppHandle?
        private let focusSynchronizer: AppFocusSynchronizer

        /// The raw Ghostty app handle exposed to existing callers.
        var app: ghostty_app_t? {
            appHandle?.app
        }

        @MainActor
        init() {
            self.focusSynchronizer = AppFocusSynchronizer()

            // Create runtime config with callbacks
            let userdataPointer = Unmanaged.passUnretained(self).toOpaque()
            let runtimeConfig = CallbackRouter.runtimeConfig(userdataPointer: userdataPointer)

            self.appHandle = AppHandle(
                runtimeConfig: runtimeConfig
            )

            guard let appHandle else {
                return
            }

            focusSynchronizer.updateAppHandle(appHandle.app)

            // Start unfocused; activation notifications synchronize real app focus state.
            ghostty_app_set_focus(appHandle.app, false)

            ghosttyLogger.info("Ghostty app initialized successfully")
        }

        deinit {
            focusSynchronizer.clearAppHandleForDeinit()
        }

        /// Process pending ghostty events
        func tick() {
            appHandle?.tick()
        }

        @MainActor
        func bindApplicationLifecycleStore(_ appLifecycleStore: AppLifecycleStore) {
            focusSynchronizer.bindApplicationLifecycleStore(appLifecycleStore)
        }

        @MainActor
        static func setRuntimeRegistry(_ runtimeRegistry: RuntimeRegistry) {
            ActionRouter.setRuntimeRegistry(runtimeRegistry)
        }

        @MainActor
        static var runtimeRegistryForActionRouting: RuntimeRegistry {
            ActionRouter.runtimeRegistryForActionRouting
        }
    }
}
