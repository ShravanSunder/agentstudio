import Foundation

package enum IPCCommandMethodCompositionError: Error, Equatable, Sendable {
    case incompatibleIdentity
    case emptyCommandCatalog
    case duplicateCommandIdentifier(String)
}

/// One immutable command value supplies discovery, server registration, and
/// later descriptor-driven CLI construction.
package struct IPCCommandMethodComposition: Sendable {
    package let commands: [IPCCommandDescriptor]
    package let catalogResult: IPCCommandCatalogResult
    package let list: IPCMethodDescriptor<IPCEmptyParams, IPCCommandCatalogResult>
    package let execute: IPCMethodDescriptor<IPCCommandExecutionRequest, IPCCommandExecutionResult>

    package init(
        compatibility: IPCProtocolCatalogCompatibility,
        commands: [IPCCommandDescriptor]
    ) throws {
        guard compatibility == .current else {
            throw IPCCommandMethodCompositionError.incompatibleIdentity
        }
        guard !commands.isEmpty else { throw IPCCommandMethodCompositionError.emptyCommandCatalog }
        var observedIdentifiers: Set<String> = []
        for command in commands {
            guard observedIdentifiers.insert(command.id.rawValue).inserted else {
                throw IPCCommandMethodCompositionError.duplicateCommandIdentifier(command.id.rawValue)
            }
        }

        let commands = commands.sorted { $0.id.rawValue < $1.id.rawValue }
        let catalogResult = IPCCommandCatalogResult(
            compatibility: compatibility,
            commands: commands
        )
        let catalogSchema = try IPCCommandCatalogResult.schema(
            compatibility: compatibility,
            commands: commands
        )
        let argumentVariants = Self.uniqueArgumentVariants(in: commands)
        let resultVariants = Self.uniqueResultVariants(in: commands)
        let methodExamples = commands.flatMap(\.examples).map {
            IPCMethodExample(
                description: $0.description,
                parameters: $0.request,
                result: $0.result
            )
        }

        let list = try IPCMethodDescriptor(
            name: "command.list",
            description: "Return the complete available typed App command catalog.",
            parameterSchema: try IPCEmptyParams.ipcSchema(),
            resultSchema: catalogSchema,
            examples: [
                IPCMethodExample(
                    description: "List the commands composed for this runtime and channel.",
                    parameters: IPCEmptyParams(),
                    result: catalogResult
                )
            ],
            exposure: .allChannels,
            requiredPrivileges: [.systemRead],
            dataScope: .unspecified,
            allowedTargetKinds: [],
            commandRelationship: .noInteractiveIdentity,
            executionOwner: .queryReader,
            principalAvailability: .authenticated,
            resultSemantics: .applied,
            documentedErrors: [],
            isMutating: false,
            correlationPolicy: .notAccepted
        )
        let execute = try IPCMethodDescriptor(
            name: "command.execute",
            description: "Execute one available App command through its typed arguments.",
            parameterSchema: try IPCCommandExecutionRequest.ipcSchema(
                allowing: argumentVariants
            ),
            resultSchema: try IPCCommandExecutionResult.ipcSchema(
                allowing: resultVariants
            ),
            examples: methodExamples,
            exposure: .allChannels,
            requiredPrivileges: [.appCommandExecute],
            dataScope: .unspecified,
            allowedTargetKinds: Set(commands.flatMap(\.allowedTargetKinds)),
            commandRelationship: .appCommandParameter(field: "commandId"),
            executionOwner: .appCommand,
            principalAvailability: .authenticated,
            resultSemantics: .discriminated,
            documentedErrors: [],
            isMutating: true,
            correlationPolicy: .required
        )

        _ = try list.encodeResult(catalogResult)
        for example in methodExamples {
            _ = try execute.decodeParameters(from: JSONEncoder().encode(example.parameters))
            _ = try execute.encodeResult(example.result)
        }

        self.commands = commands
        self.catalogResult = catalogResult
        self.list = list
        self.execute = execute
    }

    private static func uniqueArgumentVariants(
        in commands: [IPCCommandDescriptor]
    ) -> [IPCCommandArgumentVariant] {
        Array(Set(commands.flatMap(\.argumentVariants))).sorted { $0.rawValue < $1.rawValue }
    }

    private static func uniqueResultVariants(
        in commands: [IPCCommandDescriptor]
    ) -> [IPCCommandResultVariant] {
        Array(Set(commands.flatMap(\.resultVariants))).sorted { $0.rawValue < $1.rawValue }
    }
}
