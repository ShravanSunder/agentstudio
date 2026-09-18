import Foundation

/// Closed observable boundaries for command execution. Individual App command
/// descriptors later select only the variants their existing owners can prove.
package enum IPCCommandResultVariant: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case applied
    case accepted
    case presented
    case unavailable
    case partial
    case uncertain

    package var schema: IPCJSONSchema {
        get throws {
            switch self {
            case .applied:
                IPCCommandResultSchemas.object(kind: self)
            case .accepted:
                IPCCommandResultSchemas.object(
                    kind: self,
                    fields: [
                        .optional(
                            "operationId",
                            description: "Existing owner operation UUID when one is available",
                            schema: IPCSchemaScalars.uuid
                        )
                    ]
                )
            case .presented:
                IPCCommandResultSchemas.object(kind: self)
            case .unavailable:
                IPCCommandResultSchemas.object(
                    kind: self,
                    fields: [
                        .init(
                            name: "reason",
                            description: "Stable reason the command is currently unavailable",
                            schema: try IPCCommandUnavailableReason.ipcSchema()
                        )
                    ]
                )
            case .partial:
                IPCCommandResultSchemas.object(
                    kind: self,
                    fields: [
                        .init(
                            name: "appliedEffects",
                            description: "Known effects applied before the remaining effects were rejected",
                            schema: .array(
                                items: IPCCommandResultSchemas.effectReference,
                                minimumCount: 1
                            )
                        ),
                        .init(
                            name: "reason",
                            description: "Stable scrubbed partial-result reason",
                            schema: try IPCCommandPartialReason.ipcSchema()
                        ),
                    ]
                )
            case .uncertain:
                IPCCommandResultSchemas.object(
                    kind: self,
                    fields: [
                        .init(
                            name: "reason",
                            description: "Stable reason command settlement is uncertain",
                            schema: try IPCCommandUncertainReason.ipcSchema()
                        )
                    ]
                )
            }
        }
    }
}

package enum IPCCommandUnavailableReason: String, CaseIterable, Codable, Equatable, Sendable,
    IPCSchemaProviding
{
    case featureUnavailable
    case noApplicableTarget
    case stateUnavailable
}

package enum IPCCommandPartialReason: String, CaseIterable, Codable, Equatable, Sendable,
    IPCSchemaProviding
{
    case ownerRejectedRemainingEffects
}

package enum IPCCommandUncertainReason: String, CaseIterable, Codable, Equatable, Sendable,
    IPCSchemaProviding
{
    case responseLostAfterSubmission
    case ownerSettlementUnknown
}

enum IPCCommandResultSchemas {
    static let effectReference = IPCJSONSchema.object(fields: [
        .init(
            name: "kind",
            description: "Kind of command effect identity",
            schema: .string(allowedValues: IPCHandleKind.allCases.map(\.rawValue))
        ),
        .init(
            name: "id",
            description: "Canonical UUID of the applied effect",
            schema: IPCSchemaScalars.uuid
        ),
    ])

    static func object(
        kind: IPCCommandResultVariant,
        fields: [IPCObjectField] = []
    ) -> IPCJSONSchema {
        .object(
            fields: [
                .init(
                    name: "kind",
                    description: "Closed command result boundary",
                    schema: .string(allowedValues: [kind.rawValue])
                ),
                .init(
                    name: "commandId",
                    description: "Open App-owned command identifier",
                    schema: .string(minimumLength: 1)
                ),
                .init(
                    name: "correlationId",
                    description: "Logical command UUID retained from the request",
                    schema: IPCSchemaScalars.uuid
                ),
            ] + fields)
    }
}
