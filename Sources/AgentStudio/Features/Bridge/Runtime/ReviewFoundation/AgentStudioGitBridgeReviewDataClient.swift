import AgentStudioGit
import Foundation

/// Thin mapper from the AgentStudioGit SDK into Bridge review contracts.
///
/// The SDK owns Git data-plane reads; Bridge owns endpoint, package, generation,
/// and content-handle semantics. This actor keeps only transient handle locators
/// so later content loads can stay handle-based without putting Git DTOs into
/// `BridgeReviewPipeline` or BridgeWeb contracts.
actor AgentStudioGitBridgeReviewDataClient<LocalClient: AgentStudioGitLocalClient>: BridgeGitReviewDataClient {
    private struct ContentLocator: Sendable {
        let target: GitDiffTarget
        let path: String
        let reviewGeneration: BridgeReviewGeneration
    }

    private struct FileDescriptorInput: Sendable {
        let path: String
        let endpoint: BridgeSourceEndpoint
        let reviewGeneration: BridgeReviewGeneration
        let sizeBytes: Int
        let isBinary: Bool
        let contentHash: String
        let contentHashAlgorithm: String
        let includeContentHandle: Bool
    }

    private let repositoryPath: URL
    private let client: LocalClient
    private let gitDataPlaneReadTimeout: Duration
    private let timeoutScheduler: any BridgeGitDataPlaneTimeoutScheduler
    private var locatorByHandleId: [String: ContentLocator] = [:]

    init(
        repositoryPath: URL,
        client: LocalClient,
        gitDataPlaneReadTimeout: Duration = AppPolicies.Bridge.defaultGitDataPlaneReadTimeout,
        timeoutScheduler: any BridgeGitDataPlaneTimeoutScheduler = DispatchBridgeGitDataPlaneTimeoutScheduler()
    ) {
        self.repositoryPath = repositoryPath
        self.client = client
        self.gitDataPlaneReadTimeout = gitDataPlaneReadTimeout
        self.timeoutScheduler = timeoutScheduler
    }

    func resolveEndpoint(_ request: BridgeEndpointResolutionRequest) async throws -> BridgeSourceEndpoint {
        request.endpoint
    }

    func compareEndpoints(_ request: BridgeEndpointComparisonRequest) async throws -> BridgeEndpointComparison {
        let baseTarget = try gitTarget(for: request.baseEndpoint)
        let headTarget = try gitTarget(for: request.headEndpoint)
        pruneContentLocators(to: request.reviewGeneration)
        let diff = try await loadGitDiff(
            GitDiffRequest(repositoryPath: repositoryPath, base: baseTarget, compare: headTarget)
        )
        let changedFiles = diff.files.map(bridgeChangedFile)
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
        let revision = try gitRevisionTarget(for: request.endpoint)
        var descriptors: [BridgeReviewItemDescriptor] = []
        for path in treeReadPaths(from: request.pathScope) {
            let tree = try await loadGitTree(
                GitTreeReadRequest(
                    repositoryPath: repositoryPath,
                    revision: revision,
                    path: path
                )
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
        let target = try gitTarget(for: request.endpoint)
        pruneContentLocators(to: request.reviewGeneration)
        let contentRequest = GitContentRequest(
            repositoryPath: repositoryPath,
            target: target,
            path: request.path,
            maxSizeBytes: Int64(AppPolicies.Bridge.contentMaxBytesPerItem)
        )
        do {
            let content = try await loadGitContentPayload(contentRequest)
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
                locatorByHandleId[handle.handleId] = ContentLocator(
                    target: target,
                    path: request.path,
                    reviewGeneration: request.reviewGeneration
                )
            }
            return descriptor
        } catch BridgeGitDataPlaneTimeoutError.timedOut {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitDataPlaneTimeoutFailure.message)
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
            throw BridgeProviderFailure.providerFailed(message: String(describing: error))
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
        let handleId = BridgeContentHandleIdentity.handleId(
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
            resourceUrl: BridgeContentHandleIdentity.resourceUrl(
                handleId: handleId,
                reviewGeneration: input.reviewGeneration
            ),
            contentHash: input.contentHash,
            contentHashAlgorithm: input.contentHashAlgorithm,
            cacheKey: "\(input.endpoint.endpointId):\(itemId):file:\(input.contentHash)",
            mimeType: mimeType(for: input.path, isBinary: input.isBinary),
            language: language(for: input.path),
            sizeBytes: input.sizeBytes,
            isBinary: input.isBinary
        )
    }

    private func pruneContentLocators(to reviewGeneration: BridgeReviewGeneration) {
        locatorByHandleId = locatorByHandleId.filter { _, locator in
            locator.reviewGeneration == reviewGeneration
        }
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
        guard let locator = locatorByHandleId[request.handle.handleId] else {
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
        let content = try await loadGitContent(
            GitContentRequest(
                repositoryPath: repositoryPath,
                target: locator.target,
                path: locator.path,
                maxSizeBytes: Int64(AppPolicies.Bridge.contentMaxBytesPerItem)
            ),
            handle: request.handle
        )
        return BridgeContentLoadResult(
            handle: request.handle,
            data: content.data,
            mimeType: request.handle.mimeType,
            contentHash: request.handle.contentHash,
            contentHashAlgorithm: request.handle.contentHashAlgorithm
        )
    }

    private func loadGitDiff(_ request: GitDiffRequest) async throws -> GitDiffSnapshot {
        let client = self.client
        do {
            return try await BridgeGitDataPlaneTimeout.readWithHardTimeout(
                gitDataPlaneReadTimeout,
                timeoutScheduler: timeoutScheduler
            ) {
                try await client.diff(request)
            }
        } catch BridgeGitDataPlaneTimeoutError.timedOut {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitDataPlaneTimeoutFailure.message)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GitDataPlaneError {
            throw bridgeFailure(for: error)
        } catch {
            throw BridgeProviderFailure.providerFailed(message: String(describing: error))
        }
    }

    private func loadGitTree(_ request: GitTreeReadRequest) async throws -> GitTreeSnapshot {
        let client = self.client
        do {
            return try await BridgeGitDataPlaneTimeout.readWithHardTimeout(
                gitDataPlaneReadTimeout,
                timeoutScheduler: timeoutScheduler
            ) {
                try await client.readTree(request)
            }
        } catch BridgeGitDataPlaneTimeoutError.timedOut {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitDataPlaneTimeoutFailure.message)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GitDataPlaneError {
            throw bridgeFailure(for: error)
        } catch {
            throw BridgeProviderFailure.providerFailed(message: String(describing: error))
        }
    }

    private func loadGitContent(
        _ request: GitContentRequest,
        handle: BridgeContentHandle?
    ) async throws -> GitContentPayload {
        do {
            return try await loadGitContentPayload(request)
        } catch BridgeGitDataPlaneTimeoutError.timedOut {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitDataPlaneTimeoutFailure.message)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GitDataPlaneError {
            throw bridgeFailure(for: error, handle: handle)
        } catch {
            throw BridgeProviderFailure.providerFailed(message: String(describing: error))
        }
    }

    private func loadGitContentPayload(_ request: GitContentRequest) async throws -> GitContentPayload {
        let client = self.client
        return try await BridgeGitDataPlaneTimeout.readWithHardTimeout(
            gitDataPlaneReadTimeout,
            timeoutScheduler: timeoutScheduler
        ) {
            try await client.content(request)
        }
    }

    private func bridgeChangedFile(_ file: GitDiffFile) -> BridgeEndpointChangedFile {
        BridgeEndpointChangedFile(
            fileId: file.fileId,
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
        locatorByHandleId[handle.handleId] = ContentLocator(
            target: target,
            path: path,
            reviewGeneration: reviewGeneration
        )
    }

    private func bridgeChangeKind(_ kind: GitDiffChangeKind) -> BridgeFileChangeKind {
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

    private func bridgeFailure(
        for error: GitDataPlaneError,
        handle: BridgeContentHandle? = nil
    ) -> BridgeProviderFailure {
        switch error {
        case .repositoryNotFound:
            return .providerUnavailable
        case .contentTooLarge(_, let sizeBytes, _):
            if let handle {
                return .oversizedContent(handleId: handle.handleId, sizeBytes: byteCount(sizeBytes))
            }
            return .providerFailed(message: "Git content was too large: \(sizeBytes) bytes")
        case .pathEscapesRepository(let path):
            return .providerFailed(message: "Git path escapes repository: \(path)")
        case .libgit2Failure(_, _, let message), .unsupported(let message), .locked(let message):
            return .providerFailed(message: message)
        case .worktreeNotFound, .worktreeNotPrunable, .unsafeWorktreeRemoval,
            .processFailed, .processTimedOut, .processCancelled, .processOutputTooLarge:
            return .providerFailed(message: String(describing: error))
        }
    }

    private func byteCount(_ sizeBytes: Int64?) -> Int {
        guard let sizeBytes else { return 0 }
        return byteCount(sizeBytes)
    }

    private func byteCount(_ sizeBytes: Int64) -> Int {
        Int(min(sizeBytes, Int64(Int.max)))
    }

    private func fileExtension(for path: String) -> String? {
        let fileExtension = (path as NSString).pathExtension
        return fileExtension.isEmpty ? nil : fileExtension
    }

    private func language(for path: String) -> String? {
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

    private func mimeType(for path: String, isBinary: Bool) -> String {
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
    init(repositoryPath: URL) {
        self.init(repositoryPath: repositoryPath, client: LibGit2AgentStudioGitLocalClient())
    }
}
