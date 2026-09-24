import AppKit
import GhosttyKit

/// One `ghostty_surface_key` call, decided from an AppKit event before the
/// surface sends it. Keeping the decision pure lets it be tested without a
/// live Ghostty surface.
struct GhosttyKeyEventPlan: Equatable {
    let action: ghostty_input_action_e
    let keycode: UInt32
    let mods: ghostty_input_mods_e
    let consumedMods: ghostty_input_mods_e
    let unshiftedCodepoint: UInt32
    /// Printable text only; control characters are encoded by Ghostty.
    let text: String?
}

/// Builds the key input for a key-down, key-up, or modifier event.
///
/// `unshiftedCodepoint` reads `characters(byApplyingModifiers:)` only for
/// key-down and key-up. Control and command never contribute to text
/// translation, so they are excluded from the consumed modifiers.
func ghosttyKeyEventPlan(
    for event: NSEvent,
    action: ghostty_input_action_e,
    text: String?
) -> GhosttyKeyEventPlan {
    var unshiftedCodepoint: UInt32 = 0
    if event.type == .keyDown || event.type == .keyUp,
        let characters = event.characters(byApplyingModifiers: []),
        let codepoint = characters.unicodeScalars.first
    {
        unshiftedCodepoint = codepoint.value
    }
    return GhosttyKeyEventPlan(
        action: action,
        keycode: UInt32(event.keyCode),
        mods: ghosttyMods(from: event.modifierFlags),
        consumedMods: ghosttyMods(from: event.modifierFlags.subtracting([.control, .command])),
        unshiftedCodepoint: unshiftedCodepoint,
        text: shouldSendKeyEventText(text) ? text : nil
    )
}

/// Modifier-only event, mirroring upstream Ghostty's `flagsChanged`: the
/// key code names one modifier, a press is that modifier held on the key's
/// own side, and anything else is a release. No text is sent. Returns nil
/// for key codes that are not modifiers and while an input method is
/// composing.
func ghosttyModifierKeyEventPlan(for event: NSEvent, hasMarkedText: Bool) -> GhosttyKeyEventPlan? {
    let modifier: UInt32
    switch event.keyCode {
    case 0x39: modifier = GHOSTTY_MODS_CAPS.rawValue
    case 0x38, 0x3C: modifier = GHOSTTY_MODS_SHIFT.rawValue
    case 0x3B, 0x3E: modifier = GHOSTTY_MODS_CTRL.rawValue
    case 0x3A, 0x3D: modifier = GHOSTTY_MODS_ALT.rawValue
    case 0x37, 0x36: modifier = GHOSTTY_MODS_SUPER.rawValue
    default: return nil
    }
    guard !hasMarkedText else { return nil }

    var action = GHOSTTY_ACTION_RELEASE
    if ghosttyMods(from: event.modifierFlags).rawValue & modifier != 0 {
        // A right-side key presses only when its own device bit is set;
        // otherwise the other side is still holding the modifier.
        let rawFlags = event.modifierFlags.rawValue
        let sidePressed: Bool
        switch event.keyCode {
        case 0x3C: sidePressed = rawFlags & UInt(NX_DEVICERSHIFTKEYMASK) != 0
        case 0x3E: sidePressed = rawFlags & UInt(NX_DEVICERCTLKEYMASK) != 0
        case 0x3D: sidePressed = rawFlags & UInt(NX_DEVICERALTKEYMASK) != 0
        case 0x36: sidePressed = rawFlags & UInt(NX_DEVICERCMDKEYMASK) != 0
        default: sidePressed = true
        }
        if sidePressed { action = GHOSTTY_ACTION_PRESS }
    }
    return ghosttyKeyEventPlan(for: event, action: action, text: nil)
}
