import Foundation
import os.log

private let terminalActivityRouterLogger = Logger(
    subsystem: "com.agentstudio",
    category: "TerminalActivityRouter"
)

@MainActor
/// Leaf runtime-bus subscriber that projects high-churn terminal facts into
/// `TerminalActivityAtom`; inbox-worthy promotion stays in the notification router.
final class TerminalActivityRouter {
    private struct TraceRequest: Sendable {
        let tag: AgentStudioTraceTag
        let body: String
        let traceID: String?
        let parentSpanID: String?
        let attributes: [String: AgentStudioTraceValue]
    }

    private struct UnseenActivityWindow {
        let id: UUID
        let paneId: UUID
        let thresholdRows: Int
        let debounceMilliseconds: Int
        let startedAtMilliseconds: Int64
        var lastObservedAtMilliseconds: Int64
        var eventCount: Int
        var rowsAdded: Int
        var baselineRows: Int
        var latestRows: Int
        var latestIsPinnedToBottom: Bool
        var didEmitExtended: Bool
        var didEmitInitialActivity: Bool
        var didEmitBurst: Bool
        var generation: Int
        var lastEnvelopeTimestamp: ContinuousClock.Instant
        var lastCorrelationId: UUID?
        var lastCausationId: UUID?
        var lastCommandId: UUID?
    }

    private let bus: EventBus<RuntimeEnvelope>
    private let activityAtom: TerminalActivityAtom
    private let attendedPane: AttendedPaneAtom?
    private let traceRuntime: AgentStudioTraceRuntime?
    private let unseenActivityDebounceDuration: Duration
    private let unseenActivityDebounceMilliseconds: Int
    private let unseenActivityClock: any Clock<Duration>
    private let nowMilliseconds: @Sendable () -> Int64
    private let isPaneCurrentlyAttended: @MainActor (UUID) -> Bool

    private var busTask: Task<Void, Never>?
    private var traceContinuation: AsyncStream<TraceRequest>.Continuation?
    private var traceWorkerTask: Task<Void, Never>?
    private var unseenActivityWindows: [UUID: UnseenActivityWindow] = [:]
    private var unseenActivityCloseTasksByPaneId: [UUID: Task<Void, Never>] = [:]
    private var derivedActivitySequence: UInt64 = 0

    init(
        bus: EventBus<RuntimeEnvelope>,
        activityAtom: TerminalActivityAtom,
        attendedPane: AttendedPaneAtom? = nil,
        traceRuntime: AgentStudioTraceRuntime? = nil,
        isPaneCurrentlyAttended: (@MainActor (UUID) -> Bool)? = nil,
        unseenActivityDebounceDuration: Duration = AppPolicies.InboxNotification.terminalActivityQuietDebounceDuration,
        unseenActivityClock: any Clock<Duration> = ContinuousClock(),
        nowMilliseconds: @escaping @Sendable () -> Int64 = {
            Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        }
    ) {
        self.bus = bus
        self.activityAtom = activityAtom
        self.attendedPane = attendedPane
        self.traceRuntime = traceRuntime
        self.unseenActivityDebounceDuration = unseenActivityDebounceDuration
        self.unseenActivityDebounceMilliseconds = Self.milliseconds(from: unseenActivityDebounceDuration)
        self.unseenActivityClock = unseenActivityClock
        self.nowMilliseconds = nowMilliseconds
        self.isPaneCurrentlyAttended =
            isPaneCurrentlyAttended
            ?? { [weak attendedPane] paneId in
                attendedPane?.attendedPaneId == paneId
            }
    }

    deinit {
        busTask?.cancel()
        traceContinuation?.finish()
        traceWorkerTask?.cancel()
        for (_, closeTask) in unseenActivityCloseTasksByPaneId {
            closeTask.cancel()
        }
    }

    func start() async {
        guard busTask == nil else { return }

        let stream = await bus.subscribe()
        busTask = Task { @MainActor [weak self] in
            for await envelope in stream {
                guard !Task.isCancelled else { return }
                guard let self, !Task.isCancelled else { return }
                await self.consume(envelope)
            }
            if !Task.isCancelled {
                terminalActivityRouterLogger.warning(
                    "Runtime event stream ended while terminal activity router was active")
            }
        }
    }

    func stop() async {
        let task = busTask
        task?.cancel()
        busTask = nil
        await task?.value
        closeAllUnseenActivityWindows(reason: "router.stop")
        await drainTraceRecords()
    }

    func markUnseenActivityObserved(paneId: UUID) {
        closeUnseenActivityWindowWithoutSettling(paneId: paneId, reason: "inbox.observed")
    }

    private func consume(_ envelope: RuntimeEnvelope) async {
        guard case .pane(let paneEnvelope) = envelope else { return }
        activityAtom.consume(paneEnvelope)
        if case .lifecycle(.paneClosed) = paneEnvelope.event {
            closeUnseenActivityWindowWithoutSettling(paneId: paneEnvelope.paneId.uuid, reason: "pane.closed")
        }
        await traceTerminalActivity(paneEnvelope)
    }

    private func traceTerminalActivity(_ envelope: PaneEnvelope) async {
        guard case .terminal(let event) = envelope.event else { return }
        if case .scrollbarChanged(let state) = event {
            await traceUnseenActivityIfNeeded(envelope, scrollbarState: state)
            return
        }
        guard traceRuntime != nil else { return }
        guard !RuntimeEnvelopeTraceSummary.isHighVolumeActivityOnly(envelope.event) else { return }
        ensureTraceWorkerStarted()
        traceEventBusDelivery(envelope)
        let attributes = terminalTraceAttributes(for: envelope, event: event)
        traceContinuation?.yield(
            .init(
                tag: .terminalActivity,
                body: "terminal.activity.observed",
                traceID: envelope.correlationId?.uuidString,
                parentSpanID: envelope.causationId?.uuidString,
                attributes: attributes
            )
        )
    }

    private func traceEventBusDelivery(_ envelope: PaneEnvelope) {
        guard !RuntimeEnvelopeTraceSummary.isHighVolumeActivityOnly(envelope.event) else { return }
        var attributes = RuntimeEnvelopeTraceSummary(envelope).attributes(
            eventBusName: "paneRuntime",
            consumerName: "TerminalActivityRouter"
        )
        attributes["agentstudio.eventbus.delivery"] = .string("consumed")
        traceContinuation?.yield(
            .init(
                tag: .eventbus,
                body: "eventbus.deliver",
                traceID: envelope.correlationId?.uuidString,
                parentSpanID: envelope.causationId?.uuidString,
                attributes: attributes
            )
        )
    }

    private func ensureTraceWorkerStarted() {
        guard traceWorkerTask == nil, let traceRuntime else { return }
        let (stream, continuation) = AsyncStream.makeStream(
            of: TraceRequest.self,
            bufferingPolicy: .bufferingNewest(AppPolicies.Diagnostics.traceEventQueueBufferLimit)
        )
        traceContinuation = continuation
        // swiftlint:disable:next no_task_detached
        traceWorkerTask = Task.detached(priority: .utility) {
            for await request in stream {
                await traceRuntime.record(
                    tag: request.tag,
                    body: request.body,
                    traceID: request.traceID,
                    parentSpanID: request.parentSpanID,
                    attributes: request.attributes
                )
            }
        }
    }

    private func drainTraceRecords() async {
        closeAllUnseenActivityWindows(reason: "router.stop")
        traceContinuation?.finish()
        traceContinuation = nil
        let workerTask = traceWorkerTask
        traceWorkerTask = nil
        await workerTask?.value
        do {
            try await traceRuntime?.flush()
        } catch {
            let diagnostics = await traceRuntime?.diagnostics() ?? .empty
            terminalActivityRouterLogger.warning(
                "Terminal activity trace flush failed: \(error.localizedDescription); failedFlushCount=\(diagnostics.failedFlushCount); lastFlushError=\(diagnostics.lastFlushErrorDescription ?? "none")"
            )
        }
    }

    private func traceUnseenActivityIfNeeded(
        _ envelope: PaneEnvelope,
        scrollbarState: ScrollbarState
    ) async {
        if isPaneCurrentlyAttended(envelope.paneId.uuid) {
            closeUnseenActivityWindowWithoutSettling(paneId: envelope.paneId.uuid, reason: "pane.attended")
            return
        }

        let paneId = envelope.paneId.uuid
        let observedAtMilliseconds = nowMilliseconds()
        var window =
            unseenActivityWindows[paneId]
            ?? UnseenActivityWindow(
                id: UUID(),
                paneId: paneId,
                thresholdRows: activityAtom.outputBurstThreshold,
                debounceMilliseconds: unseenActivityDebounceMilliseconds,
                startedAtMilliseconds: observedAtMilliseconds,
                lastObservedAtMilliseconds: observedAtMilliseconds,
                eventCount: 0,
                rowsAdded: 0,
                baselineRows: scrollbarState.total,
                latestRows: scrollbarState.total,
                latestIsPinnedToBottom: scrollbarState.isPinnedToBottom,
                didEmitExtended: false,
                didEmitInitialActivity: false,
                didEmitBurst: false,
                generation: 0,
                lastEnvelopeTimestamp: envelope.timestamp,
                lastCorrelationId: nil,
                lastCausationId: nil,
                lastCommandId: nil
            )
        let isNewWindow = window.eventCount == 0
        window.eventCount += 1
        window.lastObservedAtMilliseconds = observedAtMilliseconds
        window.latestRows = scrollbarState.total
        window.latestIsPinnedToBottom = scrollbarState.isPinnedToBottom
        window.rowsAdded = max(window.rowsAdded, max(0, scrollbarState.total - window.baselineRows))
        window.generation += 1
        window.lastEnvelopeTimestamp = envelope.timestamp
        window.lastCorrelationId = envelope.correlationId
        window.lastCausationId = envelope.causationId
        window.lastCommandId = envelope.commandId
        unseenActivityCloseTasksByPaneId[paneId]?.cancel()
        let generation = window.generation
        unseenActivityWindows[paneId] = window

        if isNewWindow {
            traceUnseenActivityWindow(
                body: "terminal.activity.unseenWindowStarted",
                window: window,
                envelope: envelope
            )
        } else if !window.didEmitExtended {
            window.didEmitExtended = true
            unseenActivityWindows[paneId] = window
            traceUnseenActivityWindow(
                body: "terminal.activity.unseenWindowExtended",
                window: window,
                envelope: envelope
            )
        }
        if !window.didEmitInitialActivity, window.rowsAdded > 0 {
            window.didEmitInitialActivity = true
            if window.rowsAdded >= window.thresholdRows {
                window.didEmitBurst = true
            }
            unseenActivityWindows[paneId] = window
            traceUnseenActivityWindow(
                body: window.rowsAdded >= window.thresholdRows
                    ? "terminal.activity.outputBurst"
                    : "terminal.activity.outputStarted",
                window: window,
                envelope: envelope
            )
        } else if !window.didEmitBurst, window.rowsAdded >= window.thresholdRows {
            window.didEmitBurst = true
            unseenActivityWindows[paneId] = window
            traceUnseenActivityWindow(
                body: "terminal.activity.outputBurst",
                window: window,
                envelope: envelope
            )
        }
        scheduleUnseenActivityClose(paneId: paneId, generation: generation)
    }

    private func postSettledUnseenActivity(
        window: UnseenActivityWindow
    ) async {
        guard window.rowsAdded > 0 else { return }
        let activity = TerminalSettledActivity(
            burstWindowId: window.id,
            thresholdRows: window.thresholdRows,
            debounceMilliseconds: window.debounceMilliseconds,
            startedAtMilliseconds: window.startedAtMilliseconds,
            settledAtMilliseconds: window.lastObservedAtMilliseconds + Int64(window.debounceMilliseconds),
            eventCount: window.eventCount,
            rowsAdded: window.rowsAdded,
            baselineRows: window.baselineRows,
            latestRows: window.latestRows,
            isPinnedToBottom: window.latestIsPinnedToBottom
        )
        _ = await bus.post(
            .pane(
                PaneEnvelope(
                    source: .system(.builtin(.terminalActivityRouter)),
                    seq: nextDerivedActivitySequence(),
                    timestamp: window.lastEnvelopeTimestamp,
                    correlationId: window.lastCorrelationId,
                    causationId: window.lastCausationId,
                    commandId: window.lastCommandId,
                    paneId: PaneId(uuid: window.paneId),
                    paneKind: .terminal,
                    event: .terminalActivity(.unseenActivitySettled(activity))
                )
            )
        )
    }

    private func nextDerivedActivitySequence() -> UInt64 {
        if derivedActivitySequence == .max {
            terminalActivityRouterLogger.warning("Derived terminal activity sequence overflow; restarting at 1")
            derivedActivitySequence = 0
        }
        derivedActivitySequence += 1
        return derivedActivitySequence
    }

    private func scheduleUnseenActivityClose(paneId: UUID, generation: Int) {
        unseenActivityCloseTasksByPaneId[paneId] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await unseenActivityClock.sleep(for: unseenActivityDebounceDuration)
            } catch {
                return
            }
            await closeUnseenActivityWindow(paneId: paneId, generation: generation, reason: "quiet")
        }
    }

    private func closeUnseenActivityWindow(paneId: UUID, generation: Int, reason: String) async {
        guard let window = unseenActivityWindows[paneId], window.generation == generation else { return }
        unseenActivityCloseTasksByPaneId[paneId] = nil
        unseenActivityWindows[paneId] = nil
        if reason == "quiet" {
            await postSettledUnseenActivity(window: window)
        }
        traceUnseenActivityWindow(
            body: "terminal.activity.unseenWindowClosed",
            window: window,
            envelope: nil,
            reason: reason
        )
    }

    private func closeUnseenActivityWindowWithoutSettling(paneId: UUID, reason: String) {
        guard let window = unseenActivityWindows[paneId] else { return }
        unseenActivityCloseTasksByPaneId[paneId]?.cancel()
        unseenActivityCloseTasksByPaneId[paneId] = nil
        unseenActivityWindows[paneId] = nil
        traceUnseenActivityWindow(
            body: "terminal.activity.unseenWindowClosed",
            window: window,
            envelope: nil,
            reason: reason
        )
    }

    private func closeAllUnseenActivityWindows(reason: String) {
        let windows = unseenActivityWindows
        unseenActivityWindows.removeAll()
        let closeTasks = unseenActivityCloseTasksByPaneId
        unseenActivityCloseTasksByPaneId.removeAll()
        for (_, closeTask) in closeTasks {
            closeTask.cancel()
        }
        for (_, window) in windows {
            traceUnseenActivityWindow(
                body: "terminal.activity.unseenWindowClosed",
                window: window,
                envelope: nil,
                reason: reason
            )
        }
    }

    private func traceUnseenActivityWindow(
        body: String,
        window: UnseenActivityWindow,
        envelope: PaneEnvelope?,
        reason: String? = nil
    ) {
        ensureTraceWorkerStarted()
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.pane.attended": .bool(false),
            "agentstudio.pane.id": .string(window.paneId.uuidString),
            "terminal.activity.baseline_rows": .int(window.baselineRows),
            "terminal.activity.debounce_ms": .int(window.debounceMilliseconds),
            "terminal.activity.duration_ms": .int(
                Int(window.lastObservedAtMilliseconds - window.startedAtMilliseconds)
            ),
            "terminal.activity.event_count": .int(window.eventCount),
            "terminal.activity.is_inferred": .bool(true),
            "terminal.activity.is_pinned_to_bottom": .bool(window.latestIsPinnedToBottom),
            "terminal.activity.latest_rows": .int(window.latestRows),
            "terminal.activity.rows_added": .int(window.rowsAdded),
            "terminal.activity.source": .string("scrollbar"),
            "terminal.activity.threshold_rows": .int(window.thresholdRows),
            "terminal.activity.window_id": .string(window.id.uuidString),
        ]
        if let reason {
            attributes["terminal.activity.close_reason"] = .string(reason)
        }
        if let envelope {
            attributes.merge(
                terminalTraceAttributes(
                    for: envelope,
                    event: .scrollbarChanged(
                        ScrollbarState(top: 0, bottom: 0, total: window.latestRows)
                    ))
            ) { current, _ in current }
        }
        traceContinuation?.yield(
            .init(
                tag: .terminalActivity,
                body: body,
                traceID: envelope?.correlationId?.uuidString ?? window.lastCorrelationId?.uuidString,
                parentSpanID: envelope?.causationId?.uuidString ?? window.lastCausationId?.uuidString,
                attributes: attributes
            )
        )
    }

    private func terminalTraceAttributes(
        for envelope: PaneEnvelope,
        event: GhosttyEvent
    ) -> [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.envelope.event_id": .string(envelope.eventId.uuidString),
            "agentstudio.envelope.seq": .int(Int(envelope.seq)),
            "agentstudio.pane.id": .string(envelope.paneId.uuidString),
            "agentstudio.pane.kind": .string(envelope.paneKind.traceName),
            "agentstudio.runtime.event": .string(event.traceEventName),
        ]
        if let commandId = envelope.commandId {
            attributes["agentstudio.command.id"] = .string(commandId.uuidString)
        }
        if let correlationId = envelope.correlationId {
            attributes["agentstudio.envelope.correlation_id"] = .string(correlationId.uuidString)
        }
        if let causationId = envelope.causationId {
            attributes["agentstudio.envelope.causation_id"] = .string(causationId.uuidString)
        }
        return attributes
    }

    private static func milliseconds(from duration: Duration) -> Int {
        let attosecondsPerMillisecond: Int64 = 1_000_000_000_000_000
        let components = duration.components
        let seconds = components.seconds.multipliedReportingOverflow(by: 1000)
        guard seconds.overflow == false else {
            terminalActivityRouterLogger.warning("Duration overflow while formatting terminal activity debounce")
            return .max
        }
        return Int(seconds.partialValue + components.attoseconds / attosecondsPerMillisecond)
    }
}
