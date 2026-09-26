import AppKit
import Testing

@testable import AgentStudioTerminal

@Suite
struct GhosttyKeyEquivalentDecisionTests {
    struct DecisionCase: CustomTestStringConvertible, Sendable {
        let name: String
        let input: GhosttyKeyEquivalentInput
        let expected: GhosttyKeyEquivalentDecision
        var testDescription: String { name }
    }

    struct CommandEventRedispatchCase: CustomTestStringConvertible, Sendable {
        let name: String
        let lastPerformKeyEvent: TimeInterval?
        let currentEventTimestamp: TimeInterval?
        let shouldRedispatch: Bool
        var testDescription: String { name }
    }

    static let cases: [DecisionCase] = [
        .init(
            name: "Ghostty binding handles before timestamp routing",
            input: .init(
                isGhosttyBinding: true,
                characters: "t",
                charactersIgnoringModifiers: "t",
                modifierFlags: .command,
                timestamp: 4,
                lastPerformKeyEvent: nil
            ),
            expected: .handleGhosttyBinding
        ),
        .init(
            name: "control return is passed through verbatim",
            input: .init(
                isGhosttyBinding: false,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                modifierFlags: .control,
                timestamp: 0,
                lastPerformKeyEvent: nil
            ),
            expected: .handleControlReturn
        ),
        .init(
            name: "control command return keeps the upstream control return case",
            input: .init(
                isGhosttyBinding: false,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                modifierFlags: [.control, .command],
                timestamp: 2,
                lastPerformKeyEvent: nil
            ),
            expected: .handleControlReturn
        ),
        .init(
            name: "return without control passes to AppKit",
            input: .init(
                isGhosttyBinding: false,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                modifierFlags: [],
                timestamp: 2,
                lastPerformKeyEvent: nil
            ),
            expected: .passToSystem
        ),
        .init(
            name: "control slash maps to control underscore",
            input: .init(
                isGhosttyBinding: false,
                characters: "/",
                charactersIgnoringModifiers: "/",
                modifierFlags: .control,
                timestamp: 2,
                lastPerformKeyEvent: nil
            ),
            expected: .handleControlSlash
        ),
        .init(
            name: "control shift slash passes to AppKit",
            input: .init(
                isGhosttyBinding: false,
                characters: "/",
                charactersIgnoringModifiers: "/",
                modifierFlags: [.control, .shift],
                timestamp: 2,
                lastPerformKeyEvent: nil
            ),
            expected: .passToSystem
        ),
        .init(
            name: "control command slash passes to AppKit",
            input: .init(
                isGhosttyBinding: false,
                characters: "/",
                charactersIgnoringModifiers: "/",
                modifierFlags: [.control, .command],
                timestamp: 2,
                lastPerformKeyEvent: nil
            ),
            expected: .passToSystem
        ),
        .init(
            name: "control option slash passes to AppKit",
            input: .init(
                isGhosttyBinding: false,
                characters: "/",
                charactersIgnoringModifiers: "/",
                modifierFlags: [.control, .option],
                timestamp: 2,
                lastPerformKeyEvent: nil
            ),
            expected: .passToSystem
        ),
        .init(
            name: "zero timestamp command event passes to AppKit",
            input: .init(
                isGhosttyBinding: false,
                characters: ".",
                charactersIgnoringModifiers: ".",
                modifierFlags: .command,
                timestamp: 0,
                lastPerformKeyEvent: nil
            ),
            expected: .passToSystem
        ),
        .init(
            name: "zero timestamp control event passes to AppKit",
            input: .init(
                isGhosttyBinding: false,
                characters: "c",
                charactersIgnoringModifiers: "c",
                modifierFlags: .control,
                timestamp: 0,
                lastPerformKeyEvent: nil
            ),
            expected: .passToSystem
        ),
        .init(
            name: "plain key resets a pending command timestamp",
            input: .init(
                isGhosttyBinding: false,
                characters: "a",
                charactersIgnoringModifiers: "a",
                modifierFlags: [],
                timestamp: 3,
                lastPerformKeyEvent: 2
            ),
            expected: .resetTimestampAndPassToSystem
        ),
        .init(
            name: "first command key records its timestamp",
            input: .init(
                isGhosttyBinding: false,
                characters: ".",
                charactersIgnoringModifiers: ".",
                modifierFlags: .command,
                timestamp: 5,
                lastPerformKeyEvent: nil
            ),
            expected: .rememberTimestamp(5)
        ),
        .init(
            name: "first control key records its timestamp",
            input: .init(
                isGhosttyBinding: false,
                characters: "c",
                charactersIgnoringModifiers: "c",
                modifierFlags: .control,
                timestamp: 6,
                lastPerformKeyEvent: nil
            ),
            expected: .rememberTimestamp(6)
        ),
        .init(
            name: "matching command timestamp redispatches the original characters",
            input: .init(
                isGhosttyBinding: false,
                characters: "ø",
                charactersIgnoringModifiers: "o",
                modifierFlags: .command,
                timestamp: 7,
                lastPerformKeyEvent: 7
            ),
            expected: .replayTimestampedKey(text: "ø")
        ),
        .init(
            name: "missing characters redispatch as empty text",
            input: .init(
                isGhosttyBinding: false,
                characters: nil,
                charactersIgnoringModifiers: "o",
                modifierFlags: .command,
                timestamp: 7,
                lastPerformKeyEvent: 7
            ),
            expected: .replayTimestampedKey(text: "")
        ),
        .init(
            name: "mismatched command timestamp replaces the pending timestamp",
            input: .init(
                isGhosttyBinding: false,
                characters: "p",
                charactersIgnoringModifiers: "p",
                modifierFlags: .command,
                timestamp: 8,
                lastPerformKeyEvent: 7
            ),
            expected: .rememberTimestamp(8)
        ),
    ]

    static let commandEventRedispatchCases: [CommandEventRedispatchCase] = [
        .init(
            name: "matching key equivalent timestamp redispatches",
            lastPerformKeyEvent: 4,
            currentEventTimestamp: 4,
            shouldRedispatch: true
        ),
        .init(
            name: "mismatched current event does not redispatch",
            lastPerformKeyEvent: 4,
            currentEventTimestamp: 5,
            shouldRedispatch: false
        ),
        .init(
            name: "missing prior timestamp does not redispatch",
            lastPerformKeyEvent: nil,
            currentEventTimestamp: 4,
            shouldRedispatch: false
        ),
        .init(
            name: "missing current event does not redispatch",
            lastPerformKeyEvent: 4,
            currentEventTimestamp: nil,
            shouldRedispatch: false
        ),
    ]

    @Test("key equivalents follow Ghostty binding and timestamp routing", arguments: cases)
    func decisionMatchesUpstream(testCase: DecisionCase) {
        #expect(ghosttyKeyEquivalentDecision(for: testCase.input) == testCase.expected)
    }

    @Test("doCommand redispatches only the matching performKeyEquivalent event", arguments: commandEventRedispatchCases)
    func commandEventRedispatchDecision(testCase: CommandEventRedispatchCase) {
        #expect(
            ghosttyShouldRedispatchCommandEvent(
                lastPerformKeyEvent: testCase.lastPerformKeyEvent,
                currentEventTimestamp: testCase.currentEventTimestamp
            ) == testCase.shouldRedispatch
        )
    }

    @Test("Ghostty binding text keeps raw event characters")
    func bindingTextUsesRawEventCharacters() {
        #expect(ghosttyBindingText(for: "\u{3}") == "\u{3}")
        #expect(ghosttyBindingText(for: nil).isEmpty)
    }
}
