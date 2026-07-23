import Foundation

/// Shared root for all app-owned on-disk state.
///
/// Default behavior:
/// - release builds use `~/.agentstudio`
/// - debug builds use `~/.agentstudio-db`
/// - `AGENTSTUDIO_DATA_DIR` overrides both when set
enum AppDataPaths {
    static let dataDirectoryEnvironmentKey = "AGENTSTUDIO_DATA_DIR"
    static let traceProofTokenEnvironmentKey = "AGENTSTUDIO_TRACE_PROOF_TOKEN"

    enum ReleaseChannel: String {
        case stable
        case beta

        static var current: Self {
            guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "AgentStudioReleaseChannel") as? String else {
                return .stable
            }
            return Self(rawValue: rawValue) ?? .stable
        }
    }

    static var isDebugBuild: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    static func allowsDebugHarnessEnvironmentOverrides(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isDebugBuild: Bool = Self.isDebugBuild
    ) -> Bool {
        guard isDebugBuild else { return false }
        return
            !(environment[traceProofTokenEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ?? true)
    }

    static func rootDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        releaseChannel: ReleaseChannel = .current,
        isDebugBuild: Bool = Self.isDebugBuild
    ) -> URL {
        if let override = environment[dataDirectoryEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty
        {
            return expandPath(override).standardizedFileURL
        }

        let baseName = rootDirectoryName(releaseChannel: releaseChannel, isDebugBuild: isDebugBuild)
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: baseName)
            .standardizedFileURL
    }

    static func globalPreferencesURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        releaseChannel: ReleaseChannel = .current,
        isDebugBuild: Bool = Self.isDebugBuild
    ) -> URL {
        rootDirectory(environment: environment, releaseChannel: releaseChannel, isDebugBuild: isDebugBuild)
            .appending(path: "preferences.global.json")
            .standardizedFileURL
    }

    static func coreSQLiteURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isDebugBuild: Bool = Self.isDebugBuild
    ) -> URL {
        rootDirectory(environment: environment, isDebugBuild: isDebugBuild)
            .appending(path: "core.sqlite")
            .standardizedFileURL
    }

    static func localSQLiteURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isDebugBuild: Bool = Self.isDebugBuild
    ) -> URL {
        rootDirectory(environment: environment, isDebugBuild: isDebugBuild)
            .appending(path: "local.sqlite")
            .standardizedFileURL
    }

    static func zmxDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        releaseChannel: ReleaseChannel = .current,
        isDebugBuild: Bool = Self.isDebugBuild
    ) -> URL {
        rootDirectory(environment: environment, releaseChannel: releaseChannel, isDebugBuild: isDebugBuild)
            .appending(path: "z")
            .standardizedFileURL
    }

    static func surfaceCheckpointURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        releaseChannel: ReleaseChannel = .current,
        isDebugBuild: Bool = Self.isDebugBuild
    ) -> URL {
        rootDirectory(environment: environment, releaseChannel: releaseChannel, isDebugBuild: isDebugBuild)
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

    private static func rootDirectoryName(releaseChannel: ReleaseChannel, isDebugBuild: Bool) -> String {
        if isDebugBuild {
            return ".agentstudio-db"
        }

        switch releaseChannel {
        case .stable:
            return ".agentstudio"
        case .beta:
            return ".agent-studio-b"
        }
    }
}
