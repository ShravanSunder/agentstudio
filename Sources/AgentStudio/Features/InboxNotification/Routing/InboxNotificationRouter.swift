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
    private let isPanePinnedToBottom: @MainActor (UUID) -> Bool
    private let focusTracker: PaneFocusTracker
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
    private var isPinnedToBottomByPaneId: [UUID: Bool] = [:]

    init(
        bus: EventBus<RuntimeEnvelope>,
        inboxAtom: InboxNotificationAtom,
        prefsAtom: InboxNotificationPrefsAtom,
        paneAtom: WorkspacePaneAtom,
        tabLayout: WorkspaceTabLayoutAtom,
        attendedPane: AttendedPaneAtom,
        isPanePinnedToBottom: @escaping @MainActor (UUID) -> Bool = { _ in false },
        focusTracker: PaneFocusTracker,
        autoClearPolicy: PaneInboxAutoClearPolicy = .init(),
        traceRuntime: AgentStudioTraceRuntime? = nil
    ) {
        self.bus = bus
        self.inboxAtom = inboxAtom
        self.prefsAtom = prefsAtom
        self.paneAtom = paneAtom
        self.tabLayout = tabLayout
        self.attendedPane = attendedPane
        self.isPanePinnedToBottom = isPanePinnedToBottom
        self.focusTracker = focusTracker
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
        isPinnedToBottomByPaneId.removeAll()
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
                if self.shouldAutoClearObservedPane(paneId) {
                    self.clearObservedPaneInboxRowsIfNeeded(paneId: paneId, unreadBefore: unreadBefore)
                }
                self.traceInboxMutation(
                    body: "inbox.focusGainedObservedPane",
                    paneId: paneId,
                    attributes: [
                        "agentstudio.inbox.unread_before": .int(unreadBefore),
                        "agentstudio.inbox.unread_after": .int(self.inboxAtom.unreadCount(forPaneId: paneId)),
                    ]
                )
            }
            if !Task.isCancelled {
                inboxNotificationRouterLogger.warning("Focus stream ended while inbox router was active")
            }
        }
    }

    private func shouldAutoClearObservedPane(_ paneId: UUID) -> Bool {
        guard attendedPane.attendedPaneId == paneId else { return false }
        return isPinnedToBottomByPaneId[paneId]
            ?? isPanePinnedToBottom(paneId)
    }

    private func clearObservedPaneInboxRowsIfNeeded(
        paneId: UUID,
        isPinnedToBottom: Bool,
        unreadBefore: Int? = nil
    ) {
        guard attendedPane.attendedPaneId == paneId, isPinnedToBottom else { return }
        clearObservedPaneInboxRowsIfNeeded(paneId: paneId, unreadBefore: unreadBefore)
    }

    private func clearObservedPaneInboxRowsIfNeeded(
        paneId: UUID,
        unreadBefore: Int? = nil
    ) {
        let unreadBefore = unreadBefore ?? inboxAtom.unreadCount(forPaneId: paneId)
        let matchingCount = inboxAtom.notifications.count { $0.paneId == paneId }
        let clearedCount = inboxAtom.autoClearPaneInbox(paneId: paneId) {
            autoClearPolicy.canAutoClear(kind: $0)
        }
        traceInboxMutation(
            body: "inbox.observedPaneCleared",
            paneId: paneId,
            attributes: [
                "agentstudio.inbox.cleared_count": .int(clearedCount),
                "agentstudio.inbox.keep_count": .int(matchingCount - clearedCount),
                "agentstudio.inbox.unread_before": .int(unreadBefore),
                "agentstudio.inbox.unread_after": .int(inboxAtom.unreadCount(forPaneId: paneId)),
            ]
        )
    }

    private func shouldAutoClearNewNotification(kind: InboxNotificationKind, paneId: UUID) -> Bool {
        shouldAutoClearObservedPane(paneId) && autoClearPolicy.canAutoClear(kind: kind)
    }

    private func handle(_ envelope: RuntimeEnvelope) {
        guard case .pane(let paneEnvelope) = envelope else { return }
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
        let shouldAutoClearNotification = shouldAutoClearNewNotification(kind: kind, paneId: paneId)
        let notification = InboxNotification(
            id: UUID(),
            timestamp: Date(),
            kind: kind,
            title: title(for: paneEnvelope.event),
            body: body(for: paneEnvelope.event),
            source: .pane(
                .init(
                    paneId: paneId,
                    tabId: resolvedContext?.tabId,
                    tabDisplayLabel: resolvedContext?.tabDisplayLabel,
                    repoId: resolvedContext?.repoId,
                    repoName: resolvedContext?.repoName,
                    worktreeId: resolvedContext?.worktreeId,
                    worktreeName: resolvedContext?.worktreeName,
                    branchName: resolvedContext?.branchName,
                    paneDisplayLabel: resolvedContext?.paneDisplayLabel,
                    paneRole: resolvedContext?.paneRole ?? .main,
                    parentPaneId: resolvedContext?.parentPaneId,
                    parentPaneDisplayLabel: resolvedContext?.parentPaneDisplayLabel,
                    drawerOrdinal: resolvedContext?.drawerOrdinal,
                    runtimeDisplayLabel: resolvedContext?.runtimeDisplayLabel
                )
            ),
            isRead: shouldAutoClearNotification,
            isDismissedFromPaneInbox: shouldAutoClearNotification
        )
        let globalUnreadBefore = inboxAtom.globalUnreadCount
        inboxAtom.append(notification)
        traceInboxMutation(
            body: "inbox.notification.appended",
            paneId: paneId,
            attributes: [
                "agentstudio.inbox.kind": .string(kind.rawValue),
                "agentstudio.inbox.notification.id": .string(notification.id.uuidString),
                "agentstudio.inbox.global_unread_before": .int(globalUnreadBefore),
                "agentstudio.inbox.global_unread_after": .int(inboxAtom.globalUnreadCount),
            ]
        )
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
        case .terminal(.scrollbarChanged(let state)):
            isPinnedToBottomByPaneId[envelope.paneId.uuid] = state.isPinnedToBottom
            clearObservedPaneInboxRowsIfNeeded(paneId: envelope.paneId.uuid, isPinnedToBottom: state.isPinnedToBottom)
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
        isPinnedToBottomByPaneId.removeValue(forKey: paneId)
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
            return normalizedString(title) ?? "Desktop notification"
        case .agentNotificationRequested(let title, _):
            return normalizedString(title) ?? "Agent notification"
        case .terminal(.bellRang):
            return "Bell"
        case .terminal(.commandFinished(let exitCode, _)):
            return exitCode == 0 ? "Command finished" : "Command failed (exit \(exitCode))"
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
        let milliseconds = (nanoseconds % 1_000_000_000) / 1_000_000
        if seconds == 0 {
            return "\(milliseconds)ms"
        }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }

    private func resolveContext(for paneId: UUID) -> ResolvedPaneContext? {
        guard let pane = paneAtom.pane(paneId) else { return nil }
        let tab = tabLayout.tabContaining(paneId: paneId)
        let parentPaneId = pane.parentPaneId
        let parentPane = parentPaneId.flatMap { paneAtom.pane($0) }
        let drawerOrdinal = parentPane?.drawer?.paneIds.firstIndex(of: paneId).map { $0 + 1 }
        return ResolvedPaneContext(
            tabId: tab?.id,
            tabDisplayLabel: tab.map(tabDisplayLabel),
            repoId: pane.repoId,
            repoName: pane.metadata.repoName,
            worktreeId: pane.worktreeId,
            worktreeName: pane.metadata.worktreeName,
            branchName: pane.metadata.checkoutRef,
            paneDisplayLabel: paneDisplayLabel(for: pane),
            paneRole: pane.isDrawerChild ? .drawerChild : .main,
            parentPaneId: parentPaneId,
            parentPaneDisplayLabel: parentPane.map(paneDisplayLabel),
            drawerOrdinal: drawerOrdinal,
            runtimeDisplayLabel: runtimeDisplayLabel(for: pane)
        )
    }

    private func tabDisplayLabel(for tab: Tab) -> String {
        let normalizedName = Tab.normalizedName(tab.name)
        if !normalizedName.isEmpty, normalizedName != "Tab" {
            return normalizedName
        }
        guard let tabIndex = tabLayout.tabs.firstIndex(where: { $0.id == tab.id }) else {
            return "Untitled Tab"
        }
        return "Tab \(tabIndex + 1)"
    }

    private func paneDisplayLabel(for pane: Pane) -> String {
        normalizedString(pane.title) ?? runtimeDisplayLabel(for: pane)
    }

    private func runtimeDisplayLabel(for pane: Pane) -> String {
        switch pane.content {
        case .terminal:
            return "Terminal"
        case .webview:
            return "Browser"
        case .bridgePanel(let bridgeState):
            switch bridgeState.panelKind {
            case .diffViewer:
                return "Diff"
            }
        case .codeViewer:
            return "Code"
        case .unsupported(let unsupported):
            return normalizedString(unsupported.type) ?? "Plugin"
        }
    }
}

private struct ResolvedPaneContext {
    let tabId: UUID?
    let tabDisplayLabel: String?
    let repoId: UUID?
    let repoName: String?
    let worktreeId: UUID?
    let worktreeName: String?
    let branchName: String?
    let paneDisplayLabel: String?
    let paneRole: InboxNotification.PaneSource.PaneRole
    let parentPaneId: UUID?
    let parentPaneDisplayLabel: String?
    let drawerOrdinal: Int?
    let runtimeDisplayLabel: String?
}

private func normalizedString(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
