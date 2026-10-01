import AgentStudioProgrammaticControl

/// Compile-only S5 RED seam. App will parse raw values against the selected
/// command's IPC variants before target resolution and authorization.
package enum AppCommandRawArgumentParser {
    package static func parse(
        arguments _: [String: String], allowedVariants _: [IPCCommandArgumentVariant]
    ) throws(IPCSchemaValidationError) -> IPCCommandArguments {
        throw IPCSchemaValidationError(
            fieldPath: "$.arguments", reason: .invalidDefinition, expected: "S5 raw argument parser implementation")
    }
}
