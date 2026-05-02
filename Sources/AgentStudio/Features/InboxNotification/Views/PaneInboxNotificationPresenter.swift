import Foundation
import Observation

@MainActor
@Observable
final class PaneInboxNotificationPresenter {
    private(set) var request: PaneInboxRequest?
    private var presentedTarget: PaneInboxTarget?
    private let traceRuntime: AgentStudioTraceRuntime?

    init(traceRuntime: AgentStudioTraceRuntime? = nil) {
        self.traceRuntime = traceRuntime
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
            presentedTarget = target
        } else if presentedTarget == target {
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
    private func tracePaneInboxInteraction(
        body: String,
        parentPaneId: UUID,
        paneIds: [UUID],
        attributes extraAttributes: [String: AgentStudioTraceValue]
    ) {
        guard let traceRuntime else { return }
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.pane.parent_id": .string(parentPaneId.uuidString),
            "agentstudio.pane.scope_count": .int(paneIds.count),
            "agentstudio.pane.scope_ids": .stringArray(paneIds.map(\.uuidString)),
        ]
        attributes.merge(extraAttributes) { current, _ in current }
        let traceAttributes = attributes
        // Escapes MainActor so JSONL file work cannot contend with UI interaction handling.
        // swiftlint:disable:next no_task_detached
        Task.detached(priority: .utility) {
            await traceRuntime.record(
                tag: .paneInbox,
                body: body,
                attributes: traceAttributes
            )
        }
    }
}

private struct PaneInboxTarget: Equatable {
    let parentPaneId: UUID
    let paneIds: [UUID]
}

extension PaneInboxRequest {
    fileprivate var target: PaneInboxTarget {
        PaneInboxTarget(parentPaneId: parentPaneId, paneIds: paneIds)
    }
}
