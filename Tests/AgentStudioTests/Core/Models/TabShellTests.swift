import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct TabShellTests {
    @Test
    func init_normalizesName() {
        let shell = TabShell(id: UUID(), name: "  Review Queue\nFor Launch  ")

        #expect(shell.name == "Review Queue For Launch")
    }

    @Test
    func rename_normalizesName() {
        var shell = TabShell(id: UUID(), name: "One")

        shell.rename(to: "  Review Queue\nFor Launch  ")

        #expect(shell.name == "Review Queue For Launch")
    }
}
