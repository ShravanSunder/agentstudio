import AppKit
import Foundation

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
    /// Drawer is open AND has no panes AND focus is on the drawer.
    /// Raw-character bindings (no modifiers) fire here, gated upstream
    /// on a neutral responder so text fields keep receiving keystrokes.
    case emptyDrawer
}

struct AppShortcutSpec: Equatable {
    /// Primary trigger — what shows in the command bar / menus.
    let trigger: ShortcutTrigger

    /// Alternate triggers keyed by the exact contexts where they are
    /// valid. This prevents a context-specific raw character binding
    /// from inheriting the broader contexts of the primary trigger.
    let alternateTriggers: [ShortcutTrigger: Set<ShortcutContext>]

    let contexts: Set<ShortcutContext>

    init(
        trigger: ShortcutTrigger,
        alternateTriggers: [ShortcutTrigger: Set<ShortcutContext>] = [:],
        contexts: Set<ShortcutContext>
    ) {
        self.trigger = trigger
        self.alternateTriggers = alternateTriggers
        self.contexts = contexts
    }

    /// Trigger to display in a given context. The first matching
    /// trigger from `[trigger] + alternateTriggers` whose modifier
    /// shape suits the context wins. Falls back to the primary
    /// trigger when no alternate is appropriate.
    ///
    /// Today the only context that prefers an alternate is
    /// `.emptyDrawer`, which prefers a no-modifier raw-character
    /// trigger when one exists. Other contexts use the primary.
    func displayTrigger(in context: ShortcutContext) -> ShortcutTrigger {
        if context == .emptyDrawer,
            let rawCharacterAlternate = alternateTriggers.first(where: { trigger, contexts in
                trigger.modifiers.isEmpty && contexts.contains(context)
            })?.key
        {
            return rawCharacterAlternate
        }
        return trigger
    }

    func matches(_ candidate: ShortcutTrigger, in context: ShortcutContext) -> Bool {
        if candidate == trigger {
            return contexts.contains(context)
        }
        guard let contexts = alternateTriggers[candidate] else {
            return false
        }
        return contexts.contains(context)
    }
}

enum AppShortcut: String, CaseIterable {
    case closeTab
    case newTab
    case undoCloseTab
    case nextTab
    case prevTab
    case cycleArrangement
    case addDrawerPane
    case toggleDrawer
    case scrollToBottom
    case openPaneLocationInBookmarkedEditor
    case openPaneLocationInFinder
    case openPaneLocationInEditorMenu
    case toggleManagementLayer
    case toggleSidebar
    case filterSidebar
    case showInboxNotifications
    case showPaneInboxNotifications
    case showWorktreeSidebar
    case newWindow
    case closeWindow
    case showCommandBarEverything
    case showCommandBarCommands
    case showCommandBarPanes
    case focusPane1
    case focusPane2
    case focusPane3
    case focusPane4
    case focusPane5
    case focusPane6
    case focusPane7
    case focusPane8
    case focusPane9
    case focusDrawerPane1
    case focusDrawerPane2
    case focusDrawerPane3
    case focusDrawerPane4
    case focusDrawerPane5
    case focusDrawerPane6
    case focusDrawerPane7
    case focusDrawerPane8
    case focusDrawerPane9
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
    case managementLayerEnterDrawer
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
                trigger: .init(key: .character(.l), modifiers: [.command, .option]),
                contexts: [.global, .terminalAppOwned]
            )
        case .prevTab:
            return .init(
                trigger: .init(key: .character(.j), modifiers: [.command, .option]),
                contexts: [.global, .terminalAppOwned]
            )
        case .cycleArrangement:
            return .init(
                trigger: .init(key: .character(.i), modifiers: [.command, .option]),
                contexts: [.global, .terminalAppOwned]
            )
        case .addDrawerPane:
            // Primary: cmd-shift-D fires globally (also in
            // terminal-app-owned context). Alternate: raw-character
            // P fires in `.emptyDrawer` (gated on neutral responder
            // upstream so text fields still receive the keystroke).
            return .init(
                trigger: .init(key: .character(.d), modifiers: [.command, .shift]),
                alternateTriggers: [
                    .init(key: .character(.p), modifiers: []): [.emptyDrawer]
                ],
                contexts: [.global, .terminalAppOwned, .emptyDrawer]
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
                trigger: .init(key: .character(.f), modifiers: [.command]),
                contexts: [.global]
            )
        case .showInboxNotifications:
            return .init(
                trigger: .init(key: .character(.i), modifiers: [.command]),
                contexts: [.global, .terminalAppOwned]
            )
        case .showPaneInboxNotifications:
            return .init(
                trigger: .init(key: .character(.i), modifiers: [.command, .shift]),
                contexts: [.global, .terminalAppOwned]
            )
        case .showWorktreeSidebar:
            return .init(
                trigger: .init(key: .character(.s), modifiers: [.command]),
                contexts: [.global, .terminalAppOwned]
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
        case .focusPane1:
            return Self.focusPaneSpec(key: .digit1)
        case .focusPane2:
            return Self.focusPaneSpec(key: .digit2)
        case .focusPane3:
            return Self.focusPaneSpec(key: .digit3)
        case .focusPane4:
            return Self.focusPaneSpec(key: .digit4)
        case .focusPane5:
            return Self.focusPaneSpec(key: .digit5)
        case .focusPane6:
            return Self.focusPaneSpec(key: .digit6)
        case .focusPane7:
            return Self.focusPaneSpec(key: .digit7)
        case .focusPane8:
            return Self.focusPaneSpec(key: .digit8)
        case .focusPane9:
            return Self.focusPaneSpec(key: .digit9)
        case .focusDrawerPane1:
            return Self.focusDrawerPaneSpec(key: .digit1)
        case .focusDrawerPane2:
            return Self.focusDrawerPaneSpec(key: .digit2)
        case .focusDrawerPane3:
            return Self.focusDrawerPaneSpec(key: .digit3)
        case .focusDrawerPane4:
            return Self.focusDrawerPaneSpec(key: .digit4)
        case .focusDrawerPane5:
            return Self.focusDrawerPaneSpec(key: .digit5)
        case .focusDrawerPane6:
            return Self.focusDrawerPaneSpec(key: .digit6)
        case .focusDrawerPane7:
            return Self.focusDrawerPaneSpec(key: .digit7)
        case .focusDrawerPane8:
            return Self.focusDrawerPaneSpec(key: .digit8)
        case .focusDrawerPane9:
            return Self.focusDrawerPaneSpec(key: .digit9)
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
        case .managementLayerEnterDrawer:
            return Self.managementSpec(key: .enter)
        case .managementLayerExitDrawer:
            return Self.managementSpec(key: .arrow(.up))
        case .managementLayerOpenDrawer:
            return Self.managementSpec(
                key: .character(.d),
                alternateTriggers: [
                    .init(key: .arrow(.down), modifiers: []): [.managementLayer]
                ]
            )
        case .managementLayerCreateTerminal:
            return Self.managementSpec(key: .character(.p))
        case .managementLayerCreateBrowser:
            return Self.managementSpec(key: .character(.b))
        case .managementLayerExit:
            return Self.managementSpec(key: .character(.r))
        }
    }

    var trigger: ShortcutTrigger { spec.trigger }

    /// All triggers (primary + alternates) that dispatch this command.
    var triggers: [ShortcutTrigger] { [spec.trigger] + Array(spec.alternateTriggers.keys) }

    var command: AppCommand {
        switch self {
        case .closeTab:
            return .closeTab
        case .newTab:
            return .showCommandBarRepos
        case .undoCloseTab:
            return .undoCloseTab
        case .nextTab:
            return .nextTab
        case .prevTab:
            return .prevTab
        case .cycleArrangement:
            return .cycleArrangement
        case .addDrawerPane:
            return .addDrawerPane
        case .toggleDrawer:
            return .toggleDrawer
        case .scrollToBottom:
            return .scrollToBottom
        case .openPaneLocationInBookmarkedEditor:
            return .openPaneLocationInBookmarkedEditor
        case .openPaneLocationInFinder:
            return .openPaneLocationInFinder
        case .openPaneLocationInEditorMenu:
            return .openPaneLocationInEditorMenu
        case .toggleManagementLayer:
            return .toggleManagementLayer
        case .toggleSidebar:
            return .toggleSidebar
        case .filterSidebar:
            return .filterSidebar
        case .showInboxNotifications:
            return .showInboxNotifications
        case .showPaneInboxNotifications:
            return .showPaneInboxNotifications
        case .showWorktreeSidebar:
            return .showWorktreeSidebar
        case .newWindow:
            return .newWindow
        case .closeWindow:
            return .closeWindow
        case .showCommandBarEverything:
            return .showCommandBarEverything
        case .showCommandBarCommands:
            return .showCommandBarCommands
        case .showCommandBarPanes:
            return .showCommandBarPanes
        case .focusPane1:
            return .focusPane1
        case .focusPane2:
            return .focusPane2
        case .focusPane3:
            return .focusPane3
        case .focusPane4:
            return .focusPane4
        case .focusPane5:
            return .focusPane5
        case .focusPane6:
            return .focusPane6
        case .focusPane7:
            return .focusPane7
        case .focusPane8:
            return .focusPane8
        case .focusPane9:
            return .focusPane9
        case .focusDrawerPane1:
            return .focusDrawerPane1
        case .focusDrawerPane2:
            return .focusDrawerPane2
        case .focusDrawerPane3:
            return .focusDrawerPane3
        case .focusDrawerPane4:
            return .focusDrawerPane4
        case .focusDrawerPane5:
            return .focusDrawerPane5
        case .focusDrawerPane6:
            return .focusDrawerPane6
        case .focusDrawerPane7:
            return .focusDrawerPane7
        case .focusDrawerPane8:
            return .focusDrawerPane8
        case .focusDrawerPane9:
            return .focusDrawerPane9
        case .selectTab1:
            return .selectTab1
        case .selectTab2:
            return .selectTab2
        case .selectTab3:
            return .selectTab3
        case .selectTab4:
            return .selectTab4
        case .selectTab5:
            return .selectTab5
        case .selectTab6:
            return .selectTab6
        case .selectTab7:
            return .selectTab7
        case .selectTab8:
            return .selectTab8
        case .selectTab9:
            return .selectTab9
        case .managementLayerFocusLeft:
            return .managementLayerFocusLeft
        case .managementLayerFocusRight:
            return .managementLayerFocusRight
        case .managementLayerEnterDrawer:
            return .managementLayerEnterDrawer
        case .managementLayerExitDrawer:
            return .managementLayerExitDrawer
        case .managementLayerOpenDrawer:
            return .managementLayerOpenDrawer
        case .managementLayerCreateTerminal:
            return .managementLayerCreateTerminal
        case .managementLayerCreateBrowser:
            return .managementLayerCreateBrowser
        case .managementLayerExit:
            return .managementLayerExit
        }
    }
    var contexts: Set<ShortcutContext> { spec.contexts }
    var keyBinding: KeyBinding? { trigger.keyBinding }
}

extension AppShortcut {
    func displayKeyBinding(in context: ShortcutContext) -> KeyBinding? {
        spec.displayTrigger(in: context).keyBinding
    }

    fileprivate static func selectTabSpec(key: ShortcutCharacterKey) -> AppShortcutSpec {
        .init(
            trigger: .init(key: .character(key), modifiers: [.command]),
            contexts: [.global]
        )
    }

    fileprivate static func focusPaneSpec(key: ShortcutCharacterKey) -> AppShortcutSpec {
        .init(
            trigger: .init(key: .character(key), modifiers: [.command, .shift]),
            contexts: [.global, .terminalAppOwned]
        )
    }

    fileprivate static func focusDrawerPaneSpec(key: ShortcutCharacterKey) -> AppShortcutSpec {
        .init(
            trigger: .init(key: .character(key), modifiers: [.command, .shift, .option]),
            contexts: [.global, .terminalAppOwned]
        )
    }

    fileprivate static func managementSpec(
        key: ShortcutInputKey,
        alternateTriggers: [ShortcutTrigger: Set<ShortcutContext>] = [:]
    ) -> AppShortcutSpec {
        .init(
            trigger: .init(key: key, modifiers: []),
            alternateTriggers: alternateTriggers,
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
            shortcut.spec.matches(trigger, in: context)
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
