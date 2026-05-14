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

    /// Process identity prefix. Includes PID and the binary path basename so
    /// logs from multiple concurrent AgentStudio processes (installed app +
    /// debug build + different worktrees) can be disambiguated in the shared
    /// /tmp/agentstudio_debug.log file.
    private static let processTag: String = {
        let pid = ProcessInfo.processInfo.processIdentifier
        let executable = ProcessInfo.processInfo.arguments.first ?? "unknown"
        let branch =
            executable.components(separatedBy: "/").reversed().first { $0.contains("agent-studio") } ?? "unknown"
        return "pid=\(pid) src=\(branch)"
    }()

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        debugLog("[restore-trace \(processTag)] \(message())")
    }
}

/// Correlates log lines belonging to a single drag session.
/// Incremented in `DragHandleDragPreview.onAppear` when SwiftUI starts a drag.
/// Read in every capture view's draggingEntered/Updated/Exited override.
@MainActor
enum DragSession {
    private static var counter: UInt64 = 0
    private(set) static var current: UInt64 = 0

    static func start() -> UInt64 {
        counter &+= 1
        current = counter
        return current
    }
}
