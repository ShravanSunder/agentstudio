import AppKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct CommandBarPanelTests {
    @Test
    func performKeyEquivalent_routesDecodedShortcutTriggerToHandler() throws {
        let panel = CommandBarPanel()
        var recordedTriggers: [ShortcutTrigger] = []
        panel.onShortcutTrigger = { trigger in
            recordedTriggers.append(trigger)
            return true
        }

        let event = try #require(
            makeKeyEvent(
                modifierFlags: [.command],
                characters: "w",
                charactersIgnoringModifiers: "w",
                keyCode: 13
            )
        )

        let handled = panel.performKeyEquivalent(with: event)

        #expect(handled)
        #expect(recordedTriggers == [ShortcutTrigger(key: .character(.w), modifiers: [.command])])
    }

    @Test
    func performKeyEquivalent_fallsThroughWhenHandlerDoesNotConsumeTrigger() throws {
        let panel = CommandBarPanel()
        panel.onShortcutTrigger = { _ in false }

        let event = try #require(
            makeKeyEvent(
                modifierFlags: [.command],
                characters: "w",
                charactersIgnoringModifiers: "w",
                keyCode: 13
            )
        )

        let handled = panel.performKeyEquivalent(with: event)

        #expect(!handled)
    }

    @Test
    func performKeyEquivalent_doesNotConsumePlainEnterWhenHandlerDeclinesIt() throws {
        let panel = CommandBarPanel()
        var recordedTriggers: [ShortcutTrigger] = []
        panel.onShortcutTrigger = { trigger in
            recordedTriggers.append(trigger)
            return false
        }

        let event = try #require(
            makeKeyEvent(
                modifierFlags: [],
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                keyCode: 36
            )
        )

        let handled = panel.performKeyEquivalent(with: event)

        #expect(!handled)
        #expect(recordedTriggers == [ShortcutTrigger(key: .enter, modifiers: [])])
    }
}
