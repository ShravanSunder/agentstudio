import AgentStudioGit
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
                        repositoryPath: try await fileMetadataSource.worktreeAnnotationRepositoryPath(),
                        publicationCoordinator: reviewPublicationCoordinator,
                        requirements: requirements,
                        productAdmission: productAdmission
                    )
                }
            }
        )
    }

    private static func reviewRefresh(
        repositoryPath: URL,
        publicationCoordinator: BridgeReviewPublicationCoordinator,
        requirements _: [WorktreeAnnotationSourceRefreshRequirement],
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
        guard let comparisonOrigin = fingerprint.reviewComparisonOrigin else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        let candidates: [WorktreeAnnotationSourceMaterialCandidate] =
            publication.package.orderedItemIds.flatMap { itemID -> [WorktreeAnnotationSourceMaterialCandidate] in
                guard let item = publication.package.itemsById[itemID] else { return [] }
                var itemCandidates: [WorktreeAnnotationSourceMaterialCandidate] = []
                if let path = item.basePath, let handle = item.contentRoles.base {
                    itemCandidates.append(
                        .init(
                            path: path,
                            sourceRole: .reviewBase,
                            sourceIdentity: .provided(handle.handleId),
                            target: .commit(comparisonOrigin.baseOID)
                        )
                    )
                }
                if let path = item.headPath, let handle = item.contentRoles.head {
                    itemCandidates.append(
                        .init(
                            path: path,
                            sourceRole: .reviewHead,
                            sourceIdentity: .provided(handle.handleId),
                            target: .commit(comparisonOrigin.reviewedHeadOID)
                        )
                    )
                }
                return itemCandidates
            }
        let provider = GitWorktreeAnnotationSourceMaterialProvider(
            client: LibGit2AgentStudioGitLocalClient()
        )
        return WorktreeAnnotationSourceRefreshCapture(
            fingerprint: fingerprint,
            material: await provider.material(
                .init(repositoryPath: repositoryPath, candidates: candidates)
            )
        )
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
    func worktreeAnnotationRepositoryPath() -> URL {
        authority.worktree.path
    }

    func currentWorktreeAnnotationRefresh(
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
                guard sourceRole == .file else {
                    throw WorktreeAnnotationSourceResolutionError.invalidSource
                }
                candidatePaths.insert(path)
            case .located(let origin):
                guard origin.sourceRole == .file else {
                    throw WorktreeAnnotationSourceResolutionError.invalidSource
                }
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

    func currentWorktreeAnnotationFingerprint(
        productAdmission: BridgeProductAdmissionContext
    ) throws -> WorktreeAnnotationSourceFingerprint {
        let context = try currentAnnotationContext(productAdmission: productAdmission)
        return annotationFingerprint(for: context.productSource)
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
