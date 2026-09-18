import Foundation

package struct IPCCommandCatalogResult: Codable, Equatable, Sendable {
    package let compatibility: IPCProtocolCatalogCompatibility
    package let commands: [IPCCommandDescriptor]

    package init(
        compatibility: IPCProtocolCatalogCompatibility,
        commands: [IPCCommandDescriptor]
    ) {
        self.compatibility = compatibility
        self.commands = commands
    }

    /// Builds a finite schema from validated descriptor fields, schema-document
    /// leaves, and exact typed examples. A future received-catalog decoder can
    /// validate the original bytes against the same concrete field contract.
    package static func schema(
        compatibility: IPCProtocolCatalogCompatibility,
        commands: [IPCCommandDescriptor]
    ) throws -> IPCJSONSchema {
        guard compatibility == .current else {
            throw IPCSchemaValidationError(
                fieldPath: "$.compatibility",
                reason: .invalidDefinition,
                expected: "the current IPC protocol catalog compatibility identity"
            )
        }
        guard !commands.isEmpty else {
            throw IPCSchemaValidationError(
                fieldPath: "$.commands",
                reason: .invalidDefinition,
                expected: "at least one composed command descriptor"
            )
        }
        let commandSchemas = try commands.map { try $0.catalogEntrySchema }
        let commandsSchema: IPCJSONSchema
        switch commandSchemas.count {
        case 1:
            commandsSchema = .array(items: commandSchemas[0])
        default:
            commandsSchema = .array(items: .oneOf(commandSchemas))
        }
        return .object(fields: [
            .init(
                name: "compatibility",
                description: "Exact wire protocol and typed catalog compatibility identity",
                schema: try IPCJSONSchema.literal(compatibility)
            ),
            .init(
                name: "commands",
                description: "Complete available typed command metadata in identity order",
                schema: commandsSchema
            ),
        ])
    }
}
