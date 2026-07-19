import AppKit
import Foundation
import GhosttyKit

@MainActor
protocol GhosttyActionRoutingLookup: AnyObject {
    func surfaceId(forViewObjectId viewObjectId: ObjectIdentifier) -> UUID?
    func paneId(for surfaceId: UUID) -> UUID?
}

extension SurfaceManager: GhosttyActionRoutingLookup {}

typealias GhosttyActionRoutingLookupProvider = @MainActor @Sendable () -> any GhosttyActionRoutingLookup

extension Ghostty {
    /// Owns Ghostty action-tag handling, host-side suppression, and trace emission.
    enum ActionRouter {
        @MainActor private static var runtimeRegistryOverride: RuntimeRegistry = .shared
        @MainActor static var startupTraceRecorder: AgentStudioStartupTraceRecorder?
        static let actionTraceQueueStore = GhosttyActionTraceQueueStore()
        static let localActionAccumulator = TerminalLocalActionAccumulator { surfaceID in
            Task { @MainActor in
                await drainLocalActions(for: surfaceID)
            }
        }
        static let explicitlyRoutedTags: Set<GhosttyActionTag> = [
            .newTab,
            .ringBell,
            .setTitle,
            .setTabTitle,
            .pwd,
            .newSplit,
            .gotoSplit,
            .resizeSplit,
            .equalizeSplits,
            .toggleSplitZoom,
            .closeTab,
            .gotoTab,
            .moveTab,
            .sizeLimit,
            .initialSize,
            .cellSize,
            .desktopNotification,
            .promptTitle,
            .mouseShape,
            .mouseVisibility,
            .mouseOverLink,
            .rendererHealth,
            .secureInput,
            .keySequence,
            .keyTable,
            .colorChange,
            .reloadConfig,
            .configChange,
            .undo,
            .redo,
            .openURL,
            .progressReport,
            .commandFinished,
            .scrollbar,
            .startSearch,
            .endSearch,
            .searchTotal,
            .searchSelected,
            .readOnly,
            .copyTitleToClipboard,
        ]
        static let deferredTags: Set<GhosttyActionTag> = []
        static let interceptedTags: Set<GhosttyActionTag> = [
            .quit,
            .newWindow,
            .closeAllWindows,
            .toggleMaximize,
            .toggleFullscreen,
            .toggleTabOverview,
            .toggleWindowDecorations,
            .toggleQuickTerminal,
            .toggleCommandPalette,
            .toggleVisibility,
            .toggleBackgroundOpacity,
            .gotoWindow,
            .presentTerminal,
            .resetWindowSize,
            .inspector,
            .showGtkInspector,
            .renderInspector,
            .render,
            .openConfig,
            .quitTimer,
            .floatWindow,
            .closeWindow,
            .checkForUpdates,
            .showChildExited,
            .showOnScreenKeyboard,
        ]

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
                traceGhosttyAction(
                    body: "ghostty.action.received",
                    actionTag: rawActionTag,
                    signalClass: .unhandled,
                    routeResult: false,
                    reason: "unknown_action"
                )
                logUnknownAction(actionTag: rawActionTag, target: target, routingLookupProvider: routingLookupProvider)
                return false
            }

            traceGhosttyAction(
                body: "ghostty.action.received",
                actionTag: rawActionTag,
                signalClass: signalClass(for: actionTag),
                routeResult: nil,
                reason: nil
            )

            if interceptedTags.contains(actionTag) {
                return handleInterceptedAction(
                    actionTag,
                    rawActionTag: rawActionTag,
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )
            }
            if let workspaceActionResult = handleWorkspaceAction(
                actionTag,
                rawActionTag: rawActionTag,
                target: target,
                action: action,
                routingLookupProvider: routingLookupProvider
            ) {
                return workspaceActionResult
            }

            if let observedActionResult = handleObservedAction(
                actionTag,
                rawActionTag: rawActionTag,
                target: target,
                action: action,
                routingLookupProvider: routingLookupProvider
            ) {
                return observedActionResult
            }

            preconditionFailure("Ghostty action tag \(actionTag) missing routing decision")
        }

        private static func handleWorkspaceAction(
            _ actionTag: GhosttyActionTag,
            rawActionTag: UInt32,
            target: ghostty_target_s,
            action: ghostty_action_s,
            routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
        ) -> Bool? {
            if let metadataAction = handleMetadataAction(
                actionTag,
                rawActionTag: rawActionTag,
                target: target,
                action: action,
                routingLookupProvider: routingLookupProvider
            ) {
                return metadataAction
            }

            if let splitAction = handleSplitAction(
                actionTag,
                rawActionTag: rawActionTag,
                target: target,
                action: action,
                routingLookupProvider: routingLookupProvider
            ) {
                return splitAction
            }

            if let tabAction = handleTabAction(
                actionTag,
                rawActionTag: rawActionTag,
                target: target,
                action: action,
                routingLookupProvider: routingLookupProvider
            ) {
                return tabAction
            }

            return nil
        }

        private static func handleMetadataAction(
            _ actionTag: GhosttyActionTag,
            rawActionTag: UInt32,
            target: ghostty_target_s,
            action: ghostty_action_s,
            routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
        ) -> Bool? {
            switch actionTag {
            case .setTitle:
                guard let titlePtr = action.action.set_title.title else {
                    logUnknownAction(
                        actionTag: rawActionTag, target: target, routingLookupProvider: routingLookupProvider)
                    return false
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
                    routingLookupProvider: routingLookupProvider,
                    handledResult: true
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
                    logUnknownAction(
                        actionTag: rawActionTag, target: target, routingLookupProvider: routingLookupProvider)
                    return false
                }
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .cwdChanged(cwdPath),
                    target: target,
                    routingLookupProvider: routingLookupProvider,
                    handledResult: true
                )
            default:
                return nil
            }
        }

        private static func handleSplitAction(
            _ actionTag: GhosttyActionTag,
            rawActionTag: UInt32,
            target: ghostty_target_s,
            action: ghostty_action_s,
            routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
        ) -> Bool? {
            switch actionTag {
            case .newSplit:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .newSplit(directionRawValue: action.action.new_split.rawValue),
                    target: target,
                    routingLookupProvider: routingLookupProvider,
                    handledResult: true
                )
            case .gotoSplit:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .gotoSplit(directionRawValue: action.action.goto_split.rawValue),
                    target: target,
                    routingLookupProvider: routingLookupProvider,
                    handledResult: true
                )
            case .resizeSplit:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .resizeSplit(
                        amount: action.action.resize_split.amount,
                        directionRawValue: action.action.resize_split.direction.rawValue
                    ),
                    target: target,
                    routingLookupProvider: routingLookupProvider,
                    handledResult: true
                )
            case .equalizeSplits:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .noPayload,
                    target: target,
                    routingLookupProvider: routingLookupProvider,
                    handledResult: true
                )
            case .toggleSplitZoom:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .noPayload,
                    target: target,
                    routingLookupProvider: routingLookupProvider,
                    handledResult: true
                )
            default:
                return nil
            }
        }

        private static func handleTabAction(
            _ actionTag: GhosttyActionTag,
            rawActionTag: UInt32,
            target: ghostty_target_s,
            action: ghostty_action_s,
            routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
        ) -> Bool? {
            switch actionTag {
            case .newTab, .ringBell:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .noPayload,
                    target: target,
                    routingLookupProvider: routingLookupProvider,
                    handledResult: true
                )
            case .closeTab:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .closeTab(modeRawValue: action.action.close_tab_mode.rawValue),
                    target: target,
                    routingLookupProvider: routingLookupProvider,
                    handledResult: true
                )
            case .gotoTab:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .gotoTab(targetRawValue: action.action.goto_tab.rawValue),
                    target: target,
                    routingLookupProvider: routingLookupProvider,
                    handledResult: true
                )
            case .moveTab:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .moveTab(amount: Int(action.action.move_tab.amount)),
                    target: target,
                    routingLookupProvider: routingLookupProvider,
                    handledResult: true
                )
            case .commandFinished:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .commandFinished(
                        exitCode: Int(action.action.command_finished.exit_code),
                        duration: action.action.command_finished.duration
                    ),
                    target: target,
                    routingLookupProvider: routingLookupProvider,
                    handledResult: true
                )
            default:
                return nil
            }
        }

        private static func handleObservedAction(
            _ actionTag: GhosttyActionTag,
            rawActionTag: UInt32,
            target: ghostty_target_s,
            action: ghostty_action_s,
            routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
        ) -> Bool? {
            if let sizeAction = handleObservedSizeAction(
                actionTag,
                rawActionTag: rawActionTag,
                target: target,
                action: action,
                routingLookupProvider: routingLookupProvider
            ) {
                return sizeAction
            }

            if let requestAction = handleObservedRequestAction(
                actionTag,
                rawActionTag: rawActionTag,
                target: target,
                action: action,
                routingLookupProvider: routingLookupProvider
            ) {
                return requestAction
            }

            if let passthroughAction = handleObservedPassthroughAction(
                actionTag,
                rawActionTag: rawActionTag,
                target: target,
                action: action,
                routingLookupProvider: routingLookupProvider
            ) {
                return passthroughAction
            }

            return nil
        }

        private static func handleObservedSizeAction(
            _ actionTag: GhosttyActionTag,
            rawActionTag: UInt32,
            target: ghostty_target_s,
            action: ghostty_action_s,
            routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
        ) -> Bool? {
            switch actionTag {
            case .setTabTitle:
                guard let titlePtr = action.action.set_tab_title.title else {
                    logUnknownAction(
                        actionTag: rawActionTag, target: target, routingLookupProvider: routingLookupProvider)
                    return false
                }
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .tabTitleChanged(String(cString: titlePtr)),
                    target: target,
                    routingLookupProvider: routingLookupProvider,
                    handledResult: false
                )
            case .sizeLimit:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .sizeLimitChanged(
                        minWidth: action.action.size_limit.min_width,
                        minHeight: action.action.size_limit.min_height,
                        maxWidth: action.action.size_limit.max_width,
                        maxHeight: action.action.size_limit.max_height
                    ),
                    target: target,
                    routingLookupProvider: routingLookupProvider,
                    handledResult: false
                )
            case .initialSize:
                updateReportedSurfaceSize(target: target, action: action, kind: .initial)
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .initialSizeChanged(
                        width: action.action.initial_size.width,
                        height: action.action.initial_size.height
                    ),
                    target: target,
                    routingLookupProvider: routingLookupProvider,
                    handledResult: false
                )
            case .cellSize:
                updateReportedSurfaceSize(target: target, action: action, kind: .cell)
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .cellSizeChanged(
                        width: action.action.cell_size.width,
                        height: action.action.cell_size.height
                    ),
                    target: target,
                    routingLookupProvider: routingLookupProvider,
                    handledResult: false
                )
            default:
                return nil
            }
        }

        private static func handleObservedRequestAction(
            _ actionTag: GhosttyActionTag,
            rawActionTag: UInt32,
            target: ghostty_target_s,
            action: ghostty_action_s,
            routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
        ) -> Bool? {
            if let displayAction = handleObservedDisplayAction(
                actionTag,
                rawActionTag: rawActionTag,
                target: target,
                action: action,
                routingLookupProvider: routingLookupProvider
            ) {
                return displayAction
            }
            if let inputAction = handleObservedInputAction(
                actionTag,
                rawActionTag: rawActionTag,
                target: target,
                action: action,
                routingLookupProvider: routingLookupProvider
            ) {
                return inputAction
            }
            if let configAction = handleObservedConfigurationAction(
                actionTag,
                rawActionTag: rawActionTag,
                target: target,
                action: action,
                routingLookupProvider: routingLookupProvider
            ) {
                return configAction
            }
            if let searchAction = handleObservedSearchAction(
                actionTag,
                rawActionTag: rawActionTag,
                target: target,
                action: action,
                routingLookupProvider: routingLookupProvider
            ) {
                return searchAction
            }
            if let controlAction = handleObservedControlAction(
                actionTag,
                rawActionTag: rawActionTag,
                target: target,
                action: action,
                routingLookupProvider: routingLookupProvider
            ) {
                return controlAction
            }
            return nil
        }

        private static func handleObservedPassthroughAction(
            _ actionTag: GhosttyActionTag,
            rawActionTag: UInt32,
            target: ghostty_target_s,
            action _: ghostty_action_s,
            routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
        ) -> Bool? {
            switch actionTag {
            case .undo, .redo, .copyTitleToClipboard:
                return routeActionToTerminalRuntime(
                    actionTag: rawActionTag,
                    payload: .noPayload,
                    target: target,
                    routingLookupProvider: routingLookupProvider,
                    handledResult: false
                )
            default:
                return nil
            }
        }

        @MainActor
        static func setRuntimeRegistry(_ runtimeRegistry: RuntimeRegistry) {
            runtimeRegistryOverride = runtimeRegistry
        }

        @MainActor
        static func bindTraceRuntime(_ runtime: AgentStudioTraceRuntime?) {
            actionTraceQueueStore.bind(runtime)
        }

        @MainActor
        static func bindStartupTraceRecorder(_ recorder: AgentStudioStartupTraceRecorder?) {
            startupTraceRecorder = recorder
        }

        @MainActor
        static func drainTraceRuntimeForActionRouting() async {
            do {
                try await actionTraceQueueStore.drain()
            } catch {
                ghosttyLogger.warning("Ghostty action trace drain failed: \(error.localizedDescription)")
            }
        }

        @MainActor
        static var runtimeRegistryForActionRouting: RuntimeRegistry {
            runtimeRegistryOverride
        }

        private enum ReportedSurfaceSizeKind: CustomStringConvertible {
            case initial
            case cell

            var description: String {
                switch self {
                case .initial: return "initial"
                case .cell: return "cell"
                }
            }
        }

        private static func updateReportedSurfaceSize(
            target: ghostty_target_s,
            action: ghostty_action_s,
            kind: ReportedSurfaceSizeKind
        ) {
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                let surface = target.target.surface,
                let resolvedSurfaceView = surfaceView(from: surface)
            else {
                ghosttyLogger.debug(
                    "updateReportedSurfaceSize dropped: target is not a resolvable surface (kind=\(kind))")
                return
            }

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

        static func logUnknownAction(
            actionTag: UInt32,
            target: ghostty_target_s,
            routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
        ) {
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
        }

        static func routeActionToTerminalRuntime(
            actionTag: UInt32,
            payload: GhosttyAdapter.ActionPayload,
            target: ghostty_target_s,
            routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider,
            handledResult: Bool
        ) -> Bool {
            guard target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface else {
                ghosttyLogger.debug(
                    "routeActionToTerminalRuntime dropped action tag \(actionTag): target is not a surface"
                )
                return false
            }

            guard let resolvedSurfaceView = surfaceView(from: surface) else {
                ghosttyLogger.warning("Dropped action tag \(actionTag): no surface view for callback target")
                return handledResult
            }

            let event = GhosttyAdapter.shared.translate(actionTag: actionTag, payload: payload)
            let disposition = admitTranslatedActionToTerminalRuntime(
                event,
                surfaceID: resolvedSurfaceView.managedSurfaceID,
                accumulator: localActionAccumulator
            )
            switch disposition {
            case .routeExactFactOrControl:
                break
            case .updateDirectHostState:
                Task { @MainActor [weak resolvedSurfaceView] in
                    guard let resolvedSurfaceView else { return }
                    updateSurfaceHostCache(
                        actionTag: actionTag,
                        payload: payload,
                        surfaceView: resolvedSurfaceView
                    )
                }
                return handledResult
            case .handledLocally:
                return handledResult
            }

            let surfaceViewObjectId = ObjectIdentifier(resolvedSurfaceView)
            // Preserve Ghostty's synchronous handled contract while the actual runtime
            // delivery completes on MainActor.
            Task { @MainActor [weak resolvedSurfaceView] in
                if let resolvedSurfaceView {
                    updateSurfaceHostCache(
                        actionTag: actionTag,
                        payload: payload,
                        surfaceView: resolvedSurfaceView
                    )
                }
                let routingLookup = routingLookupProvider()
                _ = routeActionToTerminalRuntimeOnMainActor(
                    actionTag: actionTag,
                    payload: payload,
                    surfaceViewObjectId: surfaceViewObjectId,
                    routingLookup: routingLookup
                )
            }
            return handledResult
        }

        @MainActor
        private static func updateSurfaceHostCache(
            actionTag: UInt32,
            payload: GhosttyAdapter.ActionPayload,
            surfaceView: SurfaceView
        ) {
            guard let knownActionTag = GhosttyActionTag(rawValue: actionTag) else { return }

            switch knownActionTag {
            case .scrollbar:
                guard case .scrollbar(let total, let offset, let length) = payload else { return }
                surfaceView.updateHostScrollbarState(
                    ScrollbarState(
                        top: Int(offset),
                        bottom: Int(offset + length),
                        total: Int(total)
                    )
                )
            case .configChange, .reloadConfig:
                surfaceView.updateHostConfigSnapshot(Ghostty.shared.hostConfigSnapshot())
            default:
                return
            }
        }

        @MainActor
        static func routeActionToTerminalRuntimeOnMainActor(
            actionTag: UInt32,
            payload: GhosttyAdapter.ActionPayload,
            surfaceViewObjectId: ObjectIdentifier,
            routingLookup: any GhosttyActionRoutingLookup
        ) -> Bool {
            guard let surfaceId = routingLookup.surfaceId(forViewObjectId: surfaceViewObjectId) else {
                traceGhosttyAction(
                    body: "ghostty.action.dropped",
                    actionTag: actionTag,
                    payload: payload,
                    signalClass: .unhandled,
                    routeResult: false,
                    reason: "surface_not_registered"
                )
                ghosttyLogger.warning("Dropped action tag \(actionTag): surface not registered in SurfaceManager")
                return false
            }
            guard let paneUUID = routingLookup.paneId(for: surfaceId) else {
                traceGhosttyAction(
                    body: "ghostty.action.dropped",
                    actionTag: actionTag,
                    payload: payload,
                    surfaceId: surfaceId,
                    signalClass: .unhandled,
                    routeResult: false,
                    reason: "pane_not_mapped"
                )
                ghosttyLogger.warning("Dropped action tag \(actionTag): no pane mapped for surface \(surfaceId)")
                return false
            }
            let paneId = PaneId(existingUUID: paneUUID)
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
                traceGhosttyAction(
                    body: "ghostty.action.dropped",
                    actionTag: actionTag,
                    payload: payload,
                    paneId: paneUUID,
                    surfaceId: surfaceId,
                    signalClass: .unhandled,
                    routeResult: false,
                    reason: "runtime_not_found"
                )
                ghosttyLogger.warning(
                    "Dropped action tag \(actionTag): terminal runtime not found for pane \(paneUUID)")
                return false
            }

            let event = GhosttyAdapter.shared.translate(actionTag: actionTag, payload: payload)
            traceGhosttyAction(
                body: "ghostty.action.translated",
                actionTag: actionTag,
                payload: payload,
                event: event,
                paneId: paneUUID,
                surfaceId: surfaceId,
                signalClass: signalClass(for: event, fallbackActionTag: actionTag),
                routeResult: true,
                reason: nil
            )
            traceTerminalStartupMilestones(
                actionTag: actionTag,
                event: event,
                paneID: paneUUID,
                surfaceID: surfaceId
            )
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
