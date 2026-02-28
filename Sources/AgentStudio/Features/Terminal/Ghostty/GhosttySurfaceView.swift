import AppKit
import Foundation
import GhosttyKit
import QuartzCore

extension Ghostty {
    enum SurfaceStartupStrategy: Equatable {
        /// Pass this command directly to Ghostty when creating the surface.
        case surfaceCommand(String?)
        /// Start the shell normally, then inject this command after first sizing.
        case deferredInShell(command: String)

        var startupCommandForSurface: String? {
            switch self {
            case .surfaceCommand(let command):
                return command
            case .deferredInShell:
                return nil
            }
        }

        var deferredStartupCommand: String? {
            switch self {
            case .surfaceCommand:
                return nil
            case .deferredInShell(let command):
                return command
            }
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
        var workingDirectory: String?
        var startupStrategy: SurfaceStartupStrategy
        var fontSize: Float?
        var environmentVariables: [String: String]

        init(
            workingDirectory: String? = nil,
            startupStrategy: SurfaceStartupStrategy = .surfaceCommand(nil),
            fontSize: Float? = nil,
            environmentVariables: [String: String] = [:]
        ) {
            self.workingDirectory = workingDirectory
            self.startupStrategy = startupStrategy
            self.fontSize = fontSize
            self.environmentVariables = environmentVariables
        }
    }

    /// NSView subclass that renders a Ghostty terminal surface
    final class SurfaceView: NSView {
        /// The terminal title (published for observation)
        private(set) var title: String = ""

        /// The ghostty surface handle
        nonisolated(unsafe) private(set) var surface: ghostty_surface_t?

        /// The ghostty app reference
        private weak var ghosttyApp: App?

        /// Marked text for input method
        private var markedText = NSMutableAttributedString()

        /// Whether this view has focus
        private(set) var focused: Bool = false

        /// Text accumulator for key events
        private var keyTextAccumulator: [String]?

        /// Content size for the terminal (may differ from frame during resize)
        private var contentSize: NSSize = .zero

        /// Current working directory reported by the shell via OSC 7
        private(set) var pwd: String? {
            didSet {
                if pwd != oldValue {
                    postGhosttyEvent(
                        .workingDirectoryUpdated(
                            surfaceViewId: ObjectIdentifier(self),
                            rawPwd: pwd
                        )
                    )
                }
            }
        }

        /// Health state of the renderer (for crash isolation)
        private(set) var healthy: Bool = true {
            didSet {
                if healthy != oldValue {
                    postGhosttyEvent(
                        .rendererHealthUpdated(
                            surfaceViewId: ObjectIdentifier(self),
                            isHealthy: healthy
                        )
                    )
                }
            }
        }

        /// Any error during surface initialization
        private(set) var error: Error?
        /// Command to run after first real surface sizing (post-window attach).
        private var deferredStartupCommand: String?
        private var hasSentDeferredStartupCommand = false
        private var deferredStartupWorkItem: DispatchWorkItem?
        private let deferredStartupDelaySeconds: TimeInterval = 0.18

        // MARK: - Initialization

        init(app: App, config: SurfaceConfiguration? = nil) {
            self.ghosttyApp = app
            self.deferredStartupCommand = config?.startupStrategy.deferredStartupCommand
            super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            let startupCommandForSurface = config?.startupStrategy.startupCommandForSurface
            RestoreTrace.log(
                "Ghostty.SurfaceView.init placeholderFrame=\(NSStringFromRect(frame)) cwd=\(config?.workingDirectory ?? "nil") hasCommand=\(startupCommandForSurface != nil) hasDeferred=\(self.deferredStartupCommand != nil)"
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
            surfaceConfig.font_size = config?.fontSize ?? 0

            let createSurfaceWithStrings: () -> Void = {
                // Set working directory/command if provided.
                if let wd = config?.workingDirectory {
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

            let envVars = config?.environmentVariables ?? [:]
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
                sizeDidChange(frame.size)
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        isolated deinit {
            deferredStartupWorkItem?.cancel()
            if let surface {
                ghostty_surface_free(surface)
            }
        }

        /// Called when the title changes (from App callback)
        func titleDidChange(_ newTitle: String) {
            self.title = newTitle
        }

        func pwdDidChange(_ newPwd: String?) {
            self.pwd = newPwd
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
            }
            return result
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            RestoreTrace.log(
                "Ghostty.SurfaceView.viewDidMoveToWindow window=\(window != nil) frame=\(NSStringFromRect(frame)) bounds=\(NSStringFromRect(bounds))"
            )

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
            // the parent PaneView was also initialized at the same placeholder.
            if window != nil, surface != nil {
                Task { @MainActor [weak self] in
                    guard let self, self.window != nil else { return }
                    let size = self.frame.size
                    guard size.width > 0 && size.height > 0 else { return }
                    RestoreTrace.log(
                        "Ghostty.SurfaceView.viewDidMoveToWindow async sizeDidChange size=\(NSStringFromSize(size)) frame=\(NSStringFromRect(self.frame))"
                    )
                    self.sizeDidChange(size)
                    self.triggerDeferredStartupIfReady(source: "viewDidMoveToWindow.async")
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
            // Block hover tracking during management mode — pane content is non-interactive.
            guard !ManagementModeMonitor.shared.isActive else { return }
            sendMousePos(event)
        }

        override func mouseExited(with event: NSEvent) {
            guard !ManagementModeMonitor.shared.isActive else { return }
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

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            RestoreTrace.log("Ghostty.SurfaceView.setFrameSize newSize=\(NSStringFromSize(newSize))")
            sizeDidChange(newSize)
        }

        func sizeDidChange(_ size: NSSize) {
            guard let surface else { return }
            guard size.width > 0 && size.height > 0 else { return }

            // Track content size (official pattern)
            contentSize = size

            let backingSize = convertToBacking(size)
            RestoreTrace.log(
                "Ghostty.SurfaceView.sizeDidChange logical=\(NSStringFromSize(size)) backing=\(NSStringFromSize(backingSize)) window=\(window != nil)"
            )
            ghostty_surface_set_size(
                surface,
                UInt32(backingSize.width),
                UInt32(backingSize.height)
            )
            triggerDeferredStartupIfReady(source: "sizeDidChange")
        }

        private func triggerDeferredStartupIfReady(source: String) {
            guard
                DeferredStartupReadiness.canSchedule(
                    hasSent: hasSentDeferredStartupCommand,
                    deferredStartupCommand: deferredStartupCommand,
                    hasWindow: window != nil,
                    contentSize: contentSize
                )
            else { return }
            guard let deferredStartupCommand else { return }

            deferredStartupWorkItem?.cancel()
            RestoreTrace.log(
                "Ghostty.SurfaceView.deferredStartup scheduling source=\(source) size=\(NSStringFromSize(contentSize)) cmd=\(deferredStartupCommand)"
            )
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                defer { self.deferredStartupWorkItem = nil }
                guard
                    DeferredStartupReadiness.canExecute(
                        hasSent: self.hasSentDeferredStartupCommand,
                        deferredStartupCommand: self.deferredStartupCommand,
                        hasWindow: self.window != nil,
                        contentSize: self.contentSize,
                        processExited: self.processExited
                    )
                else {
                    if self.processExited {
                        RestoreTrace.log(
                            "Ghostty.SurfaceView.deferredStartup skipped process already exited source=\(source)")
                    } else {
                        RestoreTrace.log(
                            "Ghostty.SurfaceView.deferredStartup skipped invalid readiness source=\(source)")
                    }
                    return
                }
                self.hasSentDeferredStartupCommand = true
                // `sendText` is paste-like and may not execute pasted newlines under
                // shell bracketed-paste protections. Send Return as a real key event.
                // Prefix with a single space to reduce history pollution in shells
                // that honor "leading-space means don't save to history".
                self.sendText(" \(deferredStartupCommand)")
                self.sendProgrammaticReturnKey()
                ghosttyLogger.debug("Deferred startup command sent")
                RestoreTrace.log("Ghostty.SurfaceView.deferredStartup sent source=\(source)")
            }
            deferredStartupWorkItem = workItem
            let delayMilliseconds = Int(deferredStartupDelaySeconds * 1000)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
                guard !workItem.isCancelled else { return }
                workItem.perform()
            }
        }

        // MARK: - Input Handling

        override func keyDown(with event: NSEvent) {
            let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

            // Set up text accumulator for interpretKeyEvents
            keyTextAccumulator = []
            defer { keyTextAccumulator = nil }

            // Process through input system for IME/dead keys
            self.interpretKeyEvents([event])

            // Send key event(s) to Ghostty
            if let list = keyTextAccumulator, !list.isEmpty {
                // Text was composed - send each piece
                for text in list {
                    sendKeyEvent(event, action: action, text: text)
                }
            } else {
                // No composed text - send key with ghosttyCharacters
                // This handles control characters properly (Ghostty encodes them)
                sendKeyEvent(event, action: action, text: ghosttyCharacters(from: event))
            }
        }

        override func keyUp(with event: NSEvent) {
            sendKeyEvent(event, action: GHOSTTY_ACTION_RELEASE)
        }

        override func flagsChanged(with event: NSEvent) {
            sendKeyEvent(event, action: GHOSTTY_ACTION_PRESS)
        }

        /// Shortcuts that Agent Studio owns — always pass to macOS menu bar, never to Ghostty.
        static let appOwnedShortcuts: [(key: String, mods: NSEvent.ModifierFlags)] = [
            ("p", [.command]),  // ⌘P — Quick Open
            ("p", [.command, .shift]),  // ⌘⇧P — Command Palette
            ("p", [.command, .option]),  // ⌘⌥P — Go to Pane
        ]

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard event.type == .keyDown else { return false }
            guard focused else { return false }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // App-owned shortcuts bypass Ghostty — always go to macOS menu bar.
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                for shortcut in Self.appOwnedShortcuts {
                    if chars == shortcut.key && mods == shortcut.mods {
                        return false
                    }
                }
            }

            // Cmd combinations: app menu shortcuts take priority over terminal keybindings.
            if mods.contains(.command) {
                // Let the app's main menu handle matching key equivalents first
                if let mainMenu = NSApp.mainMenu, mainMenu.performKeyEquivalent(with: event) {
                    return true
                }

                guard let surface else { return false }

                var keyEvent = ghostty_input_key_s()
                keyEvent.action = GHOSTTY_ACTION_PRESS
                keyEvent.mods = ghosttyMods(from: event.modifierFlags)
                keyEvent.keycode = UInt32(event.keyCode)
                keyEvent.composing = false
                keyEvent.text = nil

                if event.type == .keyDown || event.type == .keyUp {
                    if let chars = event.characters(byApplyingModifiers: []),
                        let codepoint = chars.unicodeScalars.first
                    {
                        keyEvent.unshifted_codepoint = codepoint.value
                    }
                }

                // Control and Command never contribute to text translation per Ghostty's KeyEncoder
                let consumedMods = event.modifierFlags.subtracting([.control, .command])
                keyEvent.consumed_mods = ghosttyMods(from: consumedMods)

                var flags = ghostty_binding_flags_e(0)
                if ghostty_surface_key_is_binding(surface, keyEvent, &flags) {
                    // Ghostty has a keybind for this — forward to keyDown
                    self.keyDown(with: event)
                    return true
                }

                // No Ghostty keybind — pass to macOS
                return false
            }

            // Ctrl+* keys must be handled here to prevent AppKit from swallowing them
            if mods.contains(.control) {
                // Special case: Ctrl+Return - prevent default context menu
                if event.charactersIgnoringModifiers == "\r" {
                    self.keyDown(with: event)
                    return true
                }

                // Special case: Ctrl+/ - convert to Ctrl+_ (prevents macOS beep)
                if event.charactersIgnoringModifiers == "/" {
                    if let modifiedEvent = NSEvent.keyEvent(
                        with: .keyDown,
                        location: event.locationInWindow,
                        modifierFlags: event.modifierFlags,
                        timestamp: event.timestamp,
                        windowNumber: event.windowNumber,
                        context: nil,
                        characters: "_",
                        charactersIgnoringModifiers: "_",
                        isARepeat: event.isARepeat,
                        keyCode: event.keyCode
                    ) {
                        self.keyDown(with: modifiedEvent)
                        return true
                    }
                }

                // All other Ctrl+* keys go directly to keyDown
                self.keyDown(with: event)
                return true
            }

            // Shift+*, Option+*, plain keys - don't intercept, let them flow to keyDown
            return false
        }

        override func doCommand(by selector: Selector) {
            // Intentionally empty - prevents system beeps for unhandled commands
            // All key input goes through keyDown, not through command selectors
        }

        private func sendKeyEvent(_ event: NSEvent, action: ghostty_input_action_e, text: String? = nil) {
            guard let surface else { return }

            var keyEvent = ghostty_input_key_s()
            keyEvent.action = action
            keyEvent.mods = ghosttyMods(from: event.modifierFlags)
            keyEvent.keycode = UInt32(event.keyCode)
            keyEvent.composing = false

            // Compute unshifted codepoint (key without modifiers)
            if event.type == .keyDown || event.type == .keyUp {
                if let chars = event.characters(byApplyingModifiers: []),
                    let codepoint = chars.unicodeScalars.first
                {
                    keyEvent.unshifted_codepoint = codepoint.value
                }
            }

            // Compute consumed mods (mods that contributed to text translation)
            // Control and command never contribute to text translation
            let consumedMods = event.modifierFlags.subtracting([.control, .command])
            keyEvent.consumed_mods = ghosttyMods(from: consumedMods)

            // Determine the text to send
            // For control characters (< 0x20), don't send text - Ghostty handles encoding
            let textToSend: String?
            if let providedText = text {
                textToSend = providedText
            } else {
                textToSend = ghosttyCharacters(from: event)
            }

            // Only send text if it's not a control character
            if let text = textToSend, !text.isEmpty,
                let codepoint = text.utf8.first, codepoint >= 0x20
            {
                text.withCString { ptr in
                    keyEvent.text = ptr
                    ghostty_surface_key(surface, keyEvent)
                }
            } else {
                keyEvent.text = nil
                ghostty_surface_key(surface, keyEvent)
            }
        }

        /// Returns text for key event, filtering control characters
        /// Control character mapping is handled by Ghostty's KeyEncoder
        private func ghosttyCharacters(from event: NSEvent) -> String? {
            guard let characters = event.characters else { return nil }

            if characters.count == 1, let scalar = characters.unicodeScalars.first {
                // Control characters < 0x20: strip control modifier, let Ghostty handle encoding
                if scalar.value < 0x20 {
                    return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
                }

                // Function keys in PUA range: don't send
                if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                    return nil
                }
            }

            return characters
        }

        private func ghosttyMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
            var mods = GHOSTTY_MODS_NONE.rawValue

            if flags.contains(.shift) {
                mods |= GHOSTTY_MODS_SHIFT.rawValue
            }
            if flags.contains(.control) {
                mods |= GHOSTTY_MODS_CTRL.rawValue
            }
            if flags.contains(.option) {
                mods |= GHOSTTY_MODS_ALT.rawValue
            }
            if flags.contains(.command) {
                mods |= GHOSTTY_MODS_SUPER.rawValue
            }
            if flags.contains(.capsLock) {
                mods |= GHOSTTY_MODS_CAPS.rawValue
            }

            return ghostty_input_mods_e(rawValue: mods)
        }

        // MARK: - Mouse Input

        override func mouseDown(with event: NSEvent) {
            sendMouseButton(event, action: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_LEFT)
        }

        override func mouseUp(with event: NSEvent) {
            sendMouseButton(event, action: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
        }

        override func rightMouseDown(with event: NSEvent) {
            sendMouseButton(event, action: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_RIGHT)
        }

        override func rightMouseUp(with event: NSEvent) {
            sendMouseButton(event, action: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_RIGHT)
        }

        override func otherMouseDown(with event: NSEvent) {
            let button = ghosttyMouseButton(from: event.buttonNumber)
            sendMouseButton(event, action: GHOSTTY_MOUSE_PRESS, button: button)
        }

        override func otherMouseUp(with event: NSEvent) {
            let button = ghosttyMouseButton(from: event.buttonNumber)
            sendMouseButton(event, action: GHOSTTY_MOUSE_RELEASE, button: button)
        }

        override func mouseMoved(with event: NSEvent) {
            guard !ManagementModeMonitor.shared.isActive else { return }
            sendMousePos(event)
        }

        override func mouseDragged(with event: NSEvent) {
            sendMousePos(event)
        }

        override func rightMouseDragged(with event: NSEvent) {
            sendMousePos(event)
        }

        override func otherMouseDragged(with event: NSEvent) {
            sendMousePos(event)
        }

        override func scrollWheel(with event: NSEvent) {
            guard let surface else { return }

            let mods = ghosttyMods(from: event.modifierFlags)
            var scrollMods: ghostty_input_scroll_mods_t = Int32(mods.rawValue)

            if !event.momentumPhase.isEmpty {
                scrollMods |= 0x10  // GHOSTTY_SCROLL_MODS_MOMENTUM
            }

            if event.hasPreciseScrollingDeltas {
                scrollMods |= 0x20  // GHOSTTY_SCROLL_MODS_PRECISION
            }

            ghostty_surface_mouse_scroll(
                surface,
                event.scrollingDeltaX,
                event.scrollingDeltaY,
                scrollMods
            )
        }

        private func sendMouseButton(
            _ event: NSEvent, action: ghostty_input_mouse_state_e, button: ghostty_input_mouse_button_e
        ) {
            guard let surface else { return }
            let mods = ghosttyMods(from: event.modifierFlags)
            ghostty_surface_mouse_button(surface, action, button, mods)
            // Note: Official Ghostty does NOT call sendMousePos after button events
        }

        private func sendMousePos(_ event: NSEvent) {
            guard let surface else { return }

            let pos = convert(event.locationInWindow, from: nil)
            let mods = ghosttyMods(from: event.modifierFlags)
            // Use view coordinates with Y-axis flipped (Ghostty expects origin at top-left)
            ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, mods)
        }

        private func ghosttyMouseButton(from buttonNumber: Int) -> ghostty_input_mouse_button_e {
            switch buttonNumber {
            case 0: return GHOSTTY_MOUSE_LEFT
            case 1: return GHOSTTY_MOUSE_RIGHT
            case 2: return GHOSTTY_MOUSE_MIDDLE
            case 3: return GHOSTTY_MOUSE_FOUR
            case 4: return GHOSTTY_MOUSE_FIVE
            case 5: return GHOSTTY_MOUSE_SIX
            case 6: return GHOSTTY_MOUSE_SEVEN
            case 7: return GHOSTTY_MOUSE_EIGHT
            default: return GHOSTTY_MOUSE_LEFT
            }
        }

        // MARK: - Edit Menu Responders

        @objc func copy(_ sender: Any?) {
            guard let surface else { return }
            let action = "copy_to_clipboard"
            action.withCString { ptr in
                _ = ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
            }
        }

        @objc func paste(_ sender: Any?) {
            guard let surface else { return }
            let action = "paste_from_clipboard"
            action.withCString { ptr in
                _ = ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
            }
        }

        @objc override func selectAll(_ sender: Any?) {
            guard let surface else { return }
            let action = "select_all"
            action.withCString { ptr in
                _ = ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
            }
        }

        // MARK: - Public API

        /// Send text to the terminal as if it was typed
        func sendText(_ text: String) {
            guard let surface else { return }
            text.withCString { ptr in
                ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
            }
        }

        /// Send Return/Enter as a key event (press+release).
        /// Needed for deferred startup commands because newline inside `sendText`
        /// can be treated as pasted content and not execute immediately.
        private func sendProgrammaticReturnKey() {
            guard let surface else { return }
            var keyDown = ghostty_input_key_s()
            keyDown.action = GHOSTTY_ACTION_PRESS
            keyDown.mods = GHOSTTY_MODS_NONE
            keyDown.consumed_mods = GHOSTTY_MODS_NONE
            keyDown.keycode = 36  // macOS Return key virtual keycode.
            keyDown.unshifted_codepoint = 0x0D
            keyDown.composing = false
            keyDown.text = nil
            ghostty_surface_key(surface, keyDown)

            var keyUp = keyDown
            keyUp.action = GHOSTTY_ACTION_RELEASE
            ghostty_surface_key(surface, keyUp)
        }

        /// Request that this surface be closed
        func requestClose() {
            guard let surface else { return }
            ghostty_surface_request_close(surface)
        }

        /// Check if the process has exited
        var processExited: Bool {
            guard let surface else { return true }
            return ghostty_surface_process_exited(surface)
        }

        /// Check if confirmation is needed before quitting
        var needsConfirmQuit: Bool {
            guard let surface else { return false }
            return ghostty_surface_needs_confirm_quit(surface)
        }
    }
}

// MARK: - NSTextInputClient Conformance

extension Ghostty.SurfaceView: @preconcurrency NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        // Must have a current event
        guard NSApp.currentEvent != nil else { return }
        guard let surface else { return }

        let text: String
        if let str = string as? String {
            text = str
        } else if let attrStr = string as? NSAttributedString {
            text = attrStr.string
        } else {
            return
        }

        // Clear marked text since we're inserting final text
        unmarkText()

        // If we have an accumulator, we're in a keyDown event - just accumulate
        // The keyDown handler will send the key event with the accumulated text
        if var acc = keyTextAccumulator {
            acc.append(text)
            keyTextAccumulator = acc
            return
        }

        // Not in keyDown - send text directly (e.g., from paste or programmatic input)
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let str = string as? String {
            markedText = NSMutableAttributedString(string: str)
        } else if let attrStr = string as? NSAttributedString {
            markedText = NSMutableAttributedString(attributedString: attrStr)
        }
    }

    func unmarkText() {
        markedText = NSMutableAttributedString()
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        if markedText.length > 0 {
            return NSRange(location: 0, length: markedText.length)
        }
        return NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window = self.window else { return .zero }
        let viewFrame = self.convert(self.bounds, to: nil)
        return window.convertToScreen(viewFrame)
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }
}
