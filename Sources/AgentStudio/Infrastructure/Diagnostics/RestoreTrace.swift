import Foundation

private final class RestoreTraceMessageCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    func append(_ message: String) {
        lock.lock()
        messages.append(message)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }
}

/// Lightweight restore/rehydration trace logger.
enum RestoreTrace {
    private static let clock = ContinuousClock()
    @TaskLocal private static var captureEnabled = false
    @TaskLocal private static var capturedMessageSink: (@Sendable (String) -> Void)?

    /// Opt-in with `AGENTSTUDIO_RESTORE_TRACE=1` for local diagnostics.
    private static let environmentEnabled: Bool = {
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

    static func nowIfEnabled() -> ContinuousClock.Instant? {
        guard isEnabled else { return nil }
        return clock.now
    }

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = "[restore-trace \(processTag)] \(message())"
        if let sink = capturedMessageSink {
            sink(line)
        } else {
            debugLog(line)
        }
    }

    @MainActor
    static func withCapturedMessages<TValue>(
        _ operation: () async throws -> TValue
    ) async rethrows -> (result: TValue, messages: [String]) {
        let collector = RestoreTraceMessageCollector()
        let result = try await $captureEnabled.withValue(
            true,
            operation: {
                try await $capturedMessageSink.withValue(
                    { message in
                        collector.append(message)
                    },
                    operation: {
                        try await operation()
                    }
                )
            }
        )
        return (result, collector.snapshot())
    }

    static func logDuration(
        _ metric: String,
        start: ContinuousClock.Instant?,
        fields: [(String, String)] = []
    ) {
        guard let start else { return }
        log(durationMetricLine(metric, duration: start.duration(to: clock.now), fields: fields))
    }

    static func durationMetricLine(
        _ metric: String,
        duration: Duration,
        fields: [(String, String)] = []
    ) -> String {
        let renderedFields = fields.map { key, value in "\(key)=\(value)" }.joined(separator: " ")
        let base = "metric=\(metric) durationMs=\(formattedMilliseconds(for: duration))"
        guard !renderedFields.isEmpty else { return base }
        return "\(base) \(renderedFields)"
    }

    static func workspaceSaveDurationLine(
        workspaceId: UUID,
        paneCount: Int,
        tabCount: Int,
        duration: Duration
    ) -> String {
        durationMetricLine(
            "workspace_save",
            duration: duration,
            fields: [
                ("workspace", workspaceId.uuidString),
                ("panes", "\(paneCount)"),
                ("tabs", "\(tabCount)"),
            ]
        )
    }

    static func logWorkspaceSaveDuration(
        workspaceId: UUID,
        paneCount: Int,
        tabCount: Int,
        start: ContinuousClock.Instant?
    ) {
        guard let start else { return }
        log(
            workspaceSaveDurationLine(
                workspaceId: workspaceId,
                paneCount: paneCount,
                tabCount: tabCount,
                duration: start.duration(to: clock.now)
            )
        )
    }

    private static func formattedMilliseconds(for duration: Duration) -> String {
        let components = duration.components
        let secondsResult = components.seconds.multipliedReportingOverflow(by: 1_000_000_000)
        let nanosecondsFromSeconds = secondsResult.partialValue
        let nanosecondsFromAttoseconds = components.attoseconds / 1_000_000_000
        let nanoseconds = nanosecondsFromSeconds + nanosecondsFromAttoseconds
        let roundedMicroseconds = (nanoseconds + 500) / 1000
        let wholeMilliseconds = roundedMicroseconds / 1000
        let fractionalMilliseconds = abs(roundedMicroseconds % 1000)
        return "\(wholeMilliseconds).\(String(format: "%03d", fractionalMilliseconds))"
    }

    private static var isEnabled: Bool {
        environmentEnabled || captureEnabled
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
