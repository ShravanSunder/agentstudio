import AppKit

extension KeyBinding {
    var nsModifierMask: NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        for modifier in modifiers {
            switch modifier {
            case .command: mask.insert(.command)
            case .control: mask.insert(.control)
            case .option: mask.insert(.option)
            case .shift: mask.insert(.shift)
            }
        }
        return mask
    }

    func apply(to item: NSMenuItem) {
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = nsModifierMask
    }
}
