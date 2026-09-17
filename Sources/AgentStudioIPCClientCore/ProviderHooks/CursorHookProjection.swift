import AgentStudioProgrammaticControl
import Foundation

/// The Cursor hook events this package installs. Every other event Cursor emits
/// is deliberately absent: an unprojected event is silence, never a nearby
/// lifecycle name.
///
/// There is no permission event here because Cursor has none. Its
/// permission-gating hooks ask the hook process for a decision; none of them
/// report that Cursor is waiting on the person.
package enum CursorHookEvent: String, CaseIterable, Equatable, Sendable {
    case sessionStart
    case beforeSubmitPrompt
    case preToolUse
    case subagentStart
    case subagentStop
    case stop
    case sessionEnd

    /// The Sessions lifecycle capability this hook event reports.
    package var projectedEventName: IPCSessionEventName {
        switch self {
        case .sessionStart: .sessionStart
        case .beforeSubmitPrompt: .turnStart
        case .preToolUse: .toolActivity
        case .subagentStart, .subagentStop: .subagentActivity
        case .stop: .turnDone
        case .sessionEnd: .sessionEnd
        }
    }
}

/// The subset of one Cursor hook's stdin document the projection reads.
/// Decoding ignores every other field, so a Cursor release that adds fields
/// keeps working and one that removes `conversation_id` fails loudly.
package struct CursorHookPayload: Decodable, Equatable, Sendable {
    package let conversationId: String
    package let hookEventName: String
    package let generationId: String?
    package let toolName: String?
    package let toolUseId: String?
    package let subagentId: String?

    package init(
        conversationId: String,
        hookEventName: String,
        generationId: String?,
        toolName: String?,
        toolUseId: String?,
        subagentId: String?
    ) {
        self.conversationId = conversationId
        self.hookEventName = hookEventName
        self.generationId = generationId
        self.toolName = toolName
        self.toolUseId = toolUseId
        self.subagentId = subagentId
    }

    private enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case hookEventName = "hook_event_name"
        case generationId = "generation_id"
        case toolName = "tool_name"
        case toolUseId = "tool_use_id"
        case subagentId = "subagent_id"
    }
}

/// Why one hook invocation produced no `session.event` call. Each case is a
/// silent, successful outcome for the hook process: Cursor must never see a
/// failure because Agent Studio declined an event.
package enum CursorHookProjectionRefusal: Equatable, Sendable {
    case unprojectedEvent(String)
    case announcedEventMismatch(announced: String, reported: String)
}

package enum CursorHookProjectionOutcome: Equatable, Sendable {
    case projected(IPCSessionEventParams)
    case refused(CursorHookProjectionRefusal)
}

/// Translates one Cursor hook document into one `session.event` call. Pure:
/// every identifier it cannot derive from the document is supplied by the
/// caller, so the projection is exercised without a socket or a clock.
package enum CursorHookProjection {
    /// - Parameters:
    ///   - announcedEvent: the event name the installed hook command passed as
    ///     its argument. It must agree with the document's `hook_event_name`; a
    ///     disagreement is refused rather than resolved by preference.
    ///   - providerVersion: the Cursor release recorded when the hooks were
    ///     installed.
    ///   - freshOccurrenceIdentifier: used whenever the document carries no
    ///     usable natural key for the work it describes.
    package static func project(
        announcedEvent: String,
        payload: CursorHookPayload,
        providerVersion: String,
        correlationIdentifier: UUID,
        freshOccurrenceIdentifier: () -> UUID
    ) -> CursorHookProjectionOutcome {
        guard payload.hookEventName == announcedEvent else {
            return .refused(
                .announcedEventMismatch(announced: announcedEvent, reported: payload.hookEventName)
            )
        }
        guard let event = CursorHookEvent(rawValue: payload.hookEventName) else {
            return .refused(.unprojectedEvent(payload.hookEventName))
        }
        let name = event.projectedEventName
        return .projected(
            IPCSessionEventParams(
                handle: "self",
                provider: IPCSessionProviderIdentity(
                    identifier: CursorProviderIdentity.identifier,
                    version: providerVersion,
                    mode: CursorProviderIdentity.operatingMode
                ),
                event: IPCSessionEventIdentity(
                    name: name,
                    conversationId: payload.conversationId,
                    turnId: CursorHookTurnIdentity.turnIdentifier(
                        conversationId: payload.conversationId,
                        generationId: payload.generationId
                    ),
                    // Cursor reports no event that asks the person for a
                    // decision, so nothing here is ever a permission request.
                    requestId: nil,
                    toolId: name == .toolActivity ? payload.toolUseId : nil,
                    subagentId: name == .subagentActivity ? payload.subagentId : nil,
                    occurrenceId: CursorHookOccurrenceIdentity.occurrenceIdentifier(
                        conversationId: payload.conversationId,
                        hookEventName: payload.hookEventName,
                        toolUseId: payload.toolUseId,
                        toolName: payload.toolName,
                        subagentId: payload.subagentId,
                        freshIdentifier: freshOccurrenceIdentifier
                    )
                ),
                correlationId: correlationIdentifier
            )
        )
    }
}

/// Decides whether one Cursor hook document carries a turn at all.
///
/// Cursor sends `generation_id` on every agent hook, but it is only a turn on
/// the events that belong to one. On `sessionStart`, `sessionEnd` and the tool
/// events it is filled in with the conversation's own identifier. Reporting
/// that as a turn would invent a turn the provider never started, so those
/// events report no turn instead.
///
/// `beforeSubmitPrompt` and `stop` do carry a real, distinct generation that is
/// shared across one turn, which is what lets turn-done record a result against
/// the turn that turn-start opened.
package enum CursorHookTurnIdentity {
    package static func turnIdentifier(conversationId: String, generationId: String?) -> String? {
        guard let generationId, !generationId.isEmpty, generationId != conversationId else {
            return nil
        }
        return generationId
    }
}

/// Derives the occurrence identity for one projected Cursor hook event.
///
/// Where Cursor offers a stable natural key for the work the event describes,
/// the identity is derived from it, so the same event retried by the same
/// conversation derives the same identifier and the app coalesces it. Without
/// one there is no natural key, and a fresh identifier is honest about that:
/// deduplication then rests on correlation alone.
///
/// Cursor's `tool_use_id` is per assistant-message chunk rather than per call —
/// two different tools invoked in one message were observed sharing one value —
/// so the tool name is part of the derived name. Two invocations of the *same*
/// tool inside one message still collide, and the second is refused as a
/// duplicate. That costs one tool breadcrumb and never any session state.
package enum CursorHookOccurrenceIdentity {
    package static func occurrenceIdentifier(
        conversationId: String,
        hookEventName: String,
        toolUseId: String?,
        toolName: String?,
        subagentId: String?,
        freshIdentifier: () -> UUID
    ) -> UUID {
        if let subagentId, !subagentId.isEmpty {
            return DeterministicUUIDv5.providerHookIdentifier(
                name: "cursor|\(conversationId)|\(hookEventName)|\(subagentId)"
            )
        }
        guard let toolUseId, !toolUseId.isEmpty else { return freshIdentifier() }
        return DeterministicUUIDv5.providerHookIdentifier(
            name: "cursor|\(conversationId)|\(hookEventName)|\(toolUseId)|\(toolName ?? "")"
        )
    }
}
