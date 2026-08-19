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

    @Test("a prompt that embeds directory and branch text is excluded when it matches the learned signature")
    func promptEmbeddingDirectoryAndBranchTextIsExcludedByLearnedSignature() {
        // This is the exact reproduction from the live-acceptance investigation: an
        // oh-my-zsh-style prompt contains letters (the directory and branch name), so the
        // zero-letters bare-prompt heuristic alone cannot recognize it as a prompt — it must be
        // excluded by an explicit learned signature instead.
        let promptLine = "➜  chip-matrix-final-live (⑂ feat/sidebar-grouping-rows)"
        let rawViewportText = "AGENTSTUDIO_L2_ACTIVE_PROOF_28b7ebd53\n\(promptLine) "

        let unexcluded = TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: rawViewportText)
        let excluded = TerminalLastOutputLineContract.contractedLastLine(
            fromRawViewportText: rawViewportText,
            excluding: promptLine
        )

        // Without a learned signature, the zero-letters heuristic alone misreads the prompt as output.
        #expect(unexcluded == promptLine)
        // With the learned signature excluded, the real echoed line surfaces instead.
        #expect(excluded == "AGENTSTUDIO_L2_ACTIVE_PROOF_28b7ebd53")
    }

    @Test("the real three-line viewport shape resolves to the echoed output, not the prompt or the echoed command")
    func realThreeLineViewportShapeResolvesToEchoedOutput() {
        // The real Ghostty viewport for a completed command has three lines, not two: the prompt
        // with the typed command echoed onto it (terminal line-editing echo), the command's real
        // output, then the fresh bare prompt printed after the command finishes. Both prompt
        // occurrences share the same learned signature text; only the second one (the fresh,
        // untyped-on prompt) matches it exactly, so contraction must skip past it and stop at the
        // real output line without also being fooled by the first (command-bearing) prompt line.
        let promptLine = "➜  chip-matrix-final-live (⑂ feat/sidebar-grouping-rows)"
        let rawViewportText = """
            \(promptLine) echo AGENTSTUDIO_RC2_ACCEPT_ECHO_7fed04fbd
            AGENTSTUDIO_RC2_ACCEPT_ECHO_7fed04fbd
            \(promptLine)
            """

        let line = TerminalLastOutputLineContract.contractedLastLine(
            fromRawViewportText: rawViewportText,
            excluding: promptLine
        )

        #expect(line == "AGENTSTUDIO_RC2_ACCEPT_ECHO_7fed04fbd")
    }

    @Test("trailingNonEmptyLine returns the freshly-printed prompt with no bare-prompt or signature filtering")
    func trailingNonEmptyLineReturnsThePromptUnfiltered() {
        let rawViewportText = "real output\n➜  agent-studio (⑂ main) "

        let trailing = TerminalLastOutputLineContract.trailingNonEmptyLine(fromRawViewportText: rawViewportText)

        #expect(trailing == "➜  agent-studio (⑂ main)")
    }

    @Test("a viewport containing only the learned-signature prompt yields no candidate line")
    func onlyLearnedSignaturePromptYieldsNilCandidate() {
        let promptLine = "➜  agent-studio (⑂ main)"

        let line = TerminalLastOutputLineContract.contractedLastLine(
            fromRawViewportText: "\(promptLine) ",
            excluding: promptLine
        )

        #expect(line == nil)
    }
}
