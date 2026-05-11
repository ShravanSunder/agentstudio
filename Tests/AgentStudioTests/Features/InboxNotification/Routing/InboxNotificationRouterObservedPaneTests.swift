import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationRouter observed-pane clearing", .serialized)
struct InboxNotificationRouterObservedPaneTests {
    struct Fixture {
        let bus: EventBus<RuntimeEnvelope>
        let inboxAtom: InboxNotificationAtom
        let prefsAtom: InboxNotificationPrefsAtom
        let paneAtom: WorkspacePaneAtom
        let tabLayout: WorkspaceTabLayoutAtom
        let windowLifecycle: WindowLifecycleAtom
        let managementLayer: ManagementLayerAtom
        let attendedPane: AttendedPaneAtom
        let terminalActivity: TerminalActivityAtom
        let tracker: PaneFocusTracker
        let router: InboxNotificationRouter
        let traceRuntime: AgentStudioTraceRuntime?
    }

    func makeFixture(traceRuntime: AgentStudioTraceRuntime? = nil) async -> Fixture {
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
        let terminalActivity = TerminalActivityAtom()
        let tracker = PaneFocusTracker(attendedPane: attendedPane)
        let router = InboxNotificationRouter(
            bus: bus,
            inboxAtom: inboxAtom,
            prefsAtom: prefsAtom,
            paneAtom: paneAtom,
            tabLayout: tabLayout,
            attendedPane: attendedPane,
            focusTracker: tracker,
            terminalActivity: terminalActivity,
            traceRuntime: traceRuntime
        )
        await router.start()

        return Fixture(
            bus: bus,
            inboxAtom: inboxAtom,
            prefsAtom: prefsAtom,
            paneAtom: paneAtom,
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer,
            attendedPane: attendedPane,
            terminalActivity: terminalActivity,
            tracker: tracker,
            router: router,
            traceRuntime: traceRuntime
        )
    }

    @Test("focused pane at bottom clears auto-clearable PaneInbox badge")
    func focusedPaneAtBottomClearsAutoClearablePaneInboxBadge() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        fixture.inboxAtom.append(makeNotification(kind: .agentDesktopNotification, paneId: paneId.uuid))
        fixture.terminalActivity.consume(
            paneEnvelope(
                paneId: paneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100)))
            )
        )

        makeWindowKey(fixture.windowLifecycle)

        await assertEventuallyMain("observed source pane should clear pane inbox unread state") {
            fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 0
        }
        #expect(fixture.inboxAtom.notifications[0].isRead == true)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == true)
        #expect(fixture.inboxAtom.globalUnreadCount == 0)
        await stop(fixture)
    }

    @Test("focused pane scrolled up keeps PaneInbox badge")
    func focusedPaneScrolledUpKeepsPaneInboxBadge() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        fixture.inboxAtom.append(makeNotification(kind: .agentDesktopNotification, paneId: paneId.uuid))
        fixture.terminalActivity.consume(
            paneEnvelope(
                paneId: paneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 40, bottom: 80, total: 100)))
            )
        )

        makeWindowKey(fixture.windowLifecycle)
        await Task.yield()

        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 1)
        await stop(fixture)
    }

    @Test("attended pane scrolling back to bottom clears auto-clearable PaneInbox badge")
    func attendedPaneScrollingBackToBottomClearsAutoClearablePaneInboxBadge() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        fixture.inboxAtom.append(makeNotification(kind: .agentDesktopNotification, paneId: paneId.uuid))
        makeWindowKey(fixture.windowLifecycle)

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 40, bottom: 80, total: 100)))
            )
        )
        await Task.yield()
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 1)

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100))),
                seq: 2
            )
        )

        await assertEventuallyMain("scrolling attended source pane to bottom should clear pane inbox badge") {
            fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 0
        }
        await stop(fixture)
    }

    @Test("unattended pane at bottom keeps PaneInbox badge")
    func unattendedPaneAtBottomKeepsPaneInboxBadge() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        fixture.inboxAtom.append(makeNotification(kind: .agentDesktopNotification, paneId: paneId.uuid))
        fixture.terminalActivity.consume(
            paneEnvelope(
                paneId: paneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100)))
            )
        )

        await Task.yield()

        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 1)
        await stop(fixture)
    }

    @Test("active tab visible pane at bottom clears auto-clearable PaneInbox badge")
    func activeTabVisiblePaneAtBottomClearsAutoClearablePaneInboxBadge() async {
        let fixture = await makeFixture()
        let attendedPaneId = PaneId()
        let visibleSiblingPaneId = PaneId()
        _ = addTerminalPane(attendedPaneId, to: fixture)
        addVisiblePaneToActiveTab(visibleSiblingPaneId, to: fixture)
        fixture.inboxAtom.append(makeNotification(kind: .agentDesktopNotification, paneId: visibleSiblingPaneId.uuid))
        fixture.terminalActivity.consume(
            paneEnvelope(
                paneId: visibleSiblingPaneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100)))
            )
        )

        makeWindowKey(fixture.windowLifecycle)

        await assertEventuallyMain("visible active-tab source pane should clear pane inbox unread state") {
            fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [visibleSiblingPaneId.uuid]) == 0
        }
        #expect(fixture.inboxAtom.notifications[0].isRead == true)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == true)
        await stop(fixture)
    }

    @Test("active tab visible pane at bottom appends auto-clearable event as read history")
    func activeTabVisiblePaneAtBottomAppendsAutoClearableEventAsReadHistory() async {
        let fixture = await makeFixture()
        let attendedPaneId = PaneId()
        let visibleSiblingPaneId = PaneId()
        _ = addTerminalPane(attendedPaneId, to: fixture)
        addVisiblePaneToActiveTab(visibleSiblingPaneId, to: fixture)
        makeWindowKey(fixture.windowLifecycle)
        fixture.terminalActivity.consume(
            paneEnvelope(
                paneId: visibleSiblingPaneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100)))
            )
        )

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: visibleSiblingPaneId,
                event: .agentNotificationRequested(title: "Visible done", body: nil)
            )
        )

        await assertEventuallyMain("visible active-tab event should append read history") {
            fixture.inboxAtom.notifications.count == 1
        }
        #expect(fixture.inboxAtom.notifications[0].isRead == true)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == true)
        #expect(fixture.inboxAtom.globalUnreadCount == 0)
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [visibleSiblingPaneId.uuid]) == 0)
        await stop(fixture)
    }

    @Test("bus scrollbar state clears immediately following visible-pane notification")
    func busScrollbarStateClearsImmediatelyFollowingVisiblePaneNotification() async {
        let fixture = await makeFixture()
        let attendedPaneId = PaneId()
        let visibleSiblingPaneId = PaneId()
        _ = addTerminalPane(attendedPaneId, to: fixture)
        addVisiblePaneToActiveTab(visibleSiblingPaneId, to: fixture)
        makeWindowKey(fixture.windowLifecycle)

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: visibleSiblingPaneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100)))
            )
        )
        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: visibleSiblingPaneId,
                event: .agentNotificationRequested(title: "Visible done", body: nil),
                seq: 2
            )
        )

        await assertEventuallyMain("same-stream pinned state should make event append as read history") {
            fixture.inboxAtom.notifications.count == 1
        }
        #expect(fixture.inboxAtom.notifications[0].isRead == true)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == true)
        #expect(fixture.inboxAtom.globalUnreadCount == 0)
        await stop(fixture)
    }

    @Test("switching to active tab clears visible bottom-pinned sibling pane unread")
    func switchingToActiveTabClearsVisibleBottomPinnedSiblingPaneUnread() async {
        let fixture = await makeFixture()
        let firstTabPaneId = PaneId()
        let secondTabFocusedPaneId = PaneId()
        let secondTabVisibleSiblingPaneId = PaneId()
        let firstTabId = addTerminalPane(firstTabPaneId, to: fixture)
        makeWindowKey(fixture.windowLifecycle)
        let secondTabId = addTerminalPane(secondTabFocusedPaneId, to: fixture)
        addVisiblePaneToActiveTab(secondTabVisibleSiblingPaneId, to: fixture)
        fixture.tabLayout.setActiveTab(firstTabId)
        fixture.inboxAtom.append(
            makeNotification(kind: .agentDesktopNotification, paneId: secondTabVisibleSiblingPaneId.uuid)
        )
        fixture.terminalActivity.consume(
            paneEnvelope(
                paneId: secondTabVisibleSiblingPaneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100)))
            )
        )
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [secondTabVisibleSiblingPaneId.uuid]) == 1)

        fixture.tabLayout.setActiveTab(secondTabId)

        await assertEventuallyMain("switching to visible source tab should clear pane inbox unread state") {
            fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [secondTabVisibleSiblingPaneId.uuid]) == 0
        }
        await stop(fixture)
    }

    @Test("scrollbar does not retrace kept user-action-required rows")
    func scrollbarDoesNotRetraceKeptUserActionRequiredRows() async throws {
        let traceRuntime = makeTraceRuntime(name: "inbox-scrollbar-keep", processIdentifier: 412)
        let fixture = await makeFixture(traceRuntime: traceRuntime)
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        makeWindowKey(fixture.windowLifecycle)

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.secureInputChanged(true))
            )
        )
        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100))),
                seq: 2
            )
        )
        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 81, bottom: 101, total: 101))),
                seq: 3
            )
        )

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        await assertEventuallyMain("secure input notification should be traced") {
            (try? String(contentsOf: outputFileURL, encoding: .utf8))?
                .contains("\"body\":\"inbox.notification.appended\"") == true
        }
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"inbox.observedPaneCleared\"") == false)
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 1)
        await stop(fixture)
    }

    @Test("observed pane does not auto-clear user-action-required rows")
    func observedPaneDoesNotAutoClearActionOrSecurityRows() async throws {
        let traceRuntime = makeTraceRuntime(name: "inbox-observed-keep", processIdentifier: 411)
        let fixture = await makeFixture(traceRuntime: traceRuntime)
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        fixture.inboxAtom.append(makeNotification(kind: .securityEvent, paneId: paneId.uuid))
        fixture.terminalActivity.consume(
            paneEnvelope(
                paneId: paneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100)))
            )
        )

        makeWindowKey(fixture.windowLifecycle)
        await Task.yield()

        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 1)
        #expect(fixture.inboxAtom.globalUnreadCount == 1)
        let outputFileURL = try #require(traceRuntime.outputFileURL)
        await assertEventuallyMain("kept observed pane row should explain why in trace") {
            (try? String(contentsOf: outputFileURL, encoding: .utf8))?
                .contains("\"body\":\"inbox.observedPaneCleared\"") == true
        }
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"agentstudio.pane_inbox.cleared_count\":0"))
        #expect(contents.contains("\"agentstudio.pane_inbox.keep_count\":1"))
        #expect(contents.contains("\"agentstudio.inbox.reason\":\"requires_user_action\""))
        await stop(fixture)
    }

    @Test("observed secure input still creates unread notification")
    func observedSecureInputStillCreatesUnreadNotification() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        makeWindowKey(fixture.windowLifecycle)
        fixture.terminalActivity.consume(
            paneEnvelope(
                paneId: paneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100)))
            )
        )

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.secureInputChanged(true))
            )
        )

        await assertEventuallyMain("observed secure input should still notify") {
            fixture.inboxAtom.notifications.count == 1
        }
        #expect(fixture.inboxAtom.notifications[0].kind == .terminalSecureInputRequested)
        #expect(fixture.inboxAtom.notifications[0].isRead == false)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false)
        #expect(fixture.inboxAtom.globalUnreadCount == 1)
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 1)
        await stop(fixture)
    }

    @Test("parent focus does not clear drawer child PaneInbox badge")
    func parentFocusDoesNotClearDrawerChildPaneInboxBadge() async throws {
        let fixture = await makeFixture()
        let parentPaneId = PaneId()
        _ = addTerminalPane(parentPaneId, to: fixture)
        let drawerPane = try #require(
            fixture.paneAtom.addDrawerPane(to: parentPaneId.uuid, parentFallbackCWD: nil)
        )
        fixture.inboxAtom.append(makeNotification(kind: .agentRpc, paneId: drawerPane.id))
        fixture.terminalActivity.consume(
            paneEnvelope(
                paneId: parentPaneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100)))
            )
        )

        makeWindowKey(fixture.windowLifecycle)
        await Task.yield()

        #expect(
            fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [parentPaneId.uuid, drawerPane.id]) == 1
        )
        await stop(fixture)
    }

    @Test("observed auto-clearable event appends read dismissed history row")
    func observedAutoClearableEventAppendsReadDismissedHistoryRow() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        makeWindowKey(fixture.windowLifecycle)
        fixture.terminalActivity.consume(
            paneEnvelope(
                paneId: paneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100)))
            )
        )

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .agentNotificationRequested(title: "Done", body: "ready")
            )
        )

        await assertEventuallyMain("observed auto-clearable event should append history") {
            fixture.inboxAtom.notifications.count == 1
        }
        #expect(fixture.inboxAtom.notifications[0].kind == .agentRpc)
        #expect(fixture.inboxAtom.notifications[0].isRead == true)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == true)
        #expect(fixture.inboxAtom.globalUnreadCount == 0)
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 0)
        await stop(fixture)
    }

    @Test("retention drop is emitted to JSONL trace")
    func retentionDropIsEmittedToJSONLTrace() async throws {
        let traceRuntime = makeTraceRuntime(name: "inbox-retention-drop", processIdentifier: 410)
        let fixture = await makeFixture(traceRuntime: traceRuntime)
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        let base = Date(timeIntervalSince1970: 1000)
        for index in 0..<AppPolicies.InboxNotification.maxRetained {
            fixture.inboxAtom.append(
                makeNotification(
                    kind: .agentRpc,
                    paneId: paneId.uuid,
                    timestamp: base.addingTimeInterval(TimeInterval(index))
                )
            )
        }

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .agentNotificationRequested(title: "Overflow", body: nil)
            )
        )

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        await assertEventuallyMain("retention drop should be traced") {
            (try? String(contentsOf: outputFileURL, encoding: .utf8))?
                .contains("\"body\":\"inbox.retention.dropped\"") == true
        }
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"agentstudio.inbox.dropped_count\":1"))
        #expect(contents.contains("\"agentstudio.notification.dropped_ids\""))
        await stop(fixture)
    }

    @Test("command finished duration uses Ghostty nanoseconds")
    func commandFinishedDurationUsesGhosttyNanoseconds() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.commandFinished(exitCode: 0, duration: 18_000_000_000))
            )
        )

        await assertEventuallyMain("nanosecond duration should notify") {
            fixture.inboxAtom.notifications.count == 1
        }
        #expect(fixture.inboxAtom.notifications[0].title == "Command finished")
        #expect(fixture.inboxAtom.notifications[0].body == "exit 0 · 18s")
        await stop(fixture)
    }

    @Test("command finished title branches on exit code")
    func commandFinishedTitleBranchesOnExitCode() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.commandFinished(exitCode: 1, duration: 18_000_000_000))
            )
        )

        await assertEventuallyMain("failed command should notify") {
            fixture.inboxAtom.notifications.count == 1
        }
        #expect(fixture.inboxAtom.notifications[0].title == "Command failed")
        #expect(fixture.inboxAtom.notifications[0].body == "exit 1 · 18s")
        await stop(fixture)
    }

    @Test("command finished duration renders minute boundary")
    func commandFinishedDurationRendersMinuteBoundary() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.commandFinished(exitCode: 0, duration: 60_000_000_000))
            )
        )

        await assertEventuallyMain("minute boundary should notify") {
            fixture.inboxAtom.notifications.count == 1
        }
        #expect(fixture.inboxAtom.notifications[0].body == "exit 0 · 1m 0s")
        await stop(fixture)
    }

    private func makeWindowKey(_ atom: WindowLifecycleAtom) {
        let id = UUID()
        atom.recordWindowRegistered(id)
        atom.recordWindowBecameKey(id)
    }

    private func addTerminalPane(
        _ paneId: PaneId,
        to fixture: Fixture
    ) -> UUID {
        let metadata = PaneMetadata(
            paneId: paneId,
            contentType: .terminal,
            source: .floating(launchDirectory: nil, title: nil),
            title: "Terminal"
        )
        let pane = Pane(
            id: paneId.uuid,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: metadata
        )
        fixture.paneAtom.addPane(pane)

        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: pane.id),
            visiblePaneIds: [pane.id]
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

    private func addVisiblePaneToActiveTab(
        _ paneId: PaneId,
        to fixture: Fixture
    ) {
        let pane = Pane(
            id: paneId.uuid,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                paneId: paneId,
                contentType: .terminal,
                source: .floating(launchDirectory: nil, title: nil),
                title: "Terminal"
            )
        )
        fixture.paneAtom.addPane(pane)
        guard let activeTab = fixture.tabLayout.activeTab else {
            Issue.record("Expected an active tab before adding visible sibling pane")
            return
        }
        guard let targetPaneId = activeTab.activePaneId else {
            Issue.record("Expected an active pane before adding visible sibling pane")
            return
        }
        let inserted = fixture.tabLayout.insertPane(
            pane.id,
            inTab: activeTab.id,
            at: targetPaneId,
            direction: .horizontal,
            position: .after,
            sizingMode: .proportional
        )
        #expect(inserted == true)
    }

    private func runtimeEnvelope(
        paneId: PaneId,
        event: PaneRuntimeEvent,
        seq: UInt64 = 1
    ) -> RuntimeEnvelope {
        .pane(paneEnvelope(paneId: paneId, event: event, seq: seq))
    }

    private func paneEnvelope(
        paneId: PaneId,
        event: PaneRuntimeEvent,
        seq: UInt64 = 1
    ) -> PaneEnvelope {
        .test(event: event, paneId: paneId, paneKind: .terminal, seq: seq)
    }

    private func makeNotification(
        kind: InboxNotificationKind,
        paneId: UUID,
        timestamp: Date = Date(timeIntervalSince1970: 100)
    ) -> InboxNotification {
        InboxNotification(
            id: UUID(),
            timestamp: timestamp,
            kind: kind,
            title: "Notification",
            body: nil,
            source: .pane(.init(paneId: paneId)),
            isRead: false,
            isDismissedFromPaneInbox: false
        )
    }

    private func makeTraceRuntime(name: String, processIdentifier: Int32) -> AgentStudioTraceRuntime {
        AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_FLUSH": "immediate",
                "AGENTSTUDIO_TRACE_NAME": name,
                "AGENTSTUDIO_TRACE_TAGS": "inbox",
            ]),
            processIdentifier: processIdentifier,
            sessionID: "inbox-observed-pane-session",
            timeUnixNano: { 3333 }
        )
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-inbox-observed-pane-trace-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func stop(_ fixture: Fixture) async {
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }
}
