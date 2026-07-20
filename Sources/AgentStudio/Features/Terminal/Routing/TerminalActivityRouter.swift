import Foundation
import Observation
import os.log

private let terminalActivityRouterLogger = Logger(
    subsystem: "com.agentstudio",
    category: "TerminalActivityRouter"
)

/// Adapts exact runtime facts and off-main terminal activity outcomes to MainActor state.
/// High-rate terminal samples are contracted before reaching this type.
@MainActor
final class TerminalActivityRouter {
    private struct TraceRequest: Sendable {
        let tag: AgentStudioTraceTag
        let body: String
        let traceID: String?
        let parentSpanID: String?
        let attributes: [String: AgentStudioTraceValue]
    }

    private let bus: EventBus<RuntimeEnvelope>
    private let projector: TerminalActivityProjector
    private let projectorBindingID = UUIDv7.generate()
    private let activityAtom: TerminalActivityAtom
    private let attendedPane: AttendedPaneDerived?
    private let traceRuntime: AgentStudioTraceRuntime?
    private let startupTraceRecorder: AgentStudioStartupTraceRecorder?
    private let surfaceIDForPaneID: @MainActor (UUID) -> UUID?
    private let isPaneCurrentlyAttended: @MainActor (UUID) -> Bool
    private let isPaneAgentClassified: @MainActor (UUID, PaneContentType) -> Bool

    private var busTask: Task<Void, Never>?
    private var derivedActivityPostTask: Task<Void, Never>?
    private var traceContinuation: AsyncStream<TraceRequest>.Continuation?
    private var traceWorkerTask: Task<Void, Never>?
    private var lastAttendedPaneID: UUID?
    private var derivedActivitySequence: UInt64 = 0

    init(
        bus: EventBus<RuntimeEnvelope>,
        activityAtom: TerminalActivityAtom,
        projector: TerminalActivityProjector? = nil,
        attendedPane: AttendedPaneDerived? = nil,
        traceRuntime: AgentStudioTraceRuntime? = nil,
        startupTraceRecorder: AgentStudioStartupTraceRecorder? = nil,
        surfaceIDForPaneID: (@MainActor (UUID) -> UUID?)? = nil,
        isPaneCurrentlyAttended: (@MainActor (UUID) -> Bool)? = nil,
        isPaneAgentClassified: (@MainActor (UUID, PaneContentType) -> Bool)? = nil,
        unseenActivityDebounceDuration: Duration = AppPolicies.InboxNotification.terminalActivityQuietDebounceDuration,
        agentSettledQuietDuration: Duration = AppPolicies.InboxNotification.agentSettledQuietDuration,
        unseenActivityClock: (any Clock<Duration> & Sendable)? = nil,
        nowMilliseconds _: @escaping @Sendable () -> Int64 = {
            Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        }
    ) {
        self.bus = bus
        self.projector =
            projector
            ?? TerminalActivityProjector(
                unseenQuietDuration: unseenActivityDebounceDuration,
                agentSettledQuietDuration: agentSettledQuietDuration,
                clock: unseenActivityClock
            )
        self.activityAtom = activityAtom
        self.attendedPane = attendedPane
        self.traceRuntime = traceRuntime
        self.startupTraceRecorder = startupTraceRecorder
        self.surfaceIDForPaneID = surfaceIDForPaneID ?? { SurfaceManager.shared.surfaceId(forPaneId: $0) }
        self.isPaneCurrentlyAttended =
            isPaneCurrentlyAttended
            ?? { [attendedPane] paneID in
                attendedPane?.attendedPaneId == paneID
            }
        self.isPaneAgentClassified = isPaneAgentClassified ?? { _, paneKind in paneKind == .agent }
    }

    deinit {
        busTask?.cancel()
        traceContinuation?.finish()
        traceWorkerTask?.cancel()
    }

    func start() async {
        guard busTask == nil else { return }

        await projector.configure { [weak self] outcomes in
            self?.consumeProjectionOutcomes(outcomes)
        }
        Ghostty.ActionRouter.bindTerminalActivityInput(
            id: projectorBindingID,
            context: { [weak self] paneID in
                self?.projectionContext(for: paneID)
                    ?? TerminalActivityProjectionContext(
                        isAttended: false,
                        isAgentClassified: false,
                        outputBurstThreshold: AppPolicies.InboxNotification.terminalActivityOutputBurstThresholdRows
                    )
            },
            sink: { [weak self] input in
                await self?.consumeTerminalActivityInput(input)
            }
        )
        lastAttendedPaneID = attendedPane?.attendedPaneId
        observeAttendedPane()

        let stream = await bus.subscribe(
            policy: .lossyNewest(BusSubscriberPolicy.standardLossyBufferLimit),
            subscriberName: "TerminalActivityRouter"
        )
        busTask = Task { @MainActor [weak self] in
            for await envelope in stream {
                guard !Task.isCancelled, let self else { return }
                await consume(envelope)
            }
            if !Task.isCancelled {
                terminalActivityRouterLogger.warning(
                    "Runtime event stream ended while terminal activity router was active")
            }
        }
    }

    func stop() async {
        Ghostty.ActionRouter.unbindTerminalActivityInput(id: projectorBindingID)
        let task = busTask
        task?.cancel()
        busTask = nil
        await task?.value
        await projector.reset()
        let derivedActivityPostTask = self.derivedActivityPostTask
        self.derivedActivityPostTask = nil
        await derivedActivityPostTask?.value
        await drainTraceRecords()
    }

    func markUnseenActivityObserved(paneId: UUID) {
        guard let surfaceID = surfaceIDForPaneID(paneId) else { return }
        Task { @MainActor in
            await Ghostty.ActionRouter.applyOrderedActivityControl(
                surfaceID: surfaceID,
                paneID: paneId,
                control: .observed
            )
        }
    }

    func consumeTerminalActivityInput(_ input: TerminalActivitySourceInput) async {
        switch input {
        case .aggregate(let surfaceID, let paneID, let input):
            guard surfaceIDForPaneID(paneID) == surfaceID else { return }
            await projector.ingest(
                surfaceID: surfaceID,
                paneID: paneID,
                aggregate: input.aggregate,
                latestState: input.latestState,
                context: input.context
            )
        case .orderedControl(let surfaceID, let paneID, let precedingAggregate, let control):
            if control != .surfaceClosed {
                guard surfaceIDForPaneID(paneID) == surfaceID else { return }
            }
            await projector.applyOrderedControl(
                surfaceID: surfaceID,
                paneID: paneID,
                precedingAggregate: precedingAggregate,
                control: control
            )
        }
    }

    private func consumeProjectionOutcomes(_ outcomes: [TerminalActivityProjectionOutcome]) {
        var derivedEnvelopes: [RuntimeEnvelope] = []
        for outcome in outcomes {
            consumeProjectionOutcome(outcome, derivedEnvelopes: &derivedEnvelopes)
        }
        enqueueDerivedActivityPosts(derivedEnvelopes)
    }

    private func consumeProjectionOutcome(
        _ outcome: TerminalActivityProjectionOutcome,
        derivedEnvelopes: inout [RuntimeEnvelope]
    ) {
        let surfaceID: UUID
        let paneID: UUID?
        switch outcome {
        case .compactStateChanged(let update):
            surfaceID = update.surfaceID
            paneID = update.paneID
        case .firstOutput(let outcomeSurfaceID, let outcomePaneID),
            .paneObservationChanged(let outcomeSurfaceID, let outcomePaneID, _),
            .unseenActivitySettled(let outcomeSurfaceID, let outcomePaneID, _),
            .agentSettledActivityPromoted(let outcomeSurfaceID, let outcomePaneID, _),
            .agentSettledActivityRevoked(let outcomeSurfaceID, let outcomePaneID):
            surfaceID = outcomeSurfaceID
            paneID = outcomePaneID
        case .surfaceClosed(let outcomeSurfaceID, let outcomePaneID):
            surfaceID = outcomeSurfaceID
            paneID = outcomePaneID
        }

        if case .surfaceClosed = outcome {
            if let paneID, surfaceIDForPaneID(paneID) != nil { return }
        } else {
            guard let paneID, surfaceIDForPaneID(paneID) == surfaceID else { return }
        }

        switch outcome {
        case .compactStateChanged(let update):
            activityAtom.apply(update)
        case .firstOutput(let surfaceID, let paneID):
            startupTraceRecorder?.recordFirstOutput(paneID: paneID, surfaceID: surfaceID)
        case .paneObservationChanged(_, let paneID, let isPinnedToBottom):
            derivedEnvelopes.append(
                derivedActivityEnvelope(
                    .paneObservationChanged(
                        TerminalPaneObservationState(isPinnedToBottom: isPinnedToBottom)
                    ),
                    paneID: paneID
                ))
        case .unseenActivitySettled(_, let paneID, let activity):
            derivedEnvelopes.append(
                derivedActivityEnvelope(.unseenActivitySettled(activity), paneID: paneID))
        case .agentSettledActivityPromoted(_, let paneID, let activity):
            derivedEnvelopes.append(
                derivedActivityEnvelope(.agentSettledActivityPromoted(activity), paneID: paneID))
        case .agentSettledActivityRevoked(_, let paneID):
            derivedEnvelopes.append(
                derivedActivityEnvelope(.agentSettledActivityRevoked, paneID: paneID))
        case .surfaceClosed(_, let paneID):
            if let paneID { activityAtom.clear(paneId: paneID) }
        }
    }

    private func projectionContext(for paneID: UUID) -> TerminalActivityProjectionContext {
        TerminalActivityProjectionContext(
            isAttended: isPaneCurrentlyAttended(paneID),
            isAgentClassified: isPaneAgentClassified(paneID, .terminal),
            outputBurstThreshold: activityAtom.outputBurstThreshold
        )
    }

    private func observeAttendedPane() {
        guard let attendedPane, busTask != nil else { return }
        withObservationTracking {
            _ = attendedPane.attendedPaneId
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, busTask != nil else { return }
                await consumeAttendedPaneTransition()
                observeAttendedPane()
            }
        }
    }

    private func consumeAttendedPaneTransition() async {
        let nextAttendedPaneID = attendedPane?.attendedPaneId
        guard nextAttendedPaneID != lastAttendedPaneID else { return }
        let previousAttendedPaneID = lastAttendedPaneID
        lastAttendedPaneID = nextAttendedPaneID

        let changedPaneIDs = Set([previousAttendedPaneID, nextAttendedPaneID].compactMap { $0 })
        for paneID in changedPaneIDs {
            guard let surfaceID = surfaceIDForPaneID(paneID) else { continue }
            let contextAfterControl = projectionContext(for: paneID)
            let contextBeforeControl = TerminalActivityProjectionContext(
                isAttended: paneID == previousAttendedPaneID,
                isAgentClassified: contextAfterControl.isAgentClassified,
                outputBurstThreshold: contextAfterControl.outputBurstThreshold
            )
            await Ghostty.ActionRouter.applyOrderedActivityControl(
                surfaceID: surfaceID,
                paneID: paneID,
                control: .contextChanged(contextAfterControl),
                contextBeforeControl: contextBeforeControl,
                contextAfterControl: contextAfterControl
            )
        }
    }

    private func consume(_ envelope: RuntimeEnvelope) async {
        guard case .pane(let paneEnvelope) = envelope else { return }
        activityAtom.consume(paneEnvelope)
        if case .terminal(let event) = paneEnvelope.event,
            !RuntimeEnvelopeTraceSummary.isHighVolumeActivityOnly(.terminal(event)),
            let surfaceID = surfaceIDForPaneID(paneEnvelope.paneId.uuid)
        {
            await Ghostty.ActionRouter.applyOrderedActivityControl(
                surfaceID: surfaceID,
                paneID: paneEnvelope.paneId.uuid,
                control: .semanticSignal
            )
        }
        await traceTerminalActivity(paneEnvelope)
    }

    private func derivedActivityEnvelope(_ event: TerminalActivityEvent, paneID: UUID) -> RuntimeEnvelope {
        .pane(
            PaneEnvelope(
                source: .system(.builtin(.terminalActivityRouter)),
                seq: nextDerivedActivitySequence(),
                timestamp: ContinuousClock().now,
                paneId: PaneId(existingUUID: paneID),
                paneKind: .terminal,
                event: .terminalActivity(event)
            )
        )
    }

    private func enqueueDerivedActivityPosts(_ envelopes: [RuntimeEnvelope]) {
        guard !envelopes.isEmpty else { return }
        let predecessor = derivedActivityPostTask
        let bus = self.bus
        derivedActivityPostTask = Task {
            await predecessor?.value
            for envelope in envelopes {
                _ = await bus.post(envelope)
            }
        }
    }

    private func nextDerivedActivitySequence() -> UInt64 {
        if derivedActivitySequence == .max {
            terminalActivityRouterLogger.warning("Derived terminal activity sequence overflow; restarting at 1")
            derivedActivitySequence = 0
        }
        derivedActivitySequence += 1
        return derivedActivitySequence
    }

    private func traceTerminalActivity(_ envelope: PaneEnvelope) async {
        guard case .terminal(let event) = envelope.event else { return }
        guard !RuntimeEnvelopeTraceSummary.isHighVolumeActivityOnly(envelope.event) else { return }
        guard traceRuntime != nil else { return }
        ensureTraceWorkerStarted()
        traceEventBusDelivery(envelope)
        traceContinuation?.yield(
            .init(
                tag: .terminalActivity,
                body: "terminal.activity.observed",
                traceID: envelope.correlationId?.uuidString,
                parentSpanID: envelope.causationId?.uuidString,
                attributes: terminalTraceAttributes(for: envelope, event: event)
            )
        )
    }

    private func traceEventBusDelivery(_ envelope: PaneEnvelope) {
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
}
