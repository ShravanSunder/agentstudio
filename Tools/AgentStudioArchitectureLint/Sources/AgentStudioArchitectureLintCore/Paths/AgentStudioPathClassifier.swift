struct AgentStudioPathClassifier {
    static let internalLayers = Set(["App", "Core", "Features", "Infrastructure", "SharedComponents"])

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

    var layer: String? {
        guard isAgentStudioSource else {
            return nil
        }
        if path.contains("/Sources/AgentStudio/App/") {
            return "App"
        }
        if path.contains("/Sources/AgentStudio/Core/") {
            return "Core"
        }
        if path.contains("/Sources/AgentStudio/Features/") {
            return "Features"
        }
        if path.contains("/Sources/AgentStudio/Infrastructure/") {
            return "Infrastructure"
        }
        if path.contains("/Sources/AgentStudio/SharedComponents/") {
            return "SharedComponents"
        }
        return nil
    }

    var featureName: String? {
        guard let range = path.range(of: "/Sources/AgentStudio/Features/") else {
            return nil
        }
        let rest = path[range.upperBound...]
        return rest.split(separator: "/", maxSplits: 1).first.map(String.init)
    }

    static func importedLayer(_ importPath: [String]) -> String? {
        let parts = importPath.filter { !$0.isEmpty }
        if let first = parts.first, internalLayers.contains(first) {
            return first
        }
        if parts.first == "AgentStudio",
            parts.count > 1,
            internalLayers.contains(parts[1])
        {
            return parts[1]
        }
        return nil
    }
}
