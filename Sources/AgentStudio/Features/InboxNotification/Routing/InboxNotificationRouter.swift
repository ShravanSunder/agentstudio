import Foundation
import os.log

private let inboxNotificationRouterLogger = Logger(
    subsystem: "com.agentstudio",
    category: "InboxNotificationRouter"
)

@MainActor
final class InboxNotificationRouter {
    private struct TraceRequest: Sendable {
        let tag: AgentStudioTraceTag
        let body: String
        let attributes: [String: AgentStudioTraceValue]
    }

    private struct ObservedPaneClearOutcome: Sendable, Equatable {
        let clearedCount: Int
        let keepCount: Int
        let reason: String?
    }

    private enum ClassificationDecision: Sendable {
        case notify(InboxNotificationKind)
        case ignore(reason: String)

        var action: String {
            switch self {
            case .notify:
                return "notify"
            case .ignore:
                return "ignore"
            }
        }

        var kind: InboxNotificationKind? {
            switch self {
            case .notify(let kind):
                return kind
            case .ignore:
                return nil
            }
        }

        var reason: String {
            switch self {
            case .notify:
                return "matched"
            case .ignore(let reason):
                return reason
            }
        }
    }

    private let bus: EventBus<RuntimeEnvelope>
    private let inboxAtom: InboxNotificationAtom
    private let prefsAtom: InboxNotificationPrefsAtom
    private let paneAtom: WorkspacePaneAtom
    private let tabLayout: WorkspaceTabLayoutAtom
    private let attendedPane: AttendedPaneAtom
    private let focusTracker: PaneFocusTracker
    private let terminalActivity: TerminalActivityAtom?
    private let autoClearPolicy: PaneInboxAutoClearPolicy
    private let traceRuntime: AgentStudioTraceRuntime?

    private var busTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var traceContinuation: AsyncStream<TraceRequest>.Continuation?
    private var traceWorkerTask: Task<Void, Never>?
    private var sandboxHealthWasHealthyByPaneId: [UUID: Bool] = [:]
    private var progressErrorWasActiveByPaneId: [UUID: Bool] = [:]
    private var rendererWasHealthyByPaneId: [UUID: Bool] = [:]
    private var secureInputWasActiveByPaneId: [UUID: Bool] = [:]
    private var pinnedToBottomByPaneId: [UUID: Bool] = [:]

    init(
        bus: EventBus<RuntimeEnvelope>,
        inboxAtom: InboxNotificationAtom,
        prefsAtom: InboxNotificationPrefsAtom,
        paneAtom: WorkspacePaneAtom,
        tabLayout: WorkspaceTabLayoutAtom,
        attendedPane: AttendedPaneAtom,
        focusTracker: PaneFocusTracker,
        terminalActivity: TerminalActivityAtom? = nil,
        autoClearPolicy: PaneInboxAutoClearPolicy = .init(),
        traceRuntime: AgentStudioTraceRuntime? = nil
    ) {
        self.bus = bus
        self.inboxAtom = inboxAtom
        self.prefsAtom = prefsAtom
        self.paneAtom = paneAtom
        self.tabLayout = tabLayout
        self.attendedPane = attendedPane
        self.focusTracker = focusTracker
        self.terminalActivity = terminalActivity
        self.autoClearPolicy = autoClearPolicy
        self.traceRuntime = traceRuntime
    }

    deinit {
        busTask?.cancel()
        focusTask?.cancel()
        traceContinuation?.finish()
        traceWorkerTask?.cancel()
    }

    func stop() async {
        let busTask = busTask
        busTask?.cancel()
        self.busTask = nil
        let focusTask = focusTask
        focusTask?.cancel()
        self.focusTask = nil
        await busTask?.value
        await focusTask?.value
        await drainTraceRecords()
        sandboxHealthWasHealthyByPaneId.removeAll()
        progressErrorWasActiveByPaneId.removeAll()
        rendererWasHealthyByPaneId.removeAll()
        secureInputWasActiveByPaneId.removeAll()
        pinnedToBottomByPaneId.removeAll()
    }

    func start() async {
        guard busTask == nil, focusTask == nil else { return }

        let stream = await bus.subscribe()
        busTask = Task { @MainActor [weak self] in
            for await envelope in stream {
                guard !Task.isCancelled else { return }
                guard let self, !Task.isCancelled else { return }
                self.handle(envelope)
            }
            if !Task.isCancelled {
                inboxNotificationRouterLogger.warning("Runtime event stream ended while inbox router was active")
            }
        }

        focusTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await paneId in self.focusTracker.focusGainedStream {
                guard !Task.isCancelled else { return }
                let unreadBefore = self.inboxAtom.unreadCount(forPaneId: paneId)
                let clearOutcome = self.clearObservedPaneInboxRowsForActiveTabIfNeeded(focusedPaneId: paneId)
                self.traceInboxMutation(
                    body: "inbox.focusGainedObservedPane",
                    paneId: paneId,
                    attributes: [
                        "agentstudio.inbox.unread_before": .int(unreadBefore),
                        "agentstudio.inbox.unread_after": .int(self.inboxAtom.unreadCount(forPaneId: paneId)),
                        "agentstudio.pane_inbox.cleared_count": .int(clearOutcome.clearedCount),
                        "agentstudio.pane_inbox.keep_count": .int(clearOutcome.keepCount),
                    ]
                )
            }
            if !Task.isCancelled {
                inboxNotificationRouterLogger.warning("Focus stream ended while inbox router was active")
            }
        }
    }

    private func handle(_ envelope: RuntimeEnvelope) {
        guard case .pane(let paneEnvelope) = envelope else { return }
        if case .terminal(.scrollbarChanged(let scrollbarState)) = paneEnvelope.event {
            pinnedToBottomByPaneId[paneEnvelope.paneId.uuid] = scrollbarState.isPinnedToBottom
            clearObservedPaneInboxRowsIfNeeded(
                paneId: paneEnvelope.paneId.uuid,
                scrollbarState: scrollbarState,
                traceKeepOnly: false
            )
        }
        let decision = classify(paneEnvelope)
        traceEventBusDelivery(decision, envelope: paneEnvelope)
        traceClassificationDecision(decision, envelope: paneEnvelope)
        guard let kind = decision.kind else { return }

        let paneId = paneEnvelope.paneId.uuid
        let resolvedContext = resolveContext(for: paneId)
        if resolvedContext == nil {
            inboxNotificationRouterLogger.warning(
                "Inbox notification context unresolved for pane \(paneId.uuidString, privacy: .public)"
            )
            traceInboxMutation(
                body: "inbox.context.unresolved",
                paneId: paneId,
                attributes: [
                    "agentstudio.inbox.context.reason": .string("pane_not_found"),
                    "agentstudio.runtime.event": .string(paneEnvelope.event.traceEventName),
                ]
            )
        }
        var notification = InboxNotification(
            id: UUID(),
            timestamp: Date(),
            kind: kind,
            title: title(for: paneEnvelope.event),
            body: body(for: paneEnvelope.event),
            source: .pane(
                .init(
                    paneId: paneId,
                    tabId: resolvedContext?.tabId,
                    repoId: resolvedContext?.repoId,
                    repoName: resolvedContext?.repoName,
                    worktreeId: resolvedContext?.worktreeId,
                    worktreeName: resolvedContext?.worktreeName,
                    branchName: resolvedContext?.branchName
                )
            ),
            isRead: false,
            isDismissedFromPaneInbox: false
        )
        if autoClearPolicy.decision(
            notification: notification,
            isSourcePaneAttended: isSourcePaneObserved(paneId),
            isSourcePanePinnedToBottom: isSourcePanePinnedToBottom(paneId)
        ) == .clear {
            notification.isRead = true
            notification.isDismissedFromPaneInbox = true
        }
        let globalUnreadBefore = inboxAtom.globalUnreadCount
        let retentionOutcome = inboxAtom.append(notification)
        traceInboxMutation(
            body: "inbox.notification.appended",
            paneId: paneId,
            attributes: [
                "agentstudio.inbox.kind": .string(kind.rawValue),
                "agentstudio.inbox.notification.id": .string(notification.id.uuidString),
                "agentstudio.inbox.global_unread_before": .int(globalUnreadBefore),
                "agentstudio.inbox.global_unread_after": .int(inboxAtom.globalUnreadCount),
                "agentstudio.pane_inbox.dismissed": .bool(notification.isDismissedFromPaneInbox),
                "agentstudio.inbox.read": .bool(notification.isRead),
            ]
        )
        traceRetentionOutcomeIfNeeded(retentionOutcome, paneId: paneId)
    }

    private func classify(_ envelope: PaneEnvelope) -> ClassificationDecision {
        switch envelope.event {
        case .terminal(.desktopNotificationRequested):
            return .notify(.agentDesktopNotification)
        case .agentNotificationRequested:
            return .notify(.agentRpc)
        case .terminal(.bellRang):
            return prefsAtom.bellEnabled ? .notify(.bellRang) : .ignore(reason: "bell_disabled")
        case .terminal(.commandFinished(_, let duration)):
            guard duration >= AppPolicies.InboxNotification.commandFinishedMinDurationNanoseconds else {
                return .ignore(reason: "below_duration_threshold")
            }
            return .notify(.commandFinished)
        case .terminal(.progressReportUpdated(let progress)):
            return classifyProgressReport(progress, paneId: envelope.paneId.uuid)
        case .terminal(.secureInputChanged(let isActive)):
            return classifySecureInput(isActive, paneId: envelope.paneId.uuid)
        case .terminal(.rendererHealthChanged(let healthy)):
            return classifyRendererHealth(healthy, paneId: envelope.paneId.uuid)
        case .lifecycle(.paneClosed):
            pruneEdgeState(for: envelope.paneId.uuid)
            return .ignore(reason: "pane_closed_pruned_edge_state")
        case .artifact(.approvalRequested):
            return .notify(.approvalRequested)
        case .security(.networkEgressBlocked),
            .security(.filesystemAccessDenied),
            .security(.secretAccessed),
            .security(.processSpawnBlocked):
            return .notify(.securityEvent)
        case .security(.sandboxHealthChanged(let healthy)):
            let paneId = envelope.paneId.uuid
            let wasHealthy = sandboxHealthWasHealthyByPaneId[paneId, default: true]
            // Health is edge-triggered per pane so one unhealthy runtime does not mute another.
            let shouldNotify = wasHealthy && !healthy
            sandboxHealthWasHealthyByPaneId[paneId] = healthy
            return shouldNotify ? .notify(.securityEvent) : .ignore(reason: "sandbox_health_no_unhealthy_edge")
        case .terminal(.scrollbarChanged):
            return .ignore(reason: "activity_only_scrollbar")
        default:
            inboxNotificationRouterLogger.warning(
                "Ignoring unclassified inbox event: \(String(describing: envelope.event), privacy: .public)"
            )
            return .ignore(reason: "unclassified")
        }
    }

    private func classifyProgressReport(_ progress: ProgressState?, paneId: UUID) -> ClassificationDecision {
        let isError = progress?.kind == .error
        let wasError = progressErrorWasActiveByPaneId[paneId, default: false]
        progressErrorWasActiveByPaneId[paneId] = isError
        return isError && !wasError ? .notify(.terminalProgressError) : .ignore(reason: "progress_error_no_new_edge")
    }

    private func classifySecureInput(_ isActive: Bool, paneId: UUID) -> ClassificationDecision {
        let wasActive = secureInputWasActiveByPaneId[paneId, default: false]
        secureInputWasActiveByPaneId[paneId] = isActive
        guard isActive && !wasActive else { return .ignore(reason: "secure_input_no_new_edge") }
        return .notify(.terminalSecureInputRequested)
    }

    private func classifyRendererHealth(_ healthy: Bool, paneId: UUID) -> ClassificationDecision {
        let wasHealthy = rendererWasHealthyByPaneId[paneId, default: true]
        let shouldNotify = wasHealthy && !healthy
        rendererWasHealthyByPaneId[paneId] = healthy
        return shouldNotify ? .notify(.terminalRendererUnhealthy) : .ignore(reason: "renderer_health_no_unhealthy_edge")
    }

    private func pruneEdgeState(for paneId: UUID) {
        sandboxHealthWasHealthyByPaneId.removeValue(forKey: paneId)
        progressErrorWasActiveByPaneId.removeValue(forKey: paneId)
        rendererWasHealthyByPaneId.removeValue(forKey: paneId)
        secureInputWasActiveByPaneId.removeValue(forKey: paneId)
        pinnedToBottomByPaneId.removeValue(forKey: paneId)
    }

    private func traceClassificationDecision(_ decision: ClassificationDecision, envelope: PaneEnvelope) {
        guard shouldTraceClassificationDecision(decision, event: envelope.event) else { return }
        var attributes = inboxTraceAttributes(paneId: envelope.paneId.uuid, event: envelope.event)
        attributes["agentstudio.inbox.decision"] = .string(decision.action)
        attributes["agentstudio.inbox.reason"] = .string(decision.reason)
        if let kind = decision.kind {
            attributes["agentstudio.inbox.kind"] = .string(kind.rawValue)
        }
        attributes["agentstudio.envelope.seq"] = .int(Int(envelope.seq))
        if let correlationId = envelope.correlationId {
            attributes["agentstudio.envelope.correlation_id"] = .string(correlationId.uuidString)
        }
        if let causationId = envelope.causationId {
            attributes["agentstudio.envelope.causation_id"] = .string(causationId.uuidString)
        }
        traceInboxRecord(body: "inbox.classify", attributes: attributes)
    }

    private func traceEventBusDelivery(_ decision: ClassificationDecision, envelope: PaneEnvelope) {
        guard shouldTraceClassificationDecision(decision, event: envelope.event) else { return }
        var attributes = RuntimeEnvelopeTraceSummary(envelope).attributes(
            eventBusName: "paneRuntime",
            consumerName: "InboxNotificationRouter"
        )
        attributes["agentstudio.eventbus.delivery"] = .string("consumed")
        attributes["agentstudio.inbox.decision"] = .string(decision.action)
        attributes["agentstudio.inbox.reason"] = .string(decision.reason)
        if let kind = decision.kind {
            attributes["agentstudio.inbox.kind"] = .string(kind.rawValue)
        }
        traceRecord(tag: .eventbus, body: "eventbus.deliver", attributes: attributes)
    }

    private func shouldTraceClassificationDecision(
        _ decision: ClassificationDecision,
        event: PaneRuntimeEvent
    ) -> Bool {
        if decision.kind != nil { return true }
        if RuntimeEnvelopeTraceSummary.isHighVolumeActivityOnly(event) {
            return false
        }
        return true
    }

    private func traceInboxMutation(
        body: String,
        paneId: UUID,
        attributes extraAttributes: [String: AgentStudioTraceValue]
    ) {
        var attributes = inboxTraceAttributes(paneId: paneId, event: nil)
        attributes.merge(extraAttributes) { current, _ in current }
        traceInboxRecord(body: body, attributes: attributes)
    }

    @discardableResult
    private func clearObservedPaneInboxRowsIfNeeded(
        paneId: UUID,
        scrollbarState: ScrollbarState? = nil,
        traceKeepOnly: Bool = true
    ) -> ObservedPaneClearOutcome {
        let isPinnedToBottom = scrollbarState?.isPinnedToBottom ?? isSourcePanePinnedToBottom(paneId)
        var clearedCount = 0
        var keepCount = 0
        var keepReason: String?
        for notification in inboxAtom.notifications where notification.paneId == paneId {
            guard !notification.isRead || !notification.isDismissedFromPaneInbox else { continue }
            let decision = autoClearPolicy.decision(
                notification: notification,
                isSourcePaneAttended: isSourcePaneObserved(paneId),
                isSourcePanePinnedToBottom: isPinnedToBottom
            )
            guard decision == .clear else {
                keepCount += 1
                if case .keep(let reason) = decision, keepReason == nil {
                    keepReason = reason
                }
                continue
            }
            let didMarkRead = inboxAtom.markRead(id: notification.id)
            let didDismiss = inboxAtom.dismissFromPaneInbox(id: notification.id)
            if didMarkRead || didDismiss {
                clearedCount += 1
            }
        }
        let outcome = ObservedPaneClearOutcome(
            clearedCount: clearedCount,
            keepCount: keepCount,
            reason: keepReason
        )
        guard clearedCount > 0 || (traceKeepOnly && keepCount > 0) else { return outcome }
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.pane_inbox.cleared_count": .int(clearedCount),
            "agentstudio.pane_inbox.keep_count": .int(keepCount),
            "agentstudio.pane.pinned_to_bottom": .bool(isPinnedToBottom),
        ]
        if let keepReason {
            attributes["agentstudio.inbox.reason"] = .string(keepReason)
        }
        traceInboxMutation(
            body: "inbox.observedPaneCleared",
            paneId: paneId,
            attributes: attributes
        )
        return outcome
    }

    private func clearObservedPaneInboxRowsForActiveTabIfNeeded(
        focusedPaneId: UUID
    ) -> ObservedPaneClearOutcome {
        let activePaneIds = tabLayout.activeTab?.activePaneIds ?? []
        var paneIds: [UUID] = [focusedPaneId]
        for paneId in activePaneIds where !paneIds.contains(paneId) {
            paneIds.append(paneId)
        }

        var clearedCount = 0
        var keepCount = 0
        var keepReason: String?
        for paneId in paneIds {
            let outcome = clearObservedPaneInboxRowsIfNeeded(paneId: paneId)
            clearedCount += outcome.clearedCount
            keepCount += outcome.keepCount
            keepReason = keepReason ?? outcome.reason
        }
        return ObservedPaneClearOutcome(
            clearedCount: clearedCount,
            keepCount: keepCount,
            reason: keepReason
        )
    }

    private func isSourcePaneObserved(_ paneId: UUID) -> Bool {
        if attendedPane.attendedPaneId == paneId { return true }
        guard attendedPane.attendedPaneId != nil else { return false }
        return tabLayout.activeTab?.activePaneIds.contains(paneId) == true
    }

    private func isSourcePanePinnedToBottom(_ paneId: UUID) -> Bool {
        pinnedToBottomByPaneId[paneId] ?? terminalActivity?.snapshot(for: paneId)?.isPinnedToBottom == true
    }

    private func traceRetentionOutcomeIfNeeded(
        _ outcome: InboxNotificationAtom.RetentionOutcome,
        paneId: UUID
    ) {
        guard outcome.droppedCount > 0 else { return }
        traceInboxMutation(
            body: "inbox.retention.dropped",
            paneId: paneId,
            attributes: [
                "agentstudio.inbox.dropped_count": .int(outcome.droppedCount),
                "agentstudio.notification.dropped_ids": .stringArray(
                    outcome.droppedNotificationIds.map(\.uuidString)
                ),
            ]
        )
    }

    private func inboxTraceAttributes(
        paneId: UUID,
        event: PaneRuntimeEvent?
    ) -> [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.inbox.global_unread_count": .int(inboxAtom.globalUnreadCount),
            "agentstudio.pane.attended": .bool(paneId == attendedPane.attendedPaneId),
            "agentstudio.pane.id": .string(paneId.uuidString),
        ]
        if let event {
            attributes["agentstudio.runtime.event"] = .string(event.traceEventName)
        }
        return attributes
    }

    private func traceInboxRecord(
        body: String,
        attributes: [String: AgentStudioTraceValue]
    ) {
        traceRecord(tag: .inbox, body: body, attributes: attributes)
    }

    private func traceRecord(
        tag: AgentStudioTraceTag,
        body: String,
        attributes: [String: AgentStudioTraceValue]
    ) {
        ensureTraceWorkerStarted()
        traceContinuation?.yield(
            .init(
                tag: tag,
                body: body,
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
            inboxNotificationRouterLogger.warning(
                "Inbox notification trace flush failed: \(error.localizedDescription); failedFlushCount=\(diagnostics.failedFlushCount); lastFlushError=\(diagnostics.lastFlushErrorDescription ?? "none")"
            )
        }
    }

    private func title(for event: PaneRuntimeEvent) -> String {
        switch event {
        case .terminal(.desktopNotificationRequested(let title, _)):
            return title
        case .agentNotificationRequested(let title, _):
            return title
        case .terminal(.bellRang):
            return "Bell"
        case .terminal(.commandFinished(let exitCode, _)):
            return exitCode == 0 ? "Command finished" : "Command failed"
        case .terminal(.secureInputChanged):
            return "Secure input requested"
        case .terminal(.progressReportUpdated):
            return "Terminal progress error"
        case .terminal(.rendererHealthChanged):
            return "Terminal renderer unhealthy"
        case .artifact(.approvalRequested):
            return "Approval requested"
        case .security(.networkEgressBlocked):
            return "Network egress blocked"
        case .security(.filesystemAccessDenied):
            return "Filesystem access denied"
        case .security(.secretAccessed):
            return "Secret accessed"
        case .security(.processSpawnBlocked):
            return "Process spawn blocked"
        case .security(.sandboxHealthChanged):
            return "Sandbox unhealthy"
        default:
            return "Notification"
        }
    }

    private func body(for event: PaneRuntimeEvent) -> String? {
        switch event {
        case .terminal(.desktopNotificationRequested(_, let body)):
            return body.isEmpty ? nil : body
        case .agentNotificationRequested(_, let body):
            return body?.isEmpty == true ? nil : body
        case .terminal(.commandFinished(let exitCode, let duration)):
            return "exit \(exitCode) · \(formattedDuration(duration))"
        case .terminal(.secureInputChanged(let isActive)):
            return isActive ? "terminal is waiting for hidden input" : nil
        case .terminal(.progressReportUpdated(let progress)):
            guard let progress else { return nil }
            guard let percent = progress.percent else { return "progress error" }
            return "progress \(percent)%"
        case .terminal(.rendererHealthChanged(let healthy)):
            return healthy ? nil : "renderer health transitioned to unhealthy"
        case .artifact(.approvalRequested(let request)):
            return request.summary
        case .security(.networkEgressBlocked(let destination, let rule)):
            return "\(destination) · \(rule)"
        case .security(.filesystemAccessDenied(let path, let operation)):
            return "\(operation) · \(path)"
        case .security(.secretAccessed(let secretId, let consumerId)):
            return "\(secretId) · \(consumerId)"
        case .security(.processSpawnBlocked(let command, let rule)):
            return "\(command) · \(rule)"
        case .security(.sandboxHealthChanged(let healthy)):
            return healthy ? nil : "health transitioned to unhealthy"
        default:
            return nil
        }
    }

    private func formattedDuration(_ nanoseconds: UInt64) -> String {
        let seconds = nanoseconds / 1_000_000_000
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }

    private func resolveContext(for paneId: UUID) -> ResolvedPaneContext? {
        guard let pane = paneAtom.pane(paneId) else { return nil }
        return ResolvedPaneContext(
            tabId: tabLayout.tabContaining(paneId: paneId)?.id,
            repoId: pane.repoId,
            repoName: pane.metadata.repoName,
            worktreeId: pane.worktreeId,
            worktreeName: pane.metadata.worktreeName,
            branchName: pane.metadata.checkoutRef
        )
    }
}

private struct ResolvedPaneContext {
    let tabId: UUID?
    let repoId: UUID?
    let repoName: String?
    let worktreeId: UUID?
    let worktreeName: String?
    let branchName: String?
}
