import Foundation
import AppKit
import GhosttyKit
import Combine
import QuartzCore

extension Ghostty {
    /// Configuration for creating a new surface
    struct SurfaceConfiguration {
        var workingDirectory: String?
        var command: String?
        var fontSize: Float?

        init(workingDirectory: String? = nil, command: String? = nil, fontSize: Float? = nil) {
            self.workingDirectory = workingDirectory
            self.command = command
            self.fontSize = fontSize
        }
    }

    /// NSView subclass that renders a Ghostty terminal surface
    final class SurfaceView: NSView {
        /// The terminal title (published for observation)
        private(set) var title: String = ""

        /// The ghostty surface handle
        private(set) var surface: ghostty_surface_t?

        /// The ghostty app reference
        private weak var ghosttyApp: App?

        /// Marked text for input method
        private var markedText: NSMutableAttributedString = NSMutableAttributedString()

        /// Whether this view has focus
        private(set) var focused: Bool = false

        /// Text accumulator for key events
        private var keyTextAccumulator: [String]? = nil

        // MARK: - Initialization

        init(app: App, config: SurfaceConfiguration? = nil) {
            self.ghosttyApp = app
            super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

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
            surfaceConfig.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(self).toOpaque()
            ))
            surfaceConfig.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2.0)
            surfaceConfig.font_size = config?.fontSize ?? 0

            // Set working directory if provided
            if let wd = config?.workingDirectory {
                wd.withCString { wdPtr in
                    surfaceConfig.working_directory = wdPtr

                    if let cmd = config?.command {
                        cmd.withCString { cmdPtr in
                            surfaceConfig.command = cmdPtr
                            self.surface = ghostty_surface_new(ghosttyApp, &surfaceConfig)
                        }
                    } else {
                        self.surface = ghostty_surface_new(ghosttyApp, &surfaceConfig)
                    }
                }
            } else if let cmd = config?.command {
                cmd.withCString { cmdPtr in
                    surfaceConfig.command = cmdPtr
                    self.surface = ghostty_surface_new(ghosttyApp, &surfaceConfig)
                }
            } else {
                self.surface = ghostty_surface_new(ghosttyApp, &surfaceConfig)
            }

            if self.surface == nil {
                ghosttyLogger.error("Failed to create ghostty surface")
            } else {
                ghosttyLogger.info("Ghostty surface created successfully")
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            if let surface = surface {
                ghostty_surface_free(surface)
            }
        }

        /// Called when the title changes (from App callback)
        func titleDidChange(_ newTitle: String) {
            self.title = newTitle
        }

        // MARK: - View Lifecycle

        override var acceptsFirstResponder: Bool { true }

        override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder()
            if result {
                focused = true
                if let surface = surface {
                    ghostty_surface_set_focus(surface, true)
                }
            }
            return result
        }

        override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder()
            if result {
                focused = false
                if let surface = surface {
                    ghostty_surface_set_focus(surface, false)
                }
            }
            return result
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            // Set clipsToBounds to prevent content overflow
            self.clipsToBounds = true

            if let window = window {
                updateForWindow(window)
            }
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()

            guard let window = window else { return }

            // Update layer's contentsScale to match backing scale factor
            // This prevents scaling artifacts on Retina displays
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()

            updateForWindow(window)
        }

        private func updateForWindow(_ window: NSWindow) {
            guard let surface = surface else { return }

            let scaleFactor = window.backingScaleFactor

            // Update Ghostty's content scale
            ghostty_surface_set_content_scale(surface, Double(scaleFactor), Double(scaleFactor))

            // Also update size when scale changes
            let backingSize = convertToBacking(frame.size)
            if backingSize.width > 0 && backingSize.height > 0 {
                ghostty_surface_set_size(
                    surface,
                    UInt32(backingSize.width),
                    UInt32(backingSize.height)
                )
            }
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            sizeDidChange(newSize)
        }

        func sizeDidChange(_ size: NSSize) {
            guard let surface = surface else { return }
            guard size.width > 0 && size.height > 0 else { return }

            let backingSize = convertToBacking(size)
            ghostty_surface_set_size(
                surface,
                UInt32(backingSize.width),
                UInt32(backingSize.height)
            )
        }

        // MARK: - Input Handling

        override func keyDown(with event: NSEvent) {
            keyTextAccumulator = []
            defer { keyTextAccumulator = nil }

            self.interpretKeyEvents([event])

            if let accumulator = keyTextAccumulator, accumulator.isEmpty {
                sendKeyEvent(event, action: GHOSTTY_ACTION_PRESS)
            }
        }

        override func keyUp(with event: NSEvent) {
            sendKeyEvent(event, action: GHOSTTY_ACTION_RELEASE)
        }

        override func flagsChanged(with event: NSEvent) {
            sendKeyEvent(event, action: GHOSTTY_ACTION_PRESS)
        }

        private func sendKeyEvent(_ event: NSEvent, action: ghostty_input_action_e) {
            guard let surface = surface else { return }

            var keyEvent = ghostty_input_key_s()
            keyEvent.action = action
            keyEvent.mods = ghosttyMods(from: event.modifierFlags)
            keyEvent.keycode = UInt32(event.keyCode)
            keyEvent.composing = false

            if let chars = event.characters, !chars.isEmpty {
                chars.withCString { ptr in
                    keyEvent.text = ptr
                    ghostty_surface_key(surface, keyEvent)
                }
            } else {
                keyEvent.text = nil
                ghostty_surface_key(surface, keyEvent)
            }
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
            guard let surface = surface else { return }

            let mods = ghosttyMods(from: event.modifierFlags)
            var scrollMods: ghostty_input_scroll_mods_t = Int32(mods.rawValue)

            if event.momentumPhase != [] {
                scrollMods |= 0x10 // GHOSTTY_SCROLL_MODS_MOMENTUM
            }

            if event.hasPreciseScrollingDeltas {
                scrollMods |= 0x20 // GHOSTTY_SCROLL_MODS_PRECISION
            }

            ghostty_surface_mouse_scroll(
                surface,
                event.scrollingDeltaX,
                event.scrollingDeltaY,
                scrollMods
            )
        }

        private func sendMouseButton(_ event: NSEvent, action: ghostty_input_mouse_state_e, button: ghostty_input_mouse_button_e) {
            guard let surface = surface else { return }
            let mods = ghosttyMods(from: event.modifierFlags)
            ghostty_surface_mouse_button(surface, action, button, mods)
            sendMousePos(event)
        }

        private func sendMousePos(_ event: NSEvent) {
            guard let surface = surface else { return }

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

        // MARK: - Public API

        /// Send text to the terminal as if it was typed
        func sendText(_ text: String) {
            guard let surface = surface else { return }
            text.withCString { ptr in
                ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
            }
        }

        /// Request that this surface be closed
        func requestClose() {
            guard let surface = surface else { return }
            ghostty_surface_request_close(surface)
        }

        /// Check if the process has exited
        var processExited: Bool {
            guard let surface = surface else { return true }
            return ghostty_surface_process_exited(surface)
        }

        /// Check if confirmation is needed before quitting
        var needsConfirmQuit: Bool {
            guard let surface = surface else { return false }
            return ghostty_surface_needs_confirm_quit(surface)
        }
    }
}

// MARK: - NSTextInputClient Conformance

extension Ghostty.SurfaceView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let surface = surface else { return }

        let text: String
        if let str = string as? String {
            text = str
        } else if let attrStr = string as? NSAttributedString {
            text = attrStr.string
        } else {
            return
        }

        keyTextAccumulator?.append(text)

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
        return NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        if markedText.length > 0 {
            return NSRange(location: 0, length: markedText.length)
        }
        return NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        return markedText.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        return nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window = self.window else { return .zero }
        let viewFrame = self.convert(self.bounds, to: nil)
        return window.convertToScreen(viewFrame)
    }

    func characterIndex(for point: NSPoint) -> Int {
        return 0
    }
}
