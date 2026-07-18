import AgentStudioGit
import Foundation

extension AgentStudioGitBridgeReviewDataClient: BridgeSharedReviewConstructionClient {
    static var defaultSharedContentRootURL: URL {
        AgentStudioGitBridgeReviewSharedContentRoot.launchRootURL
    }

    func captureSharedContent(
        handles: [BridgeContentHandle],
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeSharedReviewContentBacking {
        let artifactIdentity = UUIDv7.generate()
        let artifactDirectory = sharedContentRootURL.appending(path: artifactIdentity.uuidString)
        try await Self.createBackingDirectory(artifactDirectory)
        do {
            var sourceByIdentity: [BridgeSharedReviewContentIdentity: BridgeSharedReviewImmutableContentSource] = [:]
            var capturedByteCount = 0
            for handle in handles {
                guard let locator = locatorByIdentity[contentLocatorIdentity(for: handle)] else {
                    throw BridgeSharedReviewContentBackingError.missingLocator
                }
                let identity = BridgeSharedReviewContentIdentity(
                    itemIdentity: handle.itemId,
                    role: handle.role,
                    contentHash: handle.contentHash
                )
                switch locator.source {
                case .shared:
                    throw BridgeSharedReviewContentBackingError.invalidated
                case .live(let target, let path):
                    if target.kind == .commit {
                        sourceByIdentity[identity] = .gitObject(
                            target: target,
                            path: path,
                            declaredContentHash: handle.contentHash,
                            declaredContentHashAlgorithm: handle.contentHashAlgorithm
                        )
                    } else {
                        let payload = try await loadGitContentPayload(
                            GitContentRequest(
                                repositoryPath: repositoryPath,
                                target: target,
                                path: path,
                                maxSizeBytes: Int64(AppPolicies.Bridge.contentMaxBytesPerItem)
                            ),
                            freshnessKey: freshnessKey
                        )
                        try Self.validate(payload: payload, handle: handle)
                        let fileName = UUIDv7.generate().uuidString
                        try await Self.writeCapturedContent(
                            payload.data,
                            directoryURL: artifactDirectory,
                            fileName: fileName
                        )
                        sourceByIdentity[identity] = .capturedFile(
                            BridgeSharedReviewCapturedContentDescriptor(
                                fileName: fileName,
                                byteCount: payload.data.count,
                                declaredContentHash: handle.contentHash,
                                declaredContentHashAlgorithm: handle.contentHashAlgorithm,
                                integritySHA256: BridgeSharedReviewContentBacking.sha256(payload.data)
                            )
                        )
                        capturedByteCount += payload.data.count
                    }
                }
            }
            return BridgeSharedReviewContentBacking(
                artifactIdentity: artifactIdentity,
                directoryURL: artifactDirectory,
                sourceByIdentity: sourceByIdentity,
                capturedByteCount: capturedByteCount
            )
        } catch {
            await Self.removeBackingDirectory(artifactDirectory)
            throw error
        }
    }

    func installSharedContent(
        backing: BridgeSharedReviewContentBacking,
        handles: [BridgeContentHandle]
    ) async throws {
        let locatorIdentities = handles.map(contentLocatorIdentity)
        for handle in handles {
            let identity = BridgeSharedReviewContentIdentity(
                itemIdentity: handle.itemId,
                role: handle.role,
                contentHash: handle.contentHash
            )
            _ = try backing.source(for: identity)
            locatorByIdentity[contentLocatorIdentity(for: handle)] = ContentLocator(
                source: .shared(backing: backing, identity: identity),
                reviewGeneration: handle.reviewGeneration
            )
        }
        guard
            backing.registerUninstallOperation({ [weak self] in
                await self?.uninstallSharedContent(
                    backingArtifactIdentity: backing.artifactIdentity,
                    locatorIdentities: locatorIdentities
                )
            })
        else {
            uninstallSharedContent(
                backingArtifactIdentity: backing.artifactIdentity,
                locatorIdentities: locatorIdentities
            )
            throw BridgeSharedReviewContentBackingError.invalidated
        }
    }

    func registeredContentLocatorCount() -> Int {
        locatorByIdentity.count
    }

    func contentPayload(
        for locator: ContentLocator,
        handle: BridgeContentHandle,
        requestedGeneration: BridgeReviewGeneration
    ) async throws -> GitContentPayload {
        switch locator.source {
        case .live(let target, let path):
            return try await loadGitContent(
                GitContentRequest(
                    repositoryPath: repositoryPath,
                    target: target,
                    path: path,
                    maxSizeBytes: Int64(AppPolicies.Bridge.contentMaxBytesPerItem)
                ),
                handle: handle,
                freshnessKey: gitReadFreshnessKey(for: requestedGeneration)
            )
        case .shared(let backing, let identity):
            switch try backing.source(for: identity) {
            case .gitObject(
                let target,
                let path,
                let declaredContentHash,
                let declaredContentHashAlgorithm
            ):
                let payload = try await loadGitContent(
                    GitContentRequest(
                        repositoryPath: repositoryPath,
                        target: target,
                        path: path,
                        maxSizeBytes: Int64(AppPolicies.Bridge.contentMaxBytesPerItem)
                    ),
                    handle: handle,
                    freshnessKey: gitReadFreshnessKey(for: requestedGeneration),
                    physicalReadLease: {
                        try backing.acquireRead(for: identity)
                    }
                )
                guard handle.contentHash == declaredContentHash,
                    handle.contentHashAlgorithm == declaredContentHashAlgorithm
                else {
                    throw BridgeSharedReviewContentBackingError.digestMismatch
                }
                try Self.validate(payload: payload, handle: handle)
                return payload
            case .capturedFile(let capturedContent):
                let readLease = try backing.acquireRead(for: identity)
                defer { readLease.settle() }
                let data = try await Self.readCapturedContent(
                    backing: backing,
                    fileName: capturedContent.fileName
                )
                guard data.count == capturedContent.byteCount,
                    BridgeSharedReviewContentBacking.sha256(data) == capturedContent.integritySHA256
                else {
                    throw BridgeSharedReviewContentBackingError.digestMismatch
                }
                return GitContentPayload(
                    data: data,
                    contentHash: capturedContent.declaredContentHash,
                    contentHashAlgorithm: capturedContent.declaredContentHashAlgorithm,
                    isBinary: handle.isBinary
                )
            }
        }
    }

    private static func validate(
        payload: GitContentPayload,
        handle: BridgeContentHandle
    ) throws {
        let computedContentHash: String
        do {
            computedContentHash = try bridgeComputedContentHash(
                for: payload.data,
                algorithm: handle.contentHashAlgorithm
            )
        } catch {
            throw BridgeSharedReviewContentBackingError.digestMismatch
        }
        guard computedContentHash == handle.contentHash,
            !handle.sizeBytesIsExact || payload.data.count == handle.sizeBytes
        else {
            throw BridgeSharedReviewContentBackingError.digestMismatch
        }
    }

    private func uninstallSharedContent(
        backingArtifactIdentity: UUID,
        locatorIdentities: [ContentLocatorIdentity]
    ) {
        for locatorIdentity in locatorIdentities {
            guard let locator = locatorByIdentity[locatorIdentity],
                case .shared(let backing, _) = locator.source,
                backing.artifactIdentity == backingArtifactIdentity
            else {
                continue
            }
            locatorByIdentity.removeValue(forKey: locatorIdentity)
        }
    }

    private static func createBackingDirectory(_ directoryURL: URL) async throws {
        // File-system construction must not inherit a caller actor.
        // swiftlint:disable:next no_task_detached
        try await Task.detached {
            let rootURL = directoryURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: rootURL.path
            )
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directoryURL.path
            )
        }.value
    }

    private static func writeCapturedContent(
        _ data: Data,
        directoryURL: URL,
        fileName: String
    ) async throws {
        // File-system construction must not inherit a caller actor.
        // swiftlint:disable:next no_task_detached
        try await Task.detached {
            let fileURL = directoryURL.appending(path: fileName)
            do {
                try data.write(to: fileURL, options: [.atomic])
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: fileURL.path
                )
            } catch {
                throw BridgeSharedReviewContentBackingError.fileWriteFailed
            }
        }.value
    }

    private static func readCapturedContent(
        backing: BridgeSharedReviewContentBacking,
        fileName: String
    ) async throws -> Data {
        let directoryURL = backing.directoryURL.standardizedFileURL
        let fileURL = directoryURL.appending(path: fileName).standardizedFileURL
        let directoryPrefix =
            directoryURL.path.hasSuffix("/")
            ? directoryURL.path
            : "\(directoryURL.path)/"
        guard fileURL.path.hasPrefix(directoryPrefix), fileURL.lastPathComponent == fileName else {
            throw BridgeSharedReviewContentBackingError.invalidBackingPath
        }
        // File-system reads must not inherit the data-client actor.
        // swiftlint:disable:next no_task_detached
        return try await Task.detached {
            do {
                return try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            } catch {
                throw BridgeSharedReviewContentBackingError.fileReadFailed
            }
        }.value
    }

    private static func removeBackingDirectory(_ directoryURL: URL) async {
        // File-system cleanup must not inherit the data-client actor.
        // swiftlint:disable:next no_task_detached
        await Task.detached {
            try? FileManager.default.removeItem(at: directoryURL)
        }.value
    }
}

private enum AgentStudioGitBridgeReviewSharedContentRoot {
    private static let launchIdentity = UUID().uuidString

    static let launchRootURL = AppDataPaths.rootDirectory()
        .appending(path: "bridge-review-content")
        .appending(path: launchIdentity)
}
