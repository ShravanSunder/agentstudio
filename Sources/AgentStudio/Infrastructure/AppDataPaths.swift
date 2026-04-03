import Foundation

/// Shared root for all app-owned on-disk state.
///
/// Default behavior:
/// - release builds use `~/.agentstudio`
/// - debug builds use `~/.agentstudio-db`
/// - `AGENTSTUDIO_DATA_DIR` overrides both when set
enum AppDataPaths {
    static let dataDirectoryEnvironmentKey = "AGENTSTUDIO_DATA_DIR"

    static var isDebugBuild: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    static func rootDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isDebugBuild: Bool = Self.isDebugBuild
    ) -> URL {
        if let override = environment[dataDirectoryEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty
        {
            return expandPath(override).standardizedFileURL
        }

        let baseName = isDebugBuild ? ".agentstudio-db" : ".agentstudio"
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: baseName)
            .standardizedFileURL
    }

    static func workspacesDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isDebugBuild: Bool = Self.isDebugBuild
    ) -> URL {
        rootDirectory(environment: environment, isDebugBuild: isDebugBuild)
            .appending(path: "workspaces")
            .standardizedFileURL
    }

    static func zmxDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isDebugBuild: Bool = Self.isDebugBuild
    ) -> URL {
        rootDirectory(environment: environment, isDebugBuild: isDebugBuild)
            .appending(path: "z")
            .standardizedFileURL
    }

    static func surfaceCheckpointURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isDebugBuild: Bool = Self.isDebugBuild
    ) -> URL {
        rootDirectory(environment: environment, isDebugBuild: isDebugBuild)
            .appending(path: "surface-checkpoint.json")
            .standardizedFileURL
    }

    static func displayPath(for url: URL) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let standardizedPath = url.standardizedFileURL.path
        guard standardizedPath.hasPrefix(homePath) else {
            return standardizedPath
        }

        let suffix = standardizedPath.dropFirst(homePath.count)
        if suffix.isEmpty {
            return "~"
        }
        return "~\(suffix)"
    }

    private static func expandPath(_ rawPath: String) -> URL {
        if rawPath == "~" {
            return FileManager.default.homeDirectoryForCurrentUser
        }

        if rawPath.hasPrefix("~/") {
            let relativePath = String(rawPath.dropFirst(2))
            return FileManager.default.homeDirectoryForCurrentUser
                .appending(path: relativePath)
        }

        return URL(fileURLWithPath: rawPath)
    }
}
