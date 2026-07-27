enum AgentStudioModuleOwner: Equatable {
    case app
    case core
    case feature(String)
    case infrastructure
    case sharedComponents
    case testSupport

    var layerName: String {
        switch self {
        case .app:
            "App"
        case .core:
            "Core"
        case .feature:
            "Features"
        case .infrastructure:
            "Infrastructure"
        case .sharedComponents:
            "SharedComponents"
        case .testSupport:
            "TestSupport"
        }
    }

    var featureName: String? {
        guard case .feature(let featureName) = self else {
            return nil
        }
        return featureName
    }
}

struct AgentStudioPathClassifier {
    static let internalLayers = Set(["App", "Core", "Features", "Infrastructure", "SharedComponents"])

    private static let featureModulesByName = [
        "AgentStudioBridge": "Bridge",
        "AgentStudioCodeViewer": "CodeViewer",
        "AgentStudioCommandBar": "CommandBar",
        "AgentStudioEditorChooser": "EditorChooser",
        "AgentStudioInboxNotification": "InboxNotification",
        "AgentStudioRepoExplorer": "RepoExplorer",
        "AgentStudioTerminal": "Terminal",
        "AgentStudioWebview": "Webview",
    ]

    let path: String

    var isAgentStudioSource: Bool {
        path.contains("/Sources/AgentStudio/")
    }

    var isProgrammaticControlSource: Bool {
        path.contains("/Sources/AgentStudioProgrammaticControl/")
    }

    var isAppIPCSource: Bool {
        path.contains("/Sources/AgentStudioAppIPC/")
    }

    var isIPCCompositionSource: Bool {
        path.contains("/Sources/AgentStudio/App/IPCComposition/")
    }

    var sourceModuleOwner: AgentStudioModuleOwner? {
        guard isAgentStudioSource else {
            return nil
        }
        if path.contains("/Sources/AgentStudio/App/") {
            return .app
        }
        if path.contains("/Sources/AgentStudio/Core/") {
            return .core
        }
        if let featureName {
            return .feature(featureName)
        }
        if path.contains("/Sources/AgentStudio/Infrastructure/") {
            return .infrastructure
        }
        if path.contains("/Sources/AgentStudio/SharedComponents/") {
            return .sharedComponents
        }
        return .app
    }

    var testModuleOwner: AgentStudioModuleOwner? {
        guard path.contains("/Tests/AgentStudioTests/") else {
            return nil
        }
        if path.contains("/Tests/AgentStudioTests/Infrastructure/") {
            return .infrastructure
        }
        if path.contains("/Tests/AgentStudioTests/SharedComponents/") {
            return .sharedComponents
        }
        if path.contains("/Tests/AgentStudioTests/Core/") {
            return .core
        }
        if let range = path.range(of: "/Tests/AgentStudioTests/Features/") {
            let rest = path[range.upperBound...]
            if let featureName = rest.split(separator: "/", maxSplits: 1).first {
                return .feature(String(featureName))
            }
        }
        if path.contains("/Tests/AgentStudioTests/TestSupport/") {
            return .testSupport
        }
        return .app
    }

    var layer: String? {
        sourceModuleOwner?.layerName
    }

    var featureName: String? {
        guard let range = path.range(of: "/Sources/AgentStudio/Features/") else {
            return nil
        }
        let rest = path[range.upperBound...]
        return rest.split(separator: "/", maxSplits: 1).first.map(String.init)
    }

    static func importedModuleOwner(_ importPath: [String]) -> AgentStudioModuleOwner? {
        let parts = importPath.filter { !$0.isEmpty }
        guard let first = parts.first else {
            return nil
        }

        switch first {
        case "AgentStudio":
            if parts.count == 1 {
                return .app
            }
            return legacyModuleOwner(Array(parts[1...]))
        case "AgentStudioCore":
            return .core
        case "AgentStudioInfrastructure":
            return .infrastructure
        case "AgentStudioSharedComponents":
            return .sharedComponents
        case "AgentStudioTestSupport":
            return .testSupport
        default:
            if let featureName = featureModulesByName[first] {
                return .feature(featureName)
            }
            return legacyModuleOwner(parts)
        }
    }

    static func importedLayer(_ importPath: [String]) -> String? {
        importedModuleOwner(importPath)?.layerName
    }

    private static func legacyModuleOwner(_ parts: [String]) -> AgentStudioModuleOwner? {
        guard let first = parts.first else {
            return nil
        }
        switch first {
        case "App":
            return .app
        case "Core":
            return .core
        case "Infrastructure":
            return .infrastructure
        case "SharedComponents":
            return .sharedComponents
        case "Features":
            guard parts.count > 1 else {
                return .feature("")
            }
            return .feature(parts[1])
        default:
            return nil
        }
    }
}
