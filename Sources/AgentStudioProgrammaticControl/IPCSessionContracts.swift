import Foundation

/// Documented failure reasons the session methods declare. The descriptor's
/// error catalog, the app's error payload and the CLI's one-line model reply
/// all read these constants so the wire reason cannot drift between them.
package enum IPCSessionFailureReason {
    package static let bindingRequired = "bindingRequired"
    package static let correlationConflict = "correlationConflict"
}

/// Deliberate model vocabulary. The model never types a request identifier: the
/// app derives and coalesces the assertion identity behind these three verbs.
package enum IPCSessionReportKind: String, Codable, CaseIterable, Equatable, Sendable, IPCSchemaProviding {
    case needsYou
    case clearNeedsYou
    case done
}

/// Wire projection of the Sessions agent state. It mirrors the domain states
/// without exporting the domain type across the protocol boundary.
package enum IPCSessionAgentState: String, Codable, CaseIterable, Equatable, Sendable, IPCSchemaProviding {
    case unknown
    case running
    case needsYou
    case done
}

/// Server-assigned evidence origin. `unknown` reports the absence of a state
/// origin rather than inventing a weaker one.
package enum IPCSessionEvidenceOrigin: String, Codable, CaseIterable, Equatable, Sendable, IPCSchemaProviding {
    case unknown
    case estimated
    case agentReported
    case reported
}

/// Lifecycle capability a provider hook claims for one projected event.
package enum IPCSessionEventName: String, Codable, CaseIterable, Equatable, Sendable, IPCSchemaProviding {
    case sessionStart
    case sessionEnd
    case turnStart
    case turnDone
    case turnAbort
    case permission
    case question
    case elicitation
    case toolActivity
    case subagentActivity
}

/// Admission disposition for one projected provider event. Only an exactly
/// qualified provider/version/mode/capability is admitted.
package enum IPCSessionEventDisposition: String, Codable, CaseIterable, Equatable, Sendable, IPCSchemaProviding {
    case admitted
    case unknownCapability
    case unqualified
}

/// Liveness of the pane's current binding and source generation.
package enum IPCSessionSourceHealth: String, Codable, CaseIterable, Equatable, Sendable, IPCSchemaProviding {
    case unbound
    case live
    case ended
}

package struct IPCSessionReportParams: Codable, Equatable, Sendable {
    package let handle: String
    package let kind: IPCSessionReportKind
    package let explanation: String?
    package let correlationId: UUID

    package init(handle: String, kind: IPCSessionReportKind, explanation: String?, correlationId: UUID) {
        self.handle = handle
        self.kind = kind
        self.explanation = explanation
        self.correlationId = correlationId
    }
}

package struct IPCSessionReportResult: Codable, Equatable, Sendable {
    package let paneId: UUID
    package let state: IPCSessionAgentState
    package let origin: IPCSessionEvidenceOrigin
    package let requestId: String?
    package let correlationId: UUID

    package init(
        paneId: UUID,
        state: IPCSessionAgentState,
        origin: IPCSessionEvidenceOrigin,
        requestId: String?,
        correlationId: UUID
    ) {
        self.paneId = paneId
        self.state = state
        self.origin = origin
        self.requestId = requestId
        self.correlationId = correlationId
    }
}

package struct IPCSessionMessageParams: Codable, Equatable, Sendable {
    package let handle: String
    package let text: String
    package let correlationId: UUID

    package init(handle: String, text: String, correlationId: UUID) {
        self.handle = handle
        self.text = text
        self.correlationId = correlationId
    }
}

package struct IPCSessionMessageResult: Codable, Equatable, Sendable {
    package let paneId: UUID
    package let occurrenceId: UUID
    package let attributed: Bool
    package let correlationId: UUID

    package init(paneId: UUID, occurrenceId: UUID, attributed: Bool, correlationId: UUID) {
        self.paneId = paneId
        self.occurrenceId = occurrenceId
        self.attributed = attributed
        self.correlationId = correlationId
    }
}

package struct IPCSessionProviderIdentity: Codable, Equatable, Sendable {
    package let identifier: String
    package let version: String
    package let mode: String

    package init(identifier: String, version: String, mode: String) {
        self.identifier = identifier
        self.version = version
        self.mode = mode
    }
}

package struct IPCSessionEventIdentity: Codable, Equatable, Sendable {
    package let name: IPCSessionEventName
    package let conversationId: String
    package let turnId: String?
    package let requestId: String?
    package let toolId: String?
    package let subagentId: String?
    package let occurrenceId: UUID

    package init(
        name: IPCSessionEventName,
        conversationId: String,
        turnId: String?,
        requestId: String?,
        toolId: String?,
        subagentId: String?,
        occurrenceId: UUID
    ) {
        self.name = name
        self.conversationId = conversationId
        self.turnId = turnId
        self.requestId = requestId
        self.toolId = toolId
        self.subagentId = subagentId
        self.occurrenceId = occurrenceId
    }
}

package struct IPCSessionEventParams: Codable, Equatable, Sendable {
    package let handle: String
    package let provider: IPCSessionProviderIdentity
    package let event: IPCSessionEventIdentity
    package let correlationId: UUID

    package init(
        handle: String,
        provider: IPCSessionProviderIdentity,
        event: IPCSessionEventIdentity,
        correlationId: UUID
    ) {
        self.handle = handle
        self.provider = provider
        self.event = event
        self.correlationId = correlationId
    }
}

package struct IPCSessionEventResult: Codable, Equatable, Sendable {
    package let paneId: UUID
    package let disposition: IPCSessionEventDisposition
    package let correlationId: UUID

    package init(paneId: UUID, disposition: IPCSessionEventDisposition, correlationId: UUID) {
        self.paneId = paneId
        self.disposition = disposition
        self.correlationId = correlationId
    }
}

package struct IPCSessionQueryParams: Codable, Equatable, Sendable {
    package let handle: String

    package init(handle: String) {
        self.handle = handle
    }
}

package struct IPCSessionAttentionProjection: Codable, Equatable, Sendable {
    package let requestId: String
    package let explanation: String?

    package init(requestId: String, explanation: String?) {
        self.requestId = requestId
        self.explanation = explanation
    }
}

package struct IPCSessionMessageProjection: Codable, Equatable, Sendable {
    package let occurrenceId: UUID
    package let text: String
    package let seen: Bool
    package let receivedAt: Date

    package init(occurrenceId: UUID, text: String, seen: Bool, receivedAt: Date) {
        self.occurrenceId = occurrenceId
        self.text = text
        self.seen = seen
        self.receivedAt = receivedAt
    }
}

package struct IPCSessionQueryResult: Codable, Equatable, Sendable {
    package let paneId: UUID
    package let state: IPCSessionAgentState
    package let origin: IPCSessionEvidenceOrigin
    package let needsYou: IPCSessionAttentionProjection?
    package let messages: [IPCSessionMessageProjection]
    package let sourceHealth: IPCSessionSourceHealth

    package init(
        paneId: UUID,
        state: IPCSessionAgentState,
        origin: IPCSessionEvidenceOrigin,
        needsYou: IPCSessionAttentionProjection?,
        messages: [IPCSessionMessageProjection],
        sourceHealth: IPCSessionSourceHealth
    ) {
        self.paneId = paneId
        self.state = state
        self.origin = origin
        self.needsYou = needsYou
        self.messages = messages
        self.sourceHealth = sourceHealth
    }
}
