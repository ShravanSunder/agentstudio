import Foundation
import AppKit
import GhosttyKit
import os

/// Logger for Ghostty-related operations
let ghosttyLogger = Logger(subsystem: "com.agentstudio", category: "Ghostty")

/// Namespace for all Ghostty-related types
enum Ghostty {
    /// The shared Ghostty app instance
    private static var sharedApp: App?

    /// Access the shared Ghostty app
    static var shared: App {
        guard let app = sharedApp else {
            fatalError("Ghostty not initialized. Call Ghostty.initialize() first.")
        }
        return app
    }

    /// Check if Ghostty has been initialized
    static var isInitialized: Bool {
        sharedApp != nil
    }

    /// Initialize the shared Ghostty app (must be called on main thread)
    @discardableResult
    static func initialize() -> Bool {
        guard Thread.isMainThread else {
            var result = false
            DispatchQueue.main.sync {
                result = initialize()
            }
            return result
        }

        guard sharedApp == nil else { return true }
        sharedApp = App()
        return sharedApp?.app != nil
    }
}

// MARK: - Ghostty Notifications

extension Ghostty {
    /// Notification names for Ghostty events
    enum Notification {
        static let ghosttyNewWindow = Foundation.Notification.Name("ghosttyNewWindow")
        static let ghosttyNewTab = Foundation.Notification.Name("ghosttyNewTab")
        static let ghosttyCloseSurface = Foundation.Notification.Name("ghosttyCloseSurface")

        /// Posted when renderer health changes
        /// - object: The SurfaceView whose health changed
        /// - userInfo: ["healthy": Bool]
        static let didUpdateRendererHealth = Foundation.Notification.Name("ghosttyDidUpdateRendererHealth")

        /// Posted when a surface's title changes
        /// - object: The SurfaceView whose title changed
        /// - userInfo: ["title": String]
        static let didUpdateTitle = Foundation.Notification.Name("ghosttyDidUpdateTitle")
    }
}

extension Ghostty {
    /// Wraps the ghostty_app_t and handles app-level callbacks
    final class App {
        /// The ghostty app handle
        private(set) var app: ghostty_app_t?

        /// The ghostty configuration
        private var config: ghostty_config_t?

        init() {
            // Load default configuration
            self.config = ghostty_config_new()
            guard let config = self.config else {
                ghosttyLogger.error("Failed to create ghostty config")
                return
            }

            // Load the config from default locations
            ghostty_config_load_default_files(config)

            // Finalize the config
            ghostty_config_finalize(config)

            // Create runtime config with callbacks
            var runtimeConfig = ghostty_runtime_config_s(
                userdata: Unmanaged.passUnretained(self).toOpaque(),
                supports_selection_clipboard: true,
                wakeup_cb: { userdata in
                    guard let userdata = userdata else { return }
                    let app = Unmanaged<App>.fromOpaque(userdata).takeUnretainedValue()
                    DispatchQueue.main.async {
                        app.tick()
                    }
                },
                action_cb: { appPtr, target, action in
                    return App.handleAction(appPtr!, target: target, action: action)
                },
                read_clipboard_cb: { userdata, location, state in
                    App.readClipboard(userdata, location: location, state: state)
                },
                confirm_read_clipboard_cb: { userdata, str, state, request in
                    App.confirmReadClipboard(userdata, string: str, state: state, request: request)
                },
                write_clipboard_cb: { userdata, location, content, len, confirm in
                    App.writeClipboard(userdata, location: location, content: content, len: len, confirm: confirm)
                },
                close_surface_cb: { userdata, processAlive in
                    App.closeSurface(userdata, processAlive: processAlive)
                }
            )

            // Create the ghostty app
            self.app = ghostty_app_new(&runtimeConfig, config)

            if self.app == nil {
                ghosttyLogger.error("Failed to create ghostty app")
                ghostty_config_free(config)
                self.config = nil
                return
            }

            // Set initial focus state (safe check for NSApp existence)
            if let nsApp = NSApp {
                ghostty_app_set_focus(app, nsApp.isActive)
            } else {
                ghostty_app_set_focus(app, false)
            }

            // Register for app activation notifications
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationDidBecomeActive),
                name: NSApplication.didBecomeActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationDidResignActive),
                name: NSApplication.didResignActiveNotification,
                object: nil
            )

            ghosttyLogger.info("Ghostty app initialized successfully")
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
            if let app = app {
                ghostty_app_free(app)
            }
            if let config = config {
                ghostty_config_free(config)
            }
        }

        /// Process pending ghostty events
        func tick() {
            guard let app = app else { return }
            ghostty_app_tick(app)
        }

        @objc private func applicationDidBecomeActive(_ notification: Notification) {
            guard let app = app else { return }
            ghostty_app_set_focus(app, true)
        }

        @objc private func applicationDidResignActive(_ notification: Notification) {
            guard let app = app else { return }
            ghostty_app_set_focus(app, false)
        }

        // MARK: - Static Callbacks

        static func handleAction(_ appPtr: ghostty_app_t, target: ghostty_target_s, action: ghostty_action_s) -> Bool {
            switch action.tag {
            case GHOSTTY_ACTION_QUIT:
                // Don't quit - AgentStudio manages its own window lifecycle
                // Ghostty sends this when all surfaces are closed, but we want to stay running
                return true

            case GHOSTTY_ACTION_NEW_WINDOW:
                NotificationCenter.default.post(name: .ghosttyNewWindow, object: nil)
                return true

            case GHOSTTY_ACTION_NEW_TAB:
                NotificationCenter.default.post(name: .ghosttyNewTab, object: nil)
                return true

            case GHOSTTY_ACTION_SET_TITLE:
                if target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface {
                    if let surfaceView = surfaceView(from: surface),
                       let titlePtr = action.action.set_title.title {
                        let title = String(cString: titlePtr)
                        DispatchQueue.main.async {
                            surfaceView.titleDidChange(title)
                        }
                    }
                }
                return true

            default:
                return false
            }
        }

        static func readClipboard(_ userdata: UnsafeMutableRawPointer?, location: ghostty_clipboard_e, state: UnsafeMutableRawPointer?) {
            guard let userdata = userdata else { return }
            let surfaceView = Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
            guard let surface = surfaceView.surface else { return }

            let pasteboard = NSPasteboard.general
            let content = pasteboard.string(forType: .string) ?? ""
            content.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
            }
        }

        static func confirmReadClipboard(_ userdata: UnsafeMutableRawPointer?, string: UnsafePointer<CChar>?, state: UnsafeMutableRawPointer?, request: ghostty_clipboard_request_e) {
            guard let userdata = userdata else { return }
            let surfaceView = Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
            guard let surface = surfaceView.surface else { return }

            if let str = string {
                ghostty_surface_complete_clipboard_request(surface, str, state, true)
            }
        }

        static func writeClipboard(_ userdata: UnsafeMutableRawPointer?, location: ghostty_clipboard_e, content: UnsafePointer<ghostty_clipboard_content_s>?, len: Int, confirm: Bool) {
            guard let content = content, len > 0 else { return }

            let pasteboard = NSPasteboard.general
            let item = content[0]
            guard let data = item.data else { return }
            let str = String(cString: data)

            pasteboard.clearContents()
            pasteboard.setString(str, forType: .string)
        }

        static func closeSurface(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {
            guard let userdata = userdata else { return }
            let surfaceView = Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()

            NotificationCenter.default.post(
                name: .ghosttyCloseSurface,
                object: surfaceView,
                userInfo: ["processAlive": processAlive]
            )
        }

        static func surfaceView(from surface: ghostty_surface_t) -> SurfaceView? {
            guard let userdata = ghostty_surface_userdata(surface) else { return nil }
            return Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        }
    }
}

// MARK: - Notification Names (Backwards Compatibility)

extension Notification.Name {
    static let ghosttyNewWindow = Ghostty.Notification.ghosttyNewWindow
    static let ghosttyNewTab = Ghostty.Notification.ghosttyNewTab
    static let ghosttyCloseSurface = Ghostty.Notification.ghosttyCloseSurface
}
