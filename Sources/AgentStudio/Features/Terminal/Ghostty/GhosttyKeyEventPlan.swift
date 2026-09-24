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

/// The AppKit event used to translate a key under Ghostty's configured
/// translation modifiers. The original event remains the source of key mods.
struct GhosttyKeyTranslationPlan {
    let event: NSEvent
}

/// Applies Ghostty's translation-modifier policy while preserving AppKit's
/// other modifier bits. Reusing the original event when the flags match is
/// required for input methods such as Korean.
func ghosttyKeyTranslationPlan(
    for event: NSEvent,
    using translationModsProvider: (ghostty_input_mods_e) -> ghostty_input_mods_e
) -> GhosttyKeyTranslationPlan {
    let translatedGhosttyMods = translationModsProvider(ghosttyMods(from: event.modifierFlags))
    let translatedModifiers = ghosttyTranslationModifierFlags(from: translatedGhosttyMods)

    var translationFlags = event.modifierFlags
    for modifier in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
        if translatedModifiers.contains(modifier) {
            translationFlags.insert(modifier)
        } else {
            translationFlags.remove(modifier)
        }
    }

    guard translationFlags != event.modifierFlags else {
        return GhosttyKeyTranslationPlan(event: event)
    }

    let translationEvent =
        NSEvent.keyEvent(
            with: event.type,
            location: event.locationInWindow,
            modifierFlags: translationFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: event.characters(byApplyingModifiers: translationFlags) ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            isARepeat: event.isARepeat,
            keyCode: event.keyCode
        ) ?? event

    return GhosttyKeyTranslationPlan(event: translationEvent)
}

private func ghosttyTranslationModifierFlags(from mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
    if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
    if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
    if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
    return flags
}

/// Builds the key input for a key-down, key-up, or modifier event.
///
/// `unshiftedCodepoint` reads `characters(byApplyingModifiers:)` only for
/// key-down and key-up. Control and command never contribute to text
/// translation, so they are excluded from the consumed modifiers.
func ghosttyKeyEventPlan(
    for event: NSEvent,
    action: ghostty_input_action_e,
    text: String?,
    translationModifiers: NSEvent.ModifierFlags? = nil
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
        consumedMods: ghosttyMods(
            from: (translationModifiers ?? event.modifierFlags).subtracting([.control, .command])
        ),
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
