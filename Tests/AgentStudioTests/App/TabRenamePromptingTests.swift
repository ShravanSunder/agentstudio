import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct TabRenamePromptingTests {
    @Test
    func promptUsesCurrentTabNameInCopy() {
        #expect(AlertTabRenamePrompter.promptTitle(currentName: "Review Queue") == "Rename \"Review Queue\"")
        #expect(
            AlertTabRenamePrompter.informativeText(currentName: "Review Queue")
                == "Enter a new name for \"Review Queue\"."
        )
    }

    @Test
    func promptFallsBackToGenericCopyWhenNameIsEmpty() {
        #expect(AlertTabRenamePrompter.promptTitle(currentName: "   ") == "Rename Tab")
        #expect(AlertTabRenamePrompter.informativeText(currentName: "   ") == "Enter a new name for this tab.")
    }
}
