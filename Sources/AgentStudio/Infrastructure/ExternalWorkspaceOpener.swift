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
        let request = cursorCommand(path: path)
        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        do {
            try process.run()
            return true
        } catch {
            logger.warning(
                "Open in Cursor failed for path=\(path.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }
}
