import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer pane capture reference", .serialized)
struct RepoExplorerPaneCaptureReferenceTests {
    @Test("pane-only capture stamps a fresh wall and monotonic pair across midnight")
    func paneCaptureRefreshesBothReferenceHalves() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let pane = store.createPane(title: "Activity pane")
            store.appendTab(Tab(paneId: pane.id))
            atoms.workspaceSidebarState.setSidebarSurface(.panes)
            let dayStart = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
            let oldWall = dayStart.addingTimeInterval(9 * 60 * 60)
            let freshWall = dayStart.addingTimeInterval(25 * 60 * 60)
            let instant = ContinuousClock.now
            let activity = PaneActivityTime(
                orderingInstant: instant.advanced(by: .seconds(-7200)),
                wallTime: freshWall.addingTimeInterval(-7200),
                source: .terminal
            )
            atoms.paneActivityTime.apply([.set(pane.id, activity)])
            let capture = RepoExplorerProjectionInputCapture(
                store: store,
                preferences: RepoExplorerSidebarPrefsAtom(sidebarState: atoms.workspaceSidebarState),
                repoCache: atoms.repoCache,
                sidebarState: atoms.workspaceSidebarState,
                sidebarCache: atoms.sidebarCache,
                coreAtoms: atoms,
                bridgeAttendanceSnapshot: { _ in nil },
                latestPaneMessageSnapshot: { _ in nil },
                continuousNow: { instant },
                wallNow: { freshWall }
            )
            let prior = capture.captureRequest(query: "", referenceDate: oldWall, trigger: .dataRefresh)
            let scoped = try #require(
                capture.captureScoped(
                    .pane(pane.id), previous: prior, referenceDate: oldWall
                ))
            let referenceInstant = try #require(scoped.request.snapshot.referenceInstant)
            let bucket = RepoExplorerPaneActivityProjection.make(
                time: activity,
                referenceInstant: referenceInstant,
                wallNow: scoped.request.snapshot.referenceDate,
                calendar: scoped.request.snapshot.calendar
            ).unpinnedBucket

            #expect(scoped.request.snapshot.referenceDate == freshWall)
            #expect(referenceInstant == instant)
            #expect(bucket == .lastSevenDays)
        }
    }
}
