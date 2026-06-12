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

    func makeFixture(
        traceRuntime: AgentStudioTraceRuntime? = nil,
        startRouter: Bool = true,
        onPaneActivityObserved: @escaping @MainActor (UUID) -> Void = { _ in }
    ) async -> Fixture {
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
            traceRuntime: traceRuntime,
            drawerView: { parentPaneId in
                guard let tab = tabLayout.tabContaining(paneId: parentPaneId),
                    let drawerId = paneAtom.pane(parentPaneId)?.drawer?.drawerId
                else { return nil }
                return tab.activeArrangement.drawerViews[drawerId]
            },
            onPaneActivityObserved: onPaneActivityObserved
        )
        if startRouter {
            await router.start()
        }

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

    @Test("startup clears existing observed bottom-pinned PaneInbox rows")
    func startupClearsExistingObservedBottomPinnedPaneInboxRows() async {
        let bus = EventBus<RuntimeEnvelope>()
        let inboxAtom = InboxNotificationAtom()
        let prefsAtom = InboxNotificationPrefsAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayout = WorkspaceTabLayoutAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let terminalActivity = TerminalActivityAtom()
        let paneId = PaneId()

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
        paneAtom.addPane(pane)
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: pane.id)
        )
        tabLayout.appendTab(
            Tab(
                name: "Tab",
                panes: [pane.id],
                arrangements: [arrangement],
                activeArrangementId: arrangement.id,
                activePaneId: pane.id
            )
        )
        makeWindowKey(windowLifecycle)
        terminalActivity.consume(
            paneEnvelope(
                paneId: paneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100)))
            )
        )
        inboxAtom.append(makeNotification(kind: .agentDesktopNotification, paneId: paneId.uuid))
        let attendedPane = AttendedPaneAtom(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer
        )
        #expect(attendedPane.attendedPaneId == paneId.uuid)
        #expect(inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 1)
        let tracker = PaneFocusTracker(attendedPane: attendedPane)
        let router = InboxNotificationRouter(
            bus: bus,
            inboxAtom: inboxAtom,
            prefsAtom: prefsAtom,
            paneAtom: paneAtom,
            tabLayout: tabLayout,
            attendedPane: attendedPane,
            focusTracker: tracker,
            terminalActivity: terminalActivity
        )

        await router.start()

        await assertEventuallyMain("router startup should clear already-observed pane inbox rows") {
            inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 0
        }
        #expect(inboxAtom.notifications[0].isRead == true)
        #expect(inboxAtom.notifications[0].isDismissedFromPaneInbox == true)
        await router.stop()
        await tracker.stop()
        attendedPane.stop()
    }

    @Test("reading upgraded activity notification invalidates source activity window")
    func readingUpgradedActivityNotificationInvalidatesSourceActivityWindow() async {
        var observedPaneIds: [UUID] = []
        let fixture = await makeFixture(onPaneActivityObserved: { paneId in
            observedPaneIds.append(paneId)
        })
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        let sessionId = UUID()
        fixture.inboxAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: 100),
                kind: .agentRpc,
                title: "Claude is waiting for input",
                body: nil,
                source: .pane(.init(paneId: paneId.uuid)),
                activityContext: .init(
                    burstWindowId: UUID(),
                    activitySessionId: sessionId,
                    eventCount: 3,
                    rowsAdded: 80,
                    thresholdRows: 30,
                    latestRows: 180
                ),
                claimKey: .init(
                    paneId: paneId.uuid,
                    lane: .actionNeeded,
                    semantic: .approvalRequested,
                    sessionId: sessionId
                ),
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )

        #expect(fixture.inboxAtom.markRead(id: fixture.inboxAtom.notifications[0].id))
        #expect(fixture.inboxAtom.dismissFromPaneInbox(id: fixture.inboxAtom.notifications[0].id))

        await assertEventuallyMain("upgraded activity row observation should invalidate terminal activity") {
            observedPaneIds.contains(paneId.uuid)
        }
        await stop(fixture)
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

    @Test("active tab visible unattended pane at bottom keeps auto-clearable PaneInbox badge")
    func activeTabVisibleUnattendedPaneAtBottomKeepsAutoClearablePaneInboxBadge() async {
        let fixture = await makeFixture()
        let attendedPaneId = PaneId()
        let visibleSiblingPaneId = PaneId()
        let tabId = addTerminalPane(attendedPaneId, to: fixture)
        addVisiblePaneToActiveTab(visibleSiblingPaneId, to: fixture)
        fixture.tabLayout.setActivePane(attendedPaneId.uuid, inTab: tabId)
        fixture.inboxAtom.append(makeNotification(kind: .agentDesktopNotification, paneId: visibleSiblingPaneId.uuid))
        fixture.terminalActivity.consume(
            paneEnvelope(
                paneId: visibleSiblingPaneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100)))
            )
        )

        makeWindowKey(fixture.windowLifecycle)

        await Task.yield()

        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [visibleSiblingPaneId.uuid]) == 1)
        #expect(fixture.inboxAtom.notifications[0].isRead == false)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false)
        await stop(fixture)
    }

    @Test("active tab visible unattended pane at bottom appends auto-clearable event unread")
    func activeTabVisibleUnattendedPaneAtBottomAppendsAutoClearableEventUnread() async {
        let fixture = await makeFixture()
        let attendedPaneId = PaneId()
        let visibleSiblingPaneId = PaneId()
        let tabId = addTerminalPane(attendedPaneId, to: fixture)
        addVisiblePaneToActiveTab(visibleSiblingPaneId, to: fixture)
        fixture.tabLayout.setActivePane(attendedPaneId.uuid, inTab: tabId)
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

        await assertEventuallyMain("visible active-tab event should append unread notification") {
            fixture.inboxAtom.notifications.count == 1
        }
        #expect(fixture.inboxAtom.notifications[0].isRead == false)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false)
        #expect(fixture.inboxAtom.globalUnreadCount == 1)
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [visibleSiblingPaneId.uuid]) == 1)
        await stop(fixture)
    }

    @Test("bus scrollbar state does not clear immediately following visible unattended pane notification")
    func busScrollbarStateDoesNotClearImmediatelyFollowingVisibleUnattendedPaneNotification() async {
        let fixture = await makeFixture()
        let attendedPaneId = PaneId()
        let visibleSiblingPaneId = PaneId()
        let tabId = addTerminalPane(attendedPaneId, to: fixture)
        addVisiblePaneToActiveTab(visibleSiblingPaneId, to: fixture)
        fixture.tabLayout.setActivePane(attendedPaneId.uuid, inTab: tabId)
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

        await assertEventuallyMain("same-stream pinned state should still append unread notification") {
            fixture.inboxAtom.notifications.count == 1
        }
        #expect(fixture.inboxAtom.notifications[0].isRead == false)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false)
        #expect(fixture.inboxAtom.globalUnreadCount == 1)
        await stop(fixture)
    }

    @Test("switching to active tab keeps visible bottom-pinned unattended sibling pane unread")
    func switchingToActiveTabKeepsVisibleBottomPinnedUnattendedSiblingPaneUnread() async {
        let fixture = await makeFixture()
        let firstTabPaneId = PaneId()
        let secondTabFocusedPaneId = PaneId()
        let secondTabVisibleSiblingPaneId = PaneId()
        let firstTabId = addTerminalPane(firstTabPaneId, to: fixture)
        makeWindowKey(fixture.windowLifecycle)
        let secondTabId = addTerminalPane(secondTabFocusedPaneId, to: fixture)
        addVisiblePaneToActiveTab(secondTabVisibleSiblingPaneId, to: fixture)
        fixture.tabLayout.setActivePane(secondTabFocusedPaneId.uuid, inTab: secondTabId)
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

        await Task.yield()

        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [secondTabVisibleSiblingPaneId.uuid]) == 1)
        #expect(fixture.inboxAtom.notifications[0].isRead == false)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false)
        await stop(fixture)
    }

    @Test("scrollbar does not retrace kept user-action-required rows")
    func scrollbarDoesNotRetraceKeptUserActionRequiredRows() async throws {
        let traceRuntime = makeTraceRuntime(name: "inbox-scrollbar-keep", processIdentifier: 412)
        let fixture = await makeFixture(traceRuntime: traceRuntime, startRouter: false)
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        makeWindowKey(fixture.windowLifecycle)
        await assertEventuallyMain("pane should be attended before creating user-action notification") {
            fixture.attendedPane.attendedPaneId == paneId.uuid
        }
        let outputFileURL = try #require(traceRuntime.outputFileURL)

        fixture.inboxAtom.append(
            makeNotification(kind: .terminalSecureInputRequested, paneId: paneId.uuid)
        )
        await fixture.router.start()
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
        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.secureInputChanged(false)),
                seq: 4
            )
        )
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 1)
        await stop(fixture)

        let afterScrollbarContents = try String(contentsOf: outputFileURL, encoding: .utf8)
        let observedClearCount = Self.countOccurrences(
            of: "\"body\":\"inbox.observedPaneCleared\"",
            in: afterScrollbarContents
        )
        #expect(observedClearCount >= 1)
        #expect(observedClearCount <= 2)
        #expect(afterScrollbarContents.contains("\"body\":\"inbox.focusGainedObservedPane\""))
    }

    @Test("observed pane does not auto-clear user-action-required rows")
    func observedPaneDoesNotAutoClearActionOrSecurityRows() async throws {
        let traceRuntime = makeTraceRuntime(name: "inbox-observed-keep", processIdentifier: 411)
        var observedPaneIds: [UUID] = []
        let fixture = await makeFixture(traceRuntime: traceRuntime) { paneId in
            observedPaneIds.append(paneId)
        }
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
        await assertEventuallyMain("focus path should observe the pane before trace drain") {
            observedPaneIds.contains(paneId.uuid)
        }
        await stop(fixture)

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        await assertEventuallyMain("kept observed pane row should explain why in trace") {
            (try? String(contentsOf: outputFileURL, encoding: .utf8))?
                .contains("\"body\":\"inbox.observedPaneCleared\"") == true
        }
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"agentstudio.pane_inbox.cleared_count\":0"))
        #expect(contents.contains("\"agentstudio.pane_inbox.keep_count\":1"))
        #expect(contents.contains("\"agentstudio.inbox.reason\":\"requires_user_action\""))
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

    @Test("opening drawer clears visible bottom-pinned drawer child PaneInbox badge")
    func openingDrawerClearsVisibleBottomPinnedDrawerChildPaneInboxBadge() async throws {
        let fixture = await makeFixture()
        let parentPaneId = PaneId()
        _ = addTerminalPane(parentPaneId, to: fixture)
        let drawerPane = try #require(
            fixture.paneAtom.addDrawerPane(to: parentPaneId.uuid, parentFallbackCWD: nil)
        )
        let parentDrawerId = try #require(fixture.paneAtom.pane(parentPaneId.uuid)?.drawer?.drawerId)
        let tabId = try #require(fixture.tabLayout.tabContaining(paneId: parentPaneId.uuid)?.id)
        fixture.tabLayout.arrangementAtom.addDrawerPaneView(
            drawerId: parentDrawerId,
            parentPaneId: parentPaneId.uuid,
            drawerPaneId: drawerPane.id,
            inTab: tabId
        )
        fixture.paneAtom.toggleDrawer(for: parentPaneId.uuid)
        makeWindowKey(fixture.windowLifecycle)
        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: PaneId(uuid: drawerPane.id),
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100)))
            )
        )
        fixture.inboxAtom.append(makeNotification(kind: .agentDesktopNotification, paneId: drawerPane.id))
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [drawerPane.id]) == 1)

        fixture.paneAtom.toggleDrawer(for: parentPaneId.uuid)

        await assertEventuallyMain("opening drawer should clear bottom-pinned child unread state") {
            fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [drawerPane.id]) == 0
        }
        #expect(fixture.inboxAtom.notifications[0].isRead == true)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == true)
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
        await assertEventuallyMain("overflow notification should be retained after dropping the oldest row") {
            fixture.inboxAtom.notifications.count == AppPolicies.InboxNotification.maxRetained
                && fixture.inboxAtom.notifications.contains { $0.title == "Overflow" }
        }
        await stop(fixture)

        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"inbox.retention.dropped\""))
        #expect(contents.contains("\"agentstudio.inbox.dropped_count\":1"))
        #expect(contents.contains("\"agentstudio.notification.dropped_ids\""))
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

    private static func countOccurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private func stop(_ fixture: Fixture) async {
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }
}
