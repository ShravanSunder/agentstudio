import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct TerminalRestoreSchedulerTests {
    @Test
    func scheduler_restoresVisiblePanes_beforeEligibleHiddenPanes() {
        let activePane = PaneId()
        let hiddenPane = PaneId()
        let resolver = TestTerminalRestoreVisibilityResolver(
            mapping: [
                activePane: .p0Visible,
                hiddenPane: .p1Hidden,
            ],
            activePane: activePane
        )

        let ordered = TerminalRestoreScheduler.order(
            [hiddenPane, activePane],
            resolver: resolver
        )

        #expect(ordered == [activePane, hiddenPane])
    }

    @Test
    func scheduler_restoresVisibleDrawerPanes_asVisibleWork() {
        let activePane = PaneId()
        let visibleDrawerPane = PaneId()
        let resolver = TestTerminalRestoreVisibilityResolver(
            mapping: [
                activePane: .p0Visible,
                visibleDrawerPane: .p0Visible,
            ],
            activePane: activePane
        )

        let ordered = TerminalRestoreScheduler.order(
            [visibleDrawerPane, activePane],
            resolver: resolver
        )

        #expect(ordered == [activePane, visibleDrawerPane])
    }

    @Test
    func scheduler_restores_allExpandedDrawerPanes_asVisibleWork() {
        let activePane = PaneId()
        let firstVisibleDrawerPane = PaneId()
        let secondVisibleDrawerPane = PaneId()
        let hiddenPane = PaneId()
        let resolver = TestTerminalRestoreVisibilityResolver(
            mapping: [
                activePane: .p0Visible,
                firstVisibleDrawerPane: .p0Visible,
                secondVisibleDrawerPane: .p0Visible,
                hiddenPane: .p1Hidden,
            ],
            activePane: activePane
        )

        let ordered = TerminalRestoreScheduler.order(
            [hiddenPane, secondVisibleDrawerPane, firstVisibleDrawerPane, activePane],
            resolver: resolver
        )

        #expect(ordered == [activePane, secondVisibleDrawerPane, firstVisibleDrawerPane, hiddenPane])
    }

    @Test
    func scheduler_startsEligibleHiddenExistingSession_beforeReveal() {
        #expect(
            TerminalRestoreScheduler.shouldStartHiddenRestore(
                policy: .existingSessionsOnly,
                hasExistingSession: true
            )
        )
    }

    @Test
    func scheduler_skipsBackgroundPane_withoutExistingSession_underDefaultPolicy() {
        #expect(
            !TerminalRestoreScheduler.shouldStartHiddenRestore(
                policy: .existingSessionsOnly,
                hasExistingSession: false
            )
        )
    }

    @Test
    func scheduler_promotes_destinationPaneAndDrawers_onTabSwitch() {
        let destinationPane = PaneId()
        let destinationDrawerPane = PaneId()
        let hiddenPane = PaneId()
        let resolver = TestTerminalRestoreVisibilityResolver(
            mapping: [
                destinationPane: .p0Visible,
                destinationDrawerPane: .p0Visible,
                hiddenPane: .p1Hidden,
            ],
            activePane: destinationPane
        )

        let ordered = TerminalRestoreScheduler.order(
            [hiddenPane, destinationDrawerPane, destinationPane],
            resolver: resolver
        )

        #expect(ordered == [destinationPane, destinationDrawerPane, hiddenPane])
    }

    @Test
    func scheduler_preemptsPendingBackgroundWork_whenVisibleWorkArrives() {
        let hiddenPane = PaneId()
        let visiblePane = PaneId()
        let resolver = TestTerminalRestoreVisibilityResolver(
            mapping: [
                hiddenPane: .p1Hidden,
                visiblePane: .p0Visible,
            ],
            activePane: visiblePane
        )

        let ordered = TerminalRestoreScheduler.order(
            [hiddenPane, visiblePane],
            resolver: resolver
        )

        #expect(ordered.first == visiblePane)
    }
}

@MainActor
private final class TestTerminalRestoreVisibilityResolver: TerminalRestoreVisibilityResolving {
    private let mapping: [PaneId: VisibilityTier]
    private let activePane: PaneId

    init(mapping: [PaneId: VisibilityTier], activePane: PaneId) {
        self.mapping = mapping
        self.activePane = activePane
    }

    func tier(for paneId: PaneId) -> VisibilityTier {
        mapping[paneId] ?? .p1Hidden
    }

    func isActive(_ paneId: PaneId) -> Bool {
        paneId == activePane
    }
}
