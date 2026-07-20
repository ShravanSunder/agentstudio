import AgentStudioGit
import CryptoKit
import Foundation

/// Thin mapper from the AgentStudioGit SDK into Bridge review contracts.
///
/// The SDK owns Git data-plane reads; Bridge owns endpoint, package, generation,
/// and content-handle semantics. This actor keeps only transient handle locators
/// so later content loads can stay handle-based without putting Git DTOs into
/// `BridgeReviewPipeline` or BridgeWeb contracts.
actor AgentStudioGitBridgeReviewDataClient<LocalClient: AgentStudioGitLocalClient>: BridgeGitReviewDataClient {
    enum ContentSource: Sendable {
        case live(target: GitDiffTarget, path: String)
        case shared(
            backing: BridgeSharedReviewContentBacking,
            identity: BridgeSharedReviewContentIdentity
        )
    }

    struct ContentLocator: Sendable {
        let registrationIdentity: UUID
        let source: ContentSource
        let reviewGeneration: BridgeReviewGeneration
    }

    struct ContentLocatorIdentity: Hashable, Sendable {
        let handleId: String
        let reviewGeneration: BridgeReviewGeneration
    }

    struct FileDescriptorInput: Sendable {
        let path: String
        let endpoint: BridgeSourceEndpoint
        let reviewGeneration: BridgeReviewGeneration
        let sizeBytes: Int
        let isBinary: Bool
        let contentHash: String
        let contentHashAlgorithm: String
        let includeContentHandle: Bool
    }

    struct FallbackContentMetadata: Sendable {
        let sizeBytes: Int
        let isBinary: Bool
        let contentHash: String
        let contentHashAlgorithm: String
    }

    struct StatusFallbackSnapshot: Sendable {
        let status: GitStatusSnapshot
        let fullStatusFailure: BridgeProviderFailure?
    }

    let repositoryPath: URL
    let client: LocalClient
    let gitReadContext: BridgeGitReadContext
    let gitDataPlaneReadTimeout: Duration
    let sharedContentRootURL: URL
    var liveLocatorByIdentity: [ContentLocatorIdentity: ContentLocator] = [:]
    var sharedLocatorStackByIdentity: [ContentLocatorIdentity: [ContentLocator]] = [:]

    init(
        repositoryPath: URL,
        client: LocalClient,
        gitReadContext: BridgeGitReadContext,
        gitDataPlaneReadTimeout: Duration = AppPolicies.Bridge.defaultGitDataPlaneReadTimeout,
        sharedContentRootURL: URL = AgentStudioGitBridgeReviewDataClient.defaultSharedContentRootURL
    ) {
        self.repositoryPath = repositoryPath
        self.client = client
        self.gitReadContext = gitReadContext
        self.gitDataPlaneReadTimeout = gitDataPlaneReadTimeout
        self.sharedContentRootURL = sharedContentRootURL
    }

    func resolveEndpoint(_ request: BridgeEndpointResolutionRequest) async throws -> BridgeSourceEndpoint {
        try await resolveEndpoint(
            request,
            freshnessKey: BridgeGitReadFreshnessKey(
                token: "\(gitReadContext.scopeKey.token):resolve:\(request.endpoint.providerIdentity)"
            )
        )
    }

    func resolveEndpoint(
        _ request: BridgeEndpointResolutionRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeSourceEndpoint {
        let endpoint = request.endpoint
        guard endpoint.kind == .gitRef else { return endpoint }
        guard !endpoint.providerIdentity.isEmpty else {
            throw BridgeProviderFailure.unavailableEndpoint(endpointId: endpoint.endpointId)
        }
        let resolved = try await loadGitResolvedRevision(
            GitRevisionResolutionRequest(
                repositoryPath: repositoryPath,
                target: .named(endpoint.providerIdentity)
            ),
            freshnessKey: freshnessKey
        )
        return BridgeSourceEndpoint(
            endpointId: endpoint.endpointId,
            kind: endpoint.kind,
            repoId: endpoint.repoId,
            worktreeId: endpoint.worktreeId,
            label: endpoint.label,
            createdAtUnixMilliseconds: endpoint.createdAtUnixMilliseconds,
            contentSetHash: resolved.oid,
            providerIdentity: resolved.oid
        )
    }

    func compareEndpoints(_ request: BridgeEndpointComparisonRequest) async throws -> BridgeEndpointComparison {
        try await compareEndpoints(
            request,
            freshnessKey: gitReadFreshnessKey(for: request.reviewGeneration)
        )
    }

    func compareEndpoints(
        _ request: BridgeEndpointComparisonRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeEndpointComparison {
        let baseTarget = try gitTarget(for: request.baseEndpoint)
        let headTarget = try gitTarget(for: request.headEndpoint)
        let changedFiles: [BridgeEndpointChangedFile]
        do {
            let diff = try await loadGitDiff(
                GitDiffRequest(repositoryPath: repositoryPath, base: baseTarget, compare: headTarget),
                freshnessKey: freshnessKey
            )
            changedFiles = diff.files.map(bridgeChangedFile)
        } catch let failure as BridgeProviderFailure {
            guard shouldRecoverWithStatusFallback(from: failure, baseTarget: baseTarget, headTarget: headTarget) else {
                throw failure
            }
            do {
                changedFiles = try await statusFallbackChangedFiles(
                    baseTarget: baseTarget,
                    headTarget: headTarget,
                    freshnessKey: freshnessKey
                )
            } catch let statusFailure as BridgeProviderFailure {
                guard shouldRetryStatusFallbackWithoutUntracked(from: statusFailure) else {
                    throw statusFailure
                }
                do {
                    let treeFallbackFiles = try await treeFilesystemFallbackChangedFiles(
                        baseTarget: baseTarget,
                        headTarget: headTarget,
                        freshnessKey: freshnessKey
                    )
                    guard !treeFallbackFiles.isEmpty else {
                        throw treeFilesystemFallbackFailure(
                            reason: "empty",
                            statusFailure: statusFailure
                        )
                    }
                    changedFiles = treeFallbackFiles
                } catch let treeFailure as BridgeProviderFailure {
                    throw treeFilesystemFallbackFailure(
                        reason: "failed",
                        statusFailure: statusFailure,
                        treeFailure: treeFailure
                    )
                } catch {
                    throw treeFilesystemFallbackFailure(
                        reason: "failed",
                        statusFailure: statusFailure,
                        treeFailure: .providerFailed(message: unexpectedGitDataPlaneErrorMessage(error))
                    )
                }
            }
        }
        registerContentLocators(
            for: changedFiles,
            baseEndpoint: request.baseEndpoint,
            headEndpoint: request.headEndpoint,
            baseTarget: baseTarget,
            headTarget: headTarget,
            reviewGeneration: request.reviewGeneration
        )
        return BridgeEndpointComparison(
            baseEndpoint: request.baseEndpoint,
            headEndpoint: request.headEndpoint,
            changedFiles: changedFiles
        )
    }

    func readTree(_ request: BridgeTreeReadRequest) async throws -> BridgeTreeReadResult {
        try await readTree(
            request,
            freshnessKey: gitReadFreshnessKey(for: request.reviewGeneration)
        )
    }

    func readTree(
        _ request: BridgeTreeReadRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeTreeReadResult {
        let revision = try gitRevisionTarget(for: request.endpoint)
        var descriptors: [BridgeReviewItemDescriptor] = []
        for path in treeReadPaths(from: request.pathScope) {
            let tree = try await loadGitTree(
                GitTreeReadRequest(
                    repositoryPath: repositoryPath,
                    revision: revision,
                    path: path
                ),
                freshnessKey: freshnessKey
            )
            let treeDescriptors = tree.entries
                .filter { !$0.isTree }
                .map { entry in
                    fileDescriptor(
                        FileDescriptorInput(
                            path: entry.path,
                            endpoint: request.endpoint,
                            reviewGeneration: request.reviewGeneration,
                            sizeBytes: byteCount(entry.sizeBytes),
                            isBinary: false,
                            contentHash: entry.oid,
                            contentHashAlgorithm: "git-oid",
                            includeContentHandle: false
                        )
                    )
                }
            descriptors.append(contentsOf: treeDescriptors)
        }
        return BridgeTreeReadResult(endpoint: request.endpoint, descriptors: descriptors)
    }

    private func treeReadPaths(from pathScope: [String]) -> [String?] {
        pathScope.isEmpty ? [nil] : pathScope.map(Optional.some)
    }

    func readReviewItemDescriptor(_ request: BridgeReviewItemDescriptorRequest) async throws
        -> BridgeReviewItemDescriptor
    {
        try await readReviewItemDescriptor(
            request,
            freshnessKey: gitReadFreshnessKey(for: request.reviewGeneration)
        )
    }

    func readReviewItemDescriptor(
        _ request: BridgeReviewItemDescriptorRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeReviewItemDescriptor {
        let target = try gitTarget(for: request.endpoint)
        let contentRequest = GitContentRequest(
            repositoryPath: repositoryPath,
            target: target,
            path: request.path,
            maxSizeBytes: Int64(AppPolicies.Bridge.contentMaxBytesPerItem)
        )
        do {
            let content = try await loadGitContentPayload(
                contentRequest,
                freshnessKey: freshnessKey
            )
            let descriptor = fileDescriptor(
                FileDescriptorInput(
                    path: request.path,
                    endpoint: request.endpoint,
                    reviewGeneration: request.reviewGeneration,
                    sizeBytes: content.data.count,
                    isBinary: content.isBinary,
                    contentHash: content.contentHash,
                    contentHashAlgorithm: content.contentHashAlgorithm,
                    includeContentHandle: true
                )
            )
            if let handle = descriptor.contentRoles.file {
                liveLocatorByIdentity[contentLocatorIdentity(for: handle)] = ContentLocator(
                    registrationIdentity: UUIDv7.generate(),
                    source: .live(target: target, path: request.path),
                    reviewGeneration: request.reviewGeneration
                )
            }
            return descriptor
        } catch BridgeGitReadSchedulerError.timedOut {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitReadFailure.timeoutMessage)
        } catch BridgeGitReadSchedulerError.capacityReached {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitReadFailure.capacityMessage)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GitDataPlaneError {
            if case .contentTooLarge(_, let sizeBytes, _) = error {
                return fileDescriptor(
                    FileDescriptorInput(
                        path: request.path,
                        endpoint: request.endpoint,
                        reviewGeneration: request.reviewGeneration,
                        sizeBytes: byteCount(sizeBytes),
                        isBinary: false,
                        contentHash: "oversized:\(sizeBytes)",
                        contentHashAlgorithm: "metadata",
                        includeContentHandle: false
                    )
                )
            }
            throw bridgeFailure(for: error)
        } catch {
            throw BridgeProviderFailure.providerFailed(message: unexpectedGitDataPlaneErrorMessage(error))
        }
    }

    private func fileDescriptor(_ input: FileDescriptorInput) -> BridgeReviewItemDescriptor {
        let itemId = "item-\(input.path)"
        let fileClass = BridgeReviewFileClassifier.classify(
            path: input.path,
            isBinary: input.isBinary,
            sizeBytes: input.sizeBytes
        )
        let contentRoles: BridgeReviewItemDescriptor.ContentRoles
        if input.includeContentHandle {
            contentRoles = BridgeReviewItemDescriptor.ContentRoles(
                file: fileContentHandle(input: input, itemId: itemId)
            )
        } else {
            contentRoles = BridgeReviewItemDescriptor.ContentRoles()
        }
        return BridgeReviewItemDescriptor(
            itemId: itemId,
            itemKind: .file,
            itemVersion: input.reviewGeneration.rawValue,
            basePath: input.path,
            headPath: input.path,
            changeKind: .modified,
            fileClass: fileClass,
            language: language(for: input.path),
            extension: fileExtension(for: input.path),
            sizeBytes: input.sizeBytes,
            baseContentHash: nil,
            headContentHash: input.contentHash,
            contentHashAlgorithm: input.contentHashAlgorithm,
            additions: 0,
            deletions: 0,
            isHiddenByDefault: fileClass == .binary || fileClass == .large,
            hiddenReason: hiddenReason(for: fileClass),
            reviewPriority: fileClass == .source || fileClass == .config ? .normal : .low,
            contentRoles: contentRoles,
            cacheKey: contentRoles.allHandles.map(\.cacheKey).joined(separator: "|"),
            provenance: BridgeProvenanceSummary(),
            annotationSummary: BridgeAnnotationSummary(threadCount: 0, unresolvedThreadCount: 0, commentCount: 0),
            reviewState: .unreviewed,
            collapsed: fileClass == .binary || fileClass == .large
        )
    }

    private func fileContentHandle(
        input: FileDescriptorInput,
        itemId: String
    ) -> BridgeContentHandle {
        let handleId = BridgeProductContentHandleIdentity.handleId(
            endpointId: input.endpoint.endpointId,
            itemId: itemId,
            role: .file,
            contentHash: input.contentHash
        )
        return BridgeContentHandle(
            handleId: handleId,
            itemId: itemId,
            role: .file,
            endpointId: input.endpoint.endpointId,
            reviewGeneration: input.reviewGeneration,
            contentHash: input.contentHash,
            contentHashAlgorithm: input.contentHashAlgorithm,
            cacheKey: "\(input.endpoint.endpointId):\(itemId):file:\(input.contentHash)",
            mimeType: mimeType(for: input.path, isBinary: input.isBinary),
            language: language(for: input.path),
            sizeBytes: input.sizeBytes,
            isBinary: input.isBinary
        )
    }

    private func gitRevisionTarget(for endpoint: BridgeSourceEndpoint) throws -> GitRevisionTarget {
        switch endpoint.kind {
        case .gitRef:
            guard !endpoint.providerIdentity.isEmpty else {
                throw BridgeProviderFailure.unavailableEndpoint(endpointId: endpoint.endpointId)
            }
            return .named(endpoint.providerIdentity)
        case .workingTree, .index:
            throw BridgeProviderFailure.providerFailed(
                message: "tree reads for \(endpoint.kind.rawValue) endpoints require SDK tree-target support"
            )
        case .promptCheckpoint, .sessionCheckpoint, .manualCheckpoint, .savedTimeWindowCheckpoint:
            throw BridgeProviderFailure.providerFailed(
                message: "checkpoint endpoint materialization remains AgentStudio-owned: \(endpoint.endpointId)"
            )
        }
    }

    func resolveCheckpointEndpoint(_ request: BridgeCheckpointEndpointRequest) async throws -> BridgeSourceEndpoint {
        throw BridgeProviderFailure.providerFailed(
            message: "checkpoint endpoint resolution remains AgentStudio-owned: \(request.checkpointId)"
        )
    }

    func loadContent(_ request: BridgeContentLoadRequest) async throws -> BridgeContentLoadResult {
        guard let locator = contentLocator(for: request.handle) else {
            throw BridgeProviderFailure.missingContent(handleId: request.handle.handleId)
        }
        guard locator.reviewGeneration == request.requestedGeneration,
            request.handle.reviewGeneration == request.requestedGeneration
        else {
            throw BridgeProviderFailure.staleReviewGeneration(
                storedGeneration: locator.reviewGeneration,
                requestedGeneration: request.requestedGeneration
            )
        }
        let content = try await contentPayload(
            for: locator,
            handle: request.handle,
            requestedGeneration: request.requestedGeneration
        )
        return BridgeContentLoadResult(
            handle: request.handle,
            data: content.data,
            mimeType: request.handle.mimeType,
            contentHash: request.handle.contentHash,
            contentHashAlgorithm: request.handle.contentHashAlgorithm
        )
    }

    func streamContent(
        _ request: BridgeContentStreamRequest,
        chunkByteCount: Int,
        emitChunk: BridgeContentStreamEmitter
    ) async throws -> BridgeContentStreamResult {
        guard let locator = contentLocator(for: request.handle) else {
            throw BridgeProviderFailure.missingContent(handleId: request.handle.handleId)
        }
        guard locator.reviewGeneration == request.requestedGeneration,
            request.handle.reviewGeneration == request.requestedGeneration
        else {
            throw BridgeProviderFailure.staleReviewGeneration(
                storedGeneration: locator.reviewGeneration,
                requestedGeneration: request.requestedGeneration
            )
        }
        guard case .live(target: .workingTree, path: let path) = locator.source else {
            let result = try await loadContent(
                BridgeContentLoadRequest(
                    handle: request.handle,
                    requestedGeneration: request.requestedGeneration
                )
            )
            var offset = 0
            while offset < result.data.count {
                let endOffset = min(offset + chunkByteCount, result.data.count)
                try await emitChunk(result.data.subdata(in: offset..<endOffset))
                offset = endOffset
            }
            return BridgeContentStreamResult(
                handle: request.handle,
                byteCount: result.data.count,
                mimeType: request.handle.mimeType,
                contentHash: request.handle.contentHash,
                contentHashAlgorithm: request.handle.contentHashAlgorithm
            )
        }
        return try await streamWorkingTreeContent(
            handle: request.handle,
            path: path,
            chunkByteCount: chunkByteCount,
            emitChunk: emitChunk
        )
    }

    private func streamWorkingTreeContent(
        handle: BridgeContentHandle,
        path: String,
        chunkByteCount: Int,
        emitChunk: BridgeContentStreamEmitter
    ) async throws -> BridgeContentStreamResult {
        let fileURL = try checkedWorkingTreeFileURL(path: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw BridgeProviderFailure.missingContent(handleId: handle.handleId)
        }
        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw BridgeProviderFailure.providerFailed(message: "gitDataPlane:fileReadFailed")
        }
        defer {
            try? fileHandle.close()
        }
        var byteCount = 0
        while true {
            let chunk: Data?
            do {
                chunk = try fileHandle.read(upToCount: chunkByteCount)
            } catch {
                throw BridgeProviderFailure.providerFailed(message: "gitDataPlane:fileReadFailed")
            }
            guard let chunk, !chunk.isEmpty else { break }
            byteCount += chunk.count
            guard byteCount <= AppPolicies.Bridge.contentMaxBytesPerItem,
                handle.sizeBytesIsExact == false || byteCount <= handle.sizeBytes
            else {
                throw BridgeProviderFailure.oversizedContent(
                    handleId: handle.handleId,
                    sizeBytes: byteCount
                )
            }
            try await emitChunk(chunk)
        }
        return BridgeContentStreamResult(
            handle: handle,
            byteCount: byteCount,
            mimeType: handle.mimeType,
            contentHash: handle.contentHash,
            contentHashAlgorithm: handle.contentHashAlgorithm
        )
    }

    private func checkedWorkingTreeFileURL(path: String) throws -> URL {
        let repositoryURL = repositoryPath.standardizedFileURL
        let fileURL = repositoryURL.appendingPathComponent(path).standardizedFileURL
        let repositoryPathPrefix =
            repositoryURL.path.hasSuffix("/")
            ? repositoryURL.path
            : "\(repositoryURL.path)/"
        guard fileURL.path.hasPrefix(repositoryPathPrefix) else {
            throw BridgeProviderFailure.providerFailed(message: "gitDataPlane:pathEscapesRepository")
        }
        return fileURL
    }

    private func bridgeChangedFile(_ file: GitDiffFile) -> BridgeEndpointChangedFile {
        BridgeEndpointChangedFile(
            fileId: BridgeDirectGitDiffFileIdNormalizer.normalize(file.fileId),
            path: file.path,
            oldPath: file.previousPath,
            changeKind: bridgeChangeKind(file.changeKind),
            language: language(for: file.path),
            fileExtension: fileExtension(for: file.path),
            sizeBytes: byteCount(file.sizeBytes),
            oldContentHash: file.oldContentHash,
            newContentHash: file.newContentHash,
            contentHashAlgorithm: file.contentHashAlgorithm,
            additions: file.additions,
            deletions: file.deletions,
            isBinary: file.isBinary,
            mimeType: mimeType(for: file.path, isBinary: file.isBinary)
        )
    }

    private func registerContentLocators(
        for changedFiles: [BridgeEndpointChangedFile],
        baseEndpoint: BridgeSourceEndpoint,
        headEndpoint: BridgeSourceEndpoint,
        baseTarget: GitDiffTarget,
        headTarget: GitDiffTarget,
        reviewGeneration: BridgeReviewGeneration
    ) {
        for changedFile in changedFiles {
            registerContentLocators(
                for: changedFile,
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                baseTarget: baseTarget,
                headTarget: headTarget,
                reviewGeneration: reviewGeneration
            )
        }
    }

    private func registerContentLocators(
        for changedFile: BridgeEndpointChangedFile,
        baseEndpoint: BridgeSourceEndpoint,
        headEndpoint: BridgeSourceEndpoint,
        baseTarget: GitDiffTarget,
        headTarget: GitDiffTarget,
        reviewGeneration: BridgeReviewGeneration
    ) {
        switch changedFile.changeKind {
        case .added, .copied:
            registerContentLocator(
                changedFile: changedFile,
                endpoint: headEndpoint,
                target: headTarget,
                path: changedFile.path,
                role: .head,
                reviewGeneration: reviewGeneration
            )
        case .deleted:
            registerContentLocator(
                changedFile: changedFile,
                endpoint: baseEndpoint,
                target: baseTarget,
                path: changedFile.oldPath ?? changedFile.path,
                role: .base,
                reviewGeneration: reviewGeneration
            )
        case .modified, .renamed:
            registerContentLocator(
                changedFile: changedFile,
                endpoint: baseEndpoint,
                target: baseTarget,
                path: changedFile.oldPath ?? changedFile.path,
                role: .base,
                reviewGeneration: reviewGeneration
            )
            registerContentLocator(
                changedFile: changedFile,
                endpoint: headEndpoint,
                target: headTarget,
                path: changedFile.path,
                role: .head,
                reviewGeneration: reviewGeneration
            )
        }
    }

    private func registerContentLocator(
        changedFile: BridgeEndpointChangedFile,
        endpoint: BridgeSourceEndpoint,
        target: GitDiffTarget,
        path: String,
        role: BridgeContentHandle.Role,
        reviewGeneration: BridgeReviewGeneration
    ) {
        let handle = BridgeReviewPackageBuilder.contentHandle(
            for: changedFile,
            endpoint: endpoint,
            role: role,
            reviewGeneration: reviewGeneration
        )
        liveLocatorByIdentity[contentLocatorIdentity(for: handle)] = ContentLocator(
            registrationIdentity: UUIDv7.generate(),
            source: .live(target: target, path: path),
            reviewGeneration: reviewGeneration
        )
    }

    func contentLocatorIdentity(for handle: BridgeContentHandle) -> ContentLocatorIdentity {
        ContentLocatorIdentity(
            handleId: handle.handleId,
            reviewGeneration: handle.reviewGeneration
        )
    }

    func contentLocator(for handle: BridgeContentHandle) -> ContentLocator? {
        let identity = contentLocatorIdentity(for: handle)
        return sharedLocatorStackByIdentity[identity]?.last ?? liveLocatorByIdentity[identity]
    }

    func bridgeChangeKind(_ kind: GitDiffChangeKind) -> BridgeFileChangeKind {
        switch kind {
        case .added:
            return .added
        case .copied:
            return .copied
        case .deleted:
            return .deleted
        case .renamed:
            return .renamed
        case .modified, .typeChanged, .unmerged:
            return .modified
        }
    }

    func bridgeChangeKind(_ entry: GitStatusEntry) -> BridgeFileChangeKind {
        if entry.untracked {
            return .added
        }
        if entry.indexState == .renamed || entry.worktreeState == .renamed || entry.previousPath != nil {
            return .renamed
        }
        if entry.indexState == .copied || entry.worktreeState == .copied {
            return .copied
        }
        if entry.indexState == .added || entry.worktreeState == .added {
            return .added
        }
        if entry.indexState == .deleted || entry.worktreeState == .deleted {
            return .deleted
        }
        return .modified
    }

    private func gitTarget(for endpoint: BridgeSourceEndpoint) throws -> GitDiffTarget {
        switch endpoint.kind {
        case .gitRef:
            guard !endpoint.providerIdentity.isEmpty else {
                throw BridgeProviderFailure.unavailableEndpoint(endpointId: endpoint.endpointId)
            }
            return .commit(endpoint.providerIdentity)
        case .workingTree:
            return .workingTree
        case .index:
            return .index
        case .promptCheckpoint, .sessionCheckpoint, .manualCheckpoint, .savedTimeWindowCheckpoint:
            throw BridgeProviderFailure.providerFailed(
                message: "checkpoint endpoint materialization remains AgentStudio-owned: \(endpoint.endpointId)"
            )
        }
    }

    func gitRevisionTarget(for target: GitDiffTarget) throws -> GitRevisionTarget {
        switch target.kind {
        case .commit:
            guard let identifier = target.identifier, !identifier.isEmpty else {
                throw BridgeProviderFailure.providerFailed(message: "commit tree fallback requires an identifier")
            }
            return .named(identifier)
        case .head:
            return .named("HEAD")
        case .index, .workingTree:
            throw BridgeProviderFailure.providerFailed(
                message: "tree fallback requires a revision target, not \(target.kind.rawValue)"
            )
        }
    }

    func libGit2FailureReason(_ message: String) -> String {
        let normalizedMessage = message.lowercased()
        if normalizedMessage.contains("operation not permitted")
            || normalizedMessage.contains("eperm")
        {
            return "operationNotPermitted"
        }
        if normalizedMessage.contains("permission denied")
            || normalizedMessage.contains("eacces")
        {
            return "permissionDenied"
        }
        if normalizedMessage.contains("no such file") || normalizedMessage.contains("not found") {
            return "notFound"
        }
        if normalizedMessage.contains("too many open files") {
            return "tooManyOpenFiles"
        }
        if normalizedMessage.contains("invalid argument") {
            return "invalidArgument"
        }
        if normalizedMessage.contains("could not open")
            || normalizedMessage.contains("failed to open")
            || normalizedMessage.contains("couldn't be opened")
            || normalizedMessage.contains("could not read")
            || normalizedMessage.contains("failed to read")
            || normalizedMessage.contains("changed before we could read")
        {
            return "fileReadFailed"
        }
        if normalizedMessage.contains("could not stat")
            || normalizedMessage.contains("failed to stat")
            || normalizedMessage.contains("lstat")
            || normalizedMessage.contains("stat file")
        {
            return "fileStatFailed"
        }
        if normalizedMessage.contains("could not scan")
            || normalizedMessage.contains("failed to scan")
            || normalizedMessage.contains("could not traverse")
            || normalizedMessage.contains("failed to traverse")
            || normalizedMessage.contains("readdir")
            || normalizedMessage.contains("opendir")
        {
            return "directoryTraversalFailed"
        }
        return "osError"
    }

    func byteCount(_ sizeBytes: Int64?) -> Int {
        guard let sizeBytes else { return 0 }
        return byteCount(sizeBytes)
    }

    func statusFallbackFileId(entry: GitStatusEntry, changeKind: BridgeFileChangeKind) -> String {
        let identity = [
            "status-fallback",
            entry.previousPath ?? "none",
            entry.path,
            changeKind.rawValue,
        ].joined(separator: ":")
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "status-\(digest.prefix(20))"
    }

    func treeFilesystemFallbackFileId(path: String, changeKind: BridgeFileChangeKind) -> String {
        let identity = [
            "tree-filesystem-fallback",
            path,
            changeKind.rawValue,
        ].joined(separator: ":")
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "tree-fs-\(digest.prefix(20))"
    }

    func byteCount(_ sizeBytes: Int64) -> Int {
        Int(min(sizeBytes, Int64(Int.max)))
    }

    func fileExtension(for path: String) -> String? {
        let fileExtension = (path as NSString).pathExtension
        return fileExtension.isEmpty ? nil : fileExtension
    }

    func language(for path: String) -> String? {
        switch fileExtension(for: path)?.lowercased() {
        case "swift":
            return "swift"
        case "ts", "tsx":
            return "typescript"
        case "js", "jsx":
            return "javascript"
        case "json":
            return "json"
        case "md", "mdx":
            return "markdown"
        default:
            return nil
        }
    }

    func mimeType(for path: String, isBinary: Bool) -> String {
        if isBinary {
            return "application/octet-stream"
        }
        switch fileExtension(for: path)?.lowercased() {
        case "swift":
            return "text/x-swift"
        case "json":
            return "application/json"
        case "md", "mdx":
            return "text/markdown"
        default:
            return "text/plain"
        }
    }

    private func hiddenReason(for fileClass: BridgeFileClass) -> String? {
        switch fileClass {
        case .binary, .large:
            return fileClass.rawValue
        case .source, .test, .docs, .config, .generated, .vendor, .fixture, .unknown:
            return nil
        }
    }
}

extension AgentStudioGitBridgeReviewDataClient where LocalClient == LibGit2AgentStudioGitLocalClient {
    init(repositoryPath: URL, gitReadContext: BridgeGitReadContext) {
        self.init(
            repositoryPath: repositoryPath,
            client: LibGit2AgentStudioGitLocalClient(),
            gitReadContext: gitReadContext
        )
    }
}

private enum BridgeDirectGitDiffFileIdNormalizer {
    private static let itemIdPrefixByteCount = "item-".utf8.count
    private static let maximumFileIdByteCount =
        BridgeProductWireContract.maximumIdentifierByteLength - itemIdPrefixByteCount
    private static let allowedIdentifierCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-"
    )
    private static let hashDomain = "agentstudio-bridge-direct-git-diff-file-id-v1"

    static func normalize(_ candidate: String) -> String {
        if !candidate.isEmpty,
            candidate.utf8.count <= maximumFileIdByteCount,
            candidate.unicodeScalars.allSatisfy({ allowedIdentifierCharacters.contains($0) })
        {
            return candidate
        }
        let hashInput = Data("\(hashDomain):\(candidate)".utf8)
        let digest = SHA256.hash(data: hashInput)
            .map { String(format: "%02x", $0) }
            .joined()
        return "git-diff-\(digest)"
    }
}
