import Foundation

/// One typed command invocation. App owns the open command identity and checks
/// that its exhaustive IPC projection admits the supplied argument variant.
package struct IPCCommandExecutionRequest: IPCSchemaProviding, Equatable, Sendable {
    package let commandId: IPCCommandIdentifier
    package let correlationId: UUID
    package let arguments: IPCCommandArguments

    package init(
        commandId: IPCCommandIdentifier,
        correlationId: UUID,
        arguments: IPCCommandArguments
    ) {
        self.commandId = commandId
        self.correlationId = correlationId
        self.arguments = arguments
    }

    package static func ipcSchema(
        allowing argumentVariants: some Collection<IPCCommandArgumentVariant>
    ) throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "commandId",
                description: "Open App-owned command identifier",
                schema: .string(minimumLength: 1)
            ),
            .init(
                name: "correlationId",
                description: "Logical command UUID retained unchanged across retries",
                schema: IPCSchemaScalars.uuid
            ),
            .init(
                name: "arguments",
                description: "Typed arguments selected by the command's App-owned IPC projection",
                schema: try IPCCommandArguments.ipcSchema(allowing: argumentVariants)
            ),
        ])
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        try ipcSchema(allowing: IPCCommandArgumentVariant.allCases)
    }
}
