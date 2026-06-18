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

    private final class SecondSleepFailsClock: Clock, @unchecked Sendable {
        struct Instant: Sendable, Comparable, Hashable, InstantProtocol {
            fileprivate let nanoseconds: Int64

            func advanced(by duration: Duration) -> Self {
                let components = duration.components
                return .init(
                    nanoseconds: nanoseconds
                        + components.seconds * 1_000_000_000
                        + components.attoseconds / 1_000_000_000
                )
            }

            func duration(to other: Self) -> Duration {
                .nanoseconds(other.nanoseconds - nanoseconds)
            }

            static func < (lhs: Self, rhs: Self) -> Bool {
                lhs.nanoseconds < rhs.nanoseconds
            }
        }

        private enum SleepFailure: Error {
            case injected
        }

        private let lock = NSLock()
        private var sleepCount = 0
        private var pendingContinuations: [Int: UnsafeContinuation<Void, Error>] = [:]

        var now: Instant { .init(nanoseconds: 0) }
        var minimumResolution: Duration { .zero }

        var startedSleepCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return sleepCount
        }

        func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
            let generation = nextSleepGeneration()
            if generation == 2 {
                throw SleepFailure.injected
            }

            try await withTaskCancellationHandler {
                try await withUnsafeThrowingContinuation { continuation in
                    storeContinuation(continuation, for: generation)
                }
            } onCancel: {
                cancel(generation)
            }
        }

        private func nextSleepGeneration() -> Int {
            lock.lock()
            defer { lock.unlock() }
            sleepCount += 1
            return sleepCount
        }

        private func storeContinuation(_ continuation: UnsafeContinuation<Void, Error>, for generation: Int) {
            lock.lock()
            pendingContinuations[generation] = continuation
            lock.unlock()
        }

        private func cancel(_ generation: Int) {
            lock.lock()
            let continuation = pendingContinuations.removeValue(forKey: generation)
            lock.unlock()
            continuation?.resume(throwing: CancellationError())
        }
    }

    private struct TraceRecordFixture: Decodable {
        let body: String
        let traceID: String?
        let attributes: [String: TraceAttributeFixture]

        enum CodingKeys: String, CodingKey {
            case attributes
            case body
            case traceID = "trace_id"
        }
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

    @Test("consumes pane terminal events from runtime bus into activity atom")
    func consumesPaneTerminalEventsFromRuntimeBusIntoActivityAtom() async {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let router = TerminalActivityRouter(bus: bus, activityAtom: atom)
        let paneId = PaneId()

        await router.start()
        await waitForBusSubscriberCount(bus, atLeast: 1)
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
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
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
        await waitForBusSubscriberCount(bus, atLeast: 1)
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.openURLRequested(url: "https://example.com/trace", kind: .text)),
                    paneId: paneId,
                    paneKind: .terminal,
                    seq: 7,
                    correlationId: correlationId
                )
            )
        )

        await assertEventuallyMain("terminal activity router should consume before trace drain") {
            atom.snapshot(for: paneId.uuid)?.recentURLRequests.count == 1
        }
        await router.stop()

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"terminal.activity.observed\""))
        #expect(contents.contains("\"agentstudio.runtime.event\":\"terminal.openURLRequested\""))
        #expect(contents.contains("\"agentstudio.envelope.seq\":7"))
        #expect(contents.contains("\"agentstudio.pane.id\":\"\(paneId.uuidString)\""))
        #expect(contents.contains("\"agentstudio.envelope.correlation_id\":\"\(correlationId.uuidString)\""))
        #expect(contents.contains("\"agentstudio.session.id\":\"terminal-session\""))
    }

    @Test("records eventbus delivery summaries without scrollbar spam")
    func recordsEventBusDeliverySummariesWithoutScrollbarSpam() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let traceDirectory = temporaryTraceDirectoryURL()
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_FLUSH": "immediate",
                "AGENTSTUDIO_TRACE_NAME": "terminal-activity-eventbus",
                "AGENTSTUDIO_TRACE_TAGS": "eventbus",
            ]),
            processIdentifier: 251,
            sessionID: "terminal-session",
            timeUnixNano: { 909 }
        )
        let router = TerminalActivityRouter(bus: bus, activityAtom: atom, traceRuntime: traceRuntime)
        let paneId = PaneId()

        await router.start()
        await waitForBusSubscriberCount(bus, atLeast: 1)
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.bellRang),
                    paneId: paneId,
                    paneKind: .terminal,
                    seq: 1
                )
            )
        )
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: 100))),
                    paneId: paneId,
                    paneKind: .terminal,
                    seq: 2
                )
            )
        )

        await router.stop()

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        let records = try traceRecords(in: outputFileURL)
        let deliveryRecords = records.filter { $0.body == "eventbus.deliver" }
        #expect(deliveryRecords.count == 1)
        let deliveryAttributes = try #require(deliveryRecords.first?.attributes)
        #expect(deliveryAttributes["agentstudio.eventbus.consumer"] == .string("TerminalActivityRouter"))
        #expect(deliveryAttributes["agentstudio.eventbus.name"] == .string("paneRuntime"))
        #expect(deliveryAttributes["agentstudio.eventbus.delivery"] == .string("consumed"))
        #expect(deliveryAttributes["agentstudio.runtime.event"] == .string("terminal.bellRang"))
        #expect(deliveryAttributes["agentstudio.envelope.seq"] == .int(1))
        #expect(contents.contains("\"agentstudio.eventbus.consumer\":\"TerminalActivityRouter\""))
        #expect(contents.contains("\"agentstudio.eventbus.name\":\"paneRuntime\""))
        #expect(contents.contains("\"agentstudio.eventbus.delivery\":\"consumed\""))
        #expect(contents.contains("\"agentstudio.runtime.event\":\"terminal.bellRang\""))
        #expect(contents.contains("\"agentstudio.envelope.seq\":1"))
        #expect(contents.contains("\"agentstudio.runtime.event\":\"terminal.scrollbarChanged\"") == false)
    }

    @Test("stop drains buffered terminal activity trace records")
    func stopDrainsBufferedTerminalActivityTraceRecords() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let traceDirectory = temporaryTraceDirectoryURL()
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
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
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
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
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
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

        await clock.waitForPendingSleepGeneration(2)
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
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
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

    @Test("stop closes unseen activity window with router stop reason")
    func stopClosesUnseenActivityWindowWithRouterStopReason() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let traceDirectory = temporaryTraceDirectoryURL()
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "terminal-activity-stop-close",
                "AGENTSTUDIO_TRACE_TAGS": "terminal.activity",
            ]),
            processIdentifier: 252,
            sessionID: "terminal-session",
            timeUnixNano: { 1001 }
        )
        let router = TerminalActivityRouter(bus: bus, activityAtom: atom, traceRuntime: traceRuntime)
        let paneId = PaneId()
        let correlationId = UUID()

        await router.start()
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: 100))),
                    paneId: paneId,
                    paneKind: .terminal,
                    correlationId: correlationId
                )
            )
        )

        await assertEventuallyMain("terminal activity router should open an unseen activity window") {
            atom.snapshot(for: paneId.uuid)?.outputBurst != nil
        }

        await router.stop()

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        let records = try traceRecords(in: outputFileURL)
        let closeRecord = try #require(
            records.first { $0.body == "terminal.activity.unseenWindowClosed" }
        )
        #expect(closeRecord.traceID == correlationId.uuidString)
        #expect(closeRecord.attributes["terminal.activity.close_reason"] == .string("router.stop"))
    }

    @Test("non-cancellation debounce failure settles unseen activity instead of stranding it")
    func nonCancellationDebounceFailureSettlesUnseenActivityInsteadOfStrandingIt() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let traceDirectory = temporaryTraceDirectoryURL()
        let clock = SecondSleepFailsClock()
        let nowMilliseconds = MillisecondBox(2000)
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_FLUSH": "immediate",
                "AGENTSTUDIO_TRACE_NAME": "terminal-activity-debounce-failure",
                "AGENTSTUDIO_TRACE_TAGS": "terminal.activity",
            ]),
            processIdentifier: 255,
            sessionID: "terminal-session",
            timeUnixNano: { 1004 }
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
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: 100))),
                    paneId: paneId,
                    paneKind: .terminal
                )
            )
        )
        await assertEventuallyMain("first debounce sleep should be scheduled") {
            clock.startedSleepCount == 1
        }

        nowMilliseconds.set(2300)
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: 140))),
                    paneId: paneId,
                    paneKind: .terminal
                )
            )
        )
        await assertEventuallyMain("second debounce sleep should be attempted") {
            clock.startedSleepCount == 2
        }

        await router.stop()

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        let closeRecords = try traceRecords(in: outputFileURL)
            .filter { $0.body == "terminal.activity.unseenWindowClosed" }
        let closeRecord = try #require(closeRecords.first)
        #expect(closeRecords.count == 1)
        #expect(closeRecord.attributes["terminal.activity.close_reason"] == .string("quiet"))
        #expect(closeRecord.attributes["terminal.activity.rows_added"] == .int(40))
    }

    @Test("pane close prunes unseen activity window immediately")
    func paneClosePrunesUnseenActivityWindowImmediately() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let clock = TestPushClock()
        let traceSink = TerminalActivityTraceRecordingSink()
        let traceDirectory = temporaryTraceDirectoryURL()
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_FLUSH": "immediate",
                "AGENTSTUDIO_TRACE_NAME": "terminal-activity-pane-close",
                "AGENTSTUDIO_TRACE_TAGS": "terminal.activity",
            ]),
            processIdentifier: 253,
            sessionID: "terminal-session",
            sinkFactory: AgentStudioTraceSinkFactory(
                makeJSONLSink: { _ in traceSink },
                makeOTLPSink: { _ in traceSink }
            ),
            timeUnixNano: { 1002 }
        )
        let router = TerminalActivityRouter(
            bus: bus,
            activityAtom: atom,
            traceRuntime: traceRuntime,
            unseenActivityDebounceDuration: .milliseconds(750),
            unseenActivityClock: clock
        )
        let paneId = PaneId()

        await router.start()
        await waitForBusSubscriberCount(bus, atLeast: 1)
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: 100))),
                    paneId: paneId,
                    paneKind: .terminal
                )
            )
        )
        await clock.waitForPendingSleepCount(atLeast: 1)
        _ = await bus.post(
            .pane(
                .test(
                    event: .lifecycle(.paneClosed),
                    paneId: paneId,
                    paneKind: .terminal
                )
            )
        )

        await assertEventuallyMain("terminal activity router should cancel debounce on pane close") {
            clock.pendingSleepCount == 0
        }
        await router.stop()

        let closeRecords = await traceSink.records()
            .filter { $0.body == "terminal.activity.unseenWindowClosed" }
        #expect(closeRecords.count == 1)
        #expect(closeRecords.first?.attributes["terminal.activity.close_reason"] == .string("pane.closed"))
    }

    @Test("decreasing scrollbar totals do not emit negative rows added")
    func decreasingScrollbarTotalsDoNotEmitNegativeRowsAdded() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let traceDirectory = temporaryTraceDirectoryURL()
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "terminal-activity-decreasing-scrollbar",
                "AGENTSTUDIO_TRACE_TAGS": "terminal.activity",
            ]),
            processIdentifier: 254,
            sessionID: "terminal-session",
            timeUnixNano: { 1003 }
        )
        let router = TerminalActivityRouter(bus: bus, activityAtom: atom, traceRuntime: traceRuntime)
        let paneId = PaneId()

        await router.start()
        for totalRows in [100, 80] {
            _ = await bus.post(
                .pane(
                    .test(
                        event: .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: totalRows))),
                        paneId: paneId,
                        paneKind: .terminal
                    )
                )
            )
        }

        await router.stop()

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        let records = try traceRecords(in: outputFileURL)
        for record in records {
            #expect(record.attributes["terminal.activity.rows_added"] != .int(-20))
        }
        let closeRecord = try #require(records.first { $0.body == "terminal.activity.unseenWindowClosed" })
        #expect(closeRecord.attributes["terminal.activity.rows_added"] == .int(0))
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
            layout: Layout(paneId: activePaneId)
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
        try traceRecords(in: fileURL).map { record in
            guard case .int(let sequence) = record.attributes["agentstudio.envelope.seq"] else {
                Issue.record("Missing integer envelope sequence in trace record")
                return -1
            }
            return sequence
        }
    }

    private func traceRecords(in fileURL: URL) throws -> [TraceRecordFixture] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return try contents.split(separator: "\n").map { line in
            try JSONDecoder().decode(TraceRecordFixture.self, from: Data(line.utf8))
        }
    }

    private actor TerminalActivityTraceRecordingSink: AgentStudioTraceSink {
        private var recordedRecords: [AgentStudioTraceRecord] = []

        func record(_ record: AgentStudioTraceRecord) {
            recordedRecords.append(record)
        }

        func flush() {}

        func shutdown() {}

        func diagnostics() -> AgentStudioTraceWriterDiagnostics {
            .empty
        }

        func records() -> [AgentStudioTraceRecord] {
            recordedRecords
        }
    }
}
