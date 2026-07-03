import Foundation
import Observation
import os.log

private let inboxNotificationRouterLogger = Logger(
    subsystem: "com.agentstudio",
    category: "InboxNotificationRouter"
)

@MainActor
final class InboxNotificationRouter {
    private struct ObservedPaneClearOutcome: Sendable, Equatable {
        let clearedCount: Int
        let keepCount: Int
        let reason: String?
    }

    private struct ObservedActivityNotification: Sendable, Hashable {
        let id: UUID
        let paneId: UUID
    }

    struct NotificationText: Sendable, Equatable {
        let title: String
        let body: String?
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
    private let traceQueue: AgentStudioTraceEventQueue?
    private let onPaneActivityObserved: @MainActor (UUID) -> Void
    private let drawerView: @MainActor (UUID) -> DrawerView?

    private var busTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var isStarted = false
    private var attendedPaneIdSnapshot: UUID?
    private var observedPaneIdsSnapshot: Set<UUID> = []
    private var observedActivityNotificationIds: Set<UUID> = []
    private var sandboxHealthWasHealthyByPaneId: [UUID: Bool] = [:]
    private var progressErrorWasActiveByPaneId: [UUID: Bool] = [:]
    private var rendererWasHealthyByPaneId: [UUID: Bool] = [:]
    private var secureInputWasActiveByPaneId: [UUID: Bool] = [:]
    private var pinnedToBottomByPaneId: [UUID: Bool] = [:]
    private lazy var promoter = InboxPromoter(
        inboxAtom: inboxAtom,
        autoClearPolicy: autoClearPolicy,
        policySnapshot: { [weak self] in
            self?.currentPolicySnapshot() ?? .init()
        },
        traceRuntime: traceRuntime
    )

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
        traceRuntime: AgentStudioTraceRuntime? = nil,
        drawerView: @escaping @MainActor (UUID) -> DrawerView? = {
            atom(\.arrangementView).drawerView(forParent: $0)
        },
        onPaneActivityObserved: @escaping @MainActor (UUID) -> Void = { _ in }
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
        self.traceQueue = traceRuntime.map(AgentStudioTraceEventQueue.init(traceRuntime:))
        self.drawerView = drawerView
        self.onPaneActivityObserved = onPaneActivityObserved
    }

    deinit {
        busTask?.cancel()
        focusTask?.cancel()
        traceQueue?.cancel()
    }

    func stop() async {
        isStarted = false
        let busTask = busTask
        busTask?.cancel()
        self.busTask = nil
        let focusTask = focusTask
        focusTask?.cancel()
        self.focusTask = nil
        await busTask?.value
        await focusTask?.value
        await promoter.drainTraceRecords()
        await drainTraceRecords()
        attendedPaneIdSnapshot = nil
        observedPaneIdsSnapshot.removeAll()
        observedActivityNotificationIds.removeAll()
        sandboxHealthWasHealthyByPaneId.removeAll()
        progressErrorWasActiveByPaneId.removeAll()
        rendererWasHealthyByPaneId.removeAll()
        secureInputWasActiveByPaneId.removeAll()
        pinnedToBottomByPaneId.removeAll()
    }

    func flushTraceRecords() async {
        do {
            try await traceQueue?.flush()
        } catch {
            let diagnostics = await traceRuntime?.diagnostics() ?? .empty
            inboxNotificationRouterLogger.warning(
                "Inbox notification trace flush failed: \(error.localizedDescription); failedFlushCount=\(diagnostics.failedFlushCount); lastFlushError=\(diagnostics.lastFlushErrorDescription ?? "none")"
            )
        }
    }

    func start() async {
        guard busTask == nil, focusTask == nil else { return }
        isStarted = true
        attendedPaneIdSnapshot = currentAttendedPaneId()
        observedPaneIdsSnapshot = currentObservedPaneIds()
        observedActivityNotificationIds = currentObservedActivityNotificationIds()
        observeCurrentSurface()
        let clearOutcome = clearObservedPaneInboxRowsForCurrentSurfaceIfNeeded(focusedPaneId: attendedPaneIdSnapshot)
        if let tracePaneId = attendedPaneIdSnapshot ?? observedPaneIdsSnapshot.first,
            clearOutcome.clearedCount > 0 || clearOutcome.keepCount > 0
        {
            traceInboxMutation(
                body: "inbox.startupObservedPaneCleared",
                paneId: tracePaneId,
                attributes: [
                    "agentstudio.pane_inbox.cleared_count": .int(clearOutcome.clearedCount),
                    "agentstudio.pane_inbox.keep_count": .int(clearOutcome.keepCount),
                ]
            )
        }
        observeObservedActivityNotifications()

        let stream = await bus.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "InboxNotificationRouter"
        )
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
                let focusedPaneId = self.currentAttendedPaneId()
                self.attendedPaneIdSnapshot = focusedPaneId
                self.observedPaneIdsSnapshot = self.currentObservedPaneIds()
                if let focusedPaneId {
                    self.onPaneActivityObserved(focusedPaneId)
                }
                let clearOutcome = self.clearObservedPaneInboxRowsForCurrentSurfaceIfNeeded(
                    focusedPaneId: focusedPaneId)
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

    private func observeCurrentSurface() {
        guard isStarted else { return }
        withObservationTracking {
            _ = attendedPane.attendedPaneId
            _ = paneAtom.panes
            _ = tabLayout.activeTab
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.reevaluateCurrentSurfaceObservation()
                self.observeCurrentSurface()
            }
        }
    }

    private func observeObservedActivityNotifications() {
        guard isStarted else { return }
        withObservationTracking {
            _ = inboxAtom.notifications
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.processObservedActivityNotifications()
                self.observeObservedActivityNotifications()
            }
        }
    }

    private func reevaluateCurrentSurfaceObservation() {
        let updatedAttendedPaneId = currentAttendedPaneId()
        let updatedObservedPaneIds = currentObservedPaneIds()
        guard
            updatedObservedPaneIds != observedPaneIdsSnapshot
                || updatedAttendedPaneId != attendedPaneIdSnapshot
        else {
            return
        }
        attendedPaneIdSnapshot = updatedAttendedPaneId
        observedPaneIdsSnapshot = updatedObservedPaneIds
        if let updatedAttendedPaneId {
            onPaneActivityObserved(updatedAttendedPaneId)
        }
        _ = clearObservedPaneInboxRowsForCurrentSurfaceIfNeeded(focusedPaneId: updatedAttendedPaneId)
    }

    private func processObservedActivityNotifications() {
        let observedNotifications = currentObservedActivityNotifications()
        let newObservedNotifications = observedNotifications.filter {
            !observedActivityNotificationIds.contains($0.id)
        }
        observedActivityNotificationIds = Set(observedNotifications.map(\.id))
        for notification in newObservedNotifications {
            onPaneActivityObserved(notification.paneId)
        }
    }

    private func currentObservedActivityNotificationIds() -> Set<UUID> {
        Set(currentObservedActivityNotifications().map(\.id))
    }

    private func currentObservedActivityNotifications() -> [ObservedActivityNotification] {
        inboxAtom.notifications.compactMap { notification in
            guard shouldInvalidateActivityWindow(notification),
                let paneId = notification.paneId,
                notification.isRead || notification.isDismissedFromPaneInbox
            else {
                return nil
            }
            return ObservedActivityNotification(id: notification.id, paneId: paneId)
        }
    }

    private func handle(_ envelope: RuntimeEnvelope) {
        guard case .pane(let paneEnvelope) = envelope else { return }
        if case .terminal(.scrollbarChanged(let scrollbarState)) = paneEnvelope.event {
            let wasPinnedToBottom = pinnedToBottomByPaneId[paneEnvelope.paneId.uuid] == true
            pinnedToBottomByPaneId[paneEnvelope.paneId.uuid] = scrollbarState.isPinnedToBottom
            if scrollbarState.isPinnedToBottom && !wasPinnedToBottom {
                clearObservedPaneInboxRowsIfNeeded(
                    paneId: paneEnvelope.paneId.uuid,
                    scrollbarState: scrollbarState,
                    traceKeepOnly: false
                )
            }
        }
        let decision = classify(paneEnvelope)
        traceEventBusDelivery(decision, envelope: paneEnvelope)
        traceClassificationDecision(decision, envelope: paneEnvelope)
        let paneId = paneEnvelope.paneId.uuid
        if handleAgentSettledRevocationIfNeeded(paneEnvelope, paneId: paneId) { return }
        guard let kind = decision.kind else { return }

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
            return
        }
        let paneSource = paneSource(paneId: paneId, resolvedContext: resolvedContext)
        let globalUnreadBefore = inboxAtom.globalUnreadCount
        if handleTerminalActivityPromotionIfNeeded(
            paneEnvelope,
            kind: kind,
            paneId: paneId,
            paneSource: paneSource,
            globalUnreadBefore: globalUnreadBefore
        ) {
            return
        }
        let notificationText = notificationText(for: paneEnvelope.event)
        let promotionOutcome = promoter.promoteExplicit(
            .init(
                kind: kind,
                title: notificationText.title,
                body: notificationText.body,
                semantic: claimSemantic(for: paneEnvelope.event),
                paneId: paneId,
                sessionId: nil,
                context: paneSource
            )
        )
        guard let mutationOutcome = promotionOutcome.mutationOutcome else { return }
        traceAppendedNotification(
            kind: kind, mutationOutcome: mutationOutcome, paneId: paneId, before: globalUnreadBefore)
        traceRetentionOutcomeIfNeeded(mutationOutcome.retentionOutcome, paneId: paneId)
    }

    private func handleAgentSettledRevocationIfNeeded(_ envelope: PaneEnvelope, paneId: UUID) -> Bool {
        guard case .terminalActivity(.agentSettledActivityRevoked) = envelope.event else { return false }
        let didRevoke = inboxAtom.revokeSettledAgentAttention(forPaneId: paneId)
        traceInboxMutation(
            body: "inbox.notification.agentSettledRevoked",
            paneId: paneId,
            attributes: [
                "agentstudio.inbox.notification.revoked": .bool(didRevoke),
                "agentstudio.inbox.global_unread_after": .int(inboxAtom.globalUnreadCount),
            ]
        )
        return true
    }

    private func handleTerminalActivityPromotionIfNeeded(
        _ envelope: PaneEnvelope,
        kind: InboxNotificationKind,
        paneId: UUID,
        paneSource: InboxNotification.PaneSource,
        globalUnreadBefore: Int
    ) -> Bool {
        guard case .terminalActivity(let terminalActivityEvent) = envelope.event else { return false }
        let promotionOutcome: InboxPromotionOutcome
        switch terminalActivityEvent {
        case .unseenActivitySettled(let activity):
            promotionOutcome = promoter.promoteSettledActivity(activity, paneId: paneId, context: paneSource)
        case .agentSettledActivityPromoted(let activity):
            promotionOutcome = promoter.promoteAgentSettledActivity(activity, paneId: paneId, context: paneSource)
        case .agentSettledActivityRevoked:
            return true
        }
        guard let mutationOutcome = promotionOutcome.mutationOutcome else { return true }
        traceAppendedNotification(
            kind: kind, mutationOutcome: mutationOutcome, paneId: paneId, before: globalUnreadBefore)
        traceRetentionOutcomeIfNeeded(mutationOutcome.retentionOutcome, paneId: paneId)
        return true
    }

    private func traceAppendedNotification(
        kind: InboxNotificationKind,
        mutationOutcome: InboxNotificationAtom.MutationOutcome,
        paneId: UUID,
        before globalUnreadBefore: Int
    ) {
        traceInboxMutation(
            body: "inbox.notification.appended",
            paneId: paneId,
            attributes: [
                "agentstudio.inbox.kind": .string(kind.rawValue),
                "agentstudio.inbox.notification.id": .string(mutationOutcome.notificationId.uuidString),
                "agentstudio.inbox.notification.coalesced": .bool(mutationOutcome.didCoalesce),
                "agentstudio.inbox.global_unread_before": .int(globalUnreadBefore),
                "agentstudio.inbox.global_unread_after": .int(inboxAtom.globalUnreadCount),
            ]
        )
    }

    private func classify(_ envelope: PaneEnvelope) -> ClassificationDecision {
        switch envelope.event {
        case .terminalActivity(.unseenActivitySettled):
            return .notify(.unseenActivity)
        case .terminalActivity(.agentSettledActivityPromoted):
            return .notify(.agentSettledActivity)
        case .terminalActivity(.agentSettledActivityRevoked):
            return .ignore(reason: "agent_settled_revocation")
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
            guard duration <= AppPolicies.InboxNotification.commandFinishedMaxTrustedDurationNanoseconds else {
                return .ignore(reason: "implausible_duration")
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
                if shouldInvalidateActivityWindow(notification) {
                    onPaneActivityObserved(paneId)
                }
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

    private func clearObservedPaneInboxRowsForCurrentSurfaceIfNeeded(
        focusedPaneId: UUID?
    ) -> ObservedPaneClearOutcome {
        let observedPaneIds = currentObservedPaneIds()
        var paneIds: [UUID] = []
        if let focusedPaneId {
            paneIds.append(focusedPaneId)
        }
        for paneId in observedPaneIds where !paneIds.contains(paneId) {
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
        currentObservedPaneIds().contains(paneId)
    }

    private func currentAttendedPaneId() -> UUID? {
        PaneObservationResolver.currentAttendedPaneId(
            attendedPaneId: attendedPane.attendedPaneId,
            pane: { paneAtom.pane($0) },
            drawerView: drawerView
        )
    }

    private func currentObservedPaneIds() -> Set<UUID> {
        PaneObservationResolver.currentObservedPaneIds(
            attendedPaneId: attendedPane.attendedPaneId,
            activeTab: tabLayout.activeTab,
            pane: { paneAtom.pane($0) },
            drawerView: drawerView
        )
    }

    private func isSourcePanePinnedToBottom(_ paneId: UUID) -> Bool {
        pinnedToBottomByPaneId[paneId] ?? terminalActivity?.snapshot(for: paneId)?.isPinnedToBottom == true
    }

    private func shouldInvalidateActivityWindow(_ notification: InboxNotification) -> Bool {
        notification.activityContext != nil || notification.claimKey?.sessionId != nil
    }

    private func currentPolicySnapshot() -> InboxPolicySnapshot {
        var pinnedByPaneId = terminalActivity?.snapshotsByPaneId.mapValues(\.isPinnedToBottom) ?? [:]
        pinnedByPaneId.merge(pinnedToBottomByPaneId) { _, latest in latest }
        return InboxPolicySnapshot(
            attendedPaneId: currentAttendedPaneId(),
            observedPaneIds: currentObservedPaneIds(),
            pinnedToBottomByPaneId: pinnedByPaneId
        )
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
            "agentstudio.pane.attended": .bool(paneId == currentAttendedPaneId()),
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
        traceQueue?.record(tag: tag, body: body, attributes: attributes)
    }

    private func drainTraceRecords() async {
        do {
            try await traceQueue?.drain()
        } catch {
            let diagnostics = await traceRuntime?.diagnostics() ?? .empty
            inboxNotificationRouterLogger.warning(
                "Inbox notification trace flush failed: \(error.localizedDescription); failedFlushCount=\(diagnostics.failedFlushCount); lastFlushError=\(diagnostics.lastFlushErrorDescription ?? "none")"
            )
        }
    }

}

extension InboxNotificationRouter {
    private func paneSource(
        paneId: UUID,
        resolvedContext: ResolvedPaneContext?
    ) -> InboxNotification.PaneSource {
        .init(
            paneId: paneId,
            tabId: resolvedContext?.tabId,
            tabDisplayLabel: resolvedContext?.tabDisplayLabel,
            tabOrdinal: resolvedContext?.tabOrdinal,
            repoId: resolvedContext?.repoId,
            repoName: resolvedContext?.repoName,
            worktreeId: resolvedContext?.worktreeId,
            worktreeName: resolvedContext?.worktreeName,
            branchName: resolvedContext?.branchName,
            paneDisplayLabel: resolvedContext?.paneDisplayLabel,
            paneOrdinal: resolvedContext?.paneOrdinal,
            paneRole: resolvedContext?.paneRole ?? .main,
            parentPaneId: resolvedContext?.parentPaneId,
            parentPaneDisplayLabel: resolvedContext?.parentPaneDisplayLabel,
            parentPaneOrdinal: resolvedContext?.parentPaneOrdinal,
            drawerOrdinal: resolvedContext?.drawerOrdinal,
            runtimeDisplayLabel: resolvedContext?.runtimeDisplayLabel
        )
    }

    private func resolveContext(for paneId: UUID) -> ResolvedPaneContext? {
        guard let pane = paneAtom.pane(paneId) else { return nil }
        let owningPaneId = pane.parentPaneId ?? paneId
        let tab = tabLayout.tabContaining(paneId: owningPaneId)
        let tabIndex = tab.flatMap { tab in
            tabLayout.tabs.firstIndex { $0.id == tab.id }
        }
        let owningPaneIndex = tab.flatMap { tab in
            tab.activePaneIds.firstIndex(of: owningPaneId)
        }
        let parentPane = pane.parentPaneId.flatMap { paneAtom.pane($0) }
        return ResolvedPaneContext(
            tabId: tab?.id,
            tabDisplayLabel: tab.flatMap(Self.displayLabel(for:)),
            tabOrdinal: tabIndex.map { $0 + 1 },
            repoId: pane.repoId,
            repoName: pane.metadata.repoName,
            worktreeId: pane.worktreeId,
            worktreeName: pane.metadata.worktreeName,
            branchName: pane.metadata.checkoutRef,
            paneDisplayLabel: Self.displayLabel(for: pane),
            paneOrdinal: pane.isDrawerChild ? nil : owningPaneIndex.map { $0 + 1 },
            paneRole: pane.isDrawerChild ? .drawerChild : .main,
            parentPaneId: pane.parentPaneId,
            parentPaneDisplayLabel: parentPane.flatMap(Self.displayLabel(for:)),
            parentPaneOrdinal: pane.isDrawerChild ? owningPaneIndex.map { $0 + 1 } : nil,
            drawerOrdinal: drawerOrdinal(for: paneId, parentPane: parentPane),
            runtimeDisplayLabel: Self.runtimeDisplayLabel(for: pane)
        )
    }

    private func drawerOrdinal(for paneId: UUID, parentPane: Pane?) -> Int? {
        guard let paneIds = parentPane?.drawer?.paneIds else { return nil }
        guard let index = paneIds.firstIndex(of: paneId) else { return nil }
        return index + 1
    }

    private static func displayLabel(for tab: Tab) -> String? {
        Tab.normalizedName(tab.name).trimmedNonEmpty
    }

    private static func displayLabel(for pane: Pane) -> String? {
        pane.metadata.title.trimmedNonEmpty
            ?? pane.metadata.worktreeName.trimmedNonEmpty
            ?? pane.metadata.checkoutRef.trimmedNonEmpty
            ?? runtimeDisplayLabel(for: pane)
    }

    private static func runtimeDisplayLabel(for pane: Pane) -> String {
        switch pane.content {
        case .terminal:
            return "Terminal"
        case .webview:
            return "Browser"
        case .bridgePanel(let state):
            switch state.panelKind {
            case .diffViewer:
                return "Diff"
            case .fileViewer:
                return "Files"
            }
        case .codeViewer:
            return "Code"
        case .unsupported(let content):
            return content.type.isEmpty ? "Pane" : content.type
        }
    }
}

private struct ResolvedPaneContext {
    let tabId: UUID?
    let tabDisplayLabel: String?
    let tabOrdinal: Int?
    let repoId: UUID?
    let repoName: String?
    let worktreeId: UUID?
    let worktreeName: String?
    let branchName: String?
    let paneDisplayLabel: String?
    let paneOrdinal: Int?
    let paneRole: InboxNotification.PaneSource.PaneRole
    let parentPaneId: UUID?
    let parentPaneDisplayLabel: String?
    let parentPaneOrdinal: Int?
    let drawerOrdinal: Int?
    let runtimeDisplayLabel: String?
}
