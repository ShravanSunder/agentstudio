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
    }
}

extension Ghostty {
    /// Wraps the ghostty_app_t and handles app-level callbacks
    final class App {
        @MainActor private static var runtimeRegistryOverride: RuntimeRegistry = .shared
        private struct PendingRuntimeRoute: Sendable {
            let actionTag: UInt32
            let payload: GhosttyAdapter.ActionPayload
            let surfaceViewObjectId: ObjectIdentifier
        }

        private struct RuntimeRouteQueueState {
            var pending: [PendingRuntimeRoute] = []
            var isDraining = false
        }

        private static let runtimeRouteQueue = OSAllocatedUnfairLock<RuntimeRouteQueueState>(
            initialState: RuntimeRouteQueueState()
        )

        /// The ghostty app handle
        private(set) var app: ghostty_app_t?

        /// The ghostty configuration
        private var config: ghostty_config_t?
        private let focusAppHandleBits = OSAllocatedUnfairLock<UInt?>(initialState: nil)
        private var activeStateTasks: [Task<Void, Never>] = []

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

            guard let app = self.app else {
                ghosttyLogger.error("Failed to create ghostty app")
                ghostty_config_free(config)
                self.config = nil
                return
            }

            // Start unfocused; activation notifications synchronize real app focus state.
            ghostty_app_set_focus(app, false)
            let appHandleBits = UInt(bitPattern: app)
            focusAppHandleBits.withLock { $0 = appHandleBits }
            let focusAppHandleBits = self.focusAppHandleBits

            activeStateTasks.append(
                Task { @MainActor in
                    for await _ in NotificationCenter.default.notifications(
                        named: NSApplication.didBecomeActiveNotification)
                    {
                        if Task.isCancelled { break }
                        guard
                            let appHandleBits = focusAppHandleBits.withLock({ $0 }),
                            let app = UnsafeMutableRawPointer(bitPattern: appHandleBits)
                        else { continue }
                        ghostty_app_set_focus(app, true)
                        RestoreTrace.log("Ghostty.App applicationDidBecomeActive -> ghostty_app_set_focus(true)")
                    }
                })
            activeStateTasks.append(
                Task { @MainActor in
                    for await _ in NotificationCenter.default.notifications(
                        named: NSApplication.didResignActiveNotification)
                    {
                        if Task.isCancelled { break }
                        guard
                            let appHandleBits = focusAppHandleBits.withLock({ $0 }),
                            let app = UnsafeMutableRawPointer(bitPattern: appHandleBits)
                        else { continue }
                        ghostty_app_set_focus(app, false)
                        RestoreTrace.log("Ghostty.App applicationDidResignActive -> ghostty_app_set_focus(false)")
                    }
                })

            ghosttyLogger.info("Ghostty app initialized successfully")
        }

        deinit {
            focusAppHandleBits.withLock { $0 = nil }
            for task in activeStateTasks {
                task.cancel()
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

        // MARK: - Static Callbacks

        // Exhaustive action-tag switch is intentionally long to guarantee compile-time
        // coverage when Ghostty adds new action tags.
        // swiftlint:disable function_body_length
        static func handleAction(_ appPtr: ghostty_app_t, target: ghostty_target_s, action: ghostty_action_s) -> Bool {
            let rawActionTag = UInt32(truncatingIfNeeded: action.tag.rawValue)
            guard let actionTag = GhosttyActionTag(rawValue: rawActionTag) else {
                return routeUnhandledAction(actionTag: rawActionTag, target: target)
            }

            switch actionTag {
            case .quit:
                // Don't quit - AgentStudio manages its own window lifecycle
                // Ghostty sends this when all surfaces are closed, but we want to stay running
                return true

            case .newWindow:
                NotificationCenter.default.post(name: .ghosttyNewWindow, object: nil)
                return true

            case .newTab:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .noPayload,
                    target: target
                )

            case .ringBell:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .noPayload,
                    target: target
                )

            case .setTitle:
                guard let titlePtr = action.action.set_title.title else {
                    return routeUnhandledAction(actionTag: rawActionTag, target: target)
                }
                let title = String(cString: titlePtr)
                if target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface,
                    let resolvedSurfaceView = surfaceView(from: surface)
                {
                    Task { @MainActor [weak resolvedSurfaceView] in
                        resolvedSurfaceView?.titleDidChange(title)
                    }
                }
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .titleChanged(title),
                    target: target
                )

            case .pwd:
                let resolvedPwd = action.action.pwd.pwd.map { String(cString: $0) }
                if target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface,
                    let resolvedSurfaceView = surfaceView(from: surface)
                {
                    Task { @MainActor [weak resolvedSurfaceView] in
                        resolvedSurfaceView?.pwdDidChange(resolvedPwd)
                    }
                }
                guard let cwdPath = resolvedPwd else {
                    return routeUnhandledAction(actionTag: rawActionTag, target: target)
                }
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .cwdChanged(cwdPath),
                    target: target
                )

            // Split actions
            case .newSplit:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .newSplit(directionRawValue: action.action.new_split.rawValue),
                    target: target
                )

            case .gotoSplit:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .gotoSplit(directionRawValue: action.action.goto_split.rawValue),
                    target: target
                )

            case .resizeSplit:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .resizeSplit(
                        amount: action.action.resize_split.amount,
                        directionRawValue: action.action.resize_split.direction.rawValue
                    ),
                    target: target
                )

            case .equalizeSplits:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .noPayload,
                    target: target
                )

            case .toggleSplitZoom:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .noPayload,
                    target: target
                )

            // Tab actions
            case .closeTab:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .closeTab(modeRawValue: action.action.close_tab_mode.rawValue),
                    target: target
                )

            case .gotoTab:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .gotoTab(targetRawValue: action.action.goto_tab.rawValue),
                    target: target
                )

            case .moveTab:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .moveTab(amount: Int(action.action.move_tab.amount)),
                    target: target
                )
            case .commandFinished:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .commandFinished(
                        exitCode: Int(action.action.command_finished.exit_code),
                        duration: action.action.command_finished.duration
                    ),
                    target: target
                )
            case .closeAllWindows, .toggleMaximize, .toggleFullscreen, .toggleTabOverview,
                .toggleWindowDecorations, .toggleQuickTerminal, .toggleCommandPalette, .toggleVisibility,
                .toggleBackgroundOpacity, .gotoWindow, .presentTerminal, .sizeLimit, .resetWindowSize,
                .initialSize, .cellSize, .scrollbar, .render, .inspector, .showGtkInspector, .renderInspector,
                .desktopNotification, .promptTitle, .mouseShape, .mouseVisibility, .mouseOverLink,
                .rendererHealth, .openConfig, .quitTimer, .floatWindow, .secureInput, .keySequence, .keyTable,
                .colorChange, .reloadConfig, .configChange, .closeWindow, .undo, .redo, .checkForUpdates,
                .openURL, .showChildExited, .progressReport, .showOnScreenKeyboard,
                .startSearch, .endSearch, .searchTotal, .searchSelected, .readOnly, .copyTitleToClipboard:
                return routeUnhandledAction(actionTag: rawActionTag, target: target)
            }
        }
        // swiftlint:enable function_body_length

        @MainActor
        static func setRuntimeRegistry(_ runtimeRegistry: RuntimeRegistry) {
            runtimeRegistryOverride = runtimeRegistry
        }

        @MainActor
        static var runtimeRegistryForActionRouting: RuntimeRegistry {
            runtimeRegistryOverride
        }

        private static func routeUnhandledAction(actionTag: UInt32, target: ghostty_target_s) -> Bool {
            let targetTag = UInt32(truncatingIfNeeded: target.tag.rawValue)
            if target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface {
                let surfacePointerDescription = String(UInt(bitPattern: surface))
                if let resolvedSurfaceView = surfaceView(from: surface) {
                    let surfaceViewObjectId = ObjectIdentifier(resolvedSurfaceView)
                    Task { @MainActor in
                        let paneIdDescription: String
                        if let surfaceId = SurfaceManager.shared.surfaceId(forViewObjectId: surfaceViewObjectId),
                            let paneId = SurfaceManager.shared.paneId(for: surfaceId)
                        {
                            paneIdDescription = paneId.uuidString
                        } else {
                            paneIdDescription = "unknown"
                        }
                        ghosttyLogger.warning(
                            "Unhandled Ghostty action tag \(actionTag) targetTag=\(targetTag) paneId=\(paneIdDescription, privacy: .public) surfacePtr=\(surfacePointerDescription, privacy: .public)"
                        )
                    }
                } else {
                    ghosttyLogger.warning(
                        "Unhandled Ghostty action tag \(actionTag) targetTag=\(targetTag) paneId=unknown surfacePtr=\(surfacePointerDescription, privacy: .public)"
                    )
                }
            } else {
                ghosttyLogger.warning(
                    "Unhandled Ghostty action tag \(actionTag) targetTag=\(targetTag) paneId=none surfacePtr=none"
                )
            }

            guard shouldForwardUnhandledActionToRuntime(actionTag: actionTag) else {
                // Keep Ghostty defaults and avoid unnecessary runtime hops for
                // high-frequency visual tags we do not consume.
                return false
            }
            _ = routeActionToTerminalRuntime(actionTag: actionTag, payload: .noPayload, target: target)
            // Returning false preserves Ghostty's built-in default behavior for
            // tags AgentStudio does not handle yet.
            return false
        }

        private static func shouldForwardUnhandledActionToRuntime(actionTag: UInt32) -> Bool {
            guard let knownActionTag = GhosttyActionTag(rawValue: actionTag) else {
                return true
            }
            switch knownActionTag {
            case .render, .mouseShape, .mouseVisibility, .mouseOverLink, .scrollbar:
                return false
            case .quit, .newWindow, .newTab, .ringBell, .setTitle, .pwd, .newSplit, .gotoSplit, .resizeSplit,
                .equalizeSplits, .toggleSplitZoom, .closeTab, .gotoTab, .moveTab, .closeAllWindows, .toggleMaximize,
                .toggleFullscreen, .toggleTabOverview, .toggleWindowDecorations, .toggleQuickTerminal,
                .toggleCommandPalette, .toggleVisibility, .toggleBackgroundOpacity, .gotoWindow, .presentTerminal,
                .sizeLimit, .resetWindowSize, .initialSize, .cellSize, .inspector, .showGtkInspector,
                .renderInspector, .desktopNotification, .promptTitle, .rendererHealth, .openConfig, .quitTimer,
                .floatWindow, .secureInput, .keySequence, .keyTable, .colorChange, .reloadConfig, .configChange,
                .closeWindow, .undo, .redo, .checkForUpdates, .openURL, .showChildExited, .progressReport,
                .showOnScreenKeyboard, .commandFinished, .startSearch, .endSearch, .searchTotal, .searchSelected,
                .readOnly, .copyTitleToClipboard:
                return true
            }
        }

        private static func routeActionToTerminalRuntime(
            actionTag: UInt32,
            payload: GhosttyAdapter.ActionPayload,
            target: ghostty_target_s
        ) -> Bool {
            guard target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface else {
                return false
            }

            guard let resolvedSurfaceView = surfaceView(from: surface) else {
                ghosttyLogger.warning("Dropped action tag \(actionTag): no surface view for callback target")
                return true
            }

            // Resolve the callback target synchronously and pass only stable identity
            // into the async hop so we never dereference raw surface pointers later.
            let surfaceViewObjectId = ObjectIdentifier(resolvedSurfaceView)
            enqueueRuntimeRoute(
                actionTag: actionTag,
                payload: payload,
                surfaceViewObjectId: surfaceViewObjectId
            )
            return true
        }

        private static func enqueueRuntimeRoute(
            actionTag: UInt32,
            payload: GhosttyAdapter.ActionPayload,
            surfaceViewObjectId: ObjectIdentifier
        ) {
            let shouldStartDraining = runtimeRouteQueue.withLock { state in
                state.pending.append(
                    PendingRuntimeRoute(
                        actionTag: actionTag,
                        payload: payload,
                        surfaceViewObjectId: surfaceViewObjectId
                    )
                )
                guard !state.isDraining else { return false }
                state.isDraining = true
                return true
            }

            guard shouldStartDraining else { return }
            Task { @MainActor in
                drainRuntimeRouteQueueOnMainActor()
            }
        }

        @MainActor
        private static func drainRuntimeRouteQueueOnMainActor() {
            while true {
                let pendingRoute = runtimeRouteQueue.withLock { state -> PendingRuntimeRoute? in
                    guard !state.pending.isEmpty else {
                        state.isDraining = false
                        return nil
                    }
                    return state.pending.removeFirst()
                }
                guard let pendingRoute else { return }
                let didRoute = routeActionToTerminalRuntimeOnMainActor(
                    actionTag: pendingRoute.actionTag,
                    payload: pendingRoute.payload,
                    surfaceViewObjectId: pendingRoute.surfaceViewObjectId
                )
                if !didRoute {
                    ghosttyLogger.warning(
                        "Dropped action tag \(pendingRoute.actionTag): callback returned handled before runtime routing completed"
                    )
                }
            }
        }

        @MainActor
        static func routeActionToTerminalRuntimeOnMainActor(
            actionTag: UInt32,
            payload: GhosttyAdapter.ActionPayload,
            surfaceViewObjectId: ObjectIdentifier
        ) -> Bool {
            guard let surfaceId = SurfaceManager.shared.surfaceId(forViewObjectId: surfaceViewObjectId) else {
                ghosttyLogger.warning("Dropped action tag \(actionTag): surface not registered in SurfaceManager")
                return false
            }
            guard let paneUUID = SurfaceManager.shared.paneId(for: surfaceId) else {
                ghosttyLogger.warning("Dropped action tag \(actionTag): no pane mapped for surface \(surfaceId)")
                return false
            }
            guard UUIDv7.isV7(paneUUID) else {
                ghosttyLogger.warning(
                    "Dropped action tag \(actionTag): mapped pane id is not UUID v7 \(paneUUID.uuidString, privacy: .public)"
                )
                return false
            }
            let paneId = PaneId(uuid: paneUUID)
            let routedRuntime = runtimeRegistryForActionRouting.runtime(for: paneId) as? TerminalRuntime
            let runtime: TerminalRuntime?
            if let routedRuntime {
                runtime = routedRuntime
            } else if ObjectIdentifier(runtimeRegistryForActionRouting) != ObjectIdentifier(RuntimeRegistry.shared) {
                runtime = RuntimeRegistry.shared.runtime(for: paneId) as? TerminalRuntime
            } else {
                runtime = nil
            }

            guard let runtime else {
                ghosttyLogger.warning(
                    "Dropped action tag \(actionTag): terminal runtime not found for pane \(paneUUID)")
                return false
            }

            GhosttyAdapter.shared.route(
                actionTag: actionTag,
                payload: payload,
                to: runtime
            )
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
    static let ghosttyCloseSurface = Ghostty.Notification.ghosttyCloseSurface

    // CWD notification aliases
    static let didUpdateWorkingDirectory = Ghostty.Notification.didUpdateWorkingDirectory
    static let surfaceCWDChanged = Ghostty.Notification.surfaceCWDChanged
}
