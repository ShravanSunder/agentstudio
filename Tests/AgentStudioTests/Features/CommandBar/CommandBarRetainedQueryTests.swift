import AgentStudioInfrastructure
import AppKit
import Testing

@testable import AgentStudioCommandBar

@Suite("Command bar retained root query", .serialized)
struct CommandBarRetainedQueryTests {
    @Test("root query survives escape and action dismissal and selects on reopen")
    func rootQueryRestoresAfterDismissal() {
        let state = CommandBarState()
        state.show()
        state.rawInput = "oauth worktree"
        state.dismiss()
        #expect(state.lastRootQuery == "oauth worktree")

        state.show()
        #expect(state.rawInput == "oauth worktree")
        #expect(state.shouldSelectRestoredRootQuery)
        #expect(
            CommandBarTextField.Coordinator.selectionRange(for: state.rawInput, selectAll: true)
                == NSRange(location: 0, length: 14)
        )

        state.rawInput = "replacement"
        #expect(!state.shouldSelectRestoredRootQuery)
        state.dismiss()
        state.show()
        #expect(state.rawInput == "replacement")
    }

    @Test("prefix opens and nested input do not replace the retained root query")
    func prefixAndNestedInputDoNotReplaceRootQuery() {
        let state = CommandBarState()
        state.show()
        state.rawInput = "saved root"
        state.dismiss()

        state.show(prefix: "#")
        #expect(state.rawInput == "# ")
        #expect(!state.shouldSelectRestoredRootQuery)
        state.rawInput = "# another"
        state.dismiss()
        #expect(state.lastRootQuery == "saved root")

        state.show()
        state.pushLevel(CommandBarLevel(id: "nested", title: "Nested", items: []))
        state.rawInput = "nested query"
        state.dismiss()
        #expect(state.lastRootQuery == "saved root")
        state.show()
        #expect(state.rawInput == "saved root")
        state.switchPrefix(">")
        #expect(state.rawInput == "> ")
        #expect(!state.shouldSelectRestoredRootQuery)
    }
}
