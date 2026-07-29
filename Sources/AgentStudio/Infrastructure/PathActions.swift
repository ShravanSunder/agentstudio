import AppKit
import Foundation
import os

@MainActor
package protocol PathActionsExecuting: Sendable {
    @discardableResult
    func copyPath(_ path: URL) -> Bool

    @discardableResult
    func revealInFinder(_ path: URL) -> Bool
}

package struct LivePathActionsExecutor: PathActionsExecuting {
    package init() {}

    @MainActor
    package func copyPath(_ path: URL) -> Bool {
        PathActions.copyPath(path)
    }

    @MainActor
    package func revealInFinder(_ path: URL) -> Bool {
        PathActions.revealInFinder(path)
    }
}

package enum PathActions {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "PathActions")

    @MainActor
    @discardableResult
    package static func copyPath(_ path: URL) -> Bool {
        NSPasteboard.general.clearContents()
        let success = NSPasteboard.general.setString(path.path, forType: .string)
        if !success {
            logger.warning("Copy path failed for path=\(path.path, privacy: .public)")
        }
        return success
    }

    @MainActor
    @discardableResult
    package static func revealInFinder(_ path: URL) -> Bool {
        ExternalWorkspaceOpener.openInFinder(path)
    }
}
