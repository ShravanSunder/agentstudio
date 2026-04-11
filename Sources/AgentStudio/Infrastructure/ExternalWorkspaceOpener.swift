import AppKit
import Foundation
import os

enum ExternalWorkspaceOpener {
    enum OpenRequest: Equatable {
        case application(bundleIdentifier: String, targetPath: URL)
        case command(executableURL: URL, arguments: [String])
    }

    private enum EditorApp {
        static let cursorBundleIdentifier = "com.todesktop.230313mzl4w4u92"
        static let vscodeBundleIdentifier = "com.microsoft.VSCode"
    }

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

    static func cursorRequests(path: URL) -> [OpenRequest] {
        [
            .application(bundleIdentifier: EditorApp.cursorBundleIdentifier, targetPath: path),
            .command(
                executableURL: cursorCommand(path: path).executableURL,
                arguments: cursorCommand(path: path).arguments
            ),
        ]
    }

    static func vscodeRequests(path: URL) -> [OpenRequest] {
        [
            .application(bundleIdentifier: EditorApp.vscodeBundleIdentifier, targetPath: path),
            .command(
                executableURL: vscodeCommand(path: path).executableURL,
                arguments: vscodeCommand(path: path).arguments
            ),
        ]
    }

    static func preferredEditorRequests(path: URL) -> [OpenRequest] {
        cursorRequests(path: path) + vscodeRequests(path: path)
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
        open(requests: cursorRequests(path: path))
    }

    @discardableResult
    static func openInVSCode(_ path: URL) -> Bool {
        open(requests: vscodeRequests(path: path))
    }

    @discardableResult
    static func openInPreferredEditor(_ path: URL) -> Bool {
        open(requests: preferredEditorRequests(path: path))
    }

    @discardableResult
    static func open(
        requests: [OpenRequest],
        runner: (OpenRequest) -> Bool = run
    ) -> Bool {
        for request in requests {
            if runner(request) {
                return true
            }
        }
        logger.warning("No external editor opener succeeded")
        return false
    }

    @discardableResult
    private static func run(_ request: OpenRequest) -> Bool {
        switch request {
        case .application(let bundleIdentifier, let targetPath):
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                logger.debug(
                    "Editor app not registered for bundleID=\(bundleIdentifier, privacy: .public)"
                )
                return false
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([targetPath], withApplicationAt: appURL, configuration: configuration) { _, error in
                if let error {
                    logger.error(
                        "Open with app bundleID=\(bundleIdentifier, privacy: .public) failed for path=\(targetPath.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            return true
        case .command(let executableURL, let arguments):
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            do {
                try process.run()
                return true
            } catch {
                let commandName = arguments.first ?? "<unknown>"
                logger.error(
                    "Open in \(commandName, privacy: .public) failed for args=\(arguments.joined(separator: " "), privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return false
            }
        }
    }
}
