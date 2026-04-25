import AppKit
import Foundation

/// Raw-character shortcuts that fire on a single keystroke (no
/// modifiers) within a specific drawer context. Distinct from the
/// modifier-keyed `AppShortcut` cases — these only fire when a
/// neutral responder owns focus, so text-input fields still receive
/// the keystroke as text.
///
/// Single source of truth: changing the case here updates BOTH the
/// key-event gate (`PaneTabViewController.shouldCreateFirstDrawerPane`)
/// and the on-screen hint (`DrawerPanel`'s empty-state label).
enum EmptyDrawerKeyShortcut {
    /// Create the first pane in an empty, focused drawer.
    static let createFirstPane: ShortcutCharacterKey = .p
}

// swiftlint:disable identifier_name
enum ShortcutCharacterKey: String, CaseIterable {
    case a
    case b
    case d
    case e
    case f
    case i
    case j
    case k
    case l
    case m
    case n
    case o
    case p
    case r
    case s
    case t
    case w
    case comma = ","
    case leftBracket = "["
    case rightBracket = "]"
    case digit1 = "1"
    case digit2 = "2"
    case digit3 = "3"
    case digit4 = "4"
    case digit5 = "5"
    case digit6 = "6"
    case digit7 = "7"
    case digit8 = "8"
    case digit9 = "9"

    var displayString: String {
        switch self {
        case .leftBracket:
            return "["
        case .rightBracket:
            return "]"
        case .comma:
            return ","
        default:
            return rawValue.uppercased()
        }
    }
}
// swiftlint:enable identifier_name

enum ShortcutArrowKey: CaseIterable {
    case left
    case right
    case down
    case up

    var displayString: String {
        switch self {
        case .left:
            return "←"
        case .right:
            return "→"
        case .down:
            return "↓"
        case .up:
            return "↑"
        }
    }
}

enum ShortcutInputKey: Hashable {
    case character(ShortcutCharacterKey)
    case arrow(ShortcutArrowKey)
    case enter
    case escape

    var displayString: String {
        switch self {
        case .character(let key):
            return key.displayString
        case .arrow(let key):
            return key.displayString
        case .enter:
            return "↵"
        case .escape:
            return "Esc"
        }
    }
}

struct ShortcutTrigger: Hashable {
    let key: ShortcutInputKey
    let modifiers: Set<KeyBinding.Modifier>

    var keyBinding: KeyBinding? {
        guard case .character(let key) = key else { return nil }
        return KeyBinding(key: key.rawValue, modifiers: modifiers)
    }
}

enum ShortcutContext: CaseIterable, Hashable {
    case global
    case managementLayer
    case terminalAppOwned
}

struct AppShortcutSpec: Equatable {
    let trigger: ShortcutTrigger
    let contexts: Set<ShortcutContext>
}

enum AppShortcut: String, CaseIterable {
    case closeTab
    case newTab
    case undoCloseTab
    case nextTab
    case prevTab
    case addDrawerPane
    case toggleDrawer
    case scrollToBottom
    case openPaneLocationInBookmarkedEditor
    case openPaneLocationInFinder
    case openPaneLocationInEditorMenu
    case toggleManagementLayer
    case toggleSidebar
    case filterSidebar
    case newWindow
    case closeWindow
    case showCommandBarEverything
    case showCommandBarCommands
    case showCommandBarPanes
    case selectTab1
    case selectTab2
    case selectTab3
    case selectTab4
    case selectTab5
    case selectTab6
    case selectTab7
    case selectTab8
    case selectTab9
    case managementLayerFocusLeft
    case managementLayerFocusRight
    case managementLayerExitDrawer
    case managementLayerOpenDrawer
    case managementLayerCreateTerminal
    case managementLayerCreateBrowser
    case managementLayerExit

    var spec: AppShortcutSpec {
        switch self {
        case .closeTab:
            return .init(
                trigger: .init(key: .character(.w), modifiers: [.command]),
                contexts: [.global]
            )
        case .newTab:
            return .init(
                trigger: .init(key: .character(.t), modifiers: [.command]),
                contexts: [.global]
            )
        case .undoCloseTab:
            return .init(
                trigger: .init(key: .character(.t), modifiers: [.command, .shift]),
                contexts: [.global]
            )
        case .nextTab:
            return .init(
                trigger: .init(key: .character(.rightBracket), modifiers: [.command, .shift]),
                contexts: [.global]
            )
        case .prevTab:
            return .init(
                trigger: .init(key: .character(.leftBracket), modifiers: [.command, .shift]),
                contexts: [.global]
            )
        case .addDrawerPane:
            return .init(
                trigger: .init(key: .character(.d), modifiers: [.command, .shift]),
                contexts: [.global, .terminalAppOwned]
            )
        case .toggleDrawer:
            return .init(
                trigger: .init(key: .character(.d), modifiers: [.command]),
                contexts: [.global, .terminalAppOwned]
            )
        case .scrollToBottom:
            return .init(
                trigger: .init(key: .character(.k), modifiers: [.command, .option]),
                contexts: [.terminalAppOwned]
            )
        case .openPaneLocationInBookmarkedEditor:
            return .init(
                trigger: .init(key: .character(.o), modifiers: [.command]),
                contexts: [.global, .terminalAppOwned]
            )
        case .openPaneLocationInFinder:
            return .init(
                trigger: .init(key: .character(.o), modifiers: [.command, .shift]),
                contexts: [.global, .terminalAppOwned]
            )
        case .openPaneLocationInEditorMenu:
            return .init(
                trigger: .init(key: .character(.o), modifiers: [.command, .option]),
                contexts: [.global, .terminalAppOwned]
            )
        case .toggleManagementLayer:
            return .init(
                trigger: .init(key: .character(.r), modifiers: [.command]),
                contexts: [.global, .terminalAppOwned]
            )
        case .toggleSidebar:
            return .init(
                trigger: .init(key: .character(.s), modifiers: [.command, .shift]),
                contexts: [.global]
            )
        case .filterSidebar:
            return .init(
                trigger: .init(key: .character(.f), modifiers: [.command, .shift]),
                contexts: [.global]
            )
        case .newWindow:
            return .init(
                trigger: .init(key: .character(.n), modifiers: [.command]),
                contexts: [.global]
            )
        case .closeWindow:
            return .init(
                trigger: .init(key: .character(.w), modifiers: [.command, .shift]),
                contexts: [.global]
            )
        case .showCommandBarEverything:
            return .init(
                trigger: .init(key: .character(.p), modifiers: [.command]),
                contexts: [.global, .terminalAppOwned]
            )
        case .showCommandBarCommands:
            return .init(
                trigger: .init(key: .character(.p), modifiers: [.command, .shift]),
                contexts: [.global, .terminalAppOwned]
            )
        case .showCommandBarPanes:
            return .init(
                trigger: .init(key: .character(.p), modifiers: [.command, .option]),
                contexts: [.global, .terminalAppOwned]
            )
        case .selectTab1:
            return Self.selectTabSpec(key: .digit1)
        case .selectTab2:
            return Self.selectTabSpec(key: .digit2)
        case .selectTab3:
            return Self.selectTabSpec(key: .digit3)
        case .selectTab4:
            return Self.selectTabSpec(key: .digit4)
        case .selectTab5:
            return Self.selectTabSpec(key: .digit5)
        case .selectTab6:
            return Self.selectTabSpec(key: .digit6)
        case .selectTab7:
            return Self.selectTabSpec(key: .digit7)
        case .selectTab8:
            return Self.selectTabSpec(key: .digit8)
        case .selectTab9:
            return Self.selectTabSpec(key: .digit9)
        case .managementLayerFocusLeft:
            return Self.managementSpec(key: .arrow(.left))
        case .managementLayerFocusRight:
            return Self.managementSpec(key: .arrow(.right))
        case .managementLayerExitDrawer:
            return Self.managementSpec(key: .arrow(.up))
        case .managementLayerOpenDrawer:
            return Self.managementSpec(key: .character(.d))
        case .managementLayerCreateTerminal:
            return Self.managementSpec(key: .character(.p))
        case .managementLayerCreateBrowser:
            return Self.managementSpec(key: .character(.b))
        case .managementLayerExit:
            return Self.managementSpec(key: .character(.r))
        }
    }

    var trigger: ShortcutTrigger { spec.trigger }
    var command: AppCommand {
        switch self {
        case .newTab:
            return .showCommandBarRepos
        default:
            guard let command = AppCommand(rawValue: rawValue) else {
                fatalError("Missing AppCommand for shortcut \(rawValue)")
            }
            return command
        }
    }
    var contexts: Set<ShortcutContext> { spec.contexts }
    var keyBinding: KeyBinding? { trigger.keyBinding }
}

extension AppShortcut {
    fileprivate static func selectTabSpec(key: ShortcutCharacterKey) -> AppShortcutSpec {
        .init(
            trigger: .init(key: .character(key), modifiers: [.command]),
            contexts: [.global]
        )
    }

    fileprivate static func managementSpec(key: ShortcutInputKey) -> AppShortcutSpec {
        .init(
            trigger: .init(key: key, modifiers: []),
            contexts: [.managementLayer]
        )
    }
}

enum ShortcutDecoder {
    static func decode(event: NSEvent) -> ShortcutTrigger? {
        decode(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers
        )
    }

    static func decode(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        charactersIgnoringModifiers: String?
    ) -> ShortcutTrigger? {
        let modifiers = shortcutModifiers(from: modifierFlags)

        switch keyCode {
        case 36, 76:
            return .init(key: .enter, modifiers: modifiers)
        case 53:
            return .init(key: .escape, modifiers: modifiers)
        case 123:
            return .init(key: .arrow(.left), modifiers: modifiers)
        case 124:
            return .init(key: .arrow(.right), modifiers: modifiers)
        case 125:
            return .init(key: .arrow(.down), modifiers: modifiers)
        case 126:
            return .init(key: .arrow(.up), modifiers: modifiers)
        default:
            break
        }

        guard let charactersIgnoringModifiers else { return nil }
        let normalized = normalizeCharacter(charactersIgnoringModifiers)
        guard let key = ShortcutCharacterKey(rawValue: normalized) else { return nil }
        return .init(key: .character(key), modifiers: modifiers)
    }

    static func shortcut(
        for trigger: ShortcutTrigger,
        in context: ShortcutContext
    ) -> AppShortcut? {
        AppShortcut.allCases.first { shortcut in
            shortcut.trigger == trigger && shortcut.contexts.contains(context)
        }
    }

    private static func shortcutModifiers(from flags: NSEvent.ModifierFlags) -> Set<KeyBinding.Modifier> {
        let normalizedFlags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers = Set<KeyBinding.Modifier>()
        if normalizedFlags.contains(.command) { modifiers.insert(.command) }
        if normalizedFlags.contains(.control) { modifiers.insert(.control) }
        if normalizedFlags.contains(.option) { modifiers.insert(.option) }
        if normalizedFlags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }

    private static func normalizeCharacter(_ charactersIgnoringModifiers: String) -> String {
        switch charactersIgnoringModifiers {
        case "\u{1B}":
            return ShortcutCharacterKey.leftBracket.rawValue
        default:
            return charactersIgnoringModifiers.lowercased()
        }
    }
}
