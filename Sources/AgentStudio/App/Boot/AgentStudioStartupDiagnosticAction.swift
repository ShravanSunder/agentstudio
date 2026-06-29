import Foundation

struct AgentStudioStartupDiagnosticAction: Equatable, Sendable {
    static let environmentKey = "AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION"
    static let watchFolderEnvironmentKey = "AGENTSTUDIO_STARTUP_WATCH_FOLDER"

    enum Kind: String, Sendable {
        case newTab = "new-tab"
        case commandBarRepoFilter = "command-bar-repo-filter"
        #if DEBUG
            case crossTabMoveGeometrySmoke = "cross-tab-move-geometry-smoke"
            case ipcTerminalSmoke = "ipc-terminal-smoke"
            case bridgeReviewObservabilitySmoke = "bridge-review-observability-smoke"
            case sidebarPerformanceProof = "sidebar-performance-proof"
        #endif
        case addWatchFolder = "add-watch-folder"
    }

    let kind: Kind

    var commandName: String {
        switch kind {
        case .newTab:
            "newTab"
        case .commandBarRepoFilter:
            "commandBarRepoFilter"
        #if DEBUG
            case .crossTabMoveGeometrySmoke:
                "crossTabMoveGeometrySmoke"
            case .ipcTerminalSmoke:
                "ipcTerminalSmoke"
            case .bridgeReviewObservabilitySmoke:
                "bridgeReviewObservabilitySmoke"
            case .sidebarPerformanceProof:
                "sidebarPerformanceProof"
        #endif
        case .addWatchFolder:
            "addWatchFolder"
        }
    }

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self? {
        guard let rawValue = environment[environmentKey] else { return nil }
        let normalizedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let kind = Kind(rawValue: normalizedValue) else { return nil }
        return Self(kind: kind)
    }

    static func watchFolderURL(
        from environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let rawPath = environment[watchFolderEnvironmentKey] else { return nil }
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
    }
}
