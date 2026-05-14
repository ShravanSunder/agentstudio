import Foundation
import Observation
import os.log

private let paneInboxNotificationPresenterLogger = Logger(
    subsystem: "com.agentstudio",
    category: "PaneInboxNotificationPresenter"
)

@MainActor
@Observable
final class PaneInboxNotificationPresenter {
    private(set) var request: PaneInboxRequest?
    private var presentedTarget: PaneInboxTarget?
    private let traceQueue: AgentStudioTraceEventQueue?

    init(traceRuntime: AgentStudioTraceRuntime? = nil) {
        self.traceQueue = traceRuntime.map(AgentStudioTraceEventQueue.init(traceRuntime:))
    }

    deinit {
        traceQueue?.cancel()
    }

    func open(parentPaneId: UUID, paneIds: [UUID]) {
        request = PaneInboxRequest(id: UUID(), parentPaneId: parentPaneId, paneIds: paneIds, intent: .open)
        tracePaneInboxInteraction(
            body: "paneInbox.requested",
            parentPaneId: parentPaneId,
            paneIds: paneIds,
            attributes: ["agentstudio.pane_inbox.intent": .string("open")]
        )
    }

    func toggle(parentPaneId: UUID, paneIds: [UUID]) {
        let target = PaneInboxTarget(parentPaneId: parentPaneId, paneIds: paneIds)
        if presentedTarget == target {
            request = PaneInboxRequest(id: UUID(), parentPaneId: parentPaneId, paneIds: paneIds, intent: .close)
            tracePaneInboxInteraction(
                body: "paneInbox.requested",
                parentPaneId: parentPaneId,
                paneIds: paneIds,
                attributes: ["agentstudio.pane_inbox.intent": .string("close")]
            )
            return
        }

        if request?.target == target, request?.intent == .open {
            request = nil
            tracePaneInboxInteraction(
                body: "paneInbox.requestCancelled",
                parentPaneId: parentPaneId,
                paneIds: paneIds,
                attributes: ["agentstudio.pane_inbox.intent": .string("open")]
            )
            return
        }

        open(parentPaneId: parentPaneId, paneIds: paneIds)
    }

    func setPresented(parentPaneId: UUID, paneIds: [UUID], isPresented: Bool) {
        let target = PaneInboxTarget(parentPaneId: parentPaneId, paneIds: paneIds)
        if isPresented {
            guard presentedTarget != target else { return }
            presentedTarget = target
        } else {
            guard presentedTarget == target else { return }
            presentedTarget = nil
        }
        tracePaneInboxInteraction(
            body: "paneInbox.presentationChanged",
            parentPaneId: parentPaneId,
            paneIds: paneIds,
            attributes: ["agentstudio.pane_inbox.presented": .bool(isPresented)]
        )
    }

    func clearRequest(_ request: PaneInboxRequest) {
        guard self.request == request else { return }
        self.request = nil
    }

    func recordRowActivation(notification: InboxNotification, paneIds: [UUID]) {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.action.name": .string("focusPane"),
            "agentstudio.notification.id": .string(notification.id.uuidString),
            "agentstudio.notification.kind": .string(notification.kind.rawValue),
            "agentstudio.pane.scope_count": .int(paneIds.count),
            "agentstudio.pane.scope_ids": .stringArray(paneIds.map(\.uuidString)),
        ]
        if let parentPaneId = paneIds.first {
            attributes["agentstudio.pane.parent_id"] = .string(parentPaneId.uuidString)
        }
        if let paneId = notification.paneId {
            attributes["agentstudio.pane.id"] = .string(paneId.uuidString)
        }
        tracePaneInboxInteraction(
            body: "paneInbox.rowActivation",
            attributes: attributes
        )
    }

    func drainTraceRecords() async {
        do {
            try await traceQueue?.drain()
        } catch {
            paneInboxNotificationPresenterLogger.warning(
                "Pane inbox presenter trace drain failed: \(error.localizedDescription)"
            )
        }
    }

    private func tracePaneInboxInteraction(
        body: String,
        parentPaneId: UUID,
        paneIds: [UUID],
        attributes extraAttributes: [String: AgentStudioTraceValue]
    ) {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.pane.parent_id": .string(parentPaneId.uuidString),
            "agentstudio.pane.scope_count": .int(paneIds.count),
            "agentstudio.pane.scope_ids": .stringArray(paneIds.map(\.uuidString)),
        ]
        attributes.merge(extraAttributes) { current, _ in current }
        traceQueue?.record(tag: .paneInbox, body: body, attributes: attributes)
    }

    private func tracePaneInboxInteraction(
        body: String,
        attributes: [String: AgentStudioTraceValue]
    ) {
        traceQueue?.record(tag: .paneInbox, body: body, attributes: attributes)
    }
}

private struct PaneInboxTarget: Equatable {
    let parentPaneId: UUID
    let paneIdSet: Set<UUID>

    init(parentPaneId: UUID, paneIds: [UUID]) {
        self.parentPaneId = parentPaneId
        self.paneIdSet = Set(paneIds)
    }
}

extension PaneInboxRequest {
    fileprivate var target: PaneInboxTarget {
        PaneInboxTarget(parentPaneId: parentPaneId, paneIds: paneIds)
    }
}
