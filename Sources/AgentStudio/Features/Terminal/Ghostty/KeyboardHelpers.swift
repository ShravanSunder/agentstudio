import AppKit
import Carbon
import GhosttyKit

// MARK: - Modifier Conversion

/// Returns the current text input source ID, matching Ghostty's keyboard-layout
/// identity used to discard key events that switch layouts during translation.
func currentKeyboardLayoutID() -> String? {
    guard
        let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
        let sourceIDPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
    else {
        return nil
    }

    let sourceID = unsafeBitCast(sourceIDPointer, to: CFString.self)
    return sourceID as String
}

/// A layout switch consumes a key only when marked text was not already active.
/// The provider stays lazy to match upstream's short-circuit around TIS access.
func shouldAbortKeyDownForKeyboardLayoutChange(
    hasMarkedTextBefore: Bool,
    keyboardLayoutIDBefore: String?,
    currentKeyboardLayoutID: () -> String?
) -> Bool {
    guard !hasMarkedTextBefore else { return false }
    return keyboardLayoutIDBefore != currentKeyboardLayoutID()
}

/// Control characters belong to an active input method when they arrive as a
/// single C0 scalar; printable and multi-scalar text remains terminal input.
func shouldSuppressComposingControlInput(_ text: String?, composing: Bool) -> Bool {
    guard composing, let text else { return false }
    let scalars = text.unicodeScalars
    guard let scalar = scalars.first,
        scalars.index(after: scalars.startIndex) == scalars.endIndex
    else {
        return false
    }
    return scalar.value < 0x20
}

/// After an IME commits preedit text, replay only navigation keys that should
/// still affect the terminal after the composition has ended.
func shouldReplayCommittedPreeditKey(
    keyCode: UInt16,
    modifierFlags: NSEvent.ModifierFlags
) -> Bool {
    switch keyCode {
    case 0x7D, 0x7C, 0x7E:  // Down, right, and up
        return true
    case 0x7B:  // Plain left is already handled by AppKit after Korean commit.
        return !modifierFlags.isDisjoint(with: [.shift, .control, .option, .command])
    default:
        return false
    }
}

// MARK: - UTF-16 Surrogate Handling

struct GhosttyLeadSurrogate: Equatable, Sendable {
    let codeUnit: Unicode.UTF16.CodeUnit

    init?(_ text: NSString) {
        guard text.length == 1 else { return nil }
        let codeUnit = text.character(at: 0)
        guard Unicode.UTF16.isLeadSurrogate(codeUnit) else { return nil }
        self.codeUnit = codeUnit
    }

    func encode(trail: GhosttyTrailSurrogate) -> String {
        String(decoding: [codeUnit, trail.codeUnit], as: Unicode.UTF16.self)
    }
}

struct GhosttyTrailSurrogate: Equatable, Sendable {
    let codeUnit: Unicode.UTF16.CodeUnit

    init?(_ text: NSString) {
        guard text.length == 1 else { return nil }
        let codeUnit = text.character(at: 0)
        guard Unicode.UTF16.isTrailSurrogate(codeUnit) else { return nil }
        self.codeUnit = codeUnit
    }
}

/// Converts NSEvent modifier flags to Ghostty modifier bitmask
func ghosttyMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var mods = GHOSTTY_MODS_NONE.rawValue
    if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }

    let rawFlags = flags.rawValue
    if rawFlags & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
    if rawFlags & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
    if rawFlags & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
    if rawFlags & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }

    return ghostty_input_mods_e(rawValue: mods)
}

// MARK: - Character Filtering

/// Ghostty key-event text drops empty strings and strings beginning with an
/// ASCII control scalar (C0 or DEL), preserving other text unchanged.
func ghosttyKeyEventText(from text: String?) -> String? {
    guard let text, !text.isEmpty, let firstScalar = text.unicodeScalars.first else { return nil }
    guard firstScalar.value >= 0x20, firstScalar.value != 0x7F else { return nil }
    return text
}

/// Filters characters for Ghostty key events
/// - Control chars: strips control modifier, returns base character
/// - Function keys (PUA range): returns nil
/// - Normal chars: returns as-is
func filterGhosttyCharacters(
    characters: String?,
    byApplyingModifiers: (_ flags: NSEvent.ModifierFlags) -> String?,
    modifierFlags: NSEvent.ModifierFlags
) -> String? {
    guard let characters else { return nil }

    if characters.count == 1, let scalar = characters.unicodeScalars.first {
        // Control characters < 0x20: strip control modifier
        if scalar.value < 0x20 {
            return byApplyingModifiers(modifierFlags.subtracting(.control))
        }
        // Function keys in PUA range: don't send
        if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
            return nil
        }
    }
    return characters
}

/// Text Ghostty receives for a key-down event. Key-up and modifier-only
/// events carry no text, as in upstream Ghostty; AppKit raises when
/// `characters` is read from a `.flagsChanged` event.
func ghosttyKeyEventText(for event: NSEvent) -> String? {
    guard event.type == .keyDown else { return nil }
    return filterGhosttyCharacters(
        characters: event.characters,
        byApplyingModifiers: { event.characters(byApplyingModifiers: $0) },
        modifierFlags: event.modifierFlags
    )
}

// MARK: - Key Routing Decision

/// Decision for how to route a key event
enum KeyRoutingDecision: Equatable {
    case passToSystem  // Return false, let macOS handle
    case handleInTerminal  // Call keyDown, return true
    case modifyAndHandle(String)  // Modify char, call keyDown, return true
}

/// Determines how to route a key equivalent event
func determineKeyRouting(
    eventType: NSEvent.EventType,
    focused: Bool,
    modifiers: NSEvent.ModifierFlags,
    charactersIgnoringModifiers: String?
) -> KeyRoutingDecision {
    // Only handle keyDown
    guard eventType == .keyDown else { return .passToSystem }

    // Must be focused
    guard focused else { return .passToSystem }

    let mods = modifiers.intersection(.deviceIndependentFlagsMask)

    // Command combinations go to macOS
    if mods.contains(.command) {
        return .passToSystem
    }

    // Control combinations go to terminal
    if mods.contains(.control) {
        // Ctrl+/ converts to Ctrl+_
        if charactersIgnoringModifiers == "/" {
            return .modifyAndHandle("_")
        }
        return .handleInTerminal
    }

    // Everything else flows to keyDown naturally
    return .passToSystem
}

// MARK: - Key Equivalent Decision

struct GhosttyKeyEquivalentInput: Equatable, Sendable {
    let isGhosttyBinding: Bool
    let characters: String?
    let charactersIgnoringModifiers: String?
    let modifierFlags: NSEvent.ModifierFlags
    let timestamp: TimeInterval
    let lastPerformKeyEvent: TimeInterval?
}

enum GhosttyKeyEquivalentDecision: Equatable, Sendable {
    case handleGhosttyBinding
    case handleControlReturn
    case handleControlSlash
    case passToSystem
    case resetTimestampAndPassToSystem
    case rememberTimestamp(TimeInterval)
    case replayTimestampedKey(text: String)
}

/// The key-binding lookup uses AppKit's raw event text, including C0 values.
func ghosttyBindingText(for characters: String?) -> String {
    characters ?? ""
}

/// Pure counterpart of Ghostty's key-equivalent routing after the key-binding
/// lookup. The caller applies timestamp state changes and dispatches the result.
func ghosttyKeyEquivalentDecision(for input: GhosttyKeyEquivalentInput) -> GhosttyKeyEquivalentDecision {
    guard !input.isGhosttyBinding else { return .handleGhosttyBinding }

    switch input.charactersIgnoringModifiers {
    case .some("\r"):
        return input.modifierFlags.contains(.control) ? .handleControlReturn : .passToSystem
    case .some("/"):
        guard input.modifierFlags.contains(.control),
            input.modifierFlags.isDisjoint(with: [.shift, .command, .option])
        else {
            return .passToSystem
        }
        return .handleControlSlash
    default:
        break
    }

    guard input.timestamp != 0 else { return .passToSystem }
    guard input.modifierFlags.contains(.command) || input.modifierFlags.contains(.control) else {
        return .resetTimestampAndPassToSystem
    }

    if input.lastPerformKeyEvent == input.timestamp {
        return .replayTimestampedKey(text: input.characters ?? "")
    }
    return .rememberTimestamp(input.timestamp)
}

/// AppKit can redirect a key equivalent through `doCommand`; only the exact
/// timestamp saved by `performKeyEquivalent` belongs back in the event stream.
func ghosttyShouldRedispatchCommandEvent(
    lastPerformKeyEvent: TimeInterval?,
    currentEventTimestamp: TimeInterval?
) -> Bool {
    guard let lastPerformKeyEvent, let currentEventTimestamp else { return false }
    return lastPerformKeyEvent == currentEventTimestamp
}

// MARK: - Mouse Button Mapping

/// Maps macOS mouse button number to Ghostty button
func ghosttyMouseButton(from buttonNumber: Int) -> ghostty_input_mouse_button_e {
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
