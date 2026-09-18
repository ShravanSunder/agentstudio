import AgentStudioIPCClientCore
import AgentStudioInfrastructure
import Foundation

/// Binds the descriptor CLI to the real process. Everything the CLI decides
/// lives in `AgentStudioIPCClientCommandLineRunner`; this file only supplies
/// argv, the environment, stdio and the exit status, so a test can exercise the
/// same dispatch without spawning a subprocess.
@main
struct AgentStudioIPCClientMain {
    static func main() {
        exit(
            AgentStudioIPCClientCommandLineRunner.run(
                props: AgentStudioIPCClientCommandLineRunner.Props(
                    arguments: Array(CommandLine.arguments.dropFirst()),
                    environment: ProcessInfo.processInfo.environment,
                    executablePath: CommandLine.arguments[0],
                    bundleExecutableURL: Bundle.main.executableURL,
                    standardInput: { FileHandle.standardInput.readDataToEndOfFile() },
                    identifierGenerator: { UUIDv7.generate() },
                    standardOutputSink: { print($0) },
                    standardErrorSink: { fputs("\($0)\n", stderr) }
                )
            )
        )
    }
}
