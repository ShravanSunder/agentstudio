import Foundation
import Testing

@testable import AgentStudio

private struct TraceRecordFixture: Decodable {
    let body: String
    let attributes: [String: TraceAttributeFixture]
}

private enum TraceAttributeFixture: Decodable, Equatable {
    case int(Int)
    case string(String)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .other
        }
    }
}

@MainActor
@Suite("InboxNotificationRouter routing contract", .serialized)
struct InboxNotificationRouterTests {
    struct Fixture {
        let bus: EventBus<RuntimeEnvelope>
        let inboxAtom: InboxNotificationAtom
        let prefsAtom: InboxNotificationPrefsAtom
        let paneAtom: WorkspacePaneAtom
        let tabLayout: WorkspaceTabLayoutAtom
        let windowLifecycle: WindowLifecycleAtom
        let managementLayer: ManagementLayerAtom
        let attendedPane: AttendedPaneAtom
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
        let tracker = PaneFocusTracker(attendedPane: attendedPane)
        let router = InboxNotificationRouter(
            bus: bus,
            inboxAtom: inboxAtom,
            prefsAtom: prefsAtom,
            paneAtom: paneAtom,
            tabLayout: tabLayout,
            attendedPane: attendedPane,
            focusTracker: tracker,
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
            tracker: tracker,
            router: router,
            traceRuntime: traceRuntime
        )
    }

    func makeWindowKey(_ atom: WindowLifecycleAtom) {
        let id = UUID()
        atom.recordWindowRegistered(id)
        atom.recordWindowBecameKey(id)
    }

    func waitForAttendedPane(
        _ paneId: UUID,
        in fixture: Fixture,
        description: String = "focus gain should mark pane attended"
    ) async {
        await assertEventuallyMain(description) {
            fixture.attendedPane.attendedPaneId == paneId
        }
    }

    func addTerminalPane(
        _ paneId: PaneId,
        to fixture: Fixture,
        repoId: UUID? = nil,
        worktreeId: UUID? = nil
    ) -> UUID {
        let facets = PaneContextFacets(
            repoId: repoId,
            repoName: repoId.map { "Repo-\($0.uuidString.prefix(4))" },
            worktreeId: worktreeId,
            worktreeName: worktreeId.map { "Worktree-\($0.uuidString.prefix(4))" }
        )
        let metadata = PaneMetadata(
            paneId: paneId,
            contentType: .terminal,
            source: .floating(launchDirectory: nil, title: nil),
            title: "Terminal",
            facets: facets,
            checkoutRef: "main"
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

    func makePaneEnvelope(
        paneId: PaneId,
        event: PaneRuntimeEvent,
        seq: UInt64 = 1
    ) -> RuntimeEnvelope {
        .pane(
            .test(
                event: event,
                paneId: paneId,
                paneKind: .terminal,
                seq: seq
            )
        )
    }

    func waitForNotificationCount(
        _ count: Int,
        in fixture: Fixture,
        description: String
    ) async {
        await assertEventuallyMain(description) {
            fixture.inboxAtom.notifications.count == count
        }
    }

    private func makeTraceRuntime(
        name: String,
        processIdentifier: Int32,
        tags: String = "inbox"
    ) -> AgentStudioTraceRuntime {
        AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_FLUSH": "immediate",
                "AGENTSTUDIO_TRACE_NAME": name,
                "AGENTSTUDIO_TRACE_TAGS": tags,
            ]),
            processIdentifier: processIdentifier,
            sessionID: "inbox-session",
            timeUnixNano: { 1111 }
        )
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-inbox-router-trace-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func traceRecords(in fileURL: URL) throws -> [TraceRecordFixture] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return try contents.split(separator: "\n").map { line in
            try JSONDecoder().decode(TraceRecordFixture.self, from: Data(line.utf8))
        }
    }

    @Test("desktopNotificationRequested posts an inbox notification")
    func desktopNotificationRequested() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.desktopNotificationRequested(title: "Done", body: "exit 0"))
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "desktop notification should be routed"
        )

        #expect(fixture.inboxAtom.notifications.count == 1)
        #expect(fixture.inboxAtom.notifications[0].kind == .agentDesktopNotification)
        #expect(fixture.inboxAtom.notifications[0].title == "Done")
        #expect(fixture.inboxAtom.notifications[0].body == "exit 0")
        #expect(fixture.inboxAtom.notifications[0].paneId == paneId.uuid)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("missing pane context emits unresolved context trace and skips notification")
    func missingPaneContextEmitsUnresolvedContextTraceAndSkipsNotification() async throws {
        let traceRuntime = makeTraceRuntime(name: "inbox-context-unresolved", processIdentifier: 272)
        let fixture = await makeFixture(traceRuntime: traceRuntime)
        let paneId = PaneId()

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.desktopNotificationRequested(title: "Done", body: "exit 0"))
            )
        )
        let sentinelPaneId = PaneId()
        _ = addTerminalPane(sentinelPaneId, to: fixture)
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: sentinelPaneId,
                event: .agentNotificationRequested(title: "Sentinel", body: nil),
                seq: 2
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "sentinel event should prove missing-context event drained first"
        )

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()

        let records = try traceRecords(in: outputFileURL)
        let unresolvedRecord = try #require(records.first { $0.body == "inbox.context.unresolved" })
        #expect(unresolvedRecord.attributes["agentstudio.inbox.context.reason"] == .string("pane_not_found"))
        #expect(
            unresolvedRecord.attributes["agentstudio.runtime.event"]
                == .string("terminal.desktopNotificationRequested")
        )
        #expect(fixture.inboxAtom.notifications.map(\.title) == ["Sentinel"])
    }

    @Test("inbox tracing records notify decisions and suppression reasons")
    func inboxTracingRecordsNotifyDecisionsAndSuppressionReasons() async throws {
        let traceRuntime = makeTraceRuntime(name: "inbox-decisions", processIdentifier: 260)
        let fixture = await makeFixture(traceRuntime: traceRuntime)
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(makePaneEnvelope(paneId: paneId, event: .terminal(.bellRang)))
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.commandFinished(exitCode: 0, duration: 3_000_000_000)),
                seq: 2
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.desktopNotificationRequested(title: "Done", body: "exit 0")),
                seq: 3
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "desktop notification should be routed after suppressions"
        )

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        await assertEventuallyMain("inbox router should write decision and append traces") {
            (try? String(contentsOf: outputFileURL, encoding: .utf8))?
                .contains("\"body\":\"inbox.notification.appended\"") == true
        }

        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        let records = try traceRecords(in: outputFileURL)
        let classifyRecords = records.filter { $0.body == "inbox.classify" }
        #expect(classifyRecords.count == 3)
        let matchedRecord = try #require(
            classifyRecords.first {
                $0.attributes["agentstudio.inbox.reason"] == .string("matched")
            }
        )
        #expect(matchedRecord.attributes["agentstudio.inbox.decision"] == .string("notify"))
        #expect(matchedRecord.attributes["agentstudio.inbox.kind"] == .string("agentDesktopNotification"))
        #expect(
            matchedRecord.attributes["agentstudio.runtime.event"] == .string("terminal.desktopNotificationRequested"))
        #expect(matchedRecord.attributes["agentstudio.envelope.seq"] == .int(3))
        #expect(contents.contains("\"body\":\"inbox.classify\""))
        #expect(contents.contains("\"agentstudio.inbox.reason\":\"bell_disabled\""))
        #expect(contents.contains("\"agentstudio.inbox.reason\":\"below_duration_threshold\""))
        #expect(contents.contains("\"agentstudio.inbox.reason\":\"matched\""))
        #expect(contents.contains("\"agentstudio.inbox.kind\":\"agentDesktopNotification\""))
        #expect(contents.contains("\"agentstudio.inbox.global_unread_after\":1"))
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("inbox router records eventbus delivery summaries without scrollbar spam")
    func inboxRouterRecordsEventBusDeliverySummariesWithoutScrollbarSpam() async throws {
        let traceRuntime = makeTraceRuntime(
            name: "inbox-eventbus-delivery",
            processIdentifier: 263,
            tags: "eventbus"
        )
        let fixture = await makeFixture(traceRuntime: traceRuntime)
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(makePaneEnvelope(paneId: paneId, event: .terminal(.bellRang)))
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: 100))),
                seq: 2
            )
        )

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        await assertEventuallyMain("inbox router should write eventbus delivery summary") {
            (try? String(contentsOf: outputFileURL, encoding: .utf8))?
                .contains("\"body\":\"eventbus.deliver\"") == true
        }

        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        let records = try traceRecords(in: outputFileURL)
        let deliveryRecords = records.filter { $0.body == "eventbus.deliver" }
        #expect(deliveryRecords.count == 1)
        let deliveryAttributes = try #require(deliveryRecords.first?.attributes)
        #expect(deliveryAttributes["agentstudio.eventbus.consumer"] == .string("InboxNotificationRouter"))
        #expect(deliveryAttributes["agentstudio.eventbus.name"] == .string("paneRuntime"))
        #expect(deliveryAttributes["agentstudio.eventbus.delivery"] == .string("consumed"))
        #expect(deliveryAttributes["agentstudio.inbox.decision"] == .string("ignore"))
        #expect(deliveryAttributes["agentstudio.inbox.reason"] == .string("bell_disabled"))
        #expect(deliveryAttributes["agentstudio.runtime.event"] == .string("terminal.bellRang"))
        #expect(deliveryAttributes["agentstudio.envelope.seq"] == .int(1))
        #expect(contents.contains("\"agentstudio.eventbus.consumer\":\"InboxNotificationRouter\""))
        #expect(contents.contains("\"agentstudio.eventbus.name\":\"paneRuntime\""))
        #expect(contents.contains("\"agentstudio.eventbus.delivery\":\"consumed\""))
        #expect(contents.contains("\"agentstudio.inbox.reason\":\"bell_disabled\""))
        #expect(contents.contains("\"agentstudio.runtime.event\":\"terminal.bellRang\""))
        #expect(contents.contains("\"agentstudio.runtime.event\":\"terminal.scrollbarChanged\"") == false)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("activity-only scrollbar ignores do not write inbox trace records")
    func activityOnlyScrollbarIgnoresDoNotWriteInboxTraceRecords() async throws {
        let traceRuntime = makeTraceRuntime(name: "inbox-scrollbar-ignore", processIdentifier: 261)
        let fixture = await makeFixture(traceRuntime: traceRuntime)
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: 100)))
            )
        )
        await Task.yield()

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        #expect(FileManager.default.fileExists(atPath: outputFileURL.path) == false)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("focus gained trace records attention without marking pane notifications read")
    func focusGainedTraceRecordsAttentionWithoutMarkingPaneNotificationsRead() async throws {
        let traceRuntime = makeTraceRuntime(name: "inbox-focus-observed", processIdentifier: 262)
        let fixture = await makeFixture(traceRuntime: traceRuntime)
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        fixture.inboxAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(),
                kind: .bellRang,
                title: "Bell",
                body: nil,
                source: .pane(.init(paneId: paneId.uuid)),
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )

        await Task.yield()
        makeWindowKey(fixture.windowLifecycle)
        await assertEventuallyMain("focus gain should write a pane attention trace") {
            guard let outputFileURL = traceRuntime.outputFileURL else { return false }
            return (try? String(contentsOf: outputFileURL, encoding: .utf8))?
                .contains("\"body\":\"inbox.focusGainedObservedPane\"") == true
        }

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"agentstudio.inbox.unread_before\":1"))
        #expect(contents.contains("\"agentstudio.inbox.unread_after\":1"))
        #expect(fixture.inboxAtom.notifications[0].isRead == false)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("bell is gated by prefs")
    func bellIsGated() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(makePaneEnvelope(paneId: paneId, event: .terminal(.bellRang)))

        fixture.prefsAtom.setBellEnabled(true)
        _ = await fixture.bus.post(makePaneEnvelope(paneId: paneId, event: .terminal(.bellRang), seq: 2))
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "enabled bell should be routed once"
        )
        #expect(fixture.inboxAtom.notifications.count == 1)
        #expect(fixture.inboxAtom.notifications[0].kind == .bellRang)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("commandFinished notifies only above the duration threshold")
    func commandFinishedGating() async {
        let fixture = await makeFixture()

        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        await Task.yield()

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.commandFinished(exitCode: 0, duration: 3_000_000_000))
            )
        )

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.commandFinished(exitCode: 1, duration: 15_000_000_000)),
                seq: 2
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "long-running command should be routed once"
        )
        #expect(fixture.inboxAtom.notifications.count == 1)
        #expect(fixture.inboxAtom.notifications[0].kind == .commandFinished)
        #expect(fixture.inboxAtom.notifications[0].paneId == paneId.uuid)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("commandFinished routes active pane when no attended pane exists")
    func commandFinishedUsesAttendedPaneForFocusGating() async {
        let fixture = await makeFixture()

        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        #expect(fixture.tabLayout.activeTab?.activePaneId == paneId.uuid)
        #expect(fixture.attendedPane.attendedPaneId == nil)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.commandFinished(exitCode: 0, duration: 20_000_000_000))
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "unattended active pane should route while window is not key"
        )

        #expect(fixture.inboxAtom.notifications.count == 1)
        if fixture.inboxAtom.notifications.count == 1 {
            #expect(fixture.inboxAtom.notifications[0].kind == .commandFinished)
        }
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("approvalRequested and selected security alerts notify")
    func approvalAndSecurityRouting() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        let repoId = UUID()
        let worktreeId = UUID()
        _ = addTerminalPane(paneId, to: fixture, repoId: repoId, worktreeId: worktreeId)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .artifact(.approvalRequested(request: ApprovalRequest(id: UUID(), summary: "Need approval")))
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .security(.sandboxHealthChanged(healthy: false)),
                seq: 2
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .security(.sandboxHealthChanged(healthy: false)),
                seq: 3
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.progressReportUpdated(nil)),
                seq: 4
            )
        )
        await waitForNotificationCount(
            2,
            in: fixture,
            description: "approval and sandbox health should be routed"
        )

        #expect(fixture.inboxAtom.notifications.count == 2)
        #expect(fixture.inboxAtom.notifications[0].kind == .approvalRequested)
        #expect(fixture.inboxAtom.notifications[1].kind == .securityEvent)
        #expect(fixture.inboxAtom.notifications[1].repoId == repoId)
        #expect(fixture.inboxAtom.notifications[1].worktreeId == worktreeId)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("sandbox health unhealthy edge is tracked per pane and reset on stop")
    func sandboxHealthEdgesArePerPaneAndResetOnStop() async {
        let fixture = await makeFixture()
        let firstPaneId = PaneId()
        let secondPaneId = PaneId()
        _ = addTerminalPane(firstPaneId, to: fixture)
        _ = addTerminalPane(secondPaneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: firstPaneId,
                event: .security(.sandboxHealthChanged(healthy: false))
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: secondPaneId,
                event: .security(.sandboxHealthChanged(healthy: false)),
                seq: 2
            )
        )
        await waitForNotificationCount(
            2,
            in: fixture,
            description: "each pane should route its own unhealthy edge"
        )

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: secondPaneId,
                event: .security(.sandboxHealthChanged(healthy: false)),
                seq: 3
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: firstPaneId,
                event: .security(.sandboxHealthChanged(healthy: true)),
                seq: 4
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: firstPaneId,
                event: .security(.sandboxHealthChanged(healthy: false)),
                seq: 5
            )
        )
        await waitForNotificationCount(
            3,
            in: fixture,
            description: "healthy transition should arm only that pane's next unhealthy edge"
        )

        await fixture.router.stop()
        await fixture.router.start()
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: secondPaneId,
                event: .security(.sandboxHealthChanged(healthy: false)),
                seq: 6
            )
        )
        await waitForNotificationCount(
            4,
            in: fixture,
            description: "router restart should reset sandbox edge state"
        )

        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("progress error notifies on error edge and rearms after non-error progress")
    func progressErrorNotifiesOnErrorEdgeAndRearms() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.progressReportUpdated(ProgressState(kind: .set, percent: 40)))
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.progressReportUpdated(ProgressState(kind: .error, percent: 80))),
                seq: 2
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.progressReportUpdated(ProgressState(kind: .error, percent: 90))),
                seq: 3
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "first progress error edge should notify once"
        )

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.progressReportUpdated(nil)),
                seq: 4
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.progressReportUpdated(ProgressState(kind: .error, percent: nil))),
                seq: 5
            )
        )
        await waitForNotificationCount(
            2,
            in: fixture,
            description: "progress remove should rearm next progress error edge"
        )

        #expect(fixture.inboxAtom.notifications.map(\.kind) == [.terminalProgressError, .terminalProgressError])
        #expect(fixture.inboxAtom.notifications[0].body == "progress 80%")
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("secure input true notifies once and rearms after false")
    func secureInputTrueNotifiesOnceAndRearmsAfterFalse() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.secureInputChanged(true))
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.secureInputChanged(true)),
                seq: 2
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "first secure input true edge should notify once"
        )

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.secureInputChanged(false)),
                seq: 3
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.secureInputChanged(true)),
                seq: 4
            )
        )
        await waitForNotificationCount(
            2,
            in: fixture,
            description: "secure input false should rearm the next true edge"
        )

        #expect(
            fixture.inboxAtom.notifications.map(\.kind) == [
                .terminalSecureInputRequested,
                .terminalSecureInputRequested,
            ])
        #expect(fixture.inboxAtom.notifications[0].title == "Secure input requested")
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("renderer unhealthy notifies on unhealthy edge per pane")
    func rendererUnhealthyNotifiesOnUnhealthyEdgePerPane() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.rendererHealthChanged(healthy: false))
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.rendererHealthChanged(healthy: false)),
                seq: 2
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "first renderer unhealthy edge should notify once"
        )

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.rendererHealthChanged(healthy: true)),
                seq: 3
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.rendererHealthChanged(healthy: false)),
                seq: 4
            )
        )
        await waitForNotificationCount(
            2,
            in: fixture,
            description: "healthy renderer transition should rearm next unhealthy edge"
        )

        #expect(
            fixture.inboxAtom.notifications.map(\.kind) == [.terminalRendererUnhealthy, .terminalRendererUnhealthy])
        #expect(fixture.inboxAtom.notifications[0].title == "Terminal renderer unhealthy")
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

}

@MainActor
extension InboxNotificationRouterTests {
    @Test("pane closed prunes edge detector state for reused pane identifiers")
    func paneClosedPrunesEdgeDetectorState() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.rendererHealthChanged(healthy: false))
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "first unhealthy edge should notify"
        )

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .lifecycle(.paneClosed),
                seq: 2
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.rendererHealthChanged(healthy: false)),
                seq: 3
            )
        )

        await waitForNotificationCount(
            2,
            in: fixture,
            description: "closed pane should re-enter with fresh renderer edge state"
        )

        #expect(
            fixture.inboxAtom.notifications.map(\.kind) == [
                .terminalRendererUnhealthy,
                .terminalRendererUnhealthy,
            ])
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("focus-gained keeps pane notifications unread until explicit activation")
    func focusGainedKeepsPaneNotificationsUnreadUntilExplicitActivation() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        fixture.inboxAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(),
                kind: .bellRang,
                title: "Bell",
                body: nil,
                source: .pane(.init(paneId: paneId.uuid)),
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )
        #expect(fixture.inboxAtom.unreadCount(forPaneId: paneId.uuid) == 1)

        await Task.yield()
        makeWindowKey(fixture.windowLifecycle)
        await assertEventuallyMain("focus gain should mark pane attended") {
            fixture.attendedPane.attendedPaneId == paneId.uuid
        }

        #expect(fixture.inboxAtom.unreadCount(forPaneId: paneId.uuid) == 1)
        #expect(fixture.inboxAtom.notifications[0].isRead == false)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("agent notification requests become agentRpc inbox rows")
    func agentNotificationRequested() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .agentNotificationRequested(title: "Claude Code finished", body: "3 files changed")
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "agent notification should be routed"
        )

        #expect(fixture.inboxAtom.notifications.count == 1)
        #expect(fixture.inboxAtom.notifications[0].kind == .agentRpc)
        #expect(fixture.inboxAtom.notifications[0].title == "Claude Code finished")
        #expect(fixture.inboxAtom.notifications[0].body == "3 files changed")
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }
}
