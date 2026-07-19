import Testing

@testable import AgentStudio

@Suite("Ghostty action disposition")
struct GhosttyActionDispositionTests {
    @Test("local presentation and activity events never classify as exact facts")
    func localEventsAreContracted() {
        #expect(
            GhosttyActionDisposition.classify(.mouseShapeChanged(shape: .pointer))
                == .latestPresentation(.mouseShape(.pointer)))
        #expect(
            GhosttyActionDisposition.classify(.mouseVisibilityChanged(isVisible: false))
                == .latestPresentation(.mouseVisibility(false)))
        #expect(
            GhosttyActionDisposition.classify(.searchMatchesUpdated(totalMatches: 4))
                == .latestPresentation(.searchMatches(4)))
        #expect(
            GhosttyActionDisposition.classify(.searchSelectionChanged(selectedMatchIndex: 1))
                == .latestPresentation(.searchSelection(1)))
        #expect(
            GhosttyActionDisposition.classify(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: 20)))
                == .activityEvidence(.scrollbar(ScrollbarState(top: 0, bottom: 10, total: 20)))
        )
    }

    @Test("search boundaries are exact local lifecycle")
    func searchBoundariesAreLocalLifecycle() {
        #expect(
            GhosttyActionDisposition.classify(.searchStarted(query: "needle"))
                == .exactLocalLifecycle(.searchStarted(query: "needle")))
        #expect(GhosttyActionDisposition.classify(.searchEnded) == .exactLocalLifecycle(.searchEnded))
    }

    @Test("semantic facts retain their exact route")
    func semanticFactsRemainExact() {
        let events: [GhosttyEvent] = [
            .commandFinished(exitCode: 0, duration: 12),
            .bellRang,
            .titleChanged("title"),
            .cwdChanged("/tmp"),
            .progressReportUpdated(ProgressState(kind: .set, percent: 50)),
            .secureInputChanged(true),
            .rendererHealthChanged(healthy: false),
        ]

        for event in events {
            #expect(GhosttyActionDisposition.classify(event) == .exactFactOrControl(event))
        }
    }

    @Test("direct host and diagnostic signals do not enter runtime publication")
    func directAndDiagnosticSignalsAreDroppedFromRuntime() {
        #expect(
            GhosttyActionDisposition.classify(.cellSizeChanged(.init(width: 8, height: 16)))
                == .diagnostic(.directHostState))
        #expect(
            GhosttyActionDisposition.classify(.initialSizeChanged(.init(width: 800, height: 600)))
                == .diagnostic(.directHostState))
        #expect(
            GhosttyActionDisposition.classify(.mouseLinkHovered(url: "https://example.com")) == .diagnostic(.localOnly))
        #expect(GhosttyActionDisposition.classify(.deferred(tag: 7)) == .diagnostic(.deferred))
    }
}
