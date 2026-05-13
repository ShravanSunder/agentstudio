import Foundation
import os.log

private let inboxPromoterLogger = Logger(
    subsystem: "com.agentstudio",
    category: "InboxPromoter"
)

struct InboxPolicySnapshot: Sendable, Equatable {
    var attendedPaneId: UUID?
    var observedPaneIds: Set<UUID>
    var pinnedToBottomByPaneId: [UUID: Bool]

    init(
        attendedPaneId: UUID? = nil,
        observedPaneIds: Set<UUID> = [],
        pinnedToBottomByPaneId: [UUID: Bool] = [:]
    ) {
        self.attendedPaneId = attendedPaneId
        self.observedPaneIds = observedPaneIds
        self.pinnedToBottomByPaneId = pinnedToBottomByPaneId
    }

    func isPaneAttended(_ paneId: UUID) -> Bool {
        attendedPaneId == paneId
    }

    func isPaneObserved(_ paneId: UUID) -> Bool {
        observedPaneIds.contains(paneId) || isPaneAttended(paneId)
    }

    func isPanePinnedToBottom(_ paneId: UUID) -> Bool {
        pinnedToBottomByPaneId[paneId] == true
    }
}

struct InboxExplicitPromotionRequest: Sendable, Equatable {
    let kind: InboxNotificationKind
    let title: String
    let body: String?
    let semantic: InboxNotificationClaimSemantic
    let paneId: UUID
    let sessionId: UUID?
    let context: InboxNotification.PaneSource
}

struct InboxPromotionOutcome: Sendable, Equatable {
    let mutationOutcome: InboxNotificationAtom.MutationOutcome?
    let reason: String

    var didMutate: Bool {
        mutationOutcome != nil
    }
}

@MainActor
final class InboxPromoter {
    private struct PromotionTrace: Sendable {
        let decision: String
        let reason: String
        let paneId: UUID
        let kind: InboxNotificationKind
        let claimKey: InboxNotificationClaimKey?
        let activity: TerminalSettledActivity?
        let didCoalesce: Bool
        let isRead: Bool
        let isDismissedFromPaneInbox: Bool
        let snapshot: InboxPolicySnapshot
    }

    private let inboxAtom: InboxNotificationAtom
    private let autoClearPolicy: PaneInboxAutoClearPolicy
    private let policySnapshot: () -> InboxPolicySnapshot
    private let traceQueue: AgentStudioTraceEventQueue?
    private let sessionIdleTimeoutSeconds: TimeInterval
    private let now: () -> Date

    init(
        inboxAtom: InboxNotificationAtom,
        autoClearPolicy: PaneInboxAutoClearPolicy,
        policySnapshot: @escaping () -> InboxPolicySnapshot,
        traceRuntime: AgentStudioTraceRuntime?,
        sessionIdleTimeout: Duration = AppPolicies.InboxNotification.terminalActivitySessionIdleTimeoutDuration,
        now: @escaping () -> Date = Date.init
    ) {
        self.inboxAtom = inboxAtom
        self.autoClearPolicy = autoClearPolicy
        self.policySnapshot = policySnapshot
        self.traceQueue = traceRuntime.map(AgentStudioTraceEventQueue.init(traceRuntime:))
        self.sessionIdleTimeoutSeconds = Self.seconds(from: sessionIdleTimeout)
        self.now = now
    }

    deinit {
        traceQueue?.cancel()
    }

    func drainTraceRecords() async {
        do {
            try await traceQueue?.drain()
        } catch {
            inboxPromoterLogger.warning("Inbox promoter trace drain failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func promoteSettledActivity(
        _ activity: TerminalSettledActivity,
        paneId: UUID,
        context: InboxNotification.PaneSource
    ) -> InboxPromotionOutcome {
        let snapshot = policySnapshot()
        let isPinnedToBottom = activity.isPinnedToBottom || snapshot.isPanePinnedToBottom(paneId)
        if snapshot.isPaneObserved(paneId),
            isPinnedToBottom,
            activity.rowsAdded < activity.thresholdRows
        {
            let reason = "observed_small_activity"
            tracePromotion(
                .init(
                    decision: "suppress",
                    reason: reason,
                    paneId: paneId,
                    kind: .unseenActivity,
                    claimKey: nil,
                    activity: activity,
                    didCoalesce: false,
                    isRead: true,
                    isDismissedFromPaneInbox: true,
                    snapshot: snapshot
                ))
            return .init(mutationOutcome: nil, reason: reason)
        }

        let sessionId = resolveActivitySessionId(for: paneId, snapshot: snapshot)
        let shouldAppendReadDismissed =
            snapshot.isPaneAttended(paneId)
            || (snapshot.isPaneObserved(paneId) && isPinnedToBottom)
        let claimKey = InboxNotificationClaimKey(
            paneId: paneId,
            lane: .activity,
            semantic: .unseenActivity,
            sessionId: sessionId
        )
        let notification = InboxNotification(
            id: UUID(),
            timestamp: now(),
            kind: .unseenActivity,
            title: "New terminal activity",
            body: "Output appeared while you were away",
            source: .pane(context),
            activityContext: .init(
                burstWindowId: activity.burstWindowId,
                activitySessionId: sessionId,
                eventCount: activity.eventCount,
                rowsAdded: activity.rowsAdded,
                thresholdRows: activity.thresholdRows,
                latestRows: activity.latestRows
            ),
            claimKey: claimKey,
            isRead: shouldAppendReadDismissed,
            isDismissedFromPaneInbox: shouldAppendReadDismissed
        )
        let outcome = inboxAtom.upsertByClaim(notification, merge: merge(existing:incoming:))
        let reason = outcome.didCoalesce ? "claim_coalesced" : "claim_appended"
        tracePromotion(
            .init(
                decision: "promote",
                reason: reason,
                paneId: paneId,
                kind: notification.kind,
                claimKey: claimKey,
                activity: activity,
                didCoalesce: outcome.didCoalesce,
                isRead: notification.isRead,
                isDismissedFromPaneInbox: notification.isDismissedFromPaneInbox,
                snapshot: snapshot
            ))
        return .init(mutationOutcome: outcome, reason: reason)
    }

    @discardableResult
    func promoteExplicit(_ request: InboxExplicitPromotionRequest) -> InboxPromotionOutcome {
        let snapshot = policySnapshot()
        let lane = lane(for: request.semantic)
        let resolvedSessionId =
            request.sessionId
            ?? resolveExplicitSessionId(
                paneId: request.paneId,
                lane: lane,
                semantic: request.semantic,
                snapshot: snapshot
            )
        let claimKey = InboxNotificationClaimKey(
            paneId: request.paneId,
            lane: lane,
            semantic: request.semantic,
            sessionId: resolvedSessionId
        )
        var notification = InboxNotification(
            id: UUID(),
            timestamp: now(),
            kind: request.kind,
            title: request.title,
            body: request.body,
            source: .pane(request.context),
            claimKey: claimKey,
            isRead: false,
            isDismissedFromPaneInbox: false
        )
        if shouldAppendAsReadDismissed(notification, paneId: request.paneId, snapshot: snapshot) {
            notification.isRead = true
            notification.isDismissedFromPaneInbox = true
        }
        let outcome = inboxAtom.upsertByClaim(notification, merge: merge(existing:incoming:))
        let reason = outcome.didCoalesce ? "claim_coalesced" : "claim_appended"
        tracePromotion(
            .init(
                decision: "promote",
                reason: reason,
                paneId: request.paneId,
                kind: notification.kind,
                claimKey: claimKey,
                activity: nil,
                didCoalesce: outcome.didCoalesce,
                isRead: notification.isRead,
                isDismissedFromPaneInbox: notification.isDismissedFromPaneInbox,
                snapshot: snapshot
            ))
        return .init(mutationOutcome: outcome, reason: reason)
    }

    private func resolveActivitySessionId(for paneId: UUID, snapshot: InboxPolicySnapshot) -> UUID {
        activeSessionId(for: paneId, snapshot: snapshot) ?? UUID()
    }

    private func resolveExplicitSessionId(
        paneId: UUID,
        lane: InboxNotificationClaimLane,
        semantic: InboxNotificationClaimSemantic,
        snapshot: InboxPolicySnapshot
    ) -> UUID? {
        guard lane.canMergeWithinActivitySession else { return nil }
        if let activeSessionId = activeSessionId(for: paneId, snapshot: snapshot) {
            return activeSessionId
        }
        switch semantic {
        case .agentRpc, .desktopNotification, .bell, .commandFinished:
            return UUID()
        case .approvalRequested, .secureInput, .progressError, .rendererUnhealthy, .persistenceRecovery,
            .securityEvent, .unseenActivity:
            return nil
        }
    }

    private func activeSessionId(for paneId: UUID, snapshot: InboxPolicySnapshot) -> UUID? {
        let sessionActivityCutoff = now().addingTimeInterval(-sessionIdleTimeoutSeconds)
        return inboxAtom.notifications.first { notification in
            guard
                let claimKey = notification.claimKey,
                claimKey.paneId == paneId,
                claimKey.lane.canMergeWithinActivitySession
            else {
                return false
            }
            let isUnreadActiveClaim = !notification.isRead && !notification.isDismissedFromPaneInbox
            let isObservedAtBottom =
                snapshot.isPaneAttended(paneId)
                || (snapshot.isPaneObserved(paneId) && snapshot.isPanePinnedToBottom(paneId))
            let isObservedHistoryClaim =
                notification.isRead
                && notification.isDismissedFromPaneInbox
                && isObservedAtBottom
                && notification.timestamp >= sessionActivityCutoff
            guard isUnreadActiveClaim || isObservedHistoryClaim else { return false }
            return claimKey.sessionId != nil
        }?.claimKey?.sessionId
    }

    private func merge(
        existing: InboxNotification,
        incoming: InboxNotification
    ) -> InboxNotification {
        let incomingIsMoreSpecific = priority(for: incoming.claimKey?.lane) < priority(for: existing.claimKey?.lane)
        let displaySource = incomingIsMoreSpecific ? incoming : existing
        return InboxNotification(
            id: existing.id,
            timestamp: incoming.timestamp,
            kind: displaySource.kind,
            title: displaySource.title,
            body: displaySource.body,
            source: mergedSource(
                preferred: displaySource.source,
                fallback: incomingIsMoreSpecific ? existing.source : incoming.source
            ),
            activityContext: mergedActivityContext(existing.activityContext, incoming.activityContext),
            claimKey: strongerClaimKey(existing: existing.claimKey, incoming: incoming.claimKey),
            isRead: existing.isRead || incoming.isRead,
            isDismissedFromPaneInbox: existing.isDismissedFromPaneInbox || incoming.isDismissedFromPaneInbox
        )
    }

    private func priority(for lane: InboxNotificationClaimLane?) -> Int {
        switch lane {
        case .actionNeeded:
            return 0
        case .safety:
            return 1
        case .activity:
            return 2
        case nil:
            return 3
        }
    }

    private func strongerClaimKey(
        existing: InboxNotificationClaimKey?,
        incoming: InboxNotificationClaimKey?
    ) -> InboxNotificationClaimKey? {
        guard let existing else { return incoming }
        guard let incoming else { return existing }
        return priority(for: incoming.lane) < priority(for: existing.lane) ? incoming : existing
    }

    private func mergedActivityContext(
        _ existing: InboxNotification.ActivityContext?,
        _ incoming: InboxNotification.ActivityContext?
    ) -> InboxNotification.ActivityContext? {
        guard let existing else { return incoming }
        guard let incoming else { return existing }
        return existing.coalesced(with: incoming)
    }

    private func mergedSource(
        preferred: InboxNotification.Source,
        fallback: InboxNotification.Source
    ) -> InboxNotification.Source {
        switch (preferred, fallback) {
        case (.pane(let preferredPane), .pane(let fallbackPane)):
            return .pane(mergedPaneSource(preferred: preferredPane, fallback: fallbackPane))
        case (.pane, .global):
            return preferred
        case (.global, .pane):
            return fallback
        case (.global, .global):
            return .global
        }
    }

    private func mergedPaneSource(
        preferred: InboxNotification.PaneSource,
        fallback: InboxNotification.PaneSource
    ) -> InboxNotification.PaneSource {
        .init(
            paneId: preferred.paneId,
            tabId: preferred.tabId ?? fallback.tabId,
            tabDisplayLabel: preferred.tabDisplayLabel ?? fallback.tabDisplayLabel,
            repoId: preferred.repo?.id ?? fallback.repo?.id,
            repoName: preferred.repo?.name ?? fallback.repo?.name,
            worktreeId: preferred.worktree?.id ?? fallback.worktree?.id,
            worktreeName: preferred.worktree?.name ?? fallback.worktree?.name,
            branchName: preferred.branchName ?? fallback.branchName,
            paneDisplayLabel: preferred.paneDisplayLabel ?? fallback.paneDisplayLabel,
            paneRole: paneRole(preferred: preferred, fallback: fallback),
            parentPaneId: preferred.parentPaneId ?? fallback.parentPaneId,
            parentPaneDisplayLabel: preferred.parentPaneDisplayLabel ?? fallback.parentPaneDisplayLabel,
            drawerOrdinal: preferred.drawerOrdinal ?? fallback.drawerOrdinal,
            runtimeDisplayLabel: preferred.runtimeDisplayLabel ?? fallback.runtimeDisplayLabel
        )
    }

    private func paneRole(
        preferred: InboxNotification.PaneSource,
        fallback: InboxNotification.PaneSource
    ) -> InboxNotification.PaneSource.PaneRole {
        guard preferred.parentPaneId == nil, preferred.drawerOrdinal == nil else { return preferred.paneRole }
        return fallback.parentPaneId != nil || fallback.drawerOrdinal != nil ? fallback.paneRole : preferred.paneRole
    }

    private func lane(for semantic: InboxNotificationClaimSemantic) -> InboxNotificationClaimLane {
        switch semantic {
        case .approvalRequested:
            return .actionNeeded
        case .secureInput, .progressError, .rendererUnhealthy, .persistenceRecovery, .securityEvent:
            return .safety
        case .unseenActivity, .commandFinished, .bell, .desktopNotification, .agentRpc:
            return .activity
        }
    }

    private func shouldAppendAsReadDismissed(
        _ notification: InboxNotification,
        paneId: UUID,
        snapshot: InboxPolicySnapshot
    ) -> Bool {
        let isAutoClearable =
            autoClearPolicy.decision(
                notification: notification,
                isSourcePaneAttended: true,
                isSourcePanePinnedToBottom: true
            ) == .clear
        guard isAutoClearable else { return false }
        guard !snapshot.isPaneAttended(paneId) else { return true }
        return autoClearPolicy.decision(
            notification: notification,
            isSourcePaneAttended: snapshot.isPaneObserved(paneId),
            isSourcePanePinnedToBottom: snapshot.isPanePinnedToBottom(paneId)
        ) == .clear
    }

    private func tracePromotion(_ trace: PromotionTrace) {
        guard let traceQueue else { return }
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.inbox.decision": .string(trace.decision),
            "agentstudio.inbox.kind": .string(trace.kind.rawValue),
            "agentstudio.inbox.notification.coalesced": .bool(trace.didCoalesce),
            "agentstudio.inbox.read": .bool(trace.isRead),
            "agentstudio.inbox.reason": .string(trace.reason),
            "agentstudio.pane.attended": .bool(trace.snapshot.isPaneAttended(trace.paneId)),
            "agentstudio.pane.id": .string(trace.paneId.uuidString),
            "agentstudio.pane.observed": .bool(trace.snapshot.isPaneObserved(trace.paneId)),
            "agentstudio.pane.pinned_to_bottom": .bool(trace.snapshot.isPanePinnedToBottom(trace.paneId)),
            "agentstudio.pane_inbox.dismissed": .bool(trace.isDismissedFromPaneInbox),
        ]
        if let claimKey = trace.claimKey {
            attributes["agentstudio.inbox.claim.lane"] = .string(claimKey.lane.rawValue)
            attributes["agentstudio.inbox.claim.semantic"] = .string(claimKey.semantic.rawValue)
            if let sessionId = claimKey.sessionId {
                attributes["agentstudio.inbox.claim.session_id"] = .string(sessionId.uuidString)
            }
        }
        if let activity = trace.activity {
            attributes["terminal.activity.debounce_ms"] = .int(activity.debounceMilliseconds)
            attributes["terminal.activity.event_count"] = .int(activity.eventCount)
            attributes["terminal.activity.is_pinned_to_bottom"] = .bool(activity.isPinnedToBottom)
            attributes["terminal.activity.latest_rows"] = .int(activity.latestRows)
            attributes["terminal.activity.rows_added"] = .int(activity.rowsAdded)
            attributes["terminal.activity.source"] = .string("scrollbar")
            attributes["terminal.activity.threshold_rows"] = .int(activity.thresholdRows)
            attributes["terminal.activity.window_id"] = .string(activity.burstWindowId.uuidString)
            if let activitySessionId = trace.claimKey?.sessionId {
                attributes["terminal.activity.session_id"] = .string(activitySessionId.uuidString)
            }
        }
        traceQueue.record(tag: .inbox, body: "inbox.promote", attributes: attributes)
    }

    private static func seconds(from duration: Duration) -> TimeInterval {
        let attosecondsPerSecond: Double = 1_000_000_000_000_000_000
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / attosecondsPerSecond
    }
}
