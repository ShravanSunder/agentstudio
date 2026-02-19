import Foundation

/// Lightweight restore/rehydration trace logger.
///
/// NOTE: Temporarily hard-enabled for debugging.
enum RestoreTrace {
    private static let enabled: Bool = true

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        debugLog("[restore-trace] \(message())")
    }
}
