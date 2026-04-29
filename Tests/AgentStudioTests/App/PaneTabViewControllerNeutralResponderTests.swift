import AppKit
import Foundation
import Testing

@testable import AgentStudio

/// Codex NEW P2 — `shouldCreateFirstDrawerPane` accepts a
/// `requiresNeutralFocus` parameter but the body originally never
/// read it. The local-monitor key path passes `true` so a raw `d`
/// keystroke that fires while a text-input responder owns focus
/// would still be intercepted to create a drawer pane (e.g. typing
/// `d` into the command bar).
///
/// The neutral-responder helper is the gate. NSText (and its
/// subclasses — NSTextView is what the field editor uses) absorb
/// typed characters; everything else is neutral.
@MainActor
@Suite(.serialized)
struct PaneTabViewControllerNeutralResponderTests {

    @Test
    func nilResponder_isNeutral() {
        #expect(PaneTabViewController.isNeutralResponderForRawCharacter(nil))
    }

    @Test
    func nsTextView_isNotNeutral() {
        let textView = NSTextView()
        #expect(!PaneTabViewController.isNeutralResponderForRawCharacter(textView))
    }

    @Test
    func nsText_isNotNeutral() {
        // NSText itself (the abstract superclass) shouldn't be neutral
        // either — concrete subclasses may not be the only consumers.
        let text = NSText()
        #expect(!PaneTabViewController.isNeutralResponderForRawCharacter(text))
    }

    @Test
    func plainNSView_isNeutral() {
        let view = NSView()
        #expect(PaneTabViewController.isNeutralResponderForRawCharacter(view))
    }

    @Test
    func customNonTextResponder_isNeutral() {
        final class FakeResponder: NSResponder {}
        let responder = FakeResponder()
        #expect(PaneTabViewController.isNeutralResponderForRawCharacter(responder))
    }
}
