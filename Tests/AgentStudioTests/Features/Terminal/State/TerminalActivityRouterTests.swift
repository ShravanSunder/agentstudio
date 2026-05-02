import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("TerminalActivityRouter", .serialized)
struct TerminalActivityRouterTests {
    private final class MillisecondBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int64

        init(_ value: Int64) {
            self.value = value
        }

        func set(_ value: Int64) {
            lock.lock()
            self.value = value
            lock.unlock()
        }

        func get() -> Int64 {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private struct TraceRecordFixture: Decodable {
        let attributes: [String: TraceAttributeFixture]
    }

    private enum TraceAttributeFixture: Decodable {
        case int(Int)
        case other

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Int.self) {
                self = .int(value)
            } else {
                self = .other
            }
        }
    }

    @Test("consumes pane terminal events from runtime bus into activity atom")
    func consumesPaneTerminalEventsFromRuntimeBusIntoActivityAtom() async {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let router = TerminalActivityRouter(bus: bus, activityAtom: atom)
        let paneId = PaneId()

        await router.start()
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.progressReportUpdated(ProgressState(kind: .set, percent: 25))),
                    paneId: paneId,
                    paneKind: .terminal
                )
            )
        )

        await assertEventuallyMain("terminal activity router should update progress") {
            atom.snapshot(for: paneId.uuid)?.progress == .reported(ProgressState(kind: .set, percent: 25))
        }

        await router.stop()
    }

    @Test("records terminal activity trace records when runtime tracing is enabled")
    func recordsTerminalActivityTraceRecordsWhenRuntimeTracingIsEnabled() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let traceDirectory = temporaryTraceDirectoryURL()
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_FLUSH": "immediate",
                "AGENTSTUDIO_TRACE_NAME": "terminal-activity",
                "AGENTSTUDIO_TRACE_TAGS": "terminal.activity",
            ]),
            processIdentifier: 246,
            sessionID: "terminal-session",
            timeUnixNano: { 404 }
        )
        let router = TerminalActivityRouter(bus: bus, activityAtom: atom, traceRuntime: traceRuntime)
        let paneId = PaneId()
        let correlationId = UUID()

        await router.start()
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.bellRang),
                    paneId: paneId,
                    paneKind: .terminal,
                    seq: 7,
                    correlationId: correlationId
                )
            )
        )

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        await assertEventuallyMain("terminal activity router should write a trace record") {
            (try? String(contentsOf: outputFileURL, encoding: .utf8))?
                .contains("\"body\":\"terminal.activity.observed\"") == true
        }

        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"agentstudio.runtime.event\":\"bellRang\""))
        #expect(contents.contains("\"agentstudio.envelope.seq\":7"))
        #expect(contents.contains("\"agentstudio.pane.id\":\"\(paneId.uuidString)\""))
        #expect(contents.contains("\"agentstudio.envelope.correlation_id\":\"\(correlationId.uuidString)\""))
        #expect(contents.contains("\"agentstudio.session.id\":\"terminal-session\""))
        await router.stop()
    }

    @Test("stop drains buffered terminal activity trace records")
    func stopDrainsBufferedTerminalActivityTraceRecords() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let traceDirectory = temporaryTraceDirectoryURL()
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "terminal-activity-drain",
                "AGENTSTUDIO_TRACE_TAGS": "terminal.activity",
            ]),
            processIdentifier: 247,
            sessionID: "terminal-session",
            timeUnixNano: { 505 }
        )
        let router = TerminalActivityRouter(bus: bus, activityAtom: atom, traceRuntime: traceRuntime)
        let paneId = PaneId()

        await router.start()
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.openURLRequested(url: "https://example.com/drain", kind: .text)),
                    paneId: paneId,
                    paneKind: .terminal,
                    seq: 8
                )
            )
        )

        await assertEventuallyMain("terminal activity router should consume before stop") {
            atom.snapshot(for: paneId.uuid)?.recentURLRequests.count == 1
        }

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        #expect(FileManager.default.fileExists(atPath: outputFileURL.path) == false)

        await router.stop()

        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"terminal.activity.observed\""))
        #expect(contents.contains("\"agentstudio.envelope.seq\":8"))
    }

    @Test("terminal activity trace records preserve envelope arrival order")
    func terminalActivityTraceRecordsPreserveEnvelopeArrivalOrder() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let traceDirectory = temporaryTraceDirectoryURL()
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "terminal-activity-order",
                "AGENTSTUDIO_TRACE_TAGS": "terminal.activity",
            ]),
            processIdentifier: 248,
            sessionID: "terminal-session",
            timeUnixNano: { 606 }
        )
        let router = TerminalActivityRouter(bus: bus, activityAtom: atom, traceRuntime: traceRuntime)
        let paneId = PaneId()

        await router.start()
        for sequence in 1...5 {
            _ = await bus.post(
                .pane(
                    .test(
                        event: .terminal(.openURLRequested(url: "https://example.com/\(sequence)", kind: .text)),
                        paneId: paneId,
                        paneKind: .terminal,
                        seq: UInt64(sequence)
                    )
                )
            )
        }

        await assertEventuallyMain("terminal activity router should consume all URL requests") {
            atom.snapshot(for: paneId.uuid)?.recentURLRequests.count == 5
        }

        await router.stop()

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        let sequences = try traceEnvelopeSequences(in: outputFileURL)
        #expect(sequences == [1, 2, 3, 4, 5])
    }

    @Test("scrollbar activity is debounced into unseen activity window records")
    func scrollbarActivityIsDebouncedIntoUnseenActivityWindowRecords() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let traceDirectory = temporaryTraceDirectoryURL()
        let clock = TestPushClock()
        let nowMilliseconds = MillisecondBox(1000)
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_FLUSH": "immediate",
                "AGENTSTUDIO_TRACE_NAME": "terminal-activity-unseen",
                "AGENTSTUDIO_TRACE_TAGS": "terminal.activity",
            ]),
            processIdentifier: 249,
            sessionID: "terminal-session",
            timeUnixNano: { 707 }
        )
        let router = TerminalActivityRouter(
            bus: bus,
            activityAtom: atom,
            traceRuntime: traceRuntime,
            unseenActivityDebounceDuration: .milliseconds(750),
            unseenActivityClock: clock,
            nowMilliseconds: { nowMilliseconds.get() }
        )
        let paneId = PaneId()

        await router.start()
        for (index, totalRows) in [100, 120, 140].enumerated() {
            nowMilliseconds.set(1000 + Int64(index * 100))
            _ = await bus.post(
                .pane(
                    .test(
                        event: .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: totalRows))),
                        paneId: paneId,
                        paneKind: .terminal,
                        seq: UInt64(index + 1)
                    )
                )
            )
        }

        await clock.waitForPendingSleepCount(atLeast: 1)
        clock.advance(by: .milliseconds(750))
        await router.stop()

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"terminal.activity.unseenWindowStarted\""))
        #expect(contents.contains("\"body\":\"terminal.activity.unseenWindowExtended\""))
        #expect(contents.contains("\"body\":\"terminal.activity.outputBurst\""))
        #expect(contents.contains("\"body\":\"terminal.activity.unseenWindowClosed\""))
        #expect(contents.contains("\"terminal.activity.rows_added\":40"))
        #expect(contents.contains("\"terminal.activity.threshold_rows\":30"))
        #expect(contents.contains("\"terminal.activity.event_count\":3"))
        #expect(contents.contains("\"agentstudio.pane.attended\":false"))
        #expect(contents.contains("\"body\":\"terminal.activity.observed\"") == false)
    }

    @Test("attended pane scrollbar activity does not emit unseen activity trace records")
    func attendedPaneScrollbarActivityDoesNotEmitUnseenActivityTraceRecords() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let traceDirectory = temporaryTraceDirectoryURL()
        let paneId = PaneId()
        let attendedPane = makeAttendedPaneAtom(activePaneId: paneId.uuid)
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_FLUSH": "immediate",
                "AGENTSTUDIO_TRACE_NAME": "terminal-activity-attended",
                "AGENTSTUDIO_TRACE_TAGS": "terminal.activity",
            ]),
            processIdentifier: 250,
            sessionID: "terminal-session",
            timeUnixNano: { 808 }
        )
        let router = TerminalActivityRouter(
            bus: bus,
            activityAtom: atom,
            attendedPane: attendedPane,
            traceRuntime: traceRuntime
        )

        await router.start()
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: 140))),
                    paneId: paneId,
                    paneKind: .terminal
                )
            )
        )

        await assertEventuallyMain("attended pane scrollbar activity should still update activity state") {
            atom.snapshot(for: paneId.uuid)?.outputBurst != nil
        }

        await router.stop()

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        #expect(FileManager.default.fileExists(atPath: outputFileURL.path) == false)
        attendedPane.stop()
    }

    @Test("start is idempotent and does not double-consume events")
    func startIsIdempotentAndDoesNotDoubleConsumeEvents() async {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom()
        let router = TerminalActivityRouter(bus: bus, activityAtom: atom)
        let paneId = PaneId()

        await router.start()
        await router.start()
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.openURLRequested(url: "https://example.com", kind: .text)),
                    paneId: paneId,
                    paneKind: .terminal
                )
            )
        )

        await assertEventuallyMain("idempotent start should consume one URL request") {
            atom.snapshot(for: paneId.uuid)?.recentURLRequests.count == 1
        }

        await router.stop()
    }

    @Test("stop prevents later runtime events from mutating activity")
    func stopPreventsLaterRuntimeEventsFromMutatingActivity() async {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom()
        let router = TerminalActivityRouter(bus: bus, activityAtom: atom)
        let paneId = PaneId()

        await router.start()
        await router.stop()
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.progressReportUpdated(ProgressState(kind: .set, percent: 99))),
                    paneId: paneId,
                    paneKind: .terminal
                )
            )
        )
        await Task.yield()

        #expect(atom.snapshot(for: paneId.uuid) == nil)
    }

    @Test("non-terminal pane envelopes are ignored")
    func nonTerminalPaneEnvelopesAreIgnored() async {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom()
        let router = TerminalActivityRouter(bus: bus, activityAtom: atom)
        let paneId = PaneId()

        await router.start()
        _ = await bus.post(
            .pane(
                .test(
                    event: .browser(.pageLoaded(url: URL(fileURLWithPath: "/tmp/index.html"))),
                    paneId: paneId,
                    paneKind: .browser
                )
            )
        )
        await Task.yield()

        #expect(atom.snapshot(for: paneId.uuid) == nil)
        await router.stop()
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-terminal-activity-router-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func makeAttendedPaneAtom(activePaneId: UUID) -> AttendedPaneAtom {
        let tabLayout = WorkspaceTabLayoutAtom()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: activePaneId),
            visiblePaneIds: [activePaneId]
        )
        let tab = Tab(
            name: "Tab",
            panes: [activePaneId],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: activePaneId
        )
        let windowLifecycle = WindowLifecycleAtom()
        let windowId = UUID()
        windowLifecycle.recordWindowRegistered(windowId)
        windowLifecycle.recordWindowBecameKey(windowId)
        tabLayout.appendTab(tab)
        tabLayout.setActiveTab(tab.id)
        return AttendedPaneAtom(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: ManagementLayerAtom()
        )
    }

    private func traceEnvelopeSequences(in fileURL: URL) throws -> [Int] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return try contents.split(separator: "\n").map { line in
            let data = Data(line.utf8)
            let record = try JSONDecoder().decode(TraceRecordFixture.self, from: data)
            guard case .int(let sequence) = record.attributes["agentstudio.envelope.seq"] else {
                Issue.record("Missing integer envelope sequence in trace record")
                return -1
            }
            return sequence
        }
    }
}
