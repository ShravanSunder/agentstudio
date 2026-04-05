import AppKit
import Foundation
import os

enum ExternalWorkspaceOpener {
    struct CommandRequest: Equatable {
        let executableURL: URL
        let arguments: [String]
    }

    private static let logger = Logger(subsystem: "com.agentstudio", category: "ExternalWorkspaceOpener")

    static func cursorCommand(path: URL) -> CommandRequest {
        CommandRequest(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["cursor", "--reuse-window", path.path]
        )
    }

    static func vscodeCommand(path: URL) -> CommandRequest {
        CommandRequest(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["code", "--reuse-window", path.path]
        )
    }

    static func preferredEditorCommands(path: URL) -> [CommandRequest] {
        [
            cursorCommand(path: path),
            vscodeCommand(path: path),
        ]
    }

    @discardableResult
    static func openInFinder(_ path: URL) -> Bool {
        let success = NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
        if !success {
            logger.warning("Reveal in Finder failed for path=\(path.path, privacy: .public)")
        }
        return success
    }

    @discardableResult
    static func openInCursor(_ path: URL) -> Bool {
        open(commands: [cursorCommand(path: path)])
    }

    @discardableResult
    static func openInVSCode(_ path: URL) -> Bool {
        open(commands: [vscodeCommand(path: path)])
    }

    @discardableResult
    static func openInPreferredEditor(_ path: URL) -> Bool {
        open(commands: preferredEditorCommands(path: path))
    }

    @discardableResult
    static func open(
        commands: [CommandRequest],
        runner: (CommandRequest) -> Bool = run
    ) -> Bool {
        for command in commands {
            if runner(command) {
                return true
            }
        }
        return false
    }

    @discardableResult
    private static func run(_ request: CommandRequest) -> Bool {
        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        do {
            try process.run()
            return true
        } catch {
            let commandName = request.arguments.first ?? "<unknown>"
            logger.error(
                "Open in \(commandName, privacy: .public) failed for args=\(request.arguments.joined(separator: " "), privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }
}
