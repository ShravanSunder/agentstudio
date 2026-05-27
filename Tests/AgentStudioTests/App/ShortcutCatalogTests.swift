import AppKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct ShortcutCatalogTests {
    @Test
    func everyShortcutHasASpec() {
        for shortcut in AppShortcut.allCases {
            let spec = shortcut.spec
            #expect(!spec.contexts.isEmpty)
        }
    }

    @Test
    func shortcutCatalog_declaresPaneTargetFallbacks() {
        for shortcut in AppShortcut.allCases {
            #expect(shortcut.requiresPaneTargetFallback == (shortcut == .addDrawerPane))
        }
    }

    @Test
    func shortcutTriggers_areUniqueWithinEachContext() {
        var seen: [ShortcutContext: Set<ShortcutTrigger>] = [:]

        for shortcut in AppShortcut.allCases {
            for context in shortcut.contexts {
                let inserted = seen[context, default: []].insert(shortcut.trigger).inserted
                #expect(
                    inserted,
                    "Duplicate shortcut trigger \(String(describing: shortcut.trigger)) in context \(String(describing: context))"
                )
            }
        }
    }

    @Test
    func shortcutAndCommandDefinitions_stayBidirectionallyConsistent() {
        for shortcut in AppShortcut.allCases {
            let definition = CommandDispatcher.shared.definition(for: shortcut.command)
            #expect(definition.shortcut == shortcut)
        }
    }

    @Test
    func commandSpecDerivesKeyBindingFromShortcut() {
        let managementLayerDefinition = CommandDispatcher.shared.definition(for: .toggleManagementLayer)
        let quickOpenDefinition = CommandDispatcher.shared.definition(for: .showCommandBarEverything)
        let startContextDefinition = CommandDispatcher.shared.definition(for: .showCommandBarRepos)
        let addDrawerPaneDefinition = CommandDispatcher.shared.definition(for: .addDrawerPane)
        let paneInboxDefinition = CommandDispatcher.shared.definition(for: .showPaneInboxNotifications)

        #expect(managementLayerDefinition.keyBinding?.key == "r")
        #expect(managementLayerDefinition.keyBinding?.modifiers == [.command])
        #expect(quickOpenDefinition.keyBinding?.key == "p")
        #expect(quickOpenDefinition.keyBinding?.modifiers == [.command])
        #expect(startContextDefinition.keyBinding?.key == "t")
        #expect(startContextDefinition.keyBinding?.modifiers == [.command])
        #expect(addDrawerPaneDefinition.keyBinding?.key == "d")
        #expect(addDrawerPaneDefinition.keyBinding?.modifiers == [.command, .shift])
        #expect(paneInboxDefinition.keyBinding?.key == "u")
        #expect(paneInboxDefinition.keyBinding?.modifiers == [.command, .shift])
        #expect(paneInboxDefinition.actionSpec.label == "Toggle Pane Inbox")
    }

    @Test
    func shortcutDecoder_decodesGlobalCommandBarShortcuts() {
        let quickOpen = ShortcutDecoder.shortcut(
            for: .init(key: .character(.p), modifiers: [.command]),
            in: .global
        )
        let commandPalette = ShortcutDecoder.shortcut(
            for: .init(key: .character(.p), modifiers: [.command, .shift]),
            in: .global
        )
        let panePicker = ShortcutDecoder.shortcut(
            for: .init(key: .character(.p), modifiers: [.command, .option]),
            in: .global
        )
        let smartNewTab = ShortcutDecoder.shortcut(
            for: .init(key: .character(.t), modifiers: [.command]),
            in: .global
        )

        #expect(quickOpen == .showCommandBarEverything)
        #expect(commandPalette == .showCommandBarCommands)
        #expect(panePicker == .showCommandBarPanes)
        #expect(smartNewTab == .newTab)
    }

    @Test
    func shortcutDecoder_decodesSidebarSurfaceShortcuts() {
        let showInbox = ShortcutDecoder.shortcut(
            for: .init(key: .character(.u), modifiers: [.command]),
            in: .global
        )
        let showRepos = ShortcutDecoder.shortcut(
            for: .init(key: .character(.s), modifiers: [.command]),
            in: .global
        )

        #expect(showInbox == .showInboxNotifications)
        #expect(showRepos == .showWorktreeSidebar)
    }

    @Test
    func shortcutDecoder_decodesTabAndArrangementShortcuts() {
        let previousTab = ShortcutDecoder.shortcut(
            for: .init(key: .character(.j), modifiers: [.command]),
            in: .global
        )
        let nextTab = ShortcutDecoder.shortcut(
            for: .init(key: .character(.l), modifiers: [.command]),
            in: .global
        )
        let showArrangements = ShortcutDecoder.shortcut(
            for: .init(key: .character(.i), modifiers: [.command, .option]),
            in: .global
        )
        let previousArrangement = ShortcutDecoder.shortcut(
            for: .init(key: .character(.j), modifiers: [.command, .option]),
            in: .global
        )
        let nextArrangement = ShortcutDecoder.shortcut(
            for: .init(key: .character(.l), modifiers: [.command, .option]),
            in: .global
        )

        #expect(previousTab == .prevTab)
        #expect(nextTab == .nextTab)
        #expect(showArrangements == .showArrangementPanel)
        #expect(previousArrangement == .previousArrangement)
        #expect(nextArrangement == .nextArrangement)
    }

    @Test
    func shortcutDecoder_decodesTabAndPaneOrdinalShortcuts() {
        let firstTab = ShortcutDecoder.shortcut(
            for: .init(key: .character(.digit1), modifiers: [.command]),
            in: .global
        )
        let ninthTabFromTerminal = ShortcutDecoder.shortcut(
            for: .init(key: .character(.digit9), modifiers: [.command]),
            in: .terminalAppOwned
        )
        let firstMainPane = ShortcutDecoder.shortcut(
            for: .init(key: .character(.digit1), modifiers: [.option]),
            in: .global
        )
        let ninthMainPaneFromTerminal = ShortcutDecoder.shortcut(
            for: .init(key: .character(.digit9), modifiers: [.option]),
            in: .terminalAppOwned
        )

        #expect(firstTab == .selectTab1)
        #expect(ninthTabFromTerminal == .selectTab9)
        #expect(firstMainPane == .focusPane1)
        #expect(ninthMainPaneFromTerminal == .focusPane9)
    }

    @Test
    func shortcutDecoder_decodesPaneInboxShortcut() {
        let showPaneInbox = ShortcutDecoder.shortcut(
            for: .init(key: .character(.u), modifiers: [.command, .shift]),
            in: .global
        )
        let terminalShowPaneInbox = ShortcutDecoder.shortcut(
            for: .init(key: .character(.u), modifiers: [.command, .shift]),
            in: .terminalAppOwned
        )

        #expect(showPaneInbox == .showPaneInboxNotifications)
        #expect(terminalShowPaneInbox == .showPaneInboxNotifications)
    }

    @Test
    func shortcutDecoder_decodesSidebarSurfaceShortcutsInTerminalPanes() {
        let showInbox = ShortcutDecoder.shortcut(
            for: .init(key: .character(.u), modifiers: [.command]),
            in: .terminalAppOwned
        )
        let showRepos = ShortcutDecoder.shortcut(
            for: .init(key: .character(.s), modifiers: [.command]),
            in: .terminalAppOwned
        )

        #expect(showInbox == .showInboxNotifications)
        #expect(showRepos == .showWorktreeSidebar)
    }

    @Test
    func shortcutDecoder_decodesSidebarFilterShortcut() {
        let showFilter = ShortcutDecoder.shortcut(
            for: .init(key: .character(.f), modifiers: [.command]),
            in: .global
        )

        #expect(showFilter == .filterSidebar)
    }

    @Test
    func shortcutDecoder_decodesAddDrawerPaneShortcut() {
        let addDrawerPane = ShortcutDecoder.shortcut(
            for: .init(key: .character(.d), modifiers: [.command, .shift]),
            in: .global
        )
        let rawPGlobal = ShortcutDecoder.shortcut(
            for: .init(key: .character(.p), modifiers: []),
            in: .global
        )
        let rawPTerminal = ShortcutDecoder.shortcut(
            for: .init(key: .character(.p), modifiers: []),
            in: .terminalAppOwned
        )
        let rawPEmptyDrawer = ShortcutDecoder.shortcut(
            for: .init(key: .character(.p), modifiers: []),
            in: .emptyDrawer
        )

        #expect(addDrawerPane == .addDrawerPane)
        #expect(rawPGlobal == nil)
        #expect(rawPTerminal == nil)
        #expect(rawPEmptyDrawer == .addDrawerPane)
    }

    @Test
    func shortcutDecoder_decodesTerminalScrollAndPromptShortcuts() {
        let scrollToBottom = ShortcutDecoder.shortcut(
            for: .init(key: .character(.k), modifiers: [.command, .shift]),
            in: .terminalAppOwned
        )
        let previousPrompt = ShortcutDecoder.shortcut(
            for: .init(key: .character(.j), modifiers: [.command, .shift]),
            in: .terminalAppOwned
        )
        let nextPrompt = ShortcutDecoder.shortcut(
            for: .init(key: .character(.l), modifiers: [.command, .shift]),
            in: .terminalAppOwned
        )
        let pageUp = ShortcutDecoder.shortcut(
            for: .init(key: .character(.i), modifiers: [.command, .shift]),
            in: .terminalAppOwned
        )
        let ghosttyClearScrollback = ShortcutDecoder.shortcut(
            for: .init(key: .character(.k), modifiers: [.command]),
            in: .terminalAppOwned
        )

        #expect(scrollToBottom == .scrollToBottom)
        #expect(previousPrompt == .jumpToPreviousPrompt)
        #expect(nextPrompt == .jumpToNextPrompt)
        #expect(pageUp == .scrollPageUp)
        #expect(ghosttyClearScrollback == nil)
    }

    @Test
    func shortcutDecoder_decodesDrawerEditorShortcuts() {
        let openBookmarkedEditor = ShortcutDecoder.shortcut(
            for: .init(key: .character(.o), modifiers: [.command]),
            in: .global
        )
        let openFinder = ShortcutDecoder.shortcut(
            for: .init(key: .character(.o), modifiers: [.command, .shift]),
            in: .global
        )
        let openChooser = ShortcutDecoder.shortcut(
            for: .init(key: .character(.o), modifiers: [.command, .option]),
            in: .global
        )

        #expect(openBookmarkedEditor == .openPaneLocationInBookmarkedEditor)
        #expect(openFinder == .openPaneLocationInFinder)
        #expect(openChooser == .openPaneLocationInEditorMenu)
    }

    @Test
    func shortcutDecoder_decodesPaneNoteAndCurrentPathShortcuts() {
        let editNote = ShortcutDecoder.shortcut(
            for: .init(key: .character(.n), modifiers: [.command, .option, .shift]),
            in: .global
        )
        let copyPath = ShortcutDecoder.shortcut(
            for: .init(key: .character(.o), modifiers: [.command, .option, .shift]),
            in: .terminalAppOwned
        )

        #expect(editNote == .editPaneNote)
        #expect(copyPath == .copyCurrentPanePath)
        #expect(AppShortcut.editPaneNote.command == .editPaneNote)
        #expect(AppShortcut.copyCurrentPanePath.command == .copyCurrentPanePath)
    }

    @Test
    func watchFolder_hasNoKeyboardShortcut() {
        let shortcuts = AppShortcut.allCases.filter { $0.command == .watchFolder }

        #expect(shortcuts.isEmpty)
    }

    @Test
    func shortcutDecoder_decodesCharacterAndEscapeEvents() {
        let managementToggle = ShortcutDecoder.decode(
            keyCode: 15,
            modifierFlags: [.command],
            charactersIgnoringModifiers: "r"
        )
        let escape = ShortcutDecoder.decode(
            keyCode: 53,
            modifierFlags: [],
            charactersIgnoringModifiers: nil
        )

        #expect(managementToggle == .init(key: .character(.r), modifiers: [.command]))
        #expect(escape == .init(key: .escape, modifiers: []))
    }

    @Test
    func shortcutCatalog_decodesDrawerMovementLetters() {
        let expectations: [(String, ShortcutTrigger)] = [
            ("i", .init(key: .character(.i), modifiers: [.option])),
            ("j", .init(key: .character(.j), modifiers: [.option])),
            ("k", .init(key: .character(.k), modifiers: [.option])),
            ("l", .init(key: .character(.l), modifiers: [.option])),
        ]

        for (character, expected) in expectations {
            let decoded = ShortcutDecoder.decode(
                keyCode: 0,
                modifierFlags: [.option],
                charactersIgnoringModifiers: character
            )
            #expect(decoded == expected)
        }
    }

    @Test
    func shortcutDecoder_decodesManagementShortcuts() {
        let focusLeft = ShortcutDecoder.shortcut(
            for: .init(key: .arrow(.left), modifiers: []),
            in: .managementLayer
        )
        let openDrawer = ShortcutDecoder.shortcut(
            for: .init(key: .character(.d), modifiers: []),
            in: .managementLayer
        )
        let openDrawerWithDownArrow = ShortcutDecoder.shortcut(
            for: .init(key: .arrow(.down), modifiers: []),
            in: .managementLayer
        )
        let exitMode = ShortcutDecoder.shortcut(
            for: .init(key: .character(.r), modifiers: []),
            in: .managementLayer
        )

        #expect(focusLeft == .managementLayerFocusLeft)
        #expect(openDrawer == .managementLayerOpenDrawer)
        #expect(openDrawerWithDownArrow == .managementLayerOpenDrawer)
        #expect(exitMode == .managementLayerExit)
    }

    @Test
    func shortcutDecoder_normalizesArrowKeyModifiers() {
        let trigger = ShortcutDecoder.decode(
            keyCode: 123,
            modifierFlags: [.numericPad],
            charactersIgnoringModifiers: nil
        )

        #expect(trigger == .init(key: .arrow(.left), modifiers: []))
    }

    @Test
    func shortcutDecoder_normalizesLeftBracketAndRejectsUnknownCharacters() {
        let leftBracket = ShortcutDecoder.decode(
            keyCode: 33,
            modifierFlags: [.command],
            charactersIgnoringModifiers: "\u{1B}"
        )
        let unknown = ShortcutDecoder.decode(
            keyCode: 999,
            modifierFlags: [],
            charactersIgnoringModifiers: "~"
        )

        #expect(leftBracket == .init(key: .character(.leftBracket), modifiers: [.command]))
        #expect(unknown == nil)
    }
}
