import AppKit
import Testing

@testable import AgentStudioTerminal

@Suite("TerminalSearchOverlayView")
@MainActor
struct TerminalSearchOverlayViewTests {
    @Test("overlay emits expected callbacks")
    func searchOverlayEmitsExpectedCallbacks() {
        let overlay = TerminalSearchOverlayView()
        var capturedQuery: String?
        var capturedDirections: [TerminalSearchOverlayView.NavigationDirection] = []
        var closeCount = 0

        overlay.onQueryChanged = { capturedQuery = $0 }
        overlay.onNavigate = { capturedDirections.append($0) }
        overlay.onClose = { closeCount += 1 }

        overlay.simulateQueryChangeForTesting("needle")
        overlay.simulateNavigateForTesting(.next)
        overlay.simulateNavigateForTesting(.previous)
        overlay.simulateCloseForTesting()

        #expect(capturedQuery == "needle")
        #expect(capturedDirections == [.next, .previous])
        #expect(closeCount == 1)
    }

    @Test("result updates format the result label")
    func resultUpdatesFormatResultLabel() {
        let overlay = TerminalSearchOverlayView()

        overlay.updateResults(totalMatches: 12, selectedMatchIndex: 3)
        #expect(overlay.resultLabelTextForTesting == "4 of 12")

        overlay.updateResults(totalMatches: nil, selectedMatchIndex: nil)
        #expect(overlay.resultLabelTextForTesting.isEmpty)
    }
}
