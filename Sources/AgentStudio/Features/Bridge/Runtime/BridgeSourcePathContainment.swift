import Foundation

enum BridgeSourcePathContainmentError: Error, Equatable, Sendable {
    case invalidRoot
    case invalidSelector
    case outsideRoot
    case notRegularFile
}

extension BridgeSourcePathContainmentError: CustomStringConvertible, LocalizedError {
    var description: String {
        switch self {
        case .invalidRoot:
            "Bridge source root is unavailable"
        case .invalidSelector:
            "Bridge source selector is invalid"
        case .outsideRoot:
            "Bridge source selector is outside the authorized root"
        case .notRegularFile:
            "Bridge source selector is not a regular file"
        }
    }

    var errorDescription: String? {
        description
    }
}

enum BridgeSourcePathContainment: Sendable {
    static func resolveRegularFile(
        rootURL: URL,
        relativePath: String
    ) throws -> URL {
        guard rootURL.isFileURL else {
            throw BridgeSourcePathContainmentError.invalidRoot
        }

        let resolvedRootURL = rootURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard isDirectory(resolvedRootURL) else {
            throw BridgeSourcePathContainmentError.invalidRoot
        }
        guard isValidRelativePath(relativePath) else {
            throw BridgeSourcePathContainmentError.invalidSelector
        }

        let lexicalFileURL =
            resolvedRootURL
            .appending(path: relativePath)
            .standardizedFileURL
        guard
            hasExactRelativePath(
                lexicalFileURL.path,
                rootPath: resolvedRootURL.path,
                relativePath: relativePath
            )
        else {
            throw BridgeSourcePathContainmentError.outsideRoot
        }

        let resolvedFileURL =
            lexicalFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard isContained(resolvedFileURL.path, inRootPath: resolvedRootURL.path) else {
            throw BridgeSourcePathContainmentError.outsideRoot
        }
        guard
            !rootRelativeComponents(
                resolvedFileURL.path,
                rootPath: resolvedRootURL.path
            ).contains(where: isGitInternalComponent)
        else {
            throw BridgeSourcePathContainmentError.invalidSelector
        }
        try validateFilesystemObservedSpelling(
            rootURL: resolvedRootURL,
            relativePath: relativePath
        )
        guard isRegularFile(resolvedFileURL) else {
            throw BridgeSourcePathContainmentError.notRegularFile
        }
        return resolvedFileURL
    }

    private static func isValidRelativePath(_ relativePath: String) -> Bool {
        guard
            !relativePath.isEmpty,
            !relativePath.utf8.contains(0),
            !NSString(string: relativePath).isAbsolutePath,
            relativePath.utf8.elementsEqual(
                relativePath.precomposedStringWithCanonicalMapping.utf8
            )
        else {
            return false
        }

        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return false
        }
        return !components.contains(where: isGitInternalComponent)
    }

    private static func isGitInternalComponent<PathComponent: StringProtocol>(
        _ component: PathComponent
    ) -> Bool {
        let bytes = Array(component.utf8)
        guard bytes.count == 4, bytes[0] == 0x2E else {
            return false
        }
        return (bytes[1] == 0x47 || bytes[1] == 0x67)
            && (bytes[2] == 0x49 || bytes[2] == 0x69)
            && (bytes[3] == 0x54 || bytes[3] == 0x74)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        do {
            return try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        } catch {
            return false
        }
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        do {
            return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        } catch {
            return false
        }
    }

    private static func validateFilesystemObservedSpelling(
        rootURL: URL,
        relativePath: String
    ) throws {
        var observedDirectoryURL = rootURL
        for submittedComponent in relativePath.split(separator: "/") {
            let observedNames: [String]
            do {
                observedNames = try FileManager.default.contentsOfDirectory(
                    atPath: observedDirectoryURL.path
                )
            } catch {
                throw BridgeSourcePathContainmentError.invalidSelector
            }

            let exactCanonicalMatches = observedNames.filter { observedName in
                observedName.precomposedStringWithCanonicalMapping.utf8.elementsEqual(
                    submittedComponent.utf8
                )
            }
            guard exactCanonicalMatches.count <= 1 else {
                throw BridgeSourcePathContainmentError.invalidSelector
            }
            if let observedName = exactCanonicalMatches.first {
                observedDirectoryURL.append(path: observedName)
                continue
            }

            let submittedName = String(submittedComponent)
            let hasCaseOnlyAlias = observedNames.contains { observedName in
                observedName.precomposedStringWithCanonicalMapping.compare(
                    submittedName,
                    options: [.caseInsensitive]
                ) == .orderedSame
            }
            if hasCaseOnlyAlias {
                throw BridgeSourcePathContainmentError.invalidSelector
            }
            return
        }
    }

    private static func hasExactRelativePath(
        _ candidatePath: String,
        rootPath: String,
        relativePath: String
    ) -> Bool {
        let rootPrefix = rootPath == "/" ? "/" : "\(rootPath)/"
        let candidateBytes = candidatePath.utf8
        let rootPrefixBytes = rootPrefix.utf8
        guard candidateBytes.starts(with: rootPrefixBytes) else {
            return false
        }
        guard
            let observedRelativePath = String(
                bytes: candidateBytes.dropFirst(rootPrefixBytes.count),
                encoding: .utf8
            )
        else {
            return false
        }
        return observedRelativePath.precomposedStringWithCanonicalMapping.utf8.elementsEqual(
            relativePath.utf8
        )
    }

    private static func isContained(_ candidatePath: String, inRootPath rootPath: String) -> Bool {
        if candidatePath.utf8.elementsEqual(rootPath.utf8) {
            return true
        }
        let rootPrefix = rootPath == "/" ? "/" : "\(rootPath)/"
        return candidatePath.utf8.starts(with: rootPrefix.utf8)
    }

    private static func rootRelativeComponents(
        _ candidatePath: String,
        rootPath: String
    ) -> [Substring] {
        if candidatePath.utf8.elementsEqual(rootPath.utf8) {
            return []
        }
        let rootPrefix = rootPath == "/" ? "/" : "\(rootPath)/"
        let candidateBytes = candidatePath.utf8
        guard candidateBytes.starts(with: rootPrefix.utf8) else {
            return []
        }
        guard
            let relativePath = String(
                bytes: candidateBytes.dropFirst(rootPrefix.utf8.count),
                encoding: .utf8
            )
        else {
            return []
        }
        return relativePath.split(separator: "/")
    }
}
