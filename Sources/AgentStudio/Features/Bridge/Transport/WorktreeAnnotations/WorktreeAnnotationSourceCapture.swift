import AgentStudioGit
import AgentStudioInfrastructure
import CryptoKit
import Foundation

enum WorktreeAnnotationSourceCapture {
    struct LocatedOriginProps {
        let data: Data
        let path: String
        let startLine: Int
        let endLine: Int
        let sourceRole: WorktreeAnnotationSourceRole
        let diffSide: WorktreeAnnotationDiffSide?
        let sourceIdentity: String
    }

    static func locatedOrigin(_ props: LocatedOriginProps) throws -> WorktreeAnnotationLocatedOrigin {
        guard let source = String(bytes: props.data, encoding: .utf8) else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if source.hasSuffix("\n") {
            lines.removeLast()
        }
        guard props.startLine > 0, props.endLine >= props.startLine, props.endLine <= lines.count else {
            throw WorktreeAnnotationSourceResolutionError.invalidSource
        }
        let selectedExcerpt = lines[(props.startLine - 1)...(props.endLine - 1)].joined(separator: "\n")
        let contextBefore = props.startLine > 1 ? lines[props.startLine - 2] : nil
        let contextAfter = props.endLine < lines.count ? lines[props.endLine] : nil
        return WorktreeAnnotationLocatedOrigin(
            repositoryRelativePath: props.path,
            startLine: props.startLine,
            endLine: props.endLine,
            sourceRole: props.sourceRole,
            diffSide: props.diffSide,
            sourceIdentity: props.sourceIdentity,
            selectedExcerpt: selectedExcerpt,
            contextBefore: contextBefore,
            contextAfter: contextAfter
        )
    }

    static func resolver(
        fileMetadataSource: any BridgePaneProductFileMetadataProducing,
        reviewPublicationCoordinator: BridgeReviewPublicationCoordinator,
        reviewContentLoaderCache: BridgeReviewContentLoaderCache
    ) -> WorktreeAnnotationSourceResolver {
        WorktreeAnnotationSourceResolver(
            capture: { origin, surface, productAdmission in
                switch surface {
                case .file:
                    try await fileMetadataSource.captureWorktreeAnnotationSource(
                        origin: origin,
                        productAdmission: productAdmission
                    )
                case .review:
                    try await captureReviewSource(
                        origin: origin,
                        publicationCoordinator: reviewPublicationCoordinator,
                        contentLoaderCache: reviewContentLoaderCache,
                        productAdmission: productAdmission
                    )
                }
            },
            currentFingerprint: { surface, productAdmission in
                switch surface {
                case .file:
                    try await fileMetadataSource.currentWorktreeAnnotationFingerprint(
                        productAdmission: productAdmission
                    )
                case .review:
                    try await reviewFingerprint(
                        publicationCoordinator: reviewPublicationCoordinator,
                        productAdmission: productAdmission
                    )
                }
            },
            refresh: { surface, productAdmission, requirements in
                switch surface {
                case .file:
                    try await fileMetadataSource.currentWorktreeAnnotationRefresh(
                        requirements: requirements,
                        productAdmission: productAdmission
                    )
                case .review:
                    try await reviewRefresh(
                        publicationCoordinator: reviewPublicationCoordinator,
                        contentLoaderCache: reviewContentLoaderCache,
                        requirements: requirements,
                        productAdmission: productAdmission
                    )
                }
            },
            currentSourceGeneration: { surface, productAdmission in
                switch surface {
                case .file:
                    return try await fileMetadataSource.currentWorktreeAnnotationSourceGeneration(
                        productAdmission: productAdmission
                    )
                case .review:
                    guard
                        let publication =
                            await reviewPublicationCoordinator
                            .committedPublicationForReplay(productAdmission: productAdmission)
                    else {
                        throw WorktreeAnnotationSourceResolutionError.unavailable
                    }
                    return publication.package.reviewGeneration.rawValue
                }
            }
        )
    }

    static func reviewRefresh(
        publicationCoordinator: BridgeReviewPublicationCoordinator,
        contentLoaderCache: BridgeReviewContentLoaderCache,
        requirements: [WorktreeAnnotationSourceRefreshRequirement],
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceRefreshCapture {
        guard
            let publication = await publicationCoordinator.committedPublicationForReplay(
                productAdmission: productAdmission
            )
        else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        let fingerprint = try reviewFingerprint(for: publication.package)
        let candidates = try reviewRefreshCandidates(
            requirements: requirements,
            package: publication.package
        )
        return WorktreeAnnotationSourceRefreshCapture(
            fingerprint: fingerprint,
            material: await reviewMaterial(
                candidates: candidates,
                contentLoaderCache: contentLoaderCache,
                productAdmission: productAdmission
            )
        )
    }

    private struct ReviewRefreshCandidate {
        let path: String
        let sourceRole: WorktreeAnnotationSourceRole
        let handle: BridgeContentHandle
    }

    private struct ReviewRefreshRequirement {
        let sourceRole: WorktreeAnnotationSourceRole
        let sourceIdentity: String?
        let exactHandleID: String?
    }

    private struct ReviewRefreshHandleKey: Hashable {
        let sourceRole: String
        let handleID: String
    }

    private static func reviewRefreshCandidates(
        requirements: [WorktreeAnnotationSourceRefreshRequirement],
        package: BridgeReviewPackage
    ) throws -> [ReviewRefreshCandidate] {
        let orderedItems = try package.orderedItemIds.map { itemID in
            guard let item = package.itemsById[itemID] else {
                throw WorktreeAnnotationSourceResolutionError.invalidSource
            }
            return item
        }
        let availableHandleKeys = Set(
            orderedItems.flatMap { item in
                [
                    item.contentRoles.base.map {
                        ReviewRefreshHandleKey(
                            sourceRole: WorktreeAnnotationSourceRole.reviewBase.rawValue,
                            handleID: $0.handleId
                        )
                    },
                    item.contentRoles.head.map {
                        ReviewRefreshHandleKey(
                            sourceRole: WorktreeAnnotationSourceRole.reviewHead.rawValue,
                            handleID: $0.handleId
                        )
                    },
                ].compactMap { $0 }
            }
        )
        let normalizedRequirements = try requirements.compactMap { requirement in
            try reviewRefreshRequirement(for: requirement.origin)
        }.map { requirement in
            let exactHandleID = requirement.sourceIdentity.flatMap { sourceIdentity in
                availableHandleKeys.contains(
                    ReviewRefreshHandleKey(
                        sourceRole: requirement.sourceRole.rawValue,
                        handleID: sourceIdentity
                    )
                ) ? sourceIdentity : nil
            }
            return ReviewRefreshRequirement(
                sourceRole: requirement.sourceRole,
                sourceIdentity: requirement.sourceIdentity,
                exactHandleID: exactHandleID
            )
        }
        var admittedHandleIDs = Set<String>()
        var candidates: [ReviewRefreshCandidate] = []
        for item in orderedItems {
            for requirement in normalizedRequirements {
                guard
                    let candidate = reviewRefreshCandidate(
                        for: requirement,
                        item: item
                    ),
                    admittedHandleIDs.insert(candidate.handle.handleId).inserted
                else { continue }
                candidates.append(candidate)
            }
        }
        return candidates
    }

    private static func reviewRefreshRequirement(
        for origin: WorktreeAnnotationThreadOrigin
    ) throws -> ReviewRefreshRequirement? {
        switch origin {
        case .session:
            return nil
        case .wholeFile(_, let sourceRole):
            guard sourceRole == .reviewBase || sourceRole == .reviewHead else { return nil }
            return ReviewRefreshRequirement(
                sourceRole: sourceRole,
                sourceIdentity: nil,
                exactHandleID: nil
            )
        case .located(let origin):
            guard origin.sourceRole == .reviewBase || origin.sourceRole == .reviewHead else {
                return nil
            }
            return ReviewRefreshRequirement(
                sourceRole: origin.sourceRole,
                sourceIdentity: origin.sourceIdentity,
                exactHandleID: nil
            )
        }
    }

    private static func reviewRefreshCandidate(
        for requirement: ReviewRefreshRequirement,
        item: BridgeReviewItemDescriptor
    ) -> ReviewRefreshCandidate? {
        let currentPath: String?
        let handle: BridgeContentHandle?
        switch requirement.sourceRole {
        case .reviewBase:
            currentPath = item.basePath
            handle = item.contentRoles.base
        case .reviewHead:
            currentPath = item.headPath
            handle = item.contentRoles.head
        case .file:
            return nil
        }
        guard let currentPath, let handle else { return nil }
        if let exactHandleID = requirement.exactHandleID {
            guard handle.handleId == exactHandleID else { return nil }
        }
        return ReviewRefreshCandidate(
            path: currentPath,
            sourceRole: requirement.sourceRole,
            handle: handle
        )
    }

    private static func reviewMaterial(
        candidates: [ReviewRefreshCandidate],
        contentLoaderCache: BridgeReviewContentLoaderCache,
        productAdmission: BridgeProductAdmissionContext
    ) async -> WorktreeAnnotationSourceMaterial {
        guard !candidates.isEmpty,
            candidates.count <= AppPolicies.Bridge.worktreeAnnotationMaximumSourceCandidateCount
        else {
            return .unavailable
        }
        var files: [WorktreeAnnotationCurrentSourceFile] = []
        files.reserveCapacity(candidates.count)
        for candidate in candidates {
            guard !candidate.path.isEmpty,
                !candidate.handle.isBinary,
                candidate.handle.sizeBytes
                    <= AppPolicies.Bridge.worktreeAnnotationMaximumSourceFileByteCount
            else {
                return .unavailable
            }
            let result: BridgeContentLoadResult
            do {
                result = try await contentLoaderCache.load(
                    handle: candidate.handle,
                    productAdmission: productAdmission
                )
            } catch {
                return .unavailable
            }
            guard
                result.data.count
                    <= AppPolicies.Bridge.worktreeAnnotationMaximumSourceFileByteCount,
                let body = String(data: result.data, encoding: .utf8)
            else {
                return .unavailable
            }
            files.append(
                WorktreeAnnotationCurrentSourceFile(
                    path: candidate.path,
                    sourceRole: candidate.sourceRole,
                    sourceIdentity: candidate.handle.handleId,
                    body: body
                )
            )
        }
        return .available(files)
    }

    private static func captureReviewSource(
        origin: BridgeProductWorktreeAnnotationOrigin,
        publicationCoordinator: BridgeReviewPublicationCoordinator,
        contentLoaderCache: BridgeReviewContentLoaderCache,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationCapturedSource {
        guard
            let publication = await publicationCoordinator.committedPublicationForReplay(
                productAdmission: productAdmission
            )
        else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        let fingerprint = try reviewFingerprint(for: publication.package)
        let resolved = try reviewHandle(
            path: origin.path,
            sourceRole: origin.sourceRole,
            package: publication.package
        )
        guard resolved.handle.handleId == origin.sourceIdentity else {
            throw WorktreeAnnotationSourceResolutionError.invalidSource
        }
        let content = try await contentLoaderCache.load(
            handle: resolved.handle,
            productAdmission: productAdmission
        )
        let locatedOrigin = try locatedOrigin(
            .init(
                data: content.data,
                path: origin.path,
                startLine: origin.startLine,
                endLine: origin.endLine,
                sourceRole: origin.sourceRole.domainValue,
                diffSide: origin.diffSide?.domainValue,
                sourceIdentity: origin.sourceIdentity
            )
        )
        return .init(fingerprint: fingerprint, origin: .located(locatedOrigin))
    }

    private static func reviewFingerprint(
        publicationCoordinator: BridgeReviewPublicationCoordinator,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceFingerprint {
        guard
            let publication = await publicationCoordinator.committedPublicationForReplay(
                productAdmission: productAdmission
            )
        else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        return try reviewFingerprint(for: publication.package)
    }

    private static func reviewFingerprint(
        for package: BridgeReviewPackage
    ) throws -> WorktreeAnnotationSourceFingerprint {
        guard case .contribution(let comparisonOrigin)? = package.comparisonOrigin else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let symbolicTargetData = try encoder.encode(comparisonOrigin.symbolicTarget)
        guard let symbolicTarget = String(data: symbolicTargetData, encoding: .utf8) else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        return WorktreeAnnotationSourceFingerprint(
            repositoryID: package.query.repoId.uuidString.lowercased(),
            worktreeID: package.query.worktreeId.uuidString.lowercased(),
            fileSourceIdentity: nil,
            reviewComparisonOrigin: .init(
                symbolicTarget: symbolicTarget,
                resolvedTargetOID: comparisonOrigin.resolvedTargetOID,
                reviewedHeadOID: comparisonOrigin.reviewedHeadOID,
                baseRole: comparisonOrigin.baseRole.rawValue,
                baseOID: comparisonOrigin.baseOID
            )
        )
    }

    private static func reviewHandle(
        path: String,
        sourceRole: BridgeProductWorktreeAnnotationSourceRole,
        package: BridgeReviewPackage
    ) throws -> (item: BridgeReviewItemDescriptor, handle: BridgeContentHandle) {
        let matches: [(BridgeReviewItemDescriptor, BridgeContentHandle)] =
            package.itemsById.values.compactMap { item in
                switch sourceRole {
                case .reviewBase:
                    guard item.basePath == path, let handle = item.contentRoles.base else { return nil }
                    return (item, handle)
                case .reviewHead:
                    guard item.headPath == path, let handle = item.contentRoles.head else { return nil }
                    return (item, handle)
                case .file:
                    return nil
                }
            }
        guard matches.count == 1, let match = matches.first else {
            throw WorktreeAnnotationSourceResolutionError.invalidSource
        }
        return match
    }
}

extension BridgePaneProductFileMetadataSource {
    func worktreeAnnotationAdmissionDiagnostic(
        to productAdmission: BridgeProductAdmissionContext
    ) -> BridgeWorktreeAnnotationAdmissionDiagnostic {
        let relations = contextBySubscriptionId.values.map {
            $0.productAdmission.diagnosticRelation(to: productAdmission)
        }
        return BridgeWorktreeAnnotationAdmissionDiagnostic(
            relations: relations,
            selectedGeneration: try? currentAnnotationContext(
                productAdmission: productAdmission
            ).productSource.subscriptionGeneration
        )
    }

    func worktreeAnnotationRepositoryPath() -> URL {
        authority.worktree.path
    }

    func worktreeAnnotationRefreshImplementation(
        requirements: [WorktreeAnnotationSourceRefreshRequirement],
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceRefreshCapture {
        let context = try currentAnnotationContext(productAdmission: productAdmission)
        var candidatePaths = Set<String>(
            context.descriptorByPath.compactMap { path, payload in
                guard case .available = payload.availability else { return nil }
                return path
            }
        )
        for requirement in requirements {
            switch requirement.origin {
            case .session:
                continue
            case .wholeFile(let path, let sourceRole):
                guard sourceRole == .file else { continue }
                candidatePaths.insert(path)
            case .located(let origin):
                guard origin.sourceRole == .file else { continue }
                candidatePaths.insert(origin.repositoryRelativePath)
            }
        }
        let candidates = candidatePaths.sorted().map { path in
            WorktreeAnnotationSourceMaterialCandidate(
                path: path,
                sourceRole: .file,
                sourceIdentity: .currentFileDescriptor,
                target: .workingTree
            )
        }
        let provider = GitWorktreeAnnotationSourceMaterialProvider(
            client: LibGit2AgentStudioGitLocalClient()
        )
        return WorktreeAnnotationSourceRefreshCapture(
            fingerprint: annotationFingerprint(for: context.productSource),
            material: await provider.material(
                .init(repositoryPath: authority.worktree.path, candidates: candidates)
            )
        )
    }

    func captureWorktreeAnnotationSource(
        origin: BridgeProductWorktreeAnnotationOrigin,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationCapturedSource {
        let context = try currentAnnotationContext(productAdmission: productAdmission)
        let fingerprint = annotationFingerprint(for: context.productSource)
        let descriptor = try annotationContentDescriptor(
            path: origin.path,
            sourceIdentity: origin.sourceIdentity,
            context: context
        )
        let data = try await readCompleteAnnotationFile(
            descriptor: descriptor,
            path: origin.path
        )
        return .init(
            fingerprint: fingerprint,
            origin: .located(
                try WorktreeAnnotationSourceCapture.locatedOrigin(
                    .init(
                        data: data,
                        path: origin.path,
                        startLine: origin.startLine,
                        endLine: origin.endLine,
                        sourceRole: origin.sourceRole.domainValue,
                        diffSide: origin.diffSide?.domainValue,
                        sourceIdentity: origin.sourceIdentity
                    )
                )
            )
        )
    }

    func worktreeAnnotationFingerprintImplementation(
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceFingerprint {
        let context = try currentAnnotationContext(productAdmission: productAdmission)
        return annotationFingerprint(for: context.productSource)
    }

    func worktreeAnnotationSourceGenerationImplementation(
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> Int {
        try currentAnnotationContext(productAdmission: productAdmission)
            .productSource.subscriptionGeneration
    }

    private func currentAnnotationContext(
        productAdmission: BridgeProductAdmissionContext
    ) throws -> SubscriptionContext {
        let contexts = contextBySubscriptionId.values.filter {
            $0.productAdmission.matches(productAdmission)
        }
        guard
            let context = contexts.max(by: {
                $0.productSource.subscriptionGeneration < $1.productSource.subscriptionGeneration
            })
        else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        return context
    }

    private func annotationFingerprint(
        for productSource: BridgeProductFileSourceIdentity
    ) -> WorktreeAnnotationSourceFingerprint {
        WorktreeAnnotationSourceFingerprint(
            repositoryID: productSource.repoId.lowercased(),
            worktreeID: productSource.worktreeId.lowercased(),
            fileSourceIdentity: productSource.sourceId,
            reviewComparisonOrigin: nil
        )
    }

    private func annotationContentDescriptor(
        path: String,
        sourceIdentity: String,
        context: SubscriptionContext
    ) throws -> BridgeProductFileContentDescriptor {
        guard
            let payload = context.descriptorByPath[path],
            payload.source == context.productSource,
            case .available(let descriptor) = payload.availability,
            descriptor.descriptorId == sourceIdentity
        else {
            throw WorktreeAnnotationSourceResolutionError.invalidSource
        }
        return descriptor
    }

    private func readCompleteAnnotationFile(
        descriptor: BridgeProductFileContentDescriptor,
        path: String
    ) async throws -> Data {
        let plan = BridgePaneProductFileContentReadPlan(
            descriptor: descriptor,
            relativePath: path,
            rootURL: authority.worktree.path
        )
        let reader = try await BridgePaneProductFileContentSource.openReadSession(plan)
        var data = Data()
        do {
            while let chunk = try await reader.nextChunk(maximumByteCount: 128 * 1024) {
                data.append(chunk)
            }
            await reader.close()
        } catch {
            await reader.close()
            throw error
        }
        guard data.count == descriptor.declaredByteLength,
            SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined()
                == descriptor.expectedSha256
        else {
            throw WorktreeAnnotationSourceResolutionError.invalidSource
        }
        return data
    }
}

struct BridgeWorktreeAnnotationAdmissionDiagnostic: Equatable, Sendable {
    let relations: [BridgeProductAdmissionDiagnosticRelation]
    let selectedGeneration: Int?
}

extension BridgeProductWorktreeAnnotationSourceRole {
    fileprivate var domainValue: WorktreeAnnotationSourceRole {
        switch self {
        case .file: .file
        case .reviewBase: .reviewBase
        case .reviewHead: .reviewHead
        }
    }
}

extension BridgeProductWorktreeAnnotationDiffSide {
    fileprivate var domainValue: WorktreeAnnotationDiffSide {
        switch self {
        case .additions: .additions
        case .deletions: .deletions
        }
    }
}
