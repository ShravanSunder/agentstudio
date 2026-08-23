import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Sidebar performance proof startup diagnostics", .serialized)
struct SidebarPerformanceProofStartupDiagnosticTests {
    @Test("action tracker rejects overlap and mismatched or stale readback")
    func actionTrackerRejectsOverlapAndMismatchedOrStaleReadback() throws {
        let baseline = makeReadback(
            semanticGeneration: 7,
            acknowledgedRevision: 11,
            visibleGeneration: 13,
            groupingMode: .repo
        )
        var tracker = SidebarPerformanceProofActionTracker()
        let startedAction = tracker.begin(
            sequence: 1,
            baseline: baseline,
            expectedGrouping: .pane,
            expectsFilterFocus: true
        )
        let action = try #require(startedAction)

        let overlappingAction = tracker.begin(
            sequence: 2,
            baseline: baseline,
            expectedGrouping: .tab,
            expectsFilterFocus: false
        )
        #expect(overlappingAction == nil)
        #expect(
            !SidebarPerformanceProofActionTracker.matches(
                makeReadback(
                    semanticGeneration: 8,
                    acknowledgedRevision: 11,
                    visibleGeneration: 14,
                    groupingMode: .pane,
                    queryIsEmpty: true,
                    focusDisposition: .filterFocused
                ),
                action: action
            )
        )
        #expect(
            !SidebarPerformanceProofActionTracker.matches(
                makeReadback(
                    semanticGeneration: 8,
                    acknowledgedRevision: 12,
                    visibleGeneration: 14,
                    groupingMode: .tab,
                    queryIsEmpty: true,
                    focusDisposition: .filterFocused
                ),
                action: action
            )
        )
        #expect(
            !SidebarPerformanceProofActionTracker.matches(
                makeReadback(
                    semanticGeneration: 8,
                    acknowledgedRevision: 12,
                    visibleGeneration: 14,
                    groupingMode: .pane,
                    queryIsEmpty: false,
                    focusDisposition: .filterFocused
                ),
                action: action
            )
        )
        #expect(
            SidebarPerformanceProofActionTracker.matches(
                makeReadback(
                    semanticGeneration: 8,
                    acknowledgedRevision: 12,
                    visibleGeneration: 14,
                    groupingMode: .pane,
                    queryIsEmpty: true,
                    focusDisposition: .filterFocused
                ),
                action: action
            )
        )
        let mismatchedCompletion = tracker.complete(sequence: 2)
        #expect(!mismatchedCompletion)
        #expect(tracker.outstandingAction?.sequence == 1)
        let matchingCompletion = tracker.complete(sequence: 1)
        #expect(matchingCompletion)
        #expect(tracker.outstandingAction == nil)
    }

    @Test("strict CPU populations use fixed debug selectors and one correlated action")
    func strictCPUPopulationsUseFixedDebugSelectorsAndOneCorrelatedAction() throws {
        let actionSource = try String(
            contentsOfFile: "Sources/AgentStudio/App/Boot/AgentStudioStartupDiagnosticAction.swift",
            encoding: .utf8
        )
        let sessionSource = try String(
            contentsOfFile:
                "Sources/AgentStudio/App/Boot/SidebarPerformanceProofSession.swift",
            encoding: .utf8
        )

        for selector in [
            "sidebar-cpu-zero-pty-idle", "sidebar-cpu-quiescent-pty-idle",
            "sidebar-cpu-search-clear", "sidebar-cpu-grouping", "sidebar-cpu-hide-show",
            "sidebar-cpu-tab-switch",
        ] {
            #expect(actionSource.contains(selector))
        }
        #expect(sessionSource.contains("private var actionTracker"))
        #expect(sessionSource.contains("guard outstandingAction == nil"))
        #expect(sessionSource.contains("RepoExplorerPerformanceProofReadback"))
        #expect(sessionSource.contains("AppCommandDispatcher.shared.dispatch"))
        #expect(sessionSource.contains("SidebarPerformanceProofNativeInputDriver"))
        #expect(sessionSource.contains("performance.sidebar.proof_action.started"))
        #expect(sessionSource.contains("performance.sidebar.proof_action.settled"))
        #expect(sessionSource.contains("performance.sidebar.proof_action.failed"))
        #expect(!sessionSource.contains("socket"))
        #expect(!sessionSource.contains("FIFO"))
        #expect(!sessionSource.contains("NotificationCenter"))
        #expect(!sessionSource.contains("AppEventBus"))
        #expect(!sessionSource.contains("AppCommandIPC"))
    }

    @Test("sidebar performance search driver uses native key events and policy cadence")
    func sidebarPerformanceSearchDriverUsesNativeKeyEventsAndPolicyCadence() throws {
        let source = try String(
            contentsOfFile:
                "Sources/AgentStudio/App/Boot/AppDelegate+SidebarPerformanceProofStartupDiagnostics.swift",
            encoding: .utf8
        )

        #expect(source.contains("window.firstResponder is NSTextView"))
        #expect(source.contains("NSEvent.keyEvent("))
        #expect(source.contains("window.sendEvent(event)"))
        #expect(source.contains("searchCharacterInterval"))
        #expect(source.contains("modifierFlags: modifiers"))
        #expect(source.contains("modifiers: [.command]"))
        #expect(source.contains("keyCode: 51"))
        #expect(!source.contains("setFilterText"))
        #expect(!source.contains("filterText ="))
        #expect(!source.contains("uiState."))
        #expect(!source.contains("AppCommandIPC"))
    }

    private func makeReadback(
        semanticGeneration: Int,
        acknowledgedRevision: UInt64,
        visibleGeneration: UInt64,
        groupingMode: RepoExplorerGroupingMode,
        queryIsEmpty: Bool = true,
        focusDisposition: RepoExplorerPerformanceProofReadback.FocusDisposition = .notFocused
    ) -> RepoExplorerPerformanceProofReadback {
        RepoExplorerPerformanceProofReadback(
            semanticGeneration: semanticGeneration,
            acknowledgedRevision: acknowledgedRevision,
            visibleGeneration: visibleGeneration,
            representedRowCount: 24,
            groupingMode: groupingMode,
            queryIsEmpty: queryIsEmpty,
            isDemanded: true,
            presentationIsReady: true,
            focusDisposition: focusDisposition,
            accessibilityDisposition: .ready
        )
    }
}
