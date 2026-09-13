import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Testing

@Suite("IPC typed target selectors")
struct IPCTargetSelectorTests {
    @Test("a UUID receives its declared kind and a pane ordinal remains unresolved")
    func parsingRetainsDeclaredTargetKind() throws {
        let identifier = UUIDv7.generate()
        #expect(
            try IPCTargetSelector.parse(identifier.uuidString, expectedKind: .pane)
                == .canonical(kind: .pane, id: identifier)
        )
        #expect(
            try IPCTargetSelector.parse(identifier.uuidString, expectedKind: .workspace)
                == .canonical(kind: .workspace, id: identifier)
        )
        #expect(try IPCTargetSelector.parse("self", expectedKind: .pane) == .selfPane)
        #expect(try IPCTargetSelector.parse("pane:3", expectedKind: .pane) == .paneOrdinal(3))
    }

    @Test("target-kind mismatch is distinct from an invalid selector")
    func mismatchAndInvalidSelectorAreDistinct() throws {
        for selector in ["workspace:3", "window:3", "repo:3", "tab:3"] {
            #expect(throws: IPCTargetSelectorError.wrongTargetKind) {
                try IPCTargetSelector.parse(selector, expectedKind: .pane)
            }
        }
        for selector in ["self", "pane:3"] {
            #expect(throws: IPCTargetSelectorError.wrongTargetKind) {
                try IPCTargetSelector.parse(selector, expectedKind: .workspace)
            }
        }
        for selector in ["", "focused", "pane:0", "pane:-1", "pane:01", "pane:99999999999999999999999"] {
            #expect(throws: IPCTargetSelectorError.invalidSelector) {
                try IPCTargetSelector.parse(selector, expectedKind: .pane)
            }
        }
    }
}
