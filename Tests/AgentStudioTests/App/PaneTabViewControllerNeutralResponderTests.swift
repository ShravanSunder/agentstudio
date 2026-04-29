import AppKit
import Foundation
import Testing

@testable import AgentStudio

/// Raw empty-drawer shortcuts must not steal typed input while an
/// NSText responder owns focus. Modifier-keyed shortcuts may still
/// dispatch through `performKeyEquivalent`, but plain `p` is always
/// gated by neutral focus.
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
