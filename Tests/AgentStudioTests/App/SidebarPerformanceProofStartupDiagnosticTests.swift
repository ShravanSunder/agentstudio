import AgentStudioInfrastructure
import AppKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Sidebar performance proof startup diagnostics", .serialized)
struct SidebarPerformanceProofStartupDiagnosticTests {
    @Test("action tracker rejects overlap and mismatched or stale grouping readback")
    func actionTrackerRejectsOverlapAndMismatchedOrStaleReadback() throws {
        let baseline = makeReadback(
            semanticGeneration: 7,
            acknowledgedRevision: 11,
            visibleGeneration: 13,
            groupingMode: .repo,
            nativeGroupingMode: .repo
        )
        var tracker = SidebarPerformanceProofActionTracker()
        let startedAction = tracker.begin(
            sequence: 1,
            baseline: baseline,
            expectedOutcome: .grouping(.pane)
        )
        let action = try #require(startedAction)

        let overlappingAction = tracker.begin(
            sequence: 2,
            baseline: baseline,
            expectedOutcome: .grouping(.tab)
        )
        #expect(overlappingAction == nil)
        #expect(
            !SidebarPerformanceProofActionTracker.matches(
                makeReadback(
                    semanticGeneration: 8,
                    acknowledgedRevision: 11,
                    visibleGeneration: 14,
                    groupingMode: .pane,
                    nativeGroupingMode: .pane
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
                    nativeGroupingMode: .tab
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
                    nativeGroupingMode: .repo
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
                    nativeGroupingMode: .pane
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

    @Test("visibility settlement does not require an unrelated Repo Explorer revision")
    func visibilitySettlementAllowsAnEqualProjectionBaseline() throws {
        let baseline = makeReadback(
            semanticGeneration: 7,
            acknowledgedRevision: 11,
            visibleGeneration: 13,
            groupingMode: .repo,
            nativeGroupingMode: .repo
        )
        var tracker = SidebarPerformanceProofActionTracker()
        let startedAction = tracker.begin(
            sequence: 1,
            baseline: baseline,
            expectedOutcome: .sidebarCollapsed(true)
        )
        let action = try #require(startedAction)
        let hidden = makeReadback(
            semanticGeneration: 7,
            acknowledgedRevision: 11,
            visibleGeneration: 13,
            groupingMode: .repo,
            nativeGroupingMode: nil,
            isDemanded: false,
            presentationIsReady: false,
            accessibilityDisposition: .unavailable,
            sidebarIsCollapsed: true,
            nativeSidebarGeometryIsVisible: false,
            nativeSidebarAccessibilityIsReady: false,
            nativePresentedRowCount: nil
        )

        #expect(SidebarPerformanceProofActionTracker.matches(hidden, action: action))
    }

    @Test("search must settle filtered presentation before clearing")
    func searchRequiresFilteredSettlementBeforeClear() throws {
        let fixtureQuery = "worktree"
        let baseline = makeReadback(
            semanticGeneration: 7,
            acknowledgedRevision: 11,
            visibleGeneration: 13,
            groupingMode: .repo,
            nativeGroupingMode: .repo,
            focusDisposition: .filterFocused,
            nativeFilterValue: ""
        )
        var tracker = SidebarPerformanceProofActionTracker()
        let startedAction = tracker.begin(
            sequence: 1,
            baseline: baseline,
            expectedOutcome: .search(query: fixtureQuery)
        )
        let filteredAction = try #require(startedAction)
        let prematurelyCleared = makeReadback(
            semanticGeneration: 8,
            acknowledgedRevision: 12,
            visibleGeneration: 14,
            groupingMode: .repo,
            nativeGroupingMode: .repo,
            focusDisposition: .filterFocused,
            nativeFilterValue: ""
        )
        #expect(!SidebarPerformanceProofActionTracker.matches(prematurelyCleared, action: filteredAction))

        let filtered = makeReadback(
            semanticGeneration: 8,
            acknowledgedRevision: 12,
            visibleGeneration: 14,
            groupingMode: .repo,
            nativeGroupingMode: .repo,
            query: fixtureQuery,
            focusDisposition: .filterFocused,
            nativeFilterValue: fixtureQuery
        )
        #expect(SidebarPerformanceProofActionTracker.matches(filtered, action: filteredAction))
        let advancedAction = tracker.advance(
            sequence: 1,
            baseline: filtered,
            expectedOutcome: .search(query: "")
        )
        let clearAction = try #require(advancedAction)
        let cleared = makeReadback(
            semanticGeneration: 9,
            acknowledgedRevision: 13,
            visibleGeneration: 15,
            groupingMode: .repo,
            nativeGroupingMode: .repo,
            focusDisposition: .filterFocused,
            nativeFilterValue: ""
        )
        #expect(SidebarPerformanceProofActionTracker.matches(cleared, action: clearAction))
    }

    @Test("tab settlement requires semantic identity native content and focus")
    func tabSettlementRequiresTheOwningNativeState() throws {
        let firstTabID = UUIDv7.generate()
        let secondTabID = UUIDv7.generate()
        let firstPaneID = UUIDv7.generate()
        let secondPaneID = UUIDv7.generate()
        let baseline = makeReadback(
            semanticGeneration: 7,
            acknowledgedRevision: 11,
            visibleGeneration: 13,
            groupingMode: .repo,
            nativeGroupingMode: .repo,
            orderedTabIDs: [firstTabID, secondTabID],
            activeTabID: firstTabID,
            activePaneID: firstPaneID,
            activePaneIDByTabID: [firstTabID: firstPaneID, secondTabID: secondPaneID]
        )
        var tracker = SidebarPerformanceProofActionTracker()
        let startedAction = tracker.begin(
            sequence: 1,
            baseline: baseline,
            expectedOutcome: .tabSelection(tabID: secondTabID, paneID: secondPaneID)
        )
        let action = try #require(startedAction)
        let switchedWithoutFocus = makeReadback(
            semanticGeneration: 7,
            acknowledgedRevision: 11,
            visibleGeneration: 13,
            groupingMode: .repo,
            nativeGroupingMode: .repo,
            orderedTabIDs: [firstTabID, secondTabID],
            activeTabID: secondTabID,
            activePaneID: secondPaneID,
            activePaneIDByTabID: [firstTabID: firstPaneID, secondTabID: secondPaneID],
            nativeActivePaneHasFocus: false
        )
        #expect(!SidebarPerformanceProofActionTracker.matches(switchedWithoutFocus, action: action))

        let settled = makeReadback(
            semanticGeneration: 7,
            acknowledgedRevision: 11,
            visibleGeneration: 13,
            groupingMode: .repo,
            nativeGroupingMode: .repo,
            orderedTabIDs: [firstTabID, secondTabID],
            activeTabID: secondTabID,
            activePaneID: secondPaneID,
            activePaneIDByTabID: [firstTabID: firstPaneID, secondTabID: secondPaneID]
        )
        #expect(SidebarPerformanceProofActionTracker.matches(settled, action: action))
    }

    @Test("shell accessibility readback resolves the selected grouping segment")
    func shellAccessibilityReadbackResolvesSelectedGroupingSegment() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        for groupingMode in RepoExplorerGroupingMode.allCases {
            let segment = SelectedSidebarGroupingAccessibilityButton(
                identifier: "repoSidebarGroupingSegment.\(groupingMode.rawValue)",
                label: groupingMode.title,
                isSelected: groupingMode == .pane
            )
            rootView.addSubview(segment)
        }
        let tableView = NSTableView(frame: NSRect(x: 0, y: 30, width: 300, height: 270))
        rootView.addSubview(tableView)

        #expect(
            SidebarPerformanceProofAccessibility.selectedRepoGroupingMode(in: rootView) == .pane
        )
        #expect(
            SidebarPerformanceProofAccessibility.firstDescendant(
                of: NSTableView.self,
                in: rootView
            ) === tableView
        )
    }

    @Test("strict CPU populations use fixed debug selectors and population-specific readback")
    func strictCPUPopulationsUseFixedDebugSelectorsAndOneCorrelatedAction() throws {
        let actionSource = try String(
            contentsOfFile: "Sources/AgentStudio/App/Boot/AgentStudioStartupDiagnosticAction.swift",
            encoding: .utf8
        )
        let sessionSource = try String(
            contentsOfFile: "Sources/AgentStudio/App/Boot/SidebarPerformanceProofSession.swift",
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
        #expect(sessionSource.contains("SidebarPerformanceProofExpectedOutcome"))
        #expect(sessionSource.contains("nativeSelectedGroupingMode"))
        #expect(sessionSource.contains("nativeSidebarGeometryIsVisible"))
        #expect(sessionSource.contains("nativeActivePaneHasFocus"))
        #expect(sessionSource.contains("actionTracker.advance("))
        #expect(sessionSource.contains("AppCommandDispatcher.shared.dispatch"))
        #expect(sessionSource.contains("SidebarPerformanceProofNativeInputDriver"))
        #expect(sessionSource.contains("performance.sidebar.proof_action.started"))
        #expect(sessionSource.contains("performance.sidebar.proof_action.settled"))
        #expect(sessionSource.contains("performance.sidebar.proof_action.failed"))
        let visibleReadback = try #require(
            sessionSource.range(of: "guard await waitForInitialVisibleReadback()")
        )
        let populationReady = try #require(
            sessionSource.range(of: "performance.sidebar.proof_population.ready")
        )
        #expect(visibleReadback.lowerBound < populationReady.lowerBound)
        #expect(
            sessionSource.contains(
                "SidebarPerformanceProofActionTracker.visibleSidebarIsSettled"
            )
        )
        let initialVisibleWaitStart = try #require(
            sessionSource.range(of: "private func waitForInitialVisibleReadback()")
        )
        let initialVisibleWaitEnd = try #require(
            sessionSource.range(
                of: "private func observeShellState()",
                range: initialVisibleWaitStart.upperBound..<sessionSource.endIndex
            )
        )
        let initialVisibleWait = sessionSource[
            initialVisibleWaitStart.lowerBound..<initialVisibleWaitEnd.lowerBound
        ]
        #expect(initialVisibleWait.contains("fixturePreparationTimeout"))
        #expect(!initialVisibleWait.contains("actionReadbackTimeout"))
        #expect(sessionSource.contains("await settleRepositoryFactDemandAdmission()"))
        #expect(!sessionSource.contains("socket"))
        #expect(!sessionSource.contains("FIFO"))
        #expect(!sessionSource.contains("NotificationCenter"))
        #expect(!sessionSource.contains("AppEventBus"))
        #expect(!sessionSource.contains("AppCommandIPC"))
    }

    @Test("sidebar performance search driver separates native typing from native clear")
    func sidebarPerformanceSearchDriverUsesNativeKeyEventsAndPolicyCadence() throws {
        let source = try String(
            contentsOfFile:
                "Sources/AgentStudio/App/Boot/AppDelegate+SidebarPerformanceProofStartupDiagnostics.swift",
            encoding: .utf8
        )
        #expect(source.contains("func typeFixtureQuery(in window: NSWindow) async -> Bool"))
        #expect(source.contains("func clearFixtureQuery(in window: NSWindow) -> Bool"))
        #expect(source.contains("NSEvent.keyEvent("))
        #expect(source.contains("window.sendEvent(event)"))
        #expect(source.contains("searchCharacterInterval"))
        #expect(source.contains("modifiers: [.command]"))
        #expect(source.contains("keyCode: 51"))
        #expect(!source.contains("setFilterText"))
        #expect(!source.contains("filterText ="))
        #expect(!source.contains("uiState."))
        #expect(!source.contains("AppCommandIPC"))
    }

    @Test("strict fixture is sourced from one complete two-root watched-folder refresh")
    func strictFixtureUsesOneCompleteTwoRootWatchedFolderRefresh() throws {
        let fixtureSource = try String(
            contentsOfFile: "Sources/AgentStudio/App/Boot/SidebarPerformanceProofFixture+RealSize.swift",
            encoding: .utf8
        )
        let diagnosticSource = try String(
            contentsOfFile:
                "Sources/AgentStudio/App/Boot/AppDelegate+SidebarPerformanceProofStartupDiagnostics.swift",
            encoding: .utf8
        )
        let combinedSource = fixtureSource + diagnosticSource

        let requiredRoots = try #require(
            combinedSource.range(of: "strictWatchedRootURLs")
        )
        let addWatchedPath = try #require(
            combinedSource.range(of: "mutationCoordinator.addWatchedPath")
        )
        let refreshWatchedFolders = try #require(
            diagnosticSource.range(of: "commands.refreshWatchedFolders")
        )
        let completedSummary = try #require(
            diagnosticSource.range(of: "WatchedFolderRefreshSummary")
        )
        #expect(requiredRoots.lowerBound < addWatchedPath.lowerBound)
        #expect(completedSummary.lowerBound < refreshWatchedFolders.lowerBound)
        #expect(combinedSource.contains("summary.repoPaths(in: rootURL).isEmpty"))
        #expect(!diagnosticSource.contains("populateRealSizeTopology"))
    }

    @Test("strict pane fixture registers native view slots before layout publication")
    func strictPaneFixtureRegistersNativeViewSlots() throws {
        let fixtureSource = try String(
            contentsOfFile: "Sources/AgentStudio/App/Boot/SidebarPerformanceProofFixture+RealSize.swift",
            encoding: .utf8
        )
        let diagnosticSource = try String(
            contentsOfFile:
                "Sources/AgentStudio/App/Boot/AppDelegate+SidebarPerformanceProofStartupDiagnostics.swift",
            encoding: .utf8
        )

        #expect(fixtureSource.contains("static func populateStrictPaneFleet("))
        #expect(fixtureSource.contains("viewRegistry: ViewRegistry"))
        #expect(fixtureSource.contains("viewRegistry.ensureSlot(for: pane.id)"))
        #expect(diagnosticSource.contains("SidebarPerformanceProofFixture.populateStrictPaneFleet("))
        #expect(diagnosticSource.contains("viewRegistry: viewRegistry"))
    }

    @Test("strict policy is projected before scan and fixture readiness is separate")
    func strictPolicyPrecedesScanAndFixtureReadinessIsSeparate() throws {
        let source = try String(
            contentsOfFile:
                "Sources/AgentStudio/App/Boot/AppDelegate+SidebarPerformanceProofStartupDiagnostics.swift",
            encoding: .utf8
        )
        let sessionSource = try String(
            contentsOfFile: "Sources/AgentStudio/App/Boot/SidebarPerformanceProofSession.swift",
            encoding: .utf8
        )

        let policyProjection = try #require(
            source.range(of: "app.startup_diagnostic.sidebar_proof.policy_projected")
        )
        let fixturePreparation = try #require(
            source.range(of: "await prepareStrictSidebarPerformanceProofFixture")
        )
        let fixtureReady = try #require(
            source.range(of: "app.startup_diagnostic.sidebar_proof.fixture_ready")
        )

        #expect(policyProjection.lowerBound < fixturePreparation.lowerBound)
        #expect(fixturePreparation.lowerBound < fixtureReady.lowerBound)
        #expect(source.contains("await commands.refreshWatchedFolders"))
        for attribute in [
            "open_source_root_present", "project_dev_root_present",
            "discovered_repository_count", "discovered_worktree_count",
            "topology_fingerprint", "tab_count", "pane_model_count",
            "expected_session_variant",
        ] {
            #expect(source.contains("agentstudio.startup_diagnostic.sidebar_proof.\(attribute)"))
        }
        for policyAttribute in [
            "git_status_physical_limit", "remote_reference_physical_limit",
            "forge_physical_limit", "git_maximum_settlement_ms",
        ] {
            #expect(source.contains("agentstudio.startup_diagnostic.sidebar_proof.\(policyAttribute)"))
        }
        for attribute in [
            "terminal_input_baseline", "terminal_output_baseline",
            "ordered_command_baseline",
        ] {
            #expect(sessionSource.contains("agentstudio.performance.sidebar.proof.\(attribute)"))
        }
    }

    private func makeReadback(
        semanticGeneration: Int,
        acknowledgedRevision: UInt64,
        visibleGeneration: UInt64,
        groupingMode: RepoExplorerGroupingMode,
        nativeGroupingMode: RepoExplorerGroupingMode?,
        query: String = "",
        isDemanded: Bool = true,
        presentationIsReady: Bool = true,
        accessibilityDisposition: RepoExplorerPerformanceProofReadback.AccessibilityDisposition = .ready,
        focusDisposition: RepoExplorerPerformanceProofReadback.FocusDisposition = .notFocused,
        sidebarIsCollapsed: Bool = false,
        nativeSidebarGeometryIsVisible: Bool = true,
        nativeFilterValue: String? = nil,
        nativeSidebarAccessibilityIsReady: Bool = true,
        nativePresentedRowCount: Int? = 24,
        orderedTabIDs: [UUID] = [],
        activeTabID: UUID? = nil,
        activePaneID: UUID? = nil,
        activePaneIDByTabID: [UUID: UUID] = [:],
        nativeActivePaneHasFocus: Bool = true
    ) -> SidebarPerformanceProofReadback {
        SidebarPerformanceProofReadback(
            repoExplorer: RepoExplorerPerformanceProofReadback(
                semanticGeneration: semanticGeneration,
                acknowledgedRevision: acknowledgedRevision,
                visibleGeneration: visibleGeneration,
                representedRowCount: 24,
                groupingMode: groupingMode,
                query: query,
                isDemanded: isDemanded,
                presentationIsReady: presentationIsReady,
                focusDisposition: focusDisposition,
                accessibilityDisposition: accessibilityDisposition
            ),
            shell: SidebarPerformanceProofShellReadback(
                semanticSidebarIsCollapsed: sidebarIsCollapsed,
                nativeSidebarIsCollapsed: sidebarIsCollapsed,
                nativeSidebarGeometryIsVisible: nativeSidebarGeometryIsVisible,
                nativeFilterValue: nativeFilterValue,
                nativeSelectedGroupingMode: nativeGroupingMode,
                nativeSidebarAccessibilityIsReady: nativeSidebarAccessibilityIsReady,
                nativePresentedRowCount: nativePresentedRowCount,
                tab: SidebarPerformanceProofTabReadback(
                    orderedTabIDs: orderedTabIDs,
                    activeTabID: activeTabID,
                    activePaneID: activePaneID,
                    activePaneIDByTabID: activePaneIDByTabID,
                    nativeActiveTabIsVisible: true,
                    nativeActivePaneIsVisible: true,
                    nativeActivePaneHasFocus: nativeActivePaneHasFocus
                )
            )
        )
    }
}

@MainActor
private final class SelectedSidebarGroupingAccessibilityButton: NSButton {
    private let fixedAccessibilityIdentifier: String
    private let fixedAccessibilityLabel: String
    private let fixedIsSelected: Bool

    init(identifier: String, label: String, isSelected: Bool) {
        fixedAccessibilityIdentifier = identifier
        fixedAccessibilityLabel = label
        fixedIsSelected = isSelected
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func accessibilityIdentifier() -> String {
        fixedAccessibilityIdentifier
    }

    override func accessibilityLabel() -> String? {
        fixedAccessibilityLabel
    }

    override func isAccessibilitySelected() -> Bool {
        fixedIsSelected
    }
}
