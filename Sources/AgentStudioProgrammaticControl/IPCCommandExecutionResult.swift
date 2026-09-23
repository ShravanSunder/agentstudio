import Foundation

package struct IPCCommandAppliedResult: Codable, Equatable, Sendable {
    package let commandId: IPCCommandIdentifier
    package let correlationId: UUID

    package init(commandId: IPCCommandIdentifier, correlationId: UUID) {
        self.commandId = commandId
        self.correlationId = correlationId
    }
}

package struct IPCCommandAcceptedResult: Codable, Equatable, Sendable {
    package let commandId: IPCCommandIdentifier
    package let correlationId: UUID
    package let operationId: UUID?

    package init(
        commandId: IPCCommandIdentifier,
        correlationId: UUID,
        operationId: UUID?
    ) {
        self.commandId = commandId
        self.correlationId = correlationId
        self.operationId = operationId
    }
}

package struct IPCCommandPresentedResult: Codable, Equatable, Sendable {
    package let commandId: IPCCommandIdentifier
    package let correlationId: UUID

    package init(commandId: IPCCommandIdentifier, correlationId: UUID) {
        self.commandId = commandId
        self.correlationId = correlationId
    }
}

package struct IPCCommandUnavailableResult: Codable, Equatable, Sendable {
    package let commandId: IPCCommandIdentifier
    package let correlationId: UUID
    package let reason: IPCCommandUnavailableReason

    package init(
        commandId: IPCCommandIdentifier,
        correlationId: UUID,
        reason: IPCCommandUnavailableReason
    ) {
        self.commandId = commandId
        self.correlationId = correlationId
        self.reason = reason
    }
}

package struct IPCCommandEffectReference: Codable, Equatable, Sendable {
    package let kind: IPCHandleKind
    package let id: UUID

    package init(kind: IPCHandleKind, id: UUID) {
        self.kind = kind
        self.id = id
    }
}

package struct IPCCommandPartialResult: Codable, Equatable, Sendable {
    package let commandId: IPCCommandIdentifier
    package let correlationId: UUID
    package let appliedEffects: [IPCCommandEffectReference]
    package let reason: IPCCommandPartialReason

    package init(
        commandId: IPCCommandIdentifier,
        correlationId: UUID,
        appliedEffects: [IPCCommandEffectReference],
        reason: IPCCommandPartialReason
    ) {
        self.commandId = commandId
        self.correlationId = correlationId
        self.appliedEffects = appliedEffects
        self.reason = reason
    }
}

package struct IPCCommandUncertainResult: Codable, Equatable, Sendable {
    package let commandId: IPCCommandIdentifier
    package let correlationId: UUID
    package let reason: IPCCommandUncertainReason

    package init(
        commandId: IPCCommandIdentifier,
        correlationId: UUID,
        reason: IPCCommandUncertainReason
    ) {
        self.commandId = commandId
        self.correlationId = correlationId
        self.reason = reason
    }
}

/// One truthful command boundary. The union owns the `kind` discriminator;
/// concrete receipt records remain reusable Codable data without standalone
/// schema claims.
package enum IPCCommandExecutionResult: IPCSchemaProviding, Equatable, Sendable {
    case applied(IPCCommandAppliedResult)
    case accepted(IPCCommandAcceptedResult)
    case presented(IPCCommandPresentedResult)
    case unavailable(IPCCommandUnavailableResult)
    case partial(IPCCommandPartialResult)
    case uncertain(IPCCommandUncertainResult)

    package var variant: IPCCommandResultVariant {
        switch self {
        case .applied: .applied
        case .accepted: .accepted
        case .presented: .presented
        case .unavailable: .unavailable
        case .partial: .partial
        case .uncertain: .uncertain
        }
    }

    package var commandId: IPCCommandIdentifier {
        switch self {
        case .applied(let result): result.commandId
        case .accepted(let result): result.commandId
        case .presented(let result): result.commandId
        case .unavailable(let result): result.commandId
        case .partial(let result): result.commandId
        case .uncertain(let result): result.commandId
        }
    }

    package var correlationId: UUID {
        switch self {
        case .applied(let result): result.correlationId
        case .accepted(let result): result.correlationId
        case .presented(let result): result.correlationId
        case .unavailable(let result): result.correlationId
        case .partial(let result): result.correlationId
        case .uncertain(let result): result.correlationId
        }
    }

    package static func ipcSchema(
        allowing variants: some Collection<IPCCommandResultVariant>
    ) throws -> IPCJSONSchema {
        let variants = Array(variants)
        guard !variants.isEmpty, Set(variants).count == variants.count else {
            throw IPCSchemaValidationError(
                fieldPath: "$",
                reason: .invalidDefinition,
                expected: "at least one unique command result variant"
            )
        }
        if variants.count == 1, let variant = variants.first {
            return try variant.schema
        }
        return try .oneOf(variants.map { try $0.schema })
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        try ipcSchema(allowing: IPCCommandResultVariant.allCases)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(IPCCommandResultVariant.self, forKey: .kind) {
        case .applied:
            self = .applied(try IPCCommandAppliedResult(from: decoder))
        case .accepted:
            self = .accepted(try IPCCommandAcceptedResult(from: decoder))
        case .presented:
            self = .presented(try IPCCommandPresentedResult(from: decoder))
        case .unavailable:
            self = .unavailable(try IPCCommandUnavailableResult(from: decoder))
        case .partial:
            self = .partial(try IPCCommandPartialResult(from: decoder))
        case .uncertain:
            self = .uncertain(try IPCCommandUncertainResult(from: decoder))
        }
    }

    package func encode(to encoder: any Encoder) throws {
        switch self {
        case .applied(let result): try encode(result, to: encoder)
        case .accepted(let result): try encode(result, to: encoder)
        case .presented(let result): try encode(result, to: encoder)
        case .unavailable(let result): try encode(result, to: encoder)
        case .partial(let result): try encode(result, to: encoder)
        case .uncertain(let result): try encode(result, to: encoder)
        }
    }

    private func encode<Result: Encodable>(
        _ result: Result,
        to encoder: any Encoder
    ) throws {
        try result.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(variant, forKey: .kind)
    }
}
