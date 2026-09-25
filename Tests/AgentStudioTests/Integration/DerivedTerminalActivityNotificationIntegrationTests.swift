import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInboxNotification
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite("Derived terminal activity notification integration", .serialized)
struct DerivedActivityNotificationIntegrationTests {
    private struct Fixture {
        let bus: EventBus<RuntimeEnvelope>
        let inboxAtom: InboxNotificationAtom
        let paneAtom: WorkspacePaneAtom
        let tabLayout: WorkspaceTabLayoutAtom
        let windowLifecycle: WindowLifecycleAtom
        let attendedPane: AttendedPaneDerived
        let tracker: PaneFocusTracker
        let terminalActivity: TerminalActivityAtom
        let inboxRouter: InboxNotificationRouter
        let terminalRouter: TerminalActivityRouter
        let clock: TestPushClock

        @MainActor
        func shutdown() async {
            await terminalRouter.stop()
            await inboxRouter.stop()
            await tracker.stop()
        }
    }

    @MainActor
    private final class TerminalRouterBox {
        var router: TerminalActivityRouter?

        func observeActivity(for paneId: UUID) {
            guard let router else { return }
            _ = Task { @MainActor in
                await router.consumeTerminalActivityInput(
                    .orderedControl(
                        surfaceID: paneId,
                        paneID: paneId,
                        precedingAggregate: nil,
                        control: .observed
                    )
                )
            }
        }
    }

    @Test("focused pane output burst does not create a PaneInbox row")
    func focusedPaneOutputBurstDoesNotCreatePaneInboxRow() async {
        let fixture = await makeFixture()
        let paneId = PaneId.generateUUIDv7()
        _ = addTerminalPane(paneId, to: fixture)
        makeWindowKey(fixture.windowLifecycle)
        await waitForAttendedPane(
            paneId.uuid,
            in: fixture,
            description: "focused pane should be attended before output burst"
        )

        await postScrollbackBurst(paneId: paneId, to: fixture, settle: false)

        await assertEventuallyMain("focused pane burst should still update activity state") {
            fixture.terminalActivity.snapshot(for: paneId.uuid)?.outputBurst.thresholdReached == true
        }
        #expect(fixture.inboxAtom.notifications.isEmpty)

        await fixture.shutdown()
    }

    @Test("focused drawer child output burst does not create a PaneInbox row")
    func focusedDrawerChildOutputBurstDoesNotCreatePaneInboxRow() async throws {
        let fixture = await makeFixture()
        let parentPaneId = PaneId.generateUUIDv7()
        _ = addTerminalPane(parentPaneId, to: fixture)
        let drawerPane = try #require(
            addDrawerPane(to: parentPaneId.uuid, in: fixture)
        )
        makeWindowKey(fixture.windowLifecycle)
        await waitForTerminalRouterAttendance(
            paneId: drawerPane.id,
            in: fixture,
            description: "focused drawer child should be attended before output burst"
        )

        await postScrollbackBurst(paneId: PaneId(existingUUID: drawerPane.id), to: fixture, settle: false)

        await assertEventuallyMain("focused drawer child burst should still update activity state") {
            fixture.terminalActivity.snapshot(for: drawerPane.id)?.outputBurst.thresholdReached == true
        }
        #expect(fixture.inboxAtom.notifications.isEmpty)

        await fixture.shutdown()
    }

    @Test("visible split sibling pinned to bottom ignores small output")
    func visibleSplitSiblingPinnedToBottomIgnoresSmallOutput() async {
        let fixture = await makeFixture()
        let focusedPaneId = PaneId.generateUUIDv7()
        let visibleSiblingPaneId = PaneId.generateUUIDv7()
        _ = addTerminalPane(focusedPaneId, to: fixture)
        addVisiblePaneToActiveTab(visibleSiblingPaneId, to: fixture)
        makeWindowKey(fixture.windowLifecycle)

        await postScrollbackBurst(
            paneId: visibleSiblingPaneId,
            totals: [100, 101],
            pinnedToBottom: true,
            to: fixture
        )

        await assertEventuallyMain("bottom-pinned visible sibling small output should not create inbox noise") {
            fixture.terminalActivity.snapshot(for: visibleSiblingPaneId.uuid)?.outputBurst != nil
        }
        #expect(fixture.inboxAtom.notifications.isEmpty)
        #expect(fixture.inboxAtom.globalUnreadCount == 0)

        await fixture.shutdown()
    }

    @Test("bottom-pinned small output resets before visible sibling scrolls up")
    func bottomPinnedSmallOutputResetsBeforeVisibleSiblingScrollsUp() async throws {
        let fixture = await makeFixture()
        let focusedPaneId = PaneId.generateUUIDv7()
        let visibleSiblingPaneId = PaneId.generateUUIDv7()
        _ = addTerminalPane(focusedPaneId, to: fixture)
        addVisiblePaneToActiveTab(visibleSiblingPaneId, to: fixture)
        makeWindowKey(fixture.windowLifecycle)

        await postScrollbackBurst(
            paneId: visibleSiblingPaneId,
            totals: [100, 101],
            pinnedToBottom: true,
            to: fixture
        )
        await assertEventuallyMain("bottom-pinned small output should be classified before transition") {
            fixture.terminalActivity.snapshot(for: visibleSiblingPaneId.uuid)?.outputBurst != nil
        }
        #expect(fixture.inboxAtom.notifications.isEmpty)

        await postScrollbackBurst(
            paneId: visibleSiblingPaneId,
            totals: [102, 103],
            pinnedToBottom: false,
            to: fixture,
            startingSeq: 10
        )

        await assertEventuallyMain("scrolled-up output after bottom-pinned suppression should create unread activity") {
            fixture.inboxAtom.notifications.count == 1
                && fixture.inboxAtom.notifications[0].isRead == false
                && fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false
        }
        let notification = try #require(fixture.inboxAtom.notifications.first)
        #expect(notification.paneId == visibleSiblingPaneId.uuid)
        #expect(notification.kind == .unseenActivity)
        #expect(fixture.inboxAtom.globalUnreadCount == 1)

        await fixture.shutdown()
    }

}

extension DerivedActivityNotificationIntegrationTests {
    private func makeFixture() async -> Fixture {
        let bus = EventBus<RuntimeEnvelope>()
        let inboxAtom = InboxNotificationAtom()
        let prefsAtom = InboxNotificationPrefsAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayout = WorkspaceTabLayoutAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let attendedPane = AttendedPaneDerived(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer
        )
        let tracker = PaneFocusTracker(attendedPane: attendedPane)
        let terminalActivity = TerminalActivityAtom(
            outputBurstThreshold: AppPolicies.InboxNotification.terminalActivityOutputBurstThresholdRows
        )
        let clock = TestPushClock()
        let terminalRouterBox = TerminalRouterBox()
        let drawerView: @MainActor (UUID) -> DrawerView? = { parentPaneId in
            guard let drawer = paneAtom.pane(parentPaneId)?.drawer,
                let tabId = tabLayout.tabContaining(paneId: parentPaneId)?.id
            else {
                return nil
            }
            return tabLayout.arrangementAtom.arrangementState(tabId)?.arrangements
                .first { $0.id == tabLayout.tab(tabId)?.activeArrangementId }?
                .drawerViews[drawer.drawerId]
        }
        let inboxRouter = InboxNotificationRouter(
            bus: bus,
            inboxAtom: inboxAtom,
            prefsAtom: prefsAtom,
            paneAtom: paneAtom,
            tabLayout: tabLayout,
            attendedPane: attendedPane,
            focusTracker: tracker,
            terminalIsPinnedToBottom: { paneId in
                terminalActivity.snapshot(for: paneId)?.isPinnedToBottom == true
            },
            terminalPinnedStateSnapshot: {
                terminalActivity.snapshotsByPaneId.mapValues(\.isPinnedToBottom)
            },
            drawerView: drawerView,
            onPaneActivityObserved: { paneId in
                terminalRouterBox.observeActivity(for: paneId)
            }
        )
        let terminalRouter = TerminalActivityRouter(
            bus: bus,
            activityAtom: terminalActivity,
            attendedPane: attendedPane,
            surfaceIDForPaneID: { $0 },
            isPaneCurrentlyAttended: {
                PaneObservationResolver.isPaneCurrentlyAttended(
                    paneId: $0,
                    attendedPaneId: attendedPane.attendedPaneId,
                    pane: { paneAtom.pane($0) },
                    drawerView: drawerView
                )
            },
            unseenActivityDebounceDuration: AppPolicies.InboxNotification.terminalActivityQuietDebounceDuration,
            unseenActivityClock: clock
        )
        terminalRouterBox.router = terminalRouter
        await inboxRouter.start()
        await terminalRouter.start()
        return Fixture(
            bus: bus,
            inboxAtom: inboxAtom,
            paneAtom: paneAtom,
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            attendedPane: attendedPane,
            tracker: tracker,
            terminalActivity: terminalActivity,
            inboxRouter: inboxRouter,
            terminalRouter: terminalRouter,
            clock: clock
        )
    }

    private func addTerminalPane(
        _ paneId: PaneId,
        to fixture: Fixture
    ) -> UUID {
        let metadata = PaneMetadata(
            paneId: paneId,
            contentType: .terminal,
            launchDirectory: FileManager.default.homeDirectoryForCurrentUser,
            title: "Terminal"
        )
        let pane = Pane(
            id: paneId.uuid,
            content: .terminal(
                TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
            ),
            metadata: metadata
        )
        fixture.paneAtom.addPane(pane)

        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: pane.id)
        )
        let tab = Tab(
            name: "Tab",
            panes: [pane.id],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: pane.id
        )
        fixture.tabLayout.appendTab(tab)
        return tab.id
    }

    private func addDrawerPane(to parentPaneId: UUID, in fixture: Fixture) -> Pane? {
        guard
            let drawerPane = fixture.paneAtom.addDrawerPane(
                to: parentPaneId,
                parentFallbackCWD: nil,
                zmxSessionID: .generateUUIDv7()
            )
        else {
            return nil
        }
        guard let drawer = fixture.paneAtom.pane(parentPaneId)?.drawer,
            let tabId = fixture.tabLayout.tabContaining(paneId: parentPaneId)?.id
        else {
            return drawerPane
        }
        fixture.tabLayout.arrangementAtom.addDrawerPaneView(
            drawerId: drawer.drawerId,
            parentPaneId: parentPaneId,
            drawerPaneId: drawerPane.id,
            inTab: tabId
        )
        return drawerPane
    }

    private func drawerView(for parentPaneId: UUID, in fixture: Fixture) -> DrawerView? {
        guard let drawer = fixture.paneAtom.pane(parentPaneId)?.drawer,
            let tabId = fixture.tabLayout.tabContaining(paneId: parentPaneId)?.id
        else {
            return nil
        }
        return fixture.tabLayout.arrangementAtom.arrangementState(tabId)?.arrangements
            .first { $0.id == fixture.tabLayout.tab(tabId)?.activeArrangementId }?
            .drawerViews[drawer.drawerId]
    }

    private func addVisiblePaneToActiveTab(
        _ paneId: PaneId,
        to fixture: Fixture
    ) {
        let pane = Pane(
            id: paneId.uuid,
            content: .terminal(
                TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
            ),
            metadata: PaneMetadata(
                paneId: paneId,
                contentType: .terminal,
                launchDirectory: FileManager.default.homeDirectoryForCurrentUser,
                title: "Terminal"
            )
        )
        fixture.paneAtom.addPane(pane)
        guard let activeTab = fixture.tabLayout.activeTab, let activePaneId = activeTab.activePaneId else {
            Issue.record("Expected active tab and pane before adding visible sibling")
            return
        }
        #expect(
            fixture.tabLayout.insertPane(
                pane.id,
                inTab: activeTab.id,
                at: activePaneId,
                direction: .horizontal,
                position: .after,
                sizingMode: .proportional
            ) == true
        )
        fixture.tabLayout.setActivePane(activePaneId, inTab: activeTab.id)
    }

    private func makeWindowKey(_ atom: WindowLifecycleAtom) {
        let id = UUID()
        atom.recordWindowRegistered(id)
        atom.recordWindowBecameKey(id)
    }

    private func waitForAttendedPane(_ paneId: UUID, in fixture: Fixture, description: String) async {
        await assertEventuallyMain(description) {
            fixture.attendedPane.attendedPaneId == paneId
        }
    }

    private func waitForTerminalRouterAttendance(
        paneId: UUID,
        in fixture: Fixture,
        description: String
    ) async {
        await assertEventuallyMain(description) {
            PaneObservationResolver.isPaneCurrentlyAttended(
                paneId: paneId,
                attendedPaneId: fixture.attendedPane.attendedPaneId,
                pane: { fixture.paneAtom.pane($0) },
                drawerView: { drawerView(for: $0, in: fixture) }
            )
        }
    }

    private func postScrollbackBurst(
        paneId: PaneId,
        totals: [Int] = [100, 120, 140],
        pinnedToBottom: Bool = false,
        to fixture: Fixture,
        startingSeq: UInt64 = 1,
        settle: Bool = true
    ) async {
        guard let firstTotal = totals.first, let latestTotal = totals.last else { return }
        let firstState = scrollbarState(totalRows: firstTotal, pinnedToBottom: pinnedToBottom)
        let startedAtMilliseconds = Int64(startingSeq) * 100
        var aggregate = TerminalScrollbarActivityAggregate(
            state: firstState,
            observedAtMilliseconds: startedAtMilliseconds
        )
        for (index, totalRows) in totals.dropFirst().enumerated() {
            aggregate.merge(
                state: scrollbarState(totalRows: totalRows, pinnedToBottom: pinnedToBottom),
                observedAtMilliseconds: startedAtMilliseconds + Int64((index + 1) * 100)
            )
        }
        let initialSleepGeneration = fixture.clock.scheduledSleepGeneration
        await fixture.terminalRouter.consumeTerminalActivityInput(
            .aggregate(
                surfaceID: paneId.uuid,
                paneID: paneId.uuid,
                input: TerminalActivityAggregateInput(
                    aggregate: aggregate,
                    latestState: scrollbarState(totalRows: latestTotal, pinnedToBottom: pinnedToBottom),
                    context: TerminalActivityProjectionContext(
                        isAttended: PaneObservationResolver.isPaneCurrentlyAttended(
                            paneId: paneId.uuid,
                            attendedPaneId: fixture.attendedPane.attendedPaneId,
                            pane: { fixture.paneAtom.pane($0) },
                            drawerView: { drawerView(for: $0, in: fixture) }
                        ),
                        isAgentClassified: false,
                        outputBurstThreshold: fixture.terminalActivity.outputBurstThreshold
                    )
                )
            )
        )
        await assertEventuallyMain("terminal activity atom should observe latest rows") {
            fixture.terminalActivity.snapshot(for: paneId.uuid)?.scrollbarState?.total == latestTotal
        }
        guard settle else { return }
        await fixture.clock.waitForPendingSleepGeneration(initialSleepGeneration)
        fixture.clock.advance(by: AppPolicies.InboxNotification.terminalActivityQuietDebounceDuration)
    }

    private func scrollbarState(totalRows: Int, pinnedToBottom: Bool) -> ScrollbarState {
        let bottom = pinnedToBottom ? totalRows : 10
        let top = pinnedToBottom ? max(0, totalRows - 10) : 0
        return ScrollbarState(top: top, bottom: bottom, total: totalRows)
    }
}
