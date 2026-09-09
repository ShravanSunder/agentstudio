import AgentStudioInfrastructure
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
            case paneAssociationRuntimeProof = "pane-association-runtime-proof"
            case bridgeReviewObservabilitySmoke = "bridge-review-observability-smoke"
            case bridgeFileViewObservabilitySmoke = "bridge-file-view-observability-smoke"
            case bridgeFileViewCommandRouteObservabilitySmoke =
                "bridge-file-view-command-route-observability-smoke"
            case bridgeFileViewTargetedRouteObservabilitySmoke =
                "bridge-file-view-targeted-route-observability-smoke"
            case bridgeReviewToFileViewObservabilitySmoke = "bridge-review-to-file-view-observability-smoke"
            case bridgeProductPaintCorrelation = "bridge-product-paint-correlation"
            case bridgeProductStreamWebKitFeasibility = "bridge-product-stream-webkit-feasibility"
            case sidebarPerformanceProof = "sidebar-performance-proof"
            case sidebarCPUZeroPTYIdle = "sidebar-cpu-zero-pty-idle"
            case sidebarCPUQuiescentPTYIdle = "sidebar-cpu-quiescent-pty-idle"
            case sidebarCPUSearchClear = "sidebar-cpu-search-clear"
            case sidebarCPUGrouping = "sidebar-cpu-grouping"
            case sidebarCPUHideShow = "sidebar-cpu-hide-show"
            case sidebarCPUTabSwitch = "sidebar-cpu-tab-switch"
            case repoExplorerKeyMutationProof = "repo-explorer-key-mutation-proof"
            case repoExplorerInteractionProof = "repo-explorer-interaction-proof"
        #endif
        case addWatchFolder = "add-watch-folder"
    }

    let kind: Kind

    var suppressesAutomaticLaunchPaneRestore: Bool {
        #if DEBUG
            kind == .paneAssociationRuntimeProof
                || kind == .bridgeReviewObservabilitySmoke || kind == .bridgeFileViewObservabilitySmoke
                || kind == .bridgeFileViewCommandRouteObservabilitySmoke
                || kind == .bridgeFileViewTargetedRouteObservabilitySmoke
                || kind == .bridgeReviewToFileViewObservabilitySmoke
                || kind == .bridgeProductPaintCorrelation
                || kind == .bridgeProductStreamWebKitFeasibility
                || kind == .sidebarCPUZeroPTYIdle || kind == .sidebarCPUQuiescentPTYIdle
                || kind == .sidebarCPUSearchClear || kind == .sidebarCPUGrouping
                || kind == .sidebarCPUHideShow || kind == .sidebarCPUTabSwitch
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
            case .paneAssociationRuntimeProof:
                "paneAssociationRuntimeProof"
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
            case .bridgeProductPaintCorrelation:
                "bridgeProductPaintCorrelation"
            case .bridgeProductStreamWebKitFeasibility:
                "bridgeProductStreamWebKitFeasibility"
            case .sidebarPerformanceProof:
                "sidebarPerformanceProof"
            case .sidebarCPUZeroPTYIdle:
                "sidebarCPUZeroPTYIdle"
            case .sidebarCPUQuiescentPTYIdle:
                "sidebarCPUQuiescentPTYIdle"
            case .sidebarCPUSearchClear:
                "sidebarCPUSearchClear"
            case .sidebarCPUGrouping:
                "sidebarCPUGrouping"
            case .sidebarCPUHideShow:
                "sidebarCPUHideShow"
            case .sidebarCPUTabSwitch:
                "sidebarCPUTabSwitch"
            case .repoExplorerKeyMutationProof:
                "repoExplorerKeyMutationProof"
            case .repoExplorerInteractionProof:
                "repoExplorerInteractionProof"
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

    func sidebarPerformanceControlRootURL(
        from environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        #if DEBUG
            guard AppDataPaths.allowsDebugHarnessEnvironmentOverrides(environment: environment) else {
                return nil
            }
            switch kind {
            case .sidebarCPUZeroPTYIdle, .sidebarCPUQuiescentPTYIdle,
                .sidebarCPUSearchClear, .sidebarCPUGrouping, .sidebarCPUHideShow,
                .sidebarCPUTabSwitch:
                break
            default:
                return nil
            }

            guard let candidate = Self.watchFolderURL(from: environment) else { return nil }
            let dataRoot = AppDataPaths.rootDirectory(environment: environment)
                .resolvingSymlinksInPath().standardizedFileURL
            let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
            var isDirectory: ObjCBool = false
            guard
                FileManager.default.fileExists(
                    atPath: resolvedCandidate.path,
                    isDirectory: &isDirectory
                ), isDirectory.boolValue
            else { return nil }
            let descendantPrefix = dataRoot.path.hasSuffix("/") ? dataRoot.path : dataRoot.path + "/"
            guard resolvedCandidate.path != dataRoot.path,
                resolvedCandidate.path.hasPrefix(descendantPrefix)
            else { return nil }
            return resolvedCandidate
        #else
            return nil
        #endif
    }
}
