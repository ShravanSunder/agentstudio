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
        let lines = worktreeAnnotationSourceFileLines(source)
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

    /// Read exactly the file a descriptor authorizes and prove its bytes are
    /// the ones the descriptor names.
    static func readCompleteDescribedFile(_ plan: BridgePaneProductFileContentReadPlan) async throws -> Data {
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
        guard data.count == plan.descriptor.declaredByteLength,
            sha256Hex(data) == plan.descriptor.expectedSha256
        else {
            throw WorktreeAnnotationSourceResolutionError.invalidSource
        }
        return data
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Review shows `reviewScope`, the pane's one Review worktree. Files shows
    /// whatever its source lists now: every member worktree plus each loose
    /// opened document.
    static func resolver(
        fileMetadataSource: any BridgePaneProductFileMetadataProducing,
        reviewScope: WorktreeAnnotationScope?,
        reviewPublicationCoordinator: BridgeReviewPublicationCoordinator,
        reviewContentLoaderCache: BridgeReviewContentLoaderCache,
        gitEvidenceSource: (any WorktreeAnnotationGitEvidenceSource)? = nil
    ) -> WorktreeAnnotationSourceResolver {
        WorktreeAnnotationSourceResolver(
            scope: annotationScopeResolver(fileMetadataSource: fileMetadataSource, reviewScope: reviewScope),
            capture: annotationCaptureResolver(
                fileMetadataSource: fileMetadataSource,
                reviewPublicationCoordinator: reviewPublicationCoordinator,
                reviewContentLoaderCache: reviewContentLoaderCache
            ),
            currentFingerprint: annotationFingerprintResolver(
                fileMetadataSource: fileMetadataSource,
                reviewPublicationCoordinator: reviewPublicationCoordinator
            ),
            refresh: annotationRefreshResolver(
                fileMetadataSource: fileMetadataSource,
                reviewPublicationCoordinator: reviewPublicationCoordinator,
                reviewContentLoaderCache: reviewContentLoaderCache
            ),
            currentSourceGeneration: annotationSourceGenerationResolver(
                fileMetadataSource: fileMetadataSource,
                reviewPublicationCoordinator: reviewPublicationCoordinator
            ),
            currentReviewedSubjectEvidence: reviewedSubjectEvidenceResolver(
                fileMetadataSource: fileMetadataSource,
                reviewPublicationCoordinator: reviewPublicationCoordinator,
                gitEvidenceSource: gitEvidenceSource
            ),
            ancestryDisposition: annotationAncestryResolver(gitEvidenceSource: gitEvidenceSource)
        )
    }

    private static func annotationScopeResolver(
        fileMetadataSource: any BridgePaneProductFileMetadataProducing,
        reviewScope: WorktreeAnnotationScope?
    ) -> WorktreeAnnotationSourceResolver.Scope {
        { surface in
            switch surface {
            case .file:
                return try await fileMetadataSource.worktreeAnnotationScope()
            case .review:
                guard let reviewScope else { throw WorktreeAnnotationSourceResolutionError.unavailable }
                return reviewScope
            }
        }
    }

    private static func annotationCaptureResolver(
        fileMetadataSource: any BridgePaneProductFileMetadataProducing,
        reviewPublicationCoordinator: BridgeReviewPublicationCoordinator,
        reviewContentLoaderCache: BridgeReviewContentLoaderCache
    ) -> WorktreeAnnotationSourceResolver.Capture {
        { origin, surface, reviewPublicationIdentity, productAdmission in
            switch surface {
            case .file:
                try await fileMetadataSource.captureWorktreeAnnotationSource(
                    origin: origin,
                    productAdmission: productAdmission
                )
            case .review:
                try await captureReviewSource(
                    origin: origin,
                    identity: try requireReviewIdentity(reviewPublicationIdentity),
                    publicationCoordinator: reviewPublicationCoordinator,
                    contentLoaderCache: reviewContentLoaderCache,
                    productAdmission: productAdmission
                )
            }
        }
    }

    private static func annotationFingerprintResolver(
        fileMetadataSource: any BridgePaneProductFileMetadataProducing,
        reviewPublicationCoordinator: BridgeReviewPublicationCoordinator
    ) -> WorktreeAnnotationSourceResolver.CurrentFingerprint {
        { surface, reviewPublicationIdentity, productAdmission, subject in
            switch surface {
            case .file:
                return try await fileMetadataSource.currentWorktreeAnnotationFingerprint(
                    subject: subject,
                    productAdmission: productAdmission
                )
            case .review:
                let fingerprint = try await reviewFingerprint(
                    identity: try requireReviewIdentity(reviewPublicationIdentity),
                    publicationCoordinator: reviewPublicationCoordinator,
                    productAdmission: productAdmission
                )
                guard fingerprint.subject.key == subject.key else {
                    throw WorktreeAnnotationSourceResolutionError.unavailable
                }
                return fingerprint
            }
        }
    }

    private static func annotationRefreshResolver(
        fileMetadataSource: any BridgePaneProductFileMetadataProducing,
        reviewPublicationCoordinator: BridgeReviewPublicationCoordinator,
        reviewContentLoaderCache: BridgeReviewContentLoaderCache
    ) -> WorktreeAnnotationSourceResolver.Refresh {
        { surface, reviewPublicationIdentity, productAdmission, subject, requirements in
            switch surface {
            case .file:
                return try await fileMetadataSource.currentWorktreeAnnotationRefresh(
                    subject: subject,
                    requirements: requirements,
                    productAdmission: productAdmission
                )
            case .review:
                let capture = try await reviewRefresh(
                    identity: try requireReviewIdentity(reviewPublicationIdentity),
                    publicationCoordinator: reviewPublicationCoordinator,
                    contentLoaderCache: reviewContentLoaderCache,
                    requirements: requirements,
                    productAdmission: productAdmission
                )
                guard capture.fingerprint.subject.key == subject.key else {
                    throw WorktreeAnnotationSourceResolutionError.unavailable
                }
                return capture
            }
        }
    }

    private static func annotationSourceGenerationResolver(
        fileMetadataSource: any BridgePaneProductFileMetadataProducing,
        reviewPublicationCoordinator: BridgeReviewPublicationCoordinator
    ) -> WorktreeAnnotationSourceResolver.CurrentSourceGeneration {
        { surface, reviewPublicationIdentity, productAdmission in
            switch surface {
            case .file:
                return try await fileMetadataSource.currentWorktreeAnnotationSourceGeneration(
                    productAdmission: productAdmission
                )
            case .review:
                let publication = try await retainedReviewPublication(
                    identity: try requireReviewIdentity(reviewPublicationIdentity),
                    publicationCoordinator: reviewPublicationCoordinator,
                    productAdmission: productAdmission
                )
                return publication.package.reviewGeneration.rawValue
            }
        }
    }

    private static func reviewedSubjectEvidenceResolver(
        fileMetadataSource: any BridgePaneProductFileMetadataProducing,
        reviewPublicationCoordinator: BridgeReviewPublicationCoordinator,
        gitEvidenceSource: (any WorktreeAnnotationGitEvidenceSource)?
    ) -> WorktreeAnnotationSourceResolver.CurrentReviewedSubjectEvidence {
        { surface, reviewPublicationIdentity, productAdmission in
            switch surface {
            case .file:
                guard let gitEvidenceSource else {
                    throw WorktreeAnnotationSourceResolutionError.unavailable
                }
                let sourceGeneration =
                    try await fileMetadataSource
                    .currentWorktreeAnnotationSourceGeneration(productAdmission: productAdmission)
                return try await gitEvidenceSource.currentWorktreeAnnotationReviewedSubjectEvidence(
                    sourceGeneration: sourceGeneration
                )
            case .review:
                let publication = try await retainedReviewPublication(
                    identity: try requireReviewIdentity(reviewPublicationIdentity),
                    publicationCoordinator: reviewPublicationCoordinator,
                    productAdmission: productAdmission
                )
                return try reviewedSubjectEvidence(for: publication.package)
            }
        }
    }

    private static func annotationAncestryResolver(
        gitEvidenceSource: (any WorktreeAnnotationGitEvidenceSource)?
    ) -> WorktreeAnnotationAncestryResolver {
        { acceptedOID, currentOID, sourceGeneration in
            guard let gitEvidenceSource else { return .readFailure }
            return try await gitEvidenceSource.worktreeAnnotationAncestryDisposition(
                acceptedReviewedHeadOID: acceptedOID,
                currentReviewedHeadOID: currentOID,
                sourceGeneration: sourceGeneration
            )
        }
    }

    static func reviewRefresh(
        identity: BridgeProductReviewAnnotationPublicationIdentity,
        publicationCoordinator: BridgeReviewPublicationCoordinator,
        contentLoaderCache: BridgeReviewContentLoaderCache,
        requirements: [WorktreeAnnotationSourceRefreshRequirement],
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceRefreshCapture {
        let publication = try await retainedReviewPublication(
            identity: identity,
            publicationCoordinator: publicationCoordinator,
            productAdmission: productAdmission
        )
        let fingerprint = try reviewFingerprint(for: publication.package)
        let candidates = try reviewRefreshCandidates(
            requirements: requirements,
            package: publication.package
        )
        return WorktreeAnnotationSourceRefreshCapture(
            fingerprint: fingerprint,
            material: await reviewMaterial(
                candidates: candidates,
                publication: publication,
                contentLoaderCache: contentLoaderCache,
                productAdmission: productAdmission
            )
        )
    }

    private struct ReviewRefreshCandidate {
        let itemID: String
        let path: String
        let sourceRole: WorktreeAnnotationSourceRole
        let handle: BridgeContentHandle
        let dependentThreadIDs: Set<WorktreeAnnotationThreadID>
    }

    private struct ReviewSourceLoadAdmission {
        let affectedItemIDs: Set<String>
        let cachedUnaffectedResultByHandleID: [String: BridgeContentLoadResult]
    }

    private struct ReviewRefreshRequirement {
        let threadID: WorktreeAnnotationThreadID
        let fallbackPath: String?
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
            try reviewRefreshRequirement(requirement)
        }.map { requirement in
            let exactHandleID = requirement.sourceIdentity.flatMap { sourceIdentity in
                availableHandleKeys.contains(
                    ReviewRefreshHandleKey(
                        sourceRole: requirement.sourceRole.rawValue,
                        handleID: sourceIdentity
                    )
                ) ? sourceIdentity : nil
            }
            let fallbackPath: String? = requirement.fallbackPath.flatMap { fallbackPath in
                guard exactHandleID == nil,
                    orderedItems.contains(where: { item in
                        reviewRefreshCandidate(for: requirement, item: item)?.path == fallbackPath
                    })
                else { return nil }
                return fallbackPath
            }
            return ReviewRefreshRequirement(
                threadID: requirement.threadID,
                fallbackPath: fallbackPath,
                sourceRole: requirement.sourceRole,
                sourceIdentity: requirement.sourceIdentity,
                exactHandleID: exactHandleID
            )
        }
        var candidateIndexByHandleKey: [ReviewRefreshHandleKey: Int] = [:]
        var candidates: [ReviewRefreshCandidate] = []
        for item in orderedItems {
            for requirement in normalizedRequirements {
                guard let candidate = reviewRefreshCandidate(for: requirement, item: item) else {
                    continue
                }
                let handleKey = ReviewRefreshHandleKey(
                    sourceRole: candidate.sourceRole.rawValue,
                    handleID: candidate.handle.handleId
                )
                if let index = candidateIndexByHandleKey[handleKey] {
                    let existing = candidates[index]
                    candidates[index] = ReviewRefreshCandidate(
                        itemID: existing.itemID,
                        path: existing.path,
                        sourceRole: existing.sourceRole,
                        handle: existing.handle,
                        dependentThreadIDs: existing.dependentThreadIDs.union(
                            candidate.dependentThreadIDs
                        )
                    )
                } else {
                    candidateIndexByHandleKey[handleKey] = candidates.count
                    candidates.append(candidate)
                }
            }
        }
        return candidates
    }

    private static func reviewRefreshRequirement(
        _ requirement: WorktreeAnnotationSourceRefreshRequirement
    ) throws -> ReviewRefreshRequirement? {
        switch requirement.origin {
        case .session:
            return nil
        case .wholeFile(let path, let sourceRole):
            guard sourceRole == .reviewBase || sourceRole == .reviewHead else { return nil }
            return ReviewRefreshRequirement(
                threadID: requirement.threadID,
                fallbackPath: path,
                sourceRole: sourceRole,
                sourceIdentity: nil,
                exactHandleID: nil
            )
        case .located(let origin):
            guard origin.sourceRole == .reviewBase || origin.sourceRole == .reviewHead else {
                return nil
            }
            return ReviewRefreshRequirement(
                threadID: requirement.threadID,
                fallbackPath: origin.repositoryRelativePath,
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
        } else if let fallbackPath = requirement.fallbackPath {
            guard currentPath == fallbackPath else { return nil }
        }
        return ReviewRefreshCandidate(
            itemID: item.itemId,
            path: currentPath,
            sourceRole: requirement.sourceRole,
            handle: handle,
            dependentThreadIDs: [requirement.threadID]
        )
    }

    private static func reviewMaterial(
        candidates: [ReviewRefreshCandidate],
        publication: BridgeReviewCommittedPublication,
        contentLoaderCache: BridgeReviewContentLoaderCache,
        productAdmission: BridgeProductAdmissionContext
    ) async -> WorktreeAnnotationSourceMaterial {
        guard !candidates.isEmpty,
            candidates.count <= AppPolicies.Bridge.worktreeAnnotationMaximumSourceCandidateCount
        else {
            return .unavailable
        }
        let proportionalAdmission = await reviewSourceLoadAdmission(
            candidates: candidates,
            publication: publication,
            contentLoaderCache: contentLoaderCache,
            productAdmission: productAdmission
        )
        var files: [WorktreeAnnotationCurrentSourceFile] = []
        var unavailableThreadIDs = Set<WorktreeAnnotationThreadID>()
        files.reserveCapacity(candidates.count)
        for candidate in candidates {
            guard !candidate.path.isEmpty,
                !candidate.handle.isBinary,
                candidate.handle.sizeBytes
                    <= AppPolicies.Bridge.worktreeAnnotationMaximumSourceFileByteCount
            else {
                unavailableThreadIDs.formUnion(candidate.dependentThreadIDs)
                continue
            }
            let result: BridgeContentLoadResult
            if let proportionalAdmission,
                !proportionalAdmission.affectedItemIDs.contains(candidate.itemID)
            {
                guard
                    let cachedResult = proportionalAdmission.cachedUnaffectedResultByHandleID[
                        candidate.handle.handleId
                    ]
                else {
                    unavailableThreadIDs.formUnion(candidate.dependentThreadIDs)
                    continue
                }
                result = cachedResult
            } else {
                do {
                    result = try await contentLoaderCache.load(
                        handle: candidate.handle,
                        productAdmission: productAdmission
                    )
                } catch {
                    unavailableThreadIDs.formUnion(candidate.dependentThreadIDs)
                    continue
                }
            }
            guard
                result.data.count
                    <= AppPolicies.Bridge.worktreeAnnotationMaximumSourceFileByteCount,
                let body = String(data: result.data, encoding: .utf8)
            else {
                unavailableThreadIDs.formUnion(candidate.dependentThreadIDs)
                continue
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
        guard !unavailableThreadIDs.isEmpty else { return .available(files) }
        return .availableWithThreadFailures(
            files: files,
            unavailableThreadIDs: unavailableThreadIDs
        )
    }

    private static func reviewSourceLoadAdmission(
        candidates: [ReviewRefreshCandidate],
        publication: BridgeReviewCommittedPublication,
        contentLoaderCache: BridgeReviewContentLoaderCache,
        productAdmission: BridgeProductAdmissionContext
    ) async -> ReviewSourceLoadAdmission? {
        guard let affectedItemIDs = reviewSourceLoadAffectedItemIDs(publication: publication) else {
            return nil
        }
        let unaffectedHandles = candidates.compactMap { candidate in
            affectedItemIDs.contains(candidate.itemID) ? nil : candidate.handle
        }
        guard
            let cachedResults = await contentLoaderCache.cachedResultsIfAllResident(
                handles: unaffectedHandles,
                productAdmission: productAdmission
            )
        else { return nil }
        return ReviewSourceLoadAdmission(
            affectedItemIDs: affectedItemIDs,
            cachedUnaffectedResultByHandleID: cachedResults
        )
    }

    static func reviewSourceLoadAffectedItemIDs(
        publication: BridgeReviewCommittedPublication
    ) -> Set<String>? {
        guard let delta = publication.delta,
            publication.package.revision > 0,
            delta.packageId == publication.package.packageId,
            delta.reviewGeneration == publication.package.reviewGeneration,
            delta.revision == publication.package.revision
        else { return nil }
        let addedItemIDs = delta.operations.addItems.map(\.itemId)
        let updatedItemIDs = delta.operations.updateItems.map(\.itemId)
        let removedItemIDs = delta.operations.removeItems
        let affectedItemIDs = Set(addedItemIDs + updatedItemIDs + removedItemIDs)
        guard affectedItemIDs.count == addedItemIDs.count + updatedItemIDs.count + removedItemIDs.count,
            addedItemIDs.allSatisfy({ publication.package.itemsById[$0] != nil }),
            updatedItemIDs.allSatisfy({ publication.package.itemsById[$0] != nil }),
            removedItemIDs.allSatisfy({ publication.package.itemsById[$0] == nil })
        else { return nil }
        return affectedItemIDs
    }

    private static func captureReviewSource(
        origin: BridgeProductWorktreeAnnotationOrigin,
        identity: BridgeProductReviewAnnotationPublicationIdentity,
        publicationCoordinator: BridgeReviewPublicationCoordinator,
        contentLoaderCache: BridgeReviewContentLoaderCache,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationCapturedSource {
        let publication = try await retainedReviewPublication(
            identity: identity,
            publicationCoordinator: publicationCoordinator,
            productAdmission: productAdmission
        )
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
        identity: BridgeProductReviewAnnotationPublicationIdentity,
        publicationCoordinator: BridgeReviewPublicationCoordinator,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceFingerprint {
        let publication = try await retainedReviewPublication(
            identity: identity,
            publicationCoordinator: publicationCoordinator,
            productAdmission: productAdmission
        )
        return try reviewFingerprint(for: publication.package)
    }

    private static func reviewedSubjectEvidence(
        for package: BridgeReviewPackage
    ) throws -> WorktreeAnnotationReviewedSubjectEvidence? {
        guard case .contribution(let comparisonOrigin)? = package.comparisonOrigin else {
            return nil
        }
        return try WorktreeAnnotationReviewedSubjectEvidence(
            branchName: comparisonOrigin.reviewedSubjectBranchName,
            reviewedHeadOID: comparisonOrigin.reviewedHeadOID
        )
    }

    private static func retainedReviewPublication(
        identity: BridgeProductReviewAnnotationPublicationIdentity,
        publicationCoordinator: BridgeReviewPublicationCoordinator,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgeReviewCommittedPublication {
        guard
            let publication = await publicationCoordinator.retainedPublication(
                matching: identity,
                productAdmission: productAdmission
            )
        else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        return publication
    }

    private static func requireReviewIdentity(
        _ identity: BridgeProductReviewAnnotationPublicationIdentity?
    ) throws -> BridgeProductReviewAnnotationPublicationIdentity {
        guard let identity else { throw WorktreeAnnotationSourceResolutionError.unavailable }
        return identity
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
            subject: .git(
                repositoryID: package.query.repoId.uuidString.lowercased(),
                worktreeID: package.query.worktreeId.uuidString.lowercased()
            ),
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

struct BridgeWorktreeAnnotationAdmissionDiagnostic: Equatable, Sendable {
    let relations: [BridgeProductAdmissionDiagnosticRelation]
    let selectedGeneration: Int?
}

extension BridgeProductWorktreeAnnotationSourceRole {
    var domainValue: WorktreeAnnotationSourceRole {
        switch self {
        case .file: .file
        case .reviewBase: .reviewBase
        case .reviewHead: .reviewHead
        }
    }
}

extension BridgeProductWorktreeAnnotationDiffSide {
    var domainValue: WorktreeAnnotationDiffSide {
        switch self {
        case .additions: .additions
        case .deletions: .deletions
        }
    }
}
