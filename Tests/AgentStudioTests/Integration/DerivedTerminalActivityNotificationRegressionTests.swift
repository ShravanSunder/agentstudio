import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Derived terminal activity notification regressions", .serialized)
struct DerivedTerminalActivityNotificationRegressionTests {
    private struct Fixture {
        let bus: EventBus<RuntimeEnvelope>
        let inboxAtom: InboxNotificationAtom
        let paneAtom: WorkspacePaneAtom
        let tabLayout: WorkspaceTabLayoutAtom
        let windowLifecycle: WindowLifecycleAtom
        let managementLayer: ManagementLayerAtom
        let attendedPane: AttendedPaneAtom
        let tracker: PaneFocusTracker
        let terminalActivity: TerminalActivityAtom
        let inboxRouter: InboxNotificationRouter
        let terminalRouter: TerminalActivityRouter
        let clock: TestPushClock
        let paneActivityObservationRecorder: PaneActivityObservationRecorder

        @MainActor
        func shutdown() async {
            await terminalRouter.stop()
            await inboxRouter.stop()
            await tracker.stop()
            attendedPane.stop()
        }
    }

    private final class TerminalRouterBox {
        var router: TerminalActivityRouter?
    }

    private final class PaneActivityObservationRecorder {
        private(set) var paneIds: [UUID] = []

        func record(_ paneId: UUID) {
            paneIds.append(paneId)
        }
    }

    @Test("focused pane explicit event clears existing unread activity claim")
    func focusedPaneExplicitEventClearsExistingUnreadActivityClaim() async throws {
        let fixture = await makeFixture()
        let hiddenPaneId = PaneId()
        let visiblePaneId = PaneId()
        let hiddenTabId = addTerminalPane(hiddenPaneId, to: fixture)
        _ = addTerminalPane(visiblePaneId, to: fixture)
        makeWindowKey(fixture.windowLifecycle)

        await postScrollbackBurst(paneId: hiddenPaneId, to: fixture)
        await assertEventuallyMain("hidden pane output should create one unread activity row") {
            fixture.inboxAtom.notifications.count == 1
                && fixture.inboxAtom.notifications[0].paneId == hiddenPaneId.uuid
                && fixture.inboxAtom.notifications[0].isRead == false
                && fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false
        }
        let originalNotification = try #require(fixture.inboxAtom.notifications.first)

        fixture.tabLayout.setActiveTab(hiddenTabId)
        await waitForAttendedPane(
            hiddenPaneId.uuid,
            in: fixture,
            description: "hidden pane should become focused before explicit event"
        )
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [hiddenPaneId.uuid]) == 1)

        _ = await fixture.bus.post(
            .pane(
                .test(
                    event: .agentNotificationRequested(title: "Claude needs input", body: "Approve the command"),
                    paneId: hiddenPaneId,
                    paneKind: .terminal,
                    seq: 20
                )
            )
        )

        await assertEventuallyMain("focused explicit event should clear the existing active claim") {
            fixture.inboxAtom.notifications.count == 1
                && fixture.inboxAtom.notifications[0].id == originalNotification.id
                && fixture.inboxAtom.notifications[0].isRead == true
                && fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == true
                && fixture.inboxAtom.globalUnreadCount == 0
        }
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [hiddenPaneId.uuid]) == 0)

        await fixture.shutdown()
    }

    @Test("new pane event does not rewrite existing unread activity claim")
    func newPaneEventDoesNotRewriteExistingUnreadActivityClaim() async throws {
        let fixture = await makeFixture()
        let hiddenPaneId = PaneId()
        let activePaneId = PaneId()
        _ = addTerminalPane(hiddenPaneId, to: fixture)
        _ = addTerminalPane(activePaneId, to: fixture)
        makeWindowKey(fixture.windowLifecycle)

        await postScrollbackBurst(paneId: hiddenPaneId, to: fixture)
        await assertEventuallyMain("hidden pane output should create one unread activity row") {
            fixture.inboxAtom.notifications.count == 1
        }
        let originalNotification = try #require(fixture.inboxAtom.notifications.first)
        let originalObservationCount = fixture.paneActivityObservationRecorder.paneIds.filter {
            $0 == hiddenPaneId.uuid
        }.count

        _ = await fixture.bus.post(
            .pane(
                .test(
                    event: .agentNotificationRequested(title: "Active pane event", body: "ready"),
                    paneId: activePaneId,
                    paneKind: .terminal,
                    seq: 20
                )
            )
        )

        await assertEventuallyMain("active pane event should append one additional history row") {
            fixture.inboxAtom.notifications.count == 2
        }
        let preservedNotification = try #require(
            fixture.inboxAtom.notifications.first { $0.id == originalNotification.id }
        )
        #expect(preservedNotification == originalNotification)
        #expect(
            fixture.paneActivityObservationRecorder.paneIds.filter {
                $0 == hiddenPaneId.uuid
            }.count == originalObservationCount
        )

        await fixture.shutdown()
    }

    private func makeFixture() async -> Fixture {
        let bus = EventBus<RuntimeEnvelope>()
        let inboxAtom = InboxNotificationAtom()
        let prefsAtom = InboxNotificationPrefsAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayout = WorkspaceTabLayoutAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let attendedPane = AttendedPaneAtom(
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
        let paneActivityObservationRecorder = PaneActivityObservationRecorder()
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
            terminalActivity: terminalActivity,
            drawerView: drawerView,
            onPaneActivityObserved: { paneId in
                paneActivityObservationRecorder.record(paneId)
                terminalRouterBox.router?.markUnseenActivityObserved(paneId: paneId)
            }
        )
        let terminalRouter = TerminalActivityRouter(
            bus: bus,
            activityAtom: terminalActivity,
            attendedPane: attendedPane,
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
            managementLayer: managementLayer,
            attendedPane: attendedPane,
            tracker: tracker,
            terminalActivity: terminalActivity,
            inboxRouter: inboxRouter,
            terminalRouter: terminalRouter,
            clock: clock,
            paneActivityObservationRecorder: paneActivityObservationRecorder
        )
    }

    @discardableResult
    private func addTerminalPane(
        _ paneId: PaneId,
        to fixture: Fixture
    ) -> UUID {
        let metadata = PaneMetadata(
            paneId: paneId,
            contentType: .terminal,
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

    private func makeWindowKey(_ atom: WindowLifecycleAtom) {
        let id = UUID()
        atom.recordWindowRegistered(id)
        atom.recordWindowBecameKey(id)
    }

    private func waitForAttendedPane(
        _ paneId: UUID,
        in fixture: Fixture,
        description: String
    ) async {
        await assertEventuallyMain(description) {
            fixture.attendedPane.attendedPaneId == paneId
        }
    }

    private func postScrollbackBurst(
        paneId: PaneId,
        totals: [Int] = [100, 120, 140],
        to fixture: Fixture,
        startingSeq: UInt64 = 1
    ) async {
        await waitForBusSubscriberCount(fixture.bus, atLeast: 2)
        let initialSleepGeneration = fixture.clock.scheduledSleepGeneration
        for (index, totalRows) in totals.enumerated() {
            _ = await fixture.bus.post(
                .pane(
                    .test(
                        event: .terminal(
                            .scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: totalRows))
                        ),
                        paneId: paneId,
                        paneKind: .terminal,
                        seq: startingSeq + UInt64(index)
                    )
                )
            )
            await assertEventuallyMain("terminal activity atom should observe latest rows") {
                fixture.terminalActivity.snapshot(for: paneId.uuid)?.scrollbarState?.total == totalRows
            }
            await fixture.clock.waitForPendingSleepGeneration(initialSleepGeneration + index)
        }
        await fixture.clock.waitForPendingSleepGeneration(initialSleepGeneration + totals.count - 1)
        fixture.clock.advance(by: AppPolicies.InboxNotification.terminalActivityQuietDebounceDuration)
    }
}
