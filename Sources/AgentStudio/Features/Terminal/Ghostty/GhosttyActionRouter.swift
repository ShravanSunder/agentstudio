import AppKit
import Foundation
import GhosttyKit

@MainActor
protocol GhosttyActionRoutingLookup: AnyObject {
    func surfaceId(forViewObjectId viewObjectId: ObjectIdentifier) -> UUID?
    func paneId(for surfaceId: UUID) -> UUID?
}

extension SurfaceManager: GhosttyActionRoutingLookup {}

typealias GhosttyActionRoutingLookupProvider = @MainActor () -> any GhosttyActionRoutingLookup

extension Ghostty {
    /// Owns Ghostty action-tag handling and routes surface-scoped actions into
    /// SurfaceManager and TerminalRuntime on the main actor.
    enum ActionRouter {
        @MainActor private static var runtimeRegistryOverride: RuntimeRegistry = .shared

        // Exhaustive action-tag switch is intentionally long to guarantee compile-time
        // coverage when Ghostty adds new action tags.
        // swiftlint:disable function_body_length
        static func handleAction(
            _ appPtr: ghostty_app_t,
            target: ghostty_target_s,
            action: ghostty_action_s
        ) -> Bool {
            handleAction(
                appPtr,
                target: target,
                action: action,
                routingLookupProvider: { @MainActor in SurfaceManager.shared }
            )
        }

        private static func handleAction(
            _ appPtr: ghostty_app_t,
            target: ghostty_target_s,
            action: ghostty_action_s,
            routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
        ) -> Bool {
            let rawActionTag = UInt32(truncatingIfNeeded: action.tag.rawValue)
            guard let actionTag = GhosttyActionTag(rawValue: rawActionTag) else {
                return routeUnhandledAction(
                    actionTag: rawActionTag,
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )
            }

            switch actionTag {
            case .quit:
                // Don't quit - AgentStudio manages its own window lifecycle
                // Ghostty sends this when all surfaces are closed, but we want to stay running
                return true

            case .newWindow:
                ghosttyLogger.debug(
                    "Ignoring Ghostty newWindow action because AgentStudio owns window lifecycle"
                )
                return true

            case .newTab:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .noPayload,
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )

            case .ringBell:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .noPayload,
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )

            case .setTitle:
                guard let titlePtr = action.action.set_title.title else {
                    return routeUnhandledAction(
                        actionTag: rawActionTag,
                        target: target,
                        routingLookupProvider: routingLookupProvider
                    )
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
                    target: target,
                    routingLookupProvider: routingLookupProvider
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
                    return routeUnhandledAction(
                        actionTag: rawActionTag,
                        target: target,
                        routingLookupProvider: routingLookupProvider
                    )
                }
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .cwdChanged(cwdPath),
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )

            case .newSplit:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .newSplit(directionRawValue: action.action.new_split.rawValue),
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )

            case .gotoSplit:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .gotoSplit(directionRawValue: action.action.goto_split.rawValue),
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )

            case .resizeSplit:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .resizeSplit(
                        amount: action.action.resize_split.amount,
                        directionRawValue: action.action.resize_split.direction.rawValue
                    ),
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )

            case .equalizeSplits:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .noPayload,
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )

            case .toggleSplitZoom:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .noPayload,
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )

            case .closeTab:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .closeTab(modeRawValue: action.action.close_tab_mode.rawValue),
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )

            case .gotoTab:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .gotoTab(targetRawValue: action.action.goto_tab.rawValue),
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )

            case .moveTab:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .moveTab(amount: Int(action.action.move_tab.amount)),
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )
            case .commandFinished:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .commandFinished(
                        exitCode: Int(action.action.command_finished.exit_code),
                        duration: action.action.command_finished.duration
                    ),
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )
            case .initialSize:
                updateReportedSurfaceSize(target: target, action: action, kind: .initial)
                return routeUnhandledAction(
                    actionTag: rawActionTag,
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )
            case .cellSize:
                updateReportedSurfaceSize(target: target, action: action, kind: .cell)
                return routeUnhandledAction(
                    actionTag: rawActionTag,
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )
            case .closeAllWindows, .toggleMaximize, .toggleFullscreen, .toggleTabOverview,
                .toggleWindowDecorations, .toggleQuickTerminal, .toggleCommandPalette, .toggleVisibility,
                .toggleBackgroundOpacity, .gotoWindow, .presentTerminal, .sizeLimit, .resetWindowSize,
                .scrollbar, .render, .inspector, .showGtkInspector, .renderInspector,
                .desktopNotification, .promptTitle, .mouseShape, .mouseVisibility, .mouseOverLink,
                .rendererHealth, .openConfig, .quitTimer, .floatWindow, .secureInput, .keySequence, .keyTable,
                .colorChange, .reloadConfig, .configChange, .closeWindow, .undo, .redo, .checkForUpdates,
                .openURL, .showChildExited, .progressReport, .showOnScreenKeyboard,
                .startSearch, .endSearch, .searchTotal, .searchSelected, .readOnly, .copyTitleToClipboard:
                return routeUnhandledAction(
                    actionTag: rawActionTag,
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )
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

        private enum ReportedSurfaceSizeKind {
            case initial
            case cell
        }

        private static func updateReportedSurfaceSize(
            target: ghostty_target_s,
            action: ghostty_action_s,
            kind: ReportedSurfaceSizeKind
        ) {
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                let surface = target.target.surface,
                let resolvedSurfaceView = surfaceView(from: surface)
            else { return }

            switch kind {
            case .initial:
                let size = NSSize(
                    width: Double(action.action.initial_size.width),
                    height: Double(action.action.initial_size.height)
                )
                Task { @MainActor [weak resolvedSurfaceView] in
                    resolvedSurfaceView?.updateReportedInitialSize(size)
                }
            case .cell:
                let backingSize = NSSize(
                    width: Double(action.action.cell_size.width),
                    height: Double(action.action.cell_size.height)
                )
                Task { @MainActor [weak resolvedSurfaceView] in
                    guard let resolvedSurfaceView else { return }
                    let logicalSize = resolvedSurfaceView.convertFromBacking(backingSize)
                    resolvedSurfaceView.updateReportedCellSize(logicalSize)
                }
            }
        }

        private static func routeUnhandledAction(
            actionTag: UInt32,
            target: ghostty_target_s,
            routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
        ) -> Bool {
            let targetTag = UInt32(truncatingIfNeeded: target.tag.rawValue)
            if target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface {
                let surfacePointerDescription = String(UInt(bitPattern: surface))
                if let resolvedSurfaceView = surfaceView(from: surface) {
                    let surfaceViewObjectId = ObjectIdentifier(resolvedSurfaceView)
                    Task { @MainActor in
                        let routingLookup = routingLookupProvider()
                        let paneIdDescription: String
                        if let surfaceId = routingLookup.surfaceId(forViewObjectId: surfaceViewObjectId),
                            let paneId = routingLookup.paneId(for: surfaceId)
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
                return false
            }
            _ = routeActionToTerminalRuntime(
                actionTag: actionTag,
                payload: .noPayload,
                target: target,
                routingLookupProvider: routingLookupProvider
            )
            return false
        }

        static func shouldForwardUnhandledActionToRuntime(actionTag: UInt32) -> Bool {
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
            target: ghostty_target_s,
            routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
        ) -> Bool {
            guard target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface else {
                return false
            }

            guard let resolvedSurfaceView = surfaceView(from: surface) else {
                ghosttyLogger.warning("Dropped action tag \(actionTag): no surface view for callback target")
                return true
            }

            let surfaceViewObjectId = ObjectIdentifier(resolvedSurfaceView)
            // Returning `true` here preserves Ghostty's synchronous "handled" contract
            // while the actual runtime delivery completes on MainActor.
            Task { @MainActor in
                let routingLookup = routingLookupProvider()
                _ = routeActionToTerminalRuntimeOnMainActor(
                    actionTag: actionTag,
                    payload: payload,
                    surfaceViewObjectId: surfaceViewObjectId,
                    routingLookup: routingLookup
                )
            }
            return true
        }

        @MainActor
        static func routeActionToTerminalRuntimeOnMainActor(
            actionTag: UInt32,
            payload: GhosttyAdapter.ActionPayload,
            surfaceViewObjectId: ObjectIdentifier
        ) -> Bool {
            routeActionToTerminalRuntimeOnMainActor(
                actionTag: actionTag,
                payload: payload,
                surfaceViewObjectId: surfaceViewObjectId,
                routingLookup: SurfaceManager.shared
            )
        }

        @MainActor
        static func routeActionToTerminalRuntimeOnMainActor(
            actionTag: UInt32,
            payload: GhosttyAdapter.ActionPayload,
            surfaceViewObjectId: ObjectIdentifier,
            routingLookup: any GhosttyActionRoutingLookup
        ) -> Bool {
            guard let surfaceId = routingLookup.surfaceId(forViewObjectId: surfaceViewObjectId) else {
                ghosttyLogger.warning("Dropped action tag \(actionTag): surface not registered in SurfaceManager")
                return false
            }
            guard let paneUUID = routingLookup.paneId(for: surfaceId) else {
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

        static func surfaceView(from surface: ghostty_surface_t) -> SurfaceView? {
            guard let userdata = ghostty_surface_userdata(surface) else { return nil }
            return Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        }
    }
}
