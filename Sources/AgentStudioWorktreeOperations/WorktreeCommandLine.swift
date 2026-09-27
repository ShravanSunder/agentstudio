import Foundation

package enum WorktreeCommandLine {
    package static func dispatch(
        arguments: [String],
        currentDirectory: URL,
        output: @Sendable (String) -> Void,
        runIPCCommand: @Sendable () -> Int32
    ) async -> Int32 {
        guard arguments.first == "worktree" else {
            return runIPCCommand()
        }

        return await run(
            arguments: Array(arguments.dropFirst()),
            currentDirectory: currentDirectory,
            output: output
        )
    }

    package static func run(
        arguments: [String],
        currentDirectory: URL,
        output: @Sendable (String) -> Void
    ) async -> Int32 {
        do {
            let invocation = try WorktreeCommandLineArgumentParser.parse(
                arguments,
                currentDirectory: currentDirectory
            )
            let outcome = await WorktreeOperationRunner().run(invocation.request)
            let response = try WorktreeCommandLineFormatter.format(
                outcome: outcome,
                usesJSONOutput: invocation.usesJSONOutput
            )
            output(response.text)
            return response.exitCode
        } catch let error as WorktreeCommandLineArgumentError {
            output(error.message)
            return 2
        } catch {
            output("failed: outputEncodingFailed")
            return 2
        }
    }
}
