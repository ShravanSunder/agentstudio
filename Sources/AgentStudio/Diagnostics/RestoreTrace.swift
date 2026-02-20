import Foundation

/// Lightweight restore/rehydration trace logger.
enum RestoreTrace {
    /// Opt-in with `AGENTSTUDIO_RESTORE_TRACE=1` for local diagnostics.
    private static let enabled: Bool = {
        let raw = ProcessInfo.processInfo.environment["AGENTSTUDIO_RESTORE_TRACE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return raw == "1" || raw == "true" || raw == "yes"
    }()

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        debugLog("[restore-trace] \(message())")
    }
}
