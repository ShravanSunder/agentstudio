import Foundation

package enum PaneFilesystemLocationRequirement: Equatable, Sendable {
    case required
    case optional
}

package enum PaneFilesystemLocationResolution: Equatable, Sendable {
    case valid(URL?)
    case repaired(URL)
    case degradedRequired
}

package enum PaneFilesystemRuntimeCWDUpdate: Equatable, Sendable {
    case accepted(URL)
    case rejected
}

package enum PaneFilesystemLocationPolicy {
    package static func requirement(for content: PaneContent) -> PaneFilesystemLocationRequirement {
        switch content {
        case .terminal, .bridgePanel, .codeViewer:
            .required
        case .webview, .unsupported:
            .optional
        }
    }

    package static func resolveRestoredCWD(
        for content: PaneContent,
        cwd: URL?,
        launchDirectory: URL?
    ) -> PaneFilesystemLocationResolution {
        if let cwd = normalizedAbsoluteFileURL(cwd) {
            return .valid(cwd)
        }

        if let repair = repairCandidate(for: content, launchDirectory: launchDirectory) {
            return .repaired(repair)
        }

        switch requirement(for: content) {
        case .required:
            return .degradedRequired
        case .optional:
            return .valid(nil)
        }
    }

    package static func runtimeCWDUpdate(_ candidate: URL?) -> PaneFilesystemRuntimeCWDUpdate {
        guard let normalizedCandidate = normalizedAbsoluteFileURL(candidate) else {
            return .rejected
        }
        return .accepted(normalizedCandidate)
    }

    private static func repairCandidate(
        for content: PaneContent,
        launchDirectory: URL?
    ) -> URL? {
        switch content {
        case .terminal:
            return normalizedAbsoluteFileURL(launchDirectory)
        case .bridgePanel(let state):
            guard case .workspace(let rootPath, _) = state.source else { return nil }
            return normalizedAbsoluteFileURL(URL(filePath: rootPath))
        case .codeViewer(let state):
            return normalizedAbsoluteFileURL(state.filePath.deletingLastPathComponent())
        case .webview, .unsupported:
            return nil
        }
    }

    private static func normalizedAbsoluteFileURL(_ candidate: URL?) -> URL? {
        guard let candidate, candidate.isFileURL else { return nil }
        let normalizedCandidate = candidate.standardizedFileURL
        guard normalizedCandidate.path.hasPrefix("/") else { return nil }
        return URL(filePath: normalizedCandidate.path, directoryHint: .isDirectory)
    }
}
