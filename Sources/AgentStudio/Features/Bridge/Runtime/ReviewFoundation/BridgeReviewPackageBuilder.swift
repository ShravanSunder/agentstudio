import Foundation

struct BridgeReviewPackageBuildRequest: Equatable, Sendable {
    let packageId: String
    let query: BridgeReviewQuery
    let comparison: BridgeEndpointComparison
    let checkpointIds: [String]
    let reviewGeneration: BridgeReviewGeneration
    let generatedAtUnixMilliseconds: Int64
}

struct BridgeReviewDescriptorPackageBuildRequest: Equatable, Sendable {
    let packageId: String
    let query: BridgeReviewQuery
    let baseEndpoint: BridgeSourceEndpoint
    let headEndpoint: BridgeSourceEndpoint
    let descriptors: [BridgeReviewItemDescriptor]
    let checkpointIds: [String]
    let reviewGeneration: BridgeReviewGeneration
    let generatedAtUnixMilliseconds: Int64
}

enum BridgeReviewPackageBuilder {
    static func build(request: BridgeReviewPackageBuildRequest) throws -> BridgeReviewPackage {
        let descriptors = request.comparison.changedFiles.map { changedFile in
            descriptor(
                for: changedFile,
                baseEndpoint: request.comparison.baseEndpoint,
                headEndpoint: request.comparison.headEndpoint,
                reviewGeneration: request.reviewGeneration,
                filter: request.query.viewFilter
            )
        }
        return try buildFromDescriptors(
            request: BridgeReviewDescriptorPackageBuildRequest(
                packageId: request.packageId,
                query: request.query,
                baseEndpoint: request.comparison.baseEndpoint,
                headEndpoint: request.comparison.headEndpoint,
                descriptors: descriptors,
                checkpointIds: request.checkpointIds,
                reviewGeneration: request.reviewGeneration,
                generatedAtUnixMilliseconds: request.generatedAtUnixMilliseconds
            )
        )
    }

    static func buildFromDescriptors(
        request: BridgeReviewDescriptorPackageBuildRequest
    ) throws -> BridgeReviewPackage {
        let descriptors = request.descriptors
        let groups = BridgeChangeCollator.collate(
            BridgeChangeCollationRequest(
                descriptors: descriptors,
                pathScope: request.query.pathScope,
                filter: request.query.viewFilter,
                grouping: request.query.grouping,
                checkpointIds: request.checkpointIds,
                createdAtUnixMilliseconds: request.generatedAtUnixMilliseconds
            )
        )
        let visibleDescriptors = BridgeChangeCollator.visibleDescriptors(
            from: descriptors,
            pathScope: request.query.pathScope,
            filter: request.query.viewFilter
        )
        let itemsById = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.itemId, $0) })

        return BridgeReviewPackage(
            packageId: request.packageId,
            schemaVersion: 1,
            reviewGeneration: request.reviewGeneration,
            revision: 0,
            query: request.query,
            baseEndpoint: request.baseEndpoint,
            headEndpoint: request.headEndpoint,
            orderedItemIds: descriptors.map(\.itemId),
            itemsById: itemsById,
            groups: groups,
            summary: BridgeChangeCollator.summary(for: descriptors, visibleDescriptors: visibleDescriptors),
            filterState: request.query.viewFilter,
            generatedAtUnixMilliseconds: request.generatedAtUnixMilliseconds
        )
    }

    static func contentHandle(
        for changedFile: BridgeEndpointChangedFile,
        endpoint: BridgeSourceEndpoint,
        role: BridgeContentHandle.Role,
        reviewGeneration: BridgeReviewGeneration
    ) -> BridgeContentHandle {
        let itemId = itemId(for: changedFile)
        let contentHash = contentHash(for: changedFile, role: role)
        let handleId = BridgeContentHandleIdentity.handleId(
            endpointId: endpoint.endpointId,
            itemId: itemId,
            role: role,
            contentHash: contentHash
        )
        return BridgeContentHandle(
            handleId: handleId,
            itemId: itemId,
            role: role,
            endpointId: endpoint.endpointId,
            reviewGeneration: reviewGeneration,
            resourceUrl: BridgeContentHandleIdentity.resourceUrl(
                handleId: handleId,
                reviewGeneration: reviewGeneration
            ),
            contentHash: contentHash,
            contentHashAlgorithm: changedFile.contentHashAlgorithm,
            cacheKey: "\(endpoint.endpointId):\(itemId):\(role.rawValue):\(contentHash)",
            mimeType: changedFile.mimeType,
            language: changedFile.language,
            sizeBytes: changedFile.sizeBytes,
            sizeBytesIsExact: contentHandleSizeBytesIsExact(for: changedFile, role: role),
            isBinary: changedFile.isBinary
        )
    }

    private static func descriptor(
        for changedFile: BridgeEndpointChangedFile,
        baseEndpoint: BridgeSourceEndpoint,
        headEndpoint: BridgeSourceEndpoint,
        reviewGeneration: BridgeReviewGeneration,
        filter: BridgeViewFilter
    ) -> BridgeReviewItemDescriptor {
        let fileClass = BridgeReviewFileClassifier.classify(
            path: changedFile.path,
            isBinary: changedFile.isBinary,
            sizeBytes: changedFile.sizeBytes
        )
        let isHidden = filter.excludedFileClasses.contains(fileClass) || isHiddenByDefault(fileClass)
        let roles = contentRoles(
            for: changedFile,
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            reviewGeneration: reviewGeneration
        )
        let itemId = itemId(for: changedFile)
        return BridgeReviewItemDescriptor(
            itemId: itemId,
            itemKind: .diff,
            itemVersion: reviewGeneration.rawValue,
            basePath: changedFile.oldPath ?? changedFile.path,
            headPath: changedFile.changeKind == .deleted ? nil : changedFile.path,
            changeKind: changedFile.changeKind,
            fileClass: fileClass,
            language: changedFile.language,
            extension: changedFile.fileExtension,
            sizeBytes: changedFile.sizeBytes,
            baseContentHash: changedFile.oldContentHash,
            headContentHash: changedFile.newContentHash,
            contentHashAlgorithm: changedFile.contentHashAlgorithm,
            additions: changedFile.additions,
            deletions: changedFile.deletions,
            isHiddenByDefault: isHidden,
            hiddenReason: isHidden ? fileClass.rawValue : nil,
            reviewPriority: fileClass == .source || fileClass == .config ? .normal : .low,
            contentRoles: roles,
            cacheKey: roles.allHandles.map(\.cacheKey).joined(separator: "|"),
            provenance: BridgeProvenanceSummary(),
            annotationSummary: BridgeAnnotationSummary(threadCount: 0, unresolvedThreadCount: 0, commentCount: 0),
            reviewState: .unreviewed,
            collapsed: isHidden
        )
    }

    private static func contentRoles(
        for changedFile: BridgeEndpointChangedFile,
        baseEndpoint: BridgeSourceEndpoint,
        headEndpoint: BridgeSourceEndpoint,
        reviewGeneration: BridgeReviewGeneration
    ) -> BridgeReviewItemDescriptor.ContentRoles {
        switch changedFile.changeKind {
        case .added, .copied:
            return BridgeReviewItemDescriptor.ContentRoles(
                head: contentHandle(
                    for: changedFile,
                    endpoint: headEndpoint,
                    role: .head,
                    reviewGeneration: reviewGeneration
                )
            )
        case .deleted:
            return BridgeReviewItemDescriptor.ContentRoles(
                base: contentHandle(
                    for: changedFile,
                    endpoint: baseEndpoint,
                    role: .base,
                    reviewGeneration: reviewGeneration
                )
            )
        case .modified, .renamed:
            return BridgeReviewItemDescriptor.ContentRoles(
                base: contentHandle(
                    for: changedFile,
                    endpoint: baseEndpoint,
                    role: .base,
                    reviewGeneration: reviewGeneration
                ),
                head: contentHandle(
                    for: changedFile,
                    endpoint: headEndpoint,
                    role: .head,
                    reviewGeneration: reviewGeneration
                )
            )
        }
    }

    private static func itemId(for changedFile: BridgeEndpointChangedFile) -> String {
        "item-\(changedFile.fileId)"
    }

    private static func contentHash(
        for changedFile: BridgeEndpointChangedFile,
        role: BridgeContentHandle.Role
    ) -> String {
        switch role {
        case .base:
            return changedFile.oldContentHash ?? "missing-base"
        case .head, .file:
            return changedFile.newContentHash ?? changedFile.oldContentHash ?? "unknown"
        case .diff:
            return "\(changedFile.oldContentHash ?? "none")...\(changedFile.newContentHash ?? "none")"
        }
    }

    private static func contentHandleSizeBytesIsExact(
        for changedFile: BridgeEndpointChangedFile,
        role: BridgeContentHandle.Role
    ) -> Bool {
        switch changedFile.changeKind {
        case .modified, .renamed:
            role != .base
        case .added, .copied, .deleted:
            true
        }
    }

    private static func isHiddenByDefault(_ fileClass: BridgeFileClass) -> Bool {
        switch fileClass {
        case .generated, .vendor, .binary, .large, .fixture:
            return true
        case .source, .test, .docs, .config, .unknown:
            return false
        }
    }
}
