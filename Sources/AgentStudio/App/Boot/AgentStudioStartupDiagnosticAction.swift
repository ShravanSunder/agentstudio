import Foundation

struct AgentStudioStartupDiagnosticAction: Equatable, Sendable {
    static let environmentKey = "AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION"
    static let watchFolderEnvironmentKey = "AGENTSTUDIO_STARTUP_WATCH_FOLDER"

    enum Kind: String, Sendable {
        case newTab = "new-tab"
        case commandBarRepoFilter = "command-bar-repo-filter"
        case tccUpgradeProbe = "tcc-upgrade-probe"
        #if DEBUG
            case crossTabMoveGeometrySmoke = "cross-tab-move-geometry-smoke"
            case ipcTerminalSmoke = "ipc-terminal-smoke"
            case bridgeReviewObservabilitySmoke = "bridge-review-observability-smoke"
            case bridgeFileViewObservabilitySmoke = "bridge-file-view-observability-smoke"
            case bridgeFileViewCommandRouteObservabilitySmoke =
                "bridge-file-view-command-route-observability-smoke"
            case bridgeFileViewTargetedRouteObservabilitySmoke =
                "bridge-file-view-targeted-route-observability-smoke"
            case bridgeReviewToFileViewObservabilitySmoke = "bridge-review-to-file-view-observability-smoke"
            case bridgeWorkerFetchSchemeSmoke = "bridge-worker-fetch-scheme-smoke"
        #endif
        case addWatchFolder = "add-watch-folder"
    }

    let kind: Kind

    var suppressesAutomaticLaunchPaneRestore: Bool {
        #if DEBUG
            kind == .bridgeReviewObservabilitySmoke || kind == .bridgeFileViewObservabilitySmoke
                || kind == .bridgeFileViewCommandRouteObservabilitySmoke
                || kind == .bridgeFileViewTargetedRouteObservabilitySmoke
                || kind == .bridgeReviewToFileViewObservabilitySmoke
                || kind == .bridgeWorkerFetchSchemeSmoke
        #else
            false
        #endif
    }

    var commandName: String {
        switch kind {
        case .newTab:
            "newTab"
        case .commandBarRepoFilter:
            "commandBarRepoFilter"
        case .tccUpgradeProbe:
            "tccUpgradeProbe"
        #if DEBUG
            case .crossTabMoveGeometrySmoke:
                "crossTabMoveGeometrySmoke"
            case .ipcTerminalSmoke:
                "ipcTerminalSmoke"
            case .bridgeReviewObservabilitySmoke:
                "bridgeReviewObservabilitySmoke"
            case .bridgeFileViewObservabilitySmoke:
                "bridgeFileViewObservabilitySmoke"
            case .bridgeFileViewCommandRouteObservabilitySmoke:
                "bridgeFileViewCommandRouteObservabilitySmoke"
            case .bridgeFileViewTargetedRouteObservabilitySmoke:
                "bridgeFileViewTargetedRouteObservabilitySmoke"
            case .bridgeReviewToFileViewObservabilitySmoke:
                "bridgeReviewToFileViewObservabilitySmoke"
            case .bridgeWorkerFetchSchemeSmoke:
                "bridgeWorkerFetchSchemeSmoke"
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
