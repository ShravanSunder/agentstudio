import Darwin
import Foundation

enum FilesystemVolumeCasePolicy: Hashable, Sendable {
    case caseSensitive
    case caseInsensitive
}

enum FilesystemVolumeUnicodePolicy: Hashable, Sendable {
    case canonicalEquivalent
}

enum FilesystemPathComponentPolicy: Hashable, Sendable {
    case absolutePOSIX
}

enum FilesystemVolumeFormat: Hashable, Sendable {
    case apfs
    case hfs
}

enum FilesystemLocalVolumeIdentity: Hashable, Sendable {
    case opaqueBytes(Data)
    case numeric(UInt64)
    case text(String)
}

struct FilesystemVolumeSemantics: Hashable, Sendable {
    let identity: FilesystemLocalVolumeIdentity
    let format: FilesystemVolumeFormat
    let casePolicy: FilesystemVolumeCasePolicy
    let unicodePolicy: FilesystemVolumeUnicodePolicy
    let componentPolicy: FilesystemPathComponentPolicy

    var isLocal: Bool { true }
}

struct FilesystemCanonicalPathAlias: Hashable, Sendable {
    let path: String
    let components: [String]
}

struct FilesystemRegisteredRootAliases: Hashable, Sendable {
    let standardizedLexical: FilesystemCanonicalPathAlias
    let onceResolvedCanonical: FilesystemCanonicalPathAlias
}

struct FilesystemCanonicalizedAuthorizedRoot: Hashable, Sendable {
    let aliases: FilesystemRegisteredRootAliases
    let volumeSemantics: FilesystemVolumeSemantics
}

struct FilesystemContainedDiscoveryCandidate: Hashable, Sendable {
    let canonicalURL: URL
    let canonicalAlias: FilesystemCanonicalPathAlias
}

enum FilesystemDiscoveryCandidateRejection: Hashable, Sendable {
    case notAbsoluteFileURL
    case unavailable
    case volumeSemanticsMismatch
    case outsideRegisteredRoot
}

enum FilesystemDiscoveryCandidateClassification: Hashable, Sendable {
    case contained(FilesystemContainedDiscoveryCandidate)
    case rejected(FilesystemDiscoveryCandidateRejection)
}

struct FilesystemPathCanonicalizer: Sendable {
    func canonicalizeAuthorizedRoot(
        authorizedBoundary: URL,
        registeredRoot: URL
    ) throws -> FilesystemCanonicalizedAuthorizedRoot {
        guard Self.isAbsoluteFileURL(authorizedBoundary) else {
            throw FilesystemSourceConfigurationError.authorizedBoundaryNotAbsoluteFileURL
        }
        guard Self.isAbsoluteFileURL(registeredRoot) else {
            throw FilesystemSourceConfigurationError.registeredRootNotAbsoluteFileURL
        }

        let standardizedBoundary = authorizedBoundary.standardizedFileURL
        let standardizedRoot = registeredRoot.standardizedFileURL
        let resolvedBoundary = standardizedBoundary.resolvingSymlinksInPath()
        let resolvedRoot = standardizedRoot.resolvingSymlinksInPath()
        let boundarySemantics = try inspectVolumeSemantics(at: resolvedBoundary)
        let rootSemantics = try inspectVolumeSemantics(at: resolvedRoot)
        guard boundarySemantics == rootSemantics else {
            throw FilesystemSourceConfigurationError.registeredRootOutsideAuthorizedBoundary
        }
        guard
            Self.contains(
                parent: Self.components(of: standardizedBoundary),
                child: Self.components(of: standardizedRoot),
                casePolicy: rootSemantics.casePolicy
            )
        else {
            throw FilesystemSourceConfigurationError.registeredRootOutsideAuthorizedBoundary
        }
        guard
            Self.contains(
                parent: Self.components(of: resolvedBoundary),
                child: Self.components(of: resolvedRoot),
                casePolicy: rootSemantics.casePolicy
            )
        else {
            throw FilesystemSourceConfigurationError.registeredRootOutsideAuthorizedBoundary
        }

        let rootValues: URLResourceValues
        do {
            rootValues = try resolvedRoot.resourceValues(forKeys: [.isDirectoryKey])
        } catch {
            throw FilesystemSourceConfigurationError.registeredRootUnavailable
        }
        guard rootValues.isDirectory == true else {
            throw FilesystemSourceConfigurationError.registeredRootIsNotDirectory
        }

        return FilesystemCanonicalizedAuthorizedRoot(
            aliases: FilesystemRegisteredRootAliases(
                standardizedLexical: Self.alias(for: standardizedRoot),
                onceResolvedCanonical: Self.alias(for: resolvedRoot)
            ),
            volumeSemantics: rootSemantics
        )
    }

    /// Revalidates scanner evidence against source-owned root authority immediately
    /// before a discovery read. A selected root may itself be a symlink because the
    /// descriptor already owns its once-resolved identity; a descendant replacement
    /// may not escape that resolved root.
    func classifyDiscoveryCandidate(
        _ candidateURL: URL,
        within registeredRoot: RegisteredRootDescriptor
    ) -> FilesystemDiscoveryCandidateClassification {
        guard Self.isAbsoluteFileURL(candidateURL) else {
            return .rejected(.notAbsoluteFileURL)
        }

        let canonicalCandidate = candidateURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidateSemantics: FilesystemVolumeSemantics
        do {
            candidateSemantics = try inspectVolumeSemantics(at: canonicalCandidate)
        } catch {
            return .rejected(.unavailable)
        }
        guard candidateSemantics == registeredRoot.volumeSemantics else {
            return .rejected(.volumeSemanticsMismatch)
        }
        guard
            Self.contains(
                parent: registeredRoot.aliases.onceResolvedCanonical.components,
                child: Self.components(of: canonicalCandidate),
                casePolicy: registeredRoot.volumeSemantics.casePolicy
            )
        else {
            return .rejected(.outsideRegisteredRoot)
        }

        return .contained(
            FilesystemContainedDiscoveryCandidate(
                canonicalURL: canonicalCandidate,
                canonicalAlias: Self.alias(for: canonicalCandidate)
            )
        )
    }

    private func inspectVolumeSemantics(at url: URL) throws -> FilesystemVolumeSemantics {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(
                forKeys: [
                    .volumeIdentifierKey,
                    .volumeIsLocalKey,
                    .volumeSupportsCaseSensitiveNamesKey,
                ]
            )
        } catch {
            throw FilesystemSourceConfigurationError.registeredRootUnavailable
        }
        guard values.volumeIsLocal == true else {
            throw FilesystemSourceConfigurationError.registeredRootIsNotOnLocalVolume
        }
        guard let volumeIdentifier = values.volumeIdentifier,
            let identity = Self.volumeIdentity(from: volumeIdentifier)
        else {
            throw FilesystemSourceConfigurationError.ambiguousVolumeIdentity
        }
        guard let supportsCaseSensitiveNames = values.volumeSupportsCaseSensitiveNames else {
            throw FilesystemSourceConfigurationError.ambiguousVolumeCasePolicy
        }
        let volumeFormat = try Self.volumeFormat(at: url)

        return FilesystemVolumeSemantics(
            identity: identity,
            format: volumeFormat,
            casePolicy: supportsCaseSensitiveNames ? .caseSensitive : .caseInsensitive,
            unicodePolicy: .canonicalEquivalent,
            componentPolicy: .absolutePOSIX
        )
    }

    private static func isAbsoluteFileURL(_ url: URL) -> Bool {
        url.isFileURL && url.path.hasPrefix("/")
    }

    private static func alias(for url: URL) -> FilesystemCanonicalPathAlias {
        FilesystemCanonicalPathAlias(
            path: normalizedPath(url.path),
            components: components(of: url)
        )
    }

    private static func components(of url: URL) -> [String] {
        url.pathComponents
            .filter { $0 != "/" }
            .map { $0.precomposedStringWithCanonicalMapping }
    }

    private static func normalizedPath(_ path: String) -> String {
        guard path != "/" else { return path }
        var normalized = path
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    private static func contains(
        parent: [String],
        child: [String],
        casePolicy: FilesystemVolumeCasePolicy
    ) -> Bool {
        guard parent.count <= child.count else { return false }
        return zip(parent, child).allSatisfy { parentComponent, childComponent in
            let normalizedParent = parentComponent.precomposedStringWithCanonicalMapping
            let normalizedChild = childComponent.precomposedStringWithCanonicalMapping
            switch casePolicy {
            case .caseSensitive:
                return normalizedParent == normalizedChild
            case .caseInsensitive:
                return normalizedParent.compare(
                    normalizedChild,
                    options: [.caseInsensitive, .literal]
                ) == .orderedSame
            }
        }
    }

    private static func volumeIdentity(
        from value: any NSCopying & NSSecureCoding & NSObjectProtocol
    ) -> FilesystemLocalVolumeIdentity? {
        if let data = value as? Data {
            return .opaqueBytes(data)
        }
        if let number = value as? NSNumber {
            return .numeric(number.uint64Value)
        }
        if let string = value as? NSString {
            return .text(string as String)
        }
        return nil
    }

    private static func volumeFormat(at url: URL) throws -> FilesystemVolumeFormat {
        var fileSystemInformation = statfs()
        let inspectionResult: Int32 = url.withUnsafeFileSystemRepresentation { fileSystemPath in
            guard let fileSystemPath else { return -1 }
            return statfs(fileSystemPath, &fileSystemInformation)
        }
        guard inspectionResult == 0 else {
            throw FilesystemSourceConfigurationError.registeredRootUnavailable
        }

        let nameCapacity = MemoryLayout.size(ofValue: fileSystemInformation.f_fstypename)
        let formatName = withUnsafePointer(to: &fileSystemInformation.f_fstypename) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: nameCapacity) {
                String(cString: $0).lowercased()
            }
        }
        switch formatName {
        case "apfs":
            return .apfs
        case "hfs":
            return .hfs
        default:
            throw FilesystemSourceConfigurationError.unsupportedLocalVolumeFormat(formatName)
        }
    }
}
