import AppKit
import Foundation
import GhosttyKit
import Observation
import QuartzCore

extension Ghostty {
    enum SurfaceStartupStrategy: Equatable {
        /// Pass this command directly to Ghostty when creating the surface.
        case surfaceCommand(String?)

        var startupCommandForSurface: String? {
            if case .surfaceCommand(let command) = self {
                return command
            }
            return nil
        }
    }

    /// Errors that can occur during surface creation
    enum SurfaceCreationError: Error, LocalizedError {
        case failedToCreate
        case appNotInitialized

        var errorDescription: String? {
            switch self {
            case .failedToCreate:
                return "Failed to create terminal surface"
            case .appNotInitialized:
                return "Ghostty app not initialized"
            }
        }
    }

    /// Configuration for creating a new surface
    struct SurfaceConfiguration {
        var launchDirectory: String?
        var startupStrategy: SurfaceStartupStrategy
        var initialFrame: NSRect?
        var fontSize: Float?
        var environmentVariables: [String: String]

        var hasValidInitialFrameForSurfaceCreation: Bool {
            guard let initialFrame else { return false }
            return !initialFrame.isEmpty
        }

        func requireInitialFrameForSurfaceCreation() {
            precondition(
                hasValidInitialFrameForSurfaceCreation,
                "Ghostty terminal surfaces must not start without a non-empty initialFrame"
            )
        }

        init(
            launchDirectory: String? = nil,
            startupStrategy: SurfaceStartupStrategy = .surfaceCommand(nil),
            initialFrame: NSRect? = nil,
            fontSize: Float? = nil,
            environmentVariables: [String: String] = [:]
        ) {
            self.launchDirectory = launchDirectory
            self.startupStrategy = startupStrategy
            self.initialFrame = initialFrame
            self.fontSize = fontSize
            self.environmentVariables = environmentVariables
        }
    }

    /// NSView subclass that renders a Ghostty terminal surface
    final class SurfaceView: NSView {
        var onWorkingDirectoryChanged: (@MainActor @Sendable (ObjectIdentifier, String?) -> Void)?
        var onRendererHealthChanged: (@MainActor @Sendable (ObjectIdentifier, Bool) -> Void)?
        var onCloseRequested: (@MainActor @Sendable (Bool) -> Void)?

        /// Tracks whether the surface was previously detached from a window.
        /// Used for instrumentation: distinguishes reparenting (nil→window) from initial attachment.
        private var wasDetachedFromWindow = false

        /// The terminal title (published for observation)
        private(set) var title: String = ""

        /// The ghostty surface handle
        nonisolated(unsafe) private(set) var surface: ghostty_surface_t?

        /// The ghostty app reference
        private weak var ghosttyApp: App?

        /// Marked text for input method
        var markedText = NSMutableAttributedString()

        /// Whether this view has focus
        private(set) var focused: Bool = false

        /// Text accumulator for key events
        var keyTextAccumulator: [String]?

        /// Content size for the terminal (may differ from frame during resize)
        private var contentSize: NSSize = .zero

        /// Initial content size reported by Ghostty action callbacks.
        private(set) var reportedInitialSize: NSSize?

        /// Cell size reported by Ghostty action callbacks.
        private(set) var reportedCellSize: NSSize?
        /// One-time redraw nudge for narrow panes whose prompt/cursor row can land incorrectly
        /// after restore-time replay + resize. This is an app-side workaround, not a root fix.
        private var hasPerformedNarrowPaneRedrawNudge = false

        /// Current working directory reported by the shell via OSC 7
        private(set) var pwd: String? {
            didSet {
                if pwd != oldValue {
                    let surfaceViewId = ObjectIdentifier(self)
                    let updatedPwd = pwd
                    RestoreTrace.log(
                        "Ghostty.SurfaceView.scheduleWorkingDirectoryChanged view=\(surfaceViewId) mainThread=\(Thread.isMainThread)"
                    )
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.onWorkingDirectoryChanged?(surfaceViewId, updatedPwd)
                    }
                }
            }
        }

        /// Health state of the renderer (for crash isolation)
        private(set) var healthy: Bool = true {
            didSet {
                if healthy != oldValue {
                    let surfaceViewId = ObjectIdentifier(self)
                    let updatedHealth = healthy
                    RestoreTrace.log(
                        "Ghostty.SurfaceView.scheduleRendererHealthChanged view=\(surfaceViewId) healthy=\(updatedHealth) mainThread=\(Thread.isMainThread)"
                    )
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.onRendererHealthChanged?(surfaceViewId, updatedHealth)
                    }
                }
            }
        }

        /// Any error during surface initialization
        private(set) var error: Error?
        weak var terminalRuntime: TerminalRuntime?
        let mouseVisibilityToken = UUID()
        // MARK: - Initialization

        init(app: App, config: SurfaceConfiguration? = nil) {
            guard let config else {
                preconditionFailure(
                    "Ghostty SurfaceView requires a SurfaceConfiguration with initialFrame"
                )
            }
            config.requireInitialFrameForSurfaceCreation()
            self.ghosttyApp = app
            super.init(frame: config.initialFrame!)
            let startupCommandForSurface = config.startupStrategy.startupCommandForSurface
            RestoreTrace.log(
                "Ghostty.SurfaceView.init placeholderFrame=\(NSStringFromRect(frame)) cwd=\(config.launchDirectory ?? "nil") hasCommand=\(startupCommandForSurface != nil)"
            )

            // Note: Ghostty's Metal renderer will set up the layer properly
            // when creating the surface. Do NOT set wantsLayer before that.

            // Create surface
            guard let ghosttyApp = app.app else {
                ghosttyLogger.error("Cannot create surface: ghostty app is nil")
                return
            }

            var surfaceConfig = ghostty_surface_config_new()
            surfaceConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
            surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
            surfaceConfig.platform = ghostty_platform_u(
                macos: ghostty_platform_macos_s(
                    nsview: Unmanaged.passUnretained(self).toOpaque()
                ))
            surfaceConfig.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2.0)
            surfaceConfig.font_size = config.fontSize ?? 0

            let createSurfaceWithStrings: () -> Void = {
                // Set working directory/command if provided.
                if let wd = config.launchDirectory {
                    wd.withCString { wdPtr in
                        surfaceConfig.working_directory = wdPtr

                        if let cmd = startupCommandForSurface {
                            cmd.withCString { cmdPtr in
                                surfaceConfig.command = cmdPtr
                                self.surface = ghostty_surface_new(ghosttyApp, &surfaceConfig)
                            }
                        } else {
                            self.surface = ghostty_surface_new(ghosttyApp, &surfaceConfig)
                        }
                    }
                } else if let cmd = startupCommandForSurface {
                    cmd.withCString { cmdPtr in
                        surfaceConfig.command = cmdPtr
                        self.surface = ghostty_surface_new(ghosttyApp, &surfaceConfig)
                    }
                } else {
                    self.surface = ghostty_surface_new(ghosttyApp, &surfaceConfig)
                }
            }

            let envVars = config.environmentVariables
            if envVars.isEmpty {
                createSurfaceWithStrings()
            } else {
                // Keep key/value C strings alive for the duration of ghostty_surface_new.
                let pairs = envVars.sorted { $0.key < $1.key }
                var rawPointers: [UnsafeMutablePointer<CChar>?] = []
                rawPointers.reserveCapacity(pairs.count * 2)
                var cEnvVars: [ghostty_env_var_s] = []
                cEnvVars.reserveCapacity(pairs.count)

                for (key, value) in pairs {
                    let keyPtr = strdup(key)
                    let valuePtr = strdup(value)
                    rawPointers.append(keyPtr)
                    rawPointers.append(valuePtr)
                    cEnvVars.append(
                        ghostty_env_var_s(
                            key: UnsafePointer<CChar>(keyPtr),
                            value: UnsafePointer<CChar>(valuePtr)
                        )
                    )
                }

                defer {
                    for ptr in rawPointers {
                        if let ptr {
                            free(ptr)
                        }
                    }
                }

                cEnvVars.withUnsafeMutableBufferPointer { envBuffer in
                    surfaceConfig.env_vars = envBuffer.baseAddress
                    surfaceConfig.env_var_count = envVars.count
                    createSurfaceWithStrings()
                }
            }

            if self.surface == nil {
                ghosttyLogger.error("Failed to create ghostty surface")
                self.error = SurfaceCreationError.failedToCreate
                self.healthy = false
                RestoreTrace.log("Ghostty.SurfaceView.init failed")
            } else {
                ghosttyLogger.info("Ghostty surface created successfully")
                RestoreTrace.log("Ghostty.SurfaceView.init success frame=\(NSStringFromRect(frame))")
                // Set initial size using backing coordinates
                sizeDidChange(frame.size, source: "init")
                logSurfaceSnapshot(reason: "init")
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            let mouseVisibilityToken = self.mouseVisibilityToken
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    GhosttyMouseVisibilityCoordinator.release(token: mouseVisibilityToken)
                }
            } else {
                Task { @MainActor in
                    GhosttyMouseVisibilityCoordinator.release(token: mouseVisibilityToken)
                }
            }
            if let surface {
                ghostty_surface_free(surface)
            }
        }

        /// Called when the title changes (from App callback)
        func titleDidChange(_ newTitle: String) {
            self.title = newTitle
            RestoreTrace.log(
                "Ghostty.SurfaceView.titleDidChange title=\(newTitle) \(metricsSnapshotDescription())"
            )
        }

        func pwdDidChange(_ newPwd: String?) {
            self.pwd = newPwd
            RestoreTrace.log(
                "Ghostty.SurfaceView.pwdDidChange pwd=\(newPwd ?? "nil") \(metricsSnapshotDescription())"
            )
        }

        func handleCloseRequested(processAlive: Bool) {
            RestoreTrace.log(
                "Ghostty.SurfaceView.scheduleCloseRequested processAlive=\(processAlive) mainThread=\(Thread.isMainThread)"
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onCloseRequested?(processAlive)
            }
        }

        // MARK: - View Lifecycle

        override var acceptsFirstResponder: Bool { true }

        override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder()
            if result {
                focused = true
                if let surface {
                    ghostty_surface_set_focus(surface, true)
                }
                applyMouseVisibility(isVisible: terminalRuntime?.isMouseVisible ?? true)
                logSurfaceSnapshot(reason: "becomeFirstResponder")
            }
            return result
        }

        override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder()
            if result {
                focused = false
                if let surface {
                    ghostty_surface_set_focus(surface, false)
                }
                applyMouseVisibility(isVisible: true)
                logSurfaceSnapshot(reason: "resignFirstResponder")
            }
            return result
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let isReparent = wasDetachedFromWindow && window != nil
            let viewId = ObjectIdentifier(self)
            let superviewInfo: String
            if let sv = superview {
                superviewInfo = "class=\(type(of: sv)) id=\(ObjectIdentifier(sv))"
            } else {
                superviewInfo = "nil"
            }
            let hierarchyDescription =
                (window == nil || isReparent)
                ? " ancestry=\(viewHierarchyDescription())"
                : ""
            RestoreTrace.log(
                "Ghostty.SurfaceView.viewDidMoveToWindow viewId=\(viewId) window=\(window != nil) reparent=\(isReparent) wasDetached=\(wasDetachedFromWindow) frame=\(NSStringFromRect(frame)) bounds=\(NSStringFromRect(bounds)) superview=\(superviewInfo) hidden=\(isHidden)\(hierarchyDescription)"
            )
            if window == nil {
                wasDetachedFromWindow = true
            }
            logSurfaceSnapshot(reason: "viewDidMoveToWindow")

            if let screen = window?.screen {
                updateScaleFactor(screen.backingScaleFactor)
                RestoreTrace.log("Ghostty.SurfaceView.updateScaleFactor scale=\(screen.backingScaleFactor)")
            }

            // The surface is created at a placeholder 800×600 frame before the
            // view enters any window hierarchy.  Once Auto Layout resolves the
            // actual frame (which happens after the current run-loop iteration),
            // re-send dimensions so the PTY and any attached zmx session see the
            // correct terminal size.  Without this, restored sessions remain at
            // the placeholder grid size because setFrameSize may never fire if
            // the parent PaneHostView was also initialized at the same placeholder.
            if window != nil, surface != nil {
                Task { @MainActor [weak self] in
                    guard let self, self.window != nil else { return }
                    let size = self.frame.size
                    guard size.width > 0 && size.height > 0 else { return }
                    RestoreTrace.log(
                        "Ghostty.SurfaceView.viewDidMoveToWindow async sizeDidChange size=\(NSStringFromSize(size)) frame=\(NSStringFromRect(self.frame))"
                    )
                    self.sizeDidChange(size, source: "viewDidMoveToWindow")
                    self.logSurfaceSnapshot(reason: "viewDidMoveToWindow.asyncSizeDidChange")
                }
            }
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            // Remove all existing tracking areas
            for area in trackingAreas {
                removeTrackingArea(area)
            }
            // Add new tracking area covering the entire view
            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
        }

        override func mouseEntered(with event: NSEvent) {
            // Block hover tracking during management layer — pane content is non-interactive.
            guard !atom(\.managementLayer).isActive else { return }
            sendMousePos(event)
        }

        override func mouseExited(with event: NSEvent) {
            guard !atom(\.managementLayer).isActive else { return }
            guard let surface else { return }
            let mods = ghosttyMods(from: event.modifierFlags)
            // Send -1,-1 to indicate cursor left the viewport
            ghostty_surface_mouse_pos(surface, -1, -1, mods)
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()

            guard let window else { return }
            let scaleFactor = window.backingScaleFactor

            // Update layer's contentsScale within a CATransaction to disable animations
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = scaleFactor
            CATransaction.commit()

            guard let surface else { return }

            // Calculate x and y scale factors separately (official pattern)
            let fbFrame = convertToBacking(frame)
            let xScale = fbFrame.size.width / frame.size.width
            let yScale = fbFrame.size.height / frame.size.height
            ghostty_surface_set_content_scale(surface, xScale, yScale)

            // Refresh size using contentSize (official pattern)
            if contentSize.width > 0 && contentSize.height > 0 {
                let scaledSize = convertToBacking(contentSize)
                RestoreTrace.log(
                    "Ghostty.SurfaceView.viewDidChangeBackingProperties set_size backing=\(NSStringFromSize(scaledSize)) contentSize=\(NSStringFromSize(contentSize))"
                )
                ghostty_surface_set_size(
                    surface,
                    UInt32(scaledSize.width),
                    UInt32(scaledSize.height)
                )
            }
        }

        private func updateScaleFactor(_ scaleFactor: CGFloat) {
            guard let surface else { return }

            // Update layer's contentsScale
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = scaleFactor
            CATransaction.commit()

            ghostty_surface_set_content_scale(surface, Double(scaleFactor), Double(scaleFactor))
        }

        private func viewHierarchyDescription() -> String {
            var nodes: [String] = []
            var current: NSView? = self
            while let currentView = current {
                nodes.append("class=\(type(of: currentView)) id=\(ObjectIdentifier(currentView))")
                current = currentView.superview
            }
            return nodes.joined(separator: " -> ")
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            RestoreTrace.log("Ghostty.SurfaceView.setFrameSize newSize=\(NSStringFromSize(newSize))")
            sizeDidChange(newSize, source: "setFrameSize")
        }

        func sizeDidChange(_ size: NSSize, source: StaticString = "unknown") {
            guard let surface else { return }
            guard size.width > 0 && size.height > 0 else { return }

            // Track content size (official pattern)
            contentSize = size

            let backingSize = convertToBacking(size)
            let requestedBackingWidth = UInt32(backingSize.width)
            let requestedBackingHeight = UInt32(backingSize.height)
            let currentSurfaceSize = ghostty_surface_size(surface)
            let layerState =
                layer.map { "contentsScale=\($0.contentsScale) layerBounds=\(NSStringFromRect($0.bounds))" }
                ?? "noLayer"
            RestoreTrace.log(
                "Ghostty.SurfaceView.sizeDidChange source=\(source) logical=\(NSStringFromSize(size)) backing=\(NSStringFromSize(backingSize)) requestedPx={\(requestedBackingWidth),\(requestedBackingHeight)} currentPx={\(currentSurfaceSize.width_px),\(currentSurfaceSize.height_px)} currentGrid={\(currentSurfaceSize.columns),\(currentSurfaceSize.rows)} dedupLikely=\(currentSurfaceSize.width_px == requestedBackingWidth && currentSurfaceSize.height_px == requestedBackingHeight) window=\(window != nil) superview=\(superview != nil) hidden=\(isHidden) \(layerState)"
            )
            ghostty_surface_set_size(
                surface,
                requestedBackingWidth,
                requestedBackingHeight
            )
            ghostty_surface_refresh(surface)
            logSurfaceSnapshot(reason: "sizeDidChange.\(source)")
        }

        func updateReportedInitialSize(_ size: NSSize) {
            reportedInitialSize = size
            RestoreTrace.log(
                "Ghostty.SurfaceView.initialSize reported=\(NSStringFromSize(size)) frame=\(NSStringFromRect(frame)) bounds=\(NSStringFromRect(bounds))"
            )
            logSurfaceSnapshot(reason: "initialSizeAction")
        }

        func updateReportedCellSize(_ size: NSSize) {
            reportedCellSize = size
            RestoreTrace.log(
                "Ghostty.SurfaceView.cellSize reported=\(NSStringFromSize(size)) frame=\(NSStringFromRect(frame)) bounds=\(NSStringFromRect(bounds))"
            )
            logSurfaceSnapshot(reason: "cellSizeAction")
            performNarrowPaneRedrawNudgeIfNeeded(cellSize: size)
        }

        private func performNarrowPaneRedrawNudgeIfNeeded(cellSize: NSSize) {
            guard !hasPerformedNarrowPaneRedrawNudge else { return }
            guard window != nil, let surface else { return }

            let currentMetrics = ghostty_surface_size(surface)
            guard currentMetrics.columns > 0, currentMetrics.columns <= 40 else { return }
            guard contentSize.width > 0, contentSize.height > 0 else { return }

            let originalSize = contentSize
            let nudgedSize = NSSize(
                width: originalSize.width + max(cellSize.width, 1),
                height: originalSize.height
            )

            hasPerformedNarrowPaneRedrawNudge = true
            RestoreTrace.log(
                "Ghostty.SurfaceView.narrowPaneRedrawNudge columns=\(currentMetrics.columns) rows=\(currentMetrics.rows) originalSize=\(NSStringFromSize(originalSize)) nudgedSize=\(NSStringFromSize(nudgedSize))"
            )
            sizeDidChange(nudgedSize, source: "narrowPaneRedrawNudge.expand")
            sizeDidChange(originalSize, source: "narrowPaneRedrawNudge.restore")
            logSurfaceSnapshot(reason: "narrowPaneRedrawNudge.complete")
        }

        func metricsSnapshotDescription() -> String {
            guard let surface else {
                return "surface=nil"
            }

            let metrics = ghostty_surface_size(surface)
            let initialSizeDescription = reportedInitialSize.map(NSStringFromSize) ?? "nil"
            let cellSizeDescription = reportedCellSize.map(NSStringFromSize) ?? "nil"
            return
                "frame=\(NSStringFromRect(frame)) bounds=\(NSStringFromRect(bounds)) contentSize=\(NSStringFromSize(contentSize)) initialSize=\(initialSizeDescription) cellSize=\(cellSizeDescription) columns=\(metrics.columns) rows=\(metrics.rows) widthPx=\(metrics.width_px) heightPx=\(metrics.height_px) cellWidthPx=\(metrics.cell_width_px) cellHeightPx=\(metrics.cell_height_px) focused=\(focused) window=\(window != nil)"
        }

        private func logSurfaceSnapshot(reason: String) {
            RestoreTrace.log("Ghostty.SurfaceView.snapshot reason=\(reason) \(metricsSnapshotDescription())")
        }
    }
}
