import GhosttyKit
import Testing

@testable import AgentStudioTerminal

@Suite("Ghostty event routing coverage", .serialized)
@MainActor
struct GhosttyEventRoutingCoverageTests {
    @Test("upstream action vocabulary has no unmapped values")
    func upstreamActionVocabularyHasNoUnmappedValues() {
        let upstreamValues = Set(
            UInt32(GHOSTTY_ACTION_QUIT.rawValue)...UInt32(GHOSTTY_ACTION_MOVE_TAB_TO_NEW_WINDOW.rawValue))
        #expect(Set(GhosttyActionTag.allCases.map(\.rawValue)) == upstreamValues)
    }

    @Test(
        "unsupported upstream actions translate safely",
        arguments: [
            GhosttyActionTag.exportTerminalIO, .setWindowTitle, .selectionChanged, .moveTabToNewWindow,
        ])
    func unsupportedUpstreamActionsTranslateSafely(tag: GhosttyActionTag) {
        #expect(Ghostty.ActionRouter.unsupportedTags.contains(tag))
        #expect(GhosttyAdapter.shared.translate(actionTag: tag) == .unhandled(tag: tag.rawValue))
        #expect(GhosttyAdapter.shared.translate(actionTag: tag.rawValue) == .unhandled(tag: tag.rawValue))
    }

    @Test("every known Ghostty action tag has one explicit routing decision")
    func everyKnownGhosttyActionTag_hasExplicitRoutingDecision() {
        let accountedTags =
            Ghostty.ActionRouter.explicitlyRoutedTags
            .union(Ghostty.ActionRouter.deferredTags)
            .union(Ghostty.ActionRouter.interceptedTags)
            .union(Ghostty.ActionRouter.unsupportedTags)

        #expect(accountedTags == Set(GhosttyActionTag.allCases))
    }
}
