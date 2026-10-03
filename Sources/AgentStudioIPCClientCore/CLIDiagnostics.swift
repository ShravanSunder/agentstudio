import os

/// CLI diagnostics never enter provider-visible stdout or stderr.
enum CLIDiagnostics {
    private static let logger = Logger(subsystem: "com.agentstudio.cli", category: "diagnostics")

    static func record(_ message: String) {
        logger.debug("\(message, privacy: .private)")
    }
}
