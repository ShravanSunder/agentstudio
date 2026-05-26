import AppKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct TransientKeyboardSurfaceDismissBridgeTests {
    @Test("dismiss bridge dismisses on Escape when policy opts in")
    func dismissBridgeDismissesOnEscapeWhenPolicyOptsIn() throws {
        let view = TransientKeyboardSurfaceDismissCapturingView()
        var dismissCount = 0
        view.isEnabled = true
        view.policy = .dismissable()
        view.onDismiss = {
            dismissCount += 1
        }

        let handled = view.performKeyEquivalent(
            with: try #require(
                makeKeyEvent(
                    characters: "\u{1b}",
                    charactersIgnoringModifiers: "\u{1b}",
                    keyCode: 53
                )
            )
        )

        #expect(handled)
        #expect(dismissCount == 1)
    }

    @Test("dismiss bridge passes Escape through when policy does not opt in")
    func dismissBridgePassesEscapeThroughWhenPolicyDoesNotOptIn() throws {
        let view = TransientKeyboardSurfaceDismissCapturingView()
        var dismissCount = 0
        view.isEnabled = true
        view.policy = .blocking
        view.onDismiss = {
            dismissCount += 1
        }

        let handled = view.performKeyEquivalent(
            with: try #require(
                makeKeyEvent(
                    characters: "\u{1b}",
                    charactersIgnoringModifiers: "\u{1b}",
                    keyCode: 53
                )
            )
        )

        #expect(!handled)
        #expect(dismissCount == 0)
    }

    @Test("dismiss bridge dismisses on declared activation shortcut")
    func dismissBridgeDismissesOnDeclaredActivationShortcut() throws {
        let view = TransientKeyboardSurfaceDismissCapturingView()
        var dismissCount = 0
        view.isEnabled = true
        view.policy = .dismissable(
            dismissTriggers: [ShortcutTrigger(key: .character(.i), modifiers: [.command, .option])]
        )
        view.onDismiss = {
            dismissCount += 1
        }

        let handled = view.performKeyEquivalent(
            with: try #require(
                makeKeyEvent(
                    modifierFlags: [.command, .option],
                    characters: "i",
                    charactersIgnoringModifiers: "i",
                    keyCode: 34
                )
            )
        )

        #expect(handled)
        #expect(dismissCount == 1)
    }

    @Test("dismiss bridge passes command-I through")
    func dismissBridgePassesCommandIThrough() throws {
        let view = TransientKeyboardSurfaceDismissCapturingView()
        var dismissCount = 0
        view.isEnabled = true
        view.policy = .dismissable(
            dismissTriggers: [ShortcutTrigger(key: .character(.i), modifiers: [.command, .option])]
        )
        view.onDismiss = {
            dismissCount += 1
        }

        let handled = view.performKeyEquivalent(
            with: try #require(
                makeKeyEvent(
                    modifierFlags: [.command],
                    characters: "i",
                    charactersIgnoringModifiers: "i",
                    keyCode: 34
                )
            )
        )

        #expect(!handled)
        #expect(dismissCount == 0)
    }

    @Test("dismiss bridge ignores disabled surfaces")
    func dismissBridgeIgnoresDisabledSurfaces() throws {
        let view = TransientKeyboardSurfaceDismissCapturingView()
        var dismissCount = 0
        view.isEnabled = false
        view.policy = .dismissable()
        view.onDismiss = {
            dismissCount += 1
        }

        let handled = view.performKeyEquivalent(
            with: try #require(
                makeKeyEvent(
                    characters: "\u{1b}",
                    charactersIgnoringModifiers: "\u{1b}",
                    keyCode: 53
                )
            )
        )

        #expect(!handled)
        #expect(dismissCount == 0)
    }
}
