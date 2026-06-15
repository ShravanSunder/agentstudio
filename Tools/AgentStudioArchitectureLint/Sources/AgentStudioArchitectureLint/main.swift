import AgentStudioArchitectureLintCore
import Foundation

let command = ArchitectureLintCommand(
    fileManager: .default,
    standardOutput: FileHandle.standardOutput,
    standardError: FileHandle.standardError
)

let exitCode = command.run(arguments: Array(CommandLine.arguments.dropFirst()))
Foundation.exit(Int32(exitCode))
