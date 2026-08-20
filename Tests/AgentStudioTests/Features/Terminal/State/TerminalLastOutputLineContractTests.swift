import AgentStudioInfrastructure
import Testing

@testable import AgentStudioTerminal

@Suite("Terminal last output line contract")
struct TerminalLastOutputLineContractTests {
    @Test("extracts the last non-empty trimmed line without semantic shell classification")
    func extractsLiteralTrailingNonEmptyLine() {
        let rawViewportText = "$ npm test\nall tests passed  \n\n"

        let line = TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: rawViewportText)

        #expect(line == "all tests passed")
    }

    @Test("shell prompts and echoed commands remain valid literal terminal context")
    func preservesShellPromptAndCommandText() {
        #expect(
            TerminalLastOutputLineContract.contractedLastLine(
                fromRawViewportText: "build succeeded\n⚡ ➜ agent-memory-engine (main) "
            ) == "⚡ ➜ agent-memory-engine (main)"
        )
        #expect(
            TerminalLastOutputLineContract.contractedLastLine(
                fromRawViewportText: "⚡ ➜ agent-memory-engine (main) ls"
            ) == "⚡ ➜ agent-memory-engine (main) ls"
        )
        #expect(TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: "$ ") == "$")
    }

    @Test("empty viewport read yields no candidate line")
    func emptyReadYieldsNilCandidate() {
        #expect(TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: "") == nil)
        #expect(TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: "\n\n   \n") == nil)
    }

    @Test("candidate line is truncated to the configured UTF-8 byte bound")
    func candidateLineIsBoundedToUTF8ByteLimit() {
        let longLine = String(repeating: "a", count: 400)

        let line = TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: longLine)

        #expect(line?.utf8.count == AppPolicies.TerminalOutputCapture.maxLastOutputLineUTF8Bytes)
    }

    @Test("control character residue is stripped from the candidate line")
    func controlCharacterResidueIsStripped() {
        let line = TerminalLastOutputLineContract.contractedLastLine(
            fromRawViewportText: "done\u{0007} with\u{0000}task"
        )

        #expect(line == "done  with task")
    }
}
