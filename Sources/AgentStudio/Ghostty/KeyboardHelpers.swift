import AppKit
import GhosttyKit

// MARK: - Modifier Conversion

/// Converts NSEvent modifier flags to Ghostty modifier bitmask
func ghosttyMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var mods = GHOSTTY_MODS_NONE.rawValue
    if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
    return ghostty_input_mods_e(rawValue: mods)
}

// MARK: - Character Filtering

/// Determines if text should be sent for a key event
/// Control characters (< 0x20) should not be sent - Ghostty handles encoding
func shouldSendKeyEventText(_ text: String?) -> Bool {
    guard let text, !text.isEmpty else { return false }
    guard let codepoint = text.utf8.first else { return false }
    return codepoint >= 0x20
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
