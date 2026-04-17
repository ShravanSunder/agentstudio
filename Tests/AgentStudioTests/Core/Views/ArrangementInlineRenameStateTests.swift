import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct ArrangementInlineRenameStateTests {
    @Test
    func beginEditing_nonDefaultArrangement_startsEditingWithDraftName() {
        let state = ArrangementInlineRenameState()
        let arrangementId = UUID()

        state.beginEditing(
            arrangementId: arrangementId,
            currentName: "#2",
            isDefault: false
        )

        #expect(state.editingArrangementId == arrangementId)
        #expect(state.draftName == "#2")
    }

    @Test
    func beginEditing_defaultArrangement_isIgnored() {
        let state = ArrangementInlineRenameState()

        state.beginEditing(
            arrangementId: UUID(),
            currentName: "Default",
            isDefault: true
        )

        #expect(state.editingArrangementId == nil)
        #expect(state.draftName.isEmpty)
    }

    @Test
    func commit_trimsAndReturnsRenamePayload() {
        let state = ArrangementInlineRenameState()
        let arrangementId = UUID()
        state.beginEditing(
            arrangementId: arrangementId,
            currentName: "Layout 2",
            isDefault: false
        )
        state.setDraftName("  Review Queue  ")

        let payload = state.commit()

        #expect(payload?.arrangementId == arrangementId)
        #expect(payload?.name == "Review Queue")
        #expect(state.editingArrangementId == nil)
        #expect(state.draftName.isEmpty)
    }

    @Test
    func commit_emptyDraftClearsStateAndReturnsNil() {
        let state = ArrangementInlineRenameState()
        state.beginEditing(
            arrangementId: UUID(),
            currentName: "Layout 2",
            isDefault: false
        )
        state.setDraftName("")

        let payload = state.commit()

        #expect(payload == nil)
        #expect(state.editingArrangementId == nil)
        #expect(state.draftName.isEmpty)
    }

    @Test
    func commit_whitespaceOnlyDraftClearsStateAndReturnsNil() {
        let state = ArrangementInlineRenameState()
        state.beginEditing(
            arrangementId: UUID(),
            currentName: "Layout 2",
            isDefault: false
        )
        state.setDraftName("   \t  ")

        let payload = state.commit()

        #expect(payload == nil)
        #expect(state.editingArrangementId == nil)
        #expect(state.draftName.isEmpty)
    }

    @Test
    func setDraftName_updatesObservableDraft() {
        let state = ArrangementInlineRenameState()
        state.beginEditing(
            arrangementId: UUID(),
            currentName: "Layout 2",
            isDefault: false
        )

        state.setDraftName("coding")

        #expect(state.draftName == "coding")
    }

    @Test
    func cancel_clearsEditingState() {
        let state = ArrangementInlineRenameState()
        state.beginEditing(
            arrangementId: UUID(),
            currentName: "Layout 2",
            isDefault: false
        )

        state.cancel()

        #expect(state.editingArrangementId == nil)
        #expect(state.draftName.isEmpty)
    }
}
