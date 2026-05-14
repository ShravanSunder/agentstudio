import AppKit
import GhosttyKit
import Observation

@MainActor
enum GhosttyMouseVisibilityCoordinator {
    private static var hiddenToken: UUID?
    private static var cursorHidden = false

    static func update(token: UUID, isVisible: Bool, isFocused: Bool) {
        guard isFocused, !isVisible else {
            release(token: token)
            return
        }

        guard hiddenToken != token else { return }
        if !cursorHidden {
            NSCursor.hide()
            cursorHidden = true
        }
        hiddenToken = token
    }

    static func release(token: UUID) {
        guard hiddenToken == token else { return }
        hiddenToken = nil
        guard cursorHidden else { return }
        NSCursor.unhide()
        cursorHidden = false
    }
}

extension Ghostty.SurfaceView {
    // MARK: - Input Handling

    override func keyDown(with event: NSEvent) {
        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        interpretKeyEvents([event])

        if let list = keyTextAccumulator, !list.isEmpty {
            for text in list {
                sendKeyEvent(event, action: action, text: text)
            }
        } else {
            sendKeyEvent(event, action: action, text: ghosttyCharacters(from: event))
        }
    }

    override func keyUp(with event: NSEvent) {
        sendKeyEvent(event, action: GHOSTTY_ACTION_RELEASE)
    }

    override func flagsChanged(with event: NSEvent) {
        sendKeyEvent(event, action: GHOSTTY_ACTION_PRESS)
    }

    static let appOwnedShortcuts: [AppShortcut] = AppShortcut.allCases.filter {
        $0.contexts.contains(.terminalAppOwned)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard focused else { return false }

        if let trigger = ShortcutDecoder.decode(event: event),
            let shortcut = ShortcutDecoder.shortcut(for: trigger, in: .terminalAppOwned),
            Self.appOwnedShortcuts.contains(shortcut)
        {
            if CommandDispatcher.shared.canDispatch(shortcut.command) {
                CommandDispatcher.shared.dispatch(shortcut.command)
                return true
            }
            return false
        }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if mods.contains(.command) {
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

            if event.type == .keyDown || event.type == .keyUp,
                let chars = event.characters(byApplyingModifiers: []),
                let codepoint = chars.unicodeScalars.first
            {
                keyEvent.unshifted_codepoint = codepoint.value
            }

            let consumedMods = event.modifierFlags.subtracting([.control, .command])
            keyEvent.consumed_mods = ghosttyMods(from: consumedMods)

            var flags = ghostty_binding_flags_e(0)
            if ghostty_surface_key_is_binding(surface, keyEvent, &flags) {
                keyDown(with: event)
                return true
            }

            return false
        }

        if mods.contains(.control) {
            if event.charactersIgnoringModifiers == "\r" {
                keyDown(with: event)
                return true
            }

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
                    keyDown(with: modifiedEvent)
                    return true
                }
            }

            keyDown(with: event)
            return true
        }

        return false
    }

    override func doCommand(by selector: Selector) {}

    private func sendKeyEvent(_ event: NSEvent, action: ghostty_input_action_e, text: String? = nil) {
        guard let surface else { return }

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.mods = ghosttyMods(from: event.modifierFlags)
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.composing = false

        if event.type == .keyDown || event.type == .keyUp,
            let chars = event.characters(byApplyingModifiers: []),
            let codepoint = chars.unicodeScalars.first
        {
            keyEvent.unshifted_codepoint = codepoint.value
        }

        let consumedMods = event.modifierFlags.subtracting([.control, .command])
        keyEvent.consumed_mods = ghosttyMods(from: consumedMods)

        let textToSend = text ?? ghosttyCharacters(from: event)
        if let textToSend, !textToSend.isEmpty,
            let codepoint = textToSend.utf8.first, codepoint >= 0x20
        {
            textToSend.withCString { ptr in
                keyEvent.text = ptr
                ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.text = nil
            ghostty_surface_key(surface, keyEvent)
        }
    }

    private func ghosttyCharacters(from event: NSEvent) -> String? {
        guard let characters = event.characters else { return nil }

        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
            }

            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return characters
    }

    func ghosttyMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
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
        guard !atom(\.managementLayer).isActive else { return }
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
        let translatedScroll = GhosttyScrollTranslation.translate(event: event)
        ghostty_surface_mouse_scroll(
            surface,
            translatedScroll.deltaX,
            translatedScroll.deltaY,
            translatedScroll.scrollMods
        )
    }

    private func sendMouseButton(
        _ event: NSEvent,
        action: ghostty_input_mouse_state_e,
        button: ghostty_input_mouse_button_e
    ) {
        guard let surface else { return }
        let mods = ghosttyMods(from: event.modifierFlags)
        ghostty_surface_mouse_button(surface, action, button, mods)
    }

    func sendMousePos(_ event: NSEvent) {
        guard let surface else { return }

        let pos = convert(event.locationInWindow, from: nil)
        let mods = ghosttyMods(from: event.modifierFlags)
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
        _ = performBindingAction(.copyToClipboard)
    }

    @objc func paste(_ sender: Any?) {
        _ = performBindingAction(.pasteFromClipboard)
    }

    @objc override func selectAll(_ sender: Any?) {
        _ = performBindingAction(.selectAll)
    }

    // MARK: - Public API

    func sendText(_ text: String) {
        guard let surface else { return }
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
    }

    func requestClose() {
        guard let surface else { return }
        ghostty_surface_request_close(surface)
    }

    var processExited: Bool {
        guard let surface else { return true }
        return ghostty_surface_process_exited(surface)
    }

    var needsConfirmQuit: Bool {
        guard let surface else { return false }
        return ghostty_surface_needs_confirm_quit(surface)
    }

    func bindRuntime(_ runtime: TerminalRuntime) {
        terminalRuntime = runtime
        applyMouseShape(runtime.mouseShape)
        applyMouseVisibility(isVisible: runtime.isMouseVisible)
        observeMouseState(runtime: runtime)
    }

    private func observeMouseState(runtime expectedRuntime: TerminalRuntime) {
        withObservationTracking {
            _ = expectedRuntime.mouseShape
            _ = expectedRuntime.isMouseVisible
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let runtime = self.terminalRuntime, runtime === expectedRuntime else { return }
                self.applyMouseShape(runtime.mouseShape)
                self.applyMouseVisibility(isVisible: runtime.isMouseVisible)
                self.observeMouseState(runtime: runtime)
            }
        }
    }

    private func applyMouseShape(_ mouseShape: TerminalMouseShape?) {
        guard let mouseShape else { return }
        switch mouseShape {
        case .text:
            NSCursor.iBeam.set()
        case .pointer:
            NSCursor.pointingHand.set()
        case .crosshair:
            NSCursor.crosshair.set()
        case .verticalText:
            NSCursor.iBeamCursorForVerticalLayout.set()
        case .other:
            NSCursor.arrow.set()
        }
    }

    func applyMouseVisibility(isVisible: Bool) {
        GhosttyMouseVisibilityCoordinator.update(
            token: mouseVisibilityToken,
            isVisible: isVisible,
            isFocused: focused
        )
    }
}

extension Ghostty.SurfaceView: @preconcurrency NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
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

        unmarkText()

        if var accumulator = keyTextAccumulator {
            accumulator.append(text)
            keyTextAccumulator = accumulator
            return
        }

        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let string = string as? String {
            markedText = NSMutableAttributedString(string: string)
        } else if let attributedString = string as? NSAttributedString {
            markedText = NSMutableAttributedString(attributedString: attributedString)
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
        guard let window else { return .zero }
        let viewFrame = convert(bounds, to: nil)
        return window.convertToScreen(viewFrame)
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }
}
