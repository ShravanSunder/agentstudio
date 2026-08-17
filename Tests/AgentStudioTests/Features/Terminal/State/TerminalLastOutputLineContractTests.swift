import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioTerminal

@Suite("Terminal last output line contract")
struct TerminalLastOutputLineContractTests {
    @Test("extracts the last non-empty trimmed line, ignoring trailing blank rows")
    func extractsLastNonEmptyTrimmedLine() {
        let rawViewportText = "$ npm test\nall tests passed  \n\n"

        let line = TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: rawViewportText)

        #expect(line == "all tests passed")
    }

    @Test("empty viewport read yields no candidate line")
    func emptyReadYieldsNilCandidate() {
        #expect(TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: "") == nil)
        #expect(TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: "\n\n   \n") == nil)
    }

    @Test("a bare shell prompt line is dropped in favor of the last real output line")
    func barePromptLineIsDropped() {
        let rawViewportText = "build succeeded\n➜ ~ "

        let line = TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: rawViewportText)

        #expect(line == "build succeeded")
    }

    @Test("a viewport containing only a bare prompt yields no candidate line")
    func onlyBarePromptYieldsNilCandidate() {
        #expect(TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: "$ ") == nil)
    }

    @Test("candidate line is truncated to the configured UTF-8 byte bound")
    func candidateLineIsBoundedToUTF8ByteLimit() {
        let longLine = String(repeating: "a", count: 400)

        let line = TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: longLine)

        #expect(line?.utf8.count == AppPolicies.TerminalOutputCapture.maxLastOutputLineUTF8Bytes)
        #expect(line == String(repeating: "a", count: AppPolicies.TerminalOutputCapture.maxLastOutputLineUTF8Bytes))
    }

    @Test("control character residue is stripped from the candidate line")
    func controlCharacterResidueIsStripped() {
        let rawViewportText = "done\u{0007} with\u{0000}task"

        let line = TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: rawViewportText)

        #expect(line == "done  with task")
    }
}
