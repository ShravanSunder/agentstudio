import AppKit
import Foundation
import os

@MainActor
protocol PathActionsExecuting: Sendable {
    @discardableResult
    func copyPath(_ path: URL) -> Bool

    @discardableResult
    func revealInFinder(_ path: URL) -> Bool
}

struct LivePathActionsExecutor: PathActionsExecuting {
    @MainActor
    func copyPath(_ path: URL) -> Bool {
        PathActions.copyPath(path)
    }

    @MainActor
    func revealInFinder(_ path: URL) -> Bool {
        PathActions.revealInFinder(path)
    }
}

enum PathActions {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "PathActions")

    @MainActor
    @discardableResult
    static func copyPath(_ path: URL) -> Bool {
        NSPasteboard.general.clearContents()
        let success = NSPasteboard.general.setString(path.path, forType: .string)
        if !success {
            logger.warning("Copy path failed for path=\(path.path, privacy: .public)")
        }
        return success
    }

    @MainActor
    @discardableResult
    static func revealInFinder(_ path: URL) -> Bool {
        ExternalWorkspaceOpener.openInFinder(path)
    }
}
