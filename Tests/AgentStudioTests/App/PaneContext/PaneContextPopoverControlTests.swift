import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Testing

@testable import AgentStudio

struct PaneContextPopoverControlTests {
    @Test
    func controlsUseTheLocalActionSpecs() {
        let controls = PaneContextPopoverControlProjection.controls()
        #expect(controls.answer.label == LocalActionSpec.answerPaneMessage.actionSpec.label)
        #expect(controls.goToPane.label == LocalActionSpec.goToMessagePane.actionSpec.label)
        #expect(controls.messages.icon == .system(SystemSymbol.bell.rawValue))
        #expect(
            controls.answer.tooltip
                == LocalActionSpec.answerPaneMessage.actionSpec.controlTooltipRenderValue(
                    provenance: .localAction(rawValue: LocalActionSpec.answerPaneMessage.actionSpec.label)))
        #expect(
            controls.filters.map(\.attentionType) == [nil, .needsApproval, .needsReply, .attention, .informational])
    }

    @Test
    func pullRequestPresentationKeepsCompactCopyAndNeutralUnknownState() {
        let attention = PaneContextPopoverControlProjection.pullRequestPresentation(
            .init(state: .needsAttention(count: 1), members: [.unknown(worktreeId: UUIDv7.generate())]))
        #expect(attention.header == "Needs attention (1)")
        #expect(attention.chipText == "1 ✗")
        #expect(attention.tone == .danger)
        let neutral = PaneContextPopoverControlProjection.pullRequestPresentation(
            .init(state: .noInfo, members: [.noPullRequest(worktreeId: UUIDv7.generate())]))
        #expect(neutral.chipText == "1")
        #expect(neutral.glyph == nil)
        #expect(neutral.tone == .neutral)
    }
}
