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

        /// Posted when a surface's working directory changes (OSC 7)
        /// - object: The SurfaceView whose CWD changed
        /// - userInfo: ["pwd": String] (nil userInfo when pwd cleared)
        static let didUpdateWorkingDirectory = Foundation.Notification.Name("ghosttyDidUpdateWorkingDirectory")

        /// Posted by SurfaceManager when a managed surface's CWD changes
        /// - userInfo: ["surfaceId": UUID, "url": URL] (url absent when cleared)
        static let surfaceCWDChanged = Foundation.Notification.Name("ghosttySurfaceCWDChanged")

        // Split action notifications
        static let ghosttyNewSplit = Foundation.Notification.Name("ghosttyNewSplit")
        static let ghosttyGotoSplit = Foundation.Notification.Name("ghosttyGotoSplit")
        static let ghosttyResizeSplit = Foundation.Notification.Name("ghosttyResizeSplit")
        static let ghosttyEqualizeSplits = Foundation.Notification.Name("ghosttyEqualizeSplits")
        static let ghosttyToggleSplitZoom = Foundation.Notification.Name("ghosttyToggleSplitZoom")

        // Tab action notifications
        static let ghosttyCloseTab = Foundation.Notification.Name("ghosttyCloseTab")
        static let ghosttyGotoTab = Foundation.Notification.Name("ghosttyGotoTab")
        static let ghosttyMoveTab = Foundation.Notification.Name("ghosttyMoveTab")
    }
}

extension Ghostty {
    /// Wraps the ghostty_app_t and handles app-level callbacks
    final class App {
        /// The ghostty app handle
        private(set) var app: ghostty_app_t?

        /// The ghostty configuration
        private var config: ghostty_config_t?
        private var didBecomeActiveObserver: NSObjectProtocol?
        private var didResignActiveObserver: NSObjectProtocol?

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
                    guard let userdata else { return }
                    let userdataBits = UInt(bitPattern: userdata)
                    Task { @MainActor in
                        guard let userdata = UnsafeMutableRawPointer(bitPattern: userdataBits) else { return }
                        let app = Unmanaged<App>.fromOpaque(userdata).takeUnretainedValue()
                        app.tick()
                    }
                },
                // C callbacks cannot use `Self` — it captures dynamic Self type.
                // swiftlint:disable prefer_self_in_static_references
                action_cb: { appPtr, target, action in
                    App.handleAction(appPtr!, target: target, action: action)
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
                // swiftlint:enable prefer_self_in_static_references
            )

            // Create the ghostty app
            self.app = ghostty_app_new(&runtimeConfig, config)

            if self.app == nil {
                ghosttyLogger.error("Failed to create ghostty app")
                ghostty_config_free(config)
                self.config = nil
                return
            }

            // Start unfocused; activation notifications synchronize real app focus state.
            ghostty_app_set_focus(app, false)

            didBecomeActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.applicationDidBecomeActive()
            }
            didResignActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.applicationDidResignActive()
            }

            ghosttyLogger.info("Ghostty app initialized successfully")
        }

        deinit {
            if let observer = didBecomeActiveObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = didResignActiveObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let app {
                ghostty_app_free(app)
            }
            if let config {
                ghostty_config_free(config)
            }
        }

        /// Process pending ghostty events
        func tick() {
            guard let app else { return }
            ghostty_app_tick(app)
        }

        private func applicationDidBecomeActive() {
            guard let app else { return }
            ghostty_app_set_focus(app, true)
            RestoreTrace.log("Ghostty.App applicationDidBecomeActive -> ghostty_app_set_focus(true)")
        }

        private func applicationDidResignActive() {
            guard let app else { return }
            ghostty_app_set_focus(app, false)
            RestoreTrace.log("Ghostty.App applicationDidResignActive -> ghostty_app_set_focus(false)")
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
                        let titlePtr = action.action.set_title.title
                    {
                        let title = String(cString: titlePtr)
                        Task { @MainActor [weak surfaceView] in
                            guard let surfaceView else { return }
                            surfaceView.titleDidChange(title)
                        }
                    }
                }
                return true

            case GHOSTTY_ACTION_PWD:
                if target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface {
                    if let surfaceView = surfaceView(from: surface) {
                        let pwd = action.action.pwd.pwd.map { String(cString: $0) }
                        Task { @MainActor [weak surfaceView] in
                            guard let surfaceView else { return }
                            surfaceView.pwdDidChange(pwd)
                        }
                    }
                }
                return true

            // Split actions
            case GHOSTTY_ACTION_NEW_SPLIT:
                let direction = action.action.new_split
                return postSurfaceNotification(
                    target, name: .ghosttyNewSplit,
                    userInfo: ["direction": Int(direction.rawValue)])

            case GHOSTTY_ACTION_GOTO_SPLIT:
                let goto = action.action.goto_split
                return postSurfaceNotification(
                    target, name: .ghosttyGotoSplit,
                    userInfo: ["goto": Int(goto.rawValue)])

            case GHOSTTY_ACTION_RESIZE_SPLIT:
                let resize = action.action.resize_split
                return postSurfaceNotification(
                    target, name: .ghosttyResizeSplit,
                    userInfo: [
                        "amount": Int(resize.amount),
                        "direction": Int(resize.direction.rawValue),
                    ])

            case GHOSTTY_ACTION_EQUALIZE_SPLITS:
                return postSurfaceNotification(target, name: .ghosttyEqualizeSplits)

            case GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
                return postSurfaceNotification(target, name: .ghosttyToggleSplitZoom)

            // Tab actions
            case GHOSTTY_ACTION_CLOSE_TAB:
                let mode = action.action.close_tab_mode
                return postSurfaceNotification(
                    target, name: .ghosttyCloseTab,
                    userInfo: ["mode": Int(mode.rawValue)])

            case GHOSTTY_ACTION_GOTO_TAB:
                let gotoTab = action.action.goto_tab
                return postSurfaceNotification(
                    target, name: .ghosttyGotoTab,
                    userInfo: ["target": Int(gotoTab.rawValue)])

            case GHOSTTY_ACTION_MOVE_TAB:
                let moveTab = action.action.move_tab
                return postSurfaceNotification(
                    target, name: .ghosttyMoveTab,
                    userInfo: ["amount": Int(moveTab.amount)])

            default:
                return false
            }
        }

        /// Post a notification targeting a surface. Extracts the SurfaceView from the target
        /// and posts the notification on the MainActor. Returns false if target is invalid.
        private static func postSurfaceNotification(
            _ target: ghostty_target_s,
            name: Foundation.Notification.Name,
            userInfo: [String: Int]? = nil
        ) -> Bool {
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                let surface = target.target.surface,
                let surfaceView = surfaceView(from: surface)
            else { return false }
            Task { @MainActor [weak surfaceView] in
                guard let surfaceView else { return }
                NotificationCenter.default.post(
                    name: name,
                    object: surfaceView,
                    userInfo: userInfo
                )
            }
            return true
        }

        static func readClipboard(
            _ userdata: UnsafeMutableRawPointer?, location: ghostty_clipboard_e, state: UnsafeMutableRawPointer?
        ) {
            guard let userdata else { return }
            let surfaceView = Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
            guard let surface = surfaceView.surface else { return }

            let pasteboard = NSPasteboard.general
            let content = pasteboard.string(forType: .string) ?? ""
            content.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
            }
        }

        static func confirmReadClipboard(
            _ userdata: UnsafeMutableRawPointer?, string: UnsafePointer<CChar>?, state: UnsafeMutableRawPointer?,
            request: ghostty_clipboard_request_e
        ) {
            guard let userdata else { return }
            let surfaceView = Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
            guard let surface = surfaceView.surface else { return }

            if let str = string {
                ghostty_surface_complete_clipboard_request(surface, str, state, true)
            }
        }

        static func writeClipboard(
            _ userdata: UnsafeMutableRawPointer?, location: ghostty_clipboard_e,
            content: UnsafePointer<ghostty_clipboard_content_s>?, len: Int, confirm: Bool
        ) {
            guard let content, len > 0 else { return }

            let pasteboard = NSPasteboard.general
            let item = content[0]
            guard let data = item.data else { return }
            let str = String(cString: data)

            pasteboard.clearContents()
            pasteboard.setString(str, forType: .string)
        }

        static func closeSurface(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {
            guard let userdata else { return }
            let surfaceView = Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
            RestoreTrace.log(
                "Ghostty.App.closeSurface view=\(ObjectIdentifier(surfaceView)) processAlive=\(processAlive)"
            )

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

// MARK: - Notification Name Aliases

extension Notification.Name {
    static let ghosttyNewWindow = Ghostty.Notification.ghosttyNewWindow
    static let ghosttyNewTab = Ghostty.Notification.ghosttyNewTab
    static let ghosttyCloseSurface = Ghostty.Notification.ghosttyCloseSurface

    // CWD notification aliases
    static let didUpdateWorkingDirectory = Ghostty.Notification.didUpdateWorkingDirectory
    static let surfaceCWDChanged = Ghostty.Notification.surfaceCWDChanged

    // Split action aliases
    static let ghosttyNewSplit = Ghostty.Notification.ghosttyNewSplit
    static let ghosttyGotoSplit = Ghostty.Notification.ghosttyGotoSplit
    static let ghosttyResizeSplit = Ghostty.Notification.ghosttyResizeSplit
    static let ghosttyEqualizeSplits = Ghostty.Notification.ghosttyEqualizeSplits
    static let ghosttyToggleSplitZoom = Ghostty.Notification.ghosttyToggleSplitZoom

    // Tab action aliases
    static let ghosttyCloseTab = Ghostty.Notification.ghosttyCloseTab
    static let ghosttyGotoTab = Ghostty.Notification.ghosttyGotoTab
    static let ghosttyMoveTab = Ghostty.Notification.ghosttyMoveTab
}
