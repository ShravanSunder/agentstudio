import Foundation

struct BridgeSharedReviewContentLocator: Equatable, Sendable {
    let providerIdentity: String
    let contentIdentity: String
    let digest: String
}

struct BridgeSharedReviewDescriptorCore: Equatable, Sendable {
    let itemIdentity: String
    let semanticVersion: String
    let baseLocator: BridgeSharedReviewContentLocator?
    let headLocator: BridgeSharedReviewContentLocator?
}

enum BridgeSharedReviewEndpointRole: Equatable, Sendable {
    case base
    case head
}

struct BridgeSharedReviewContentHandleTemplate: Equatable, Sendable {
    let identity: BridgeSharedReviewContentIdentity
    let endpointRole: BridgeSharedReviewEndpointRole
    let contentHashAlgorithm: String
    let mimeType: String
    let language: String?
    let sizeBytes: Int
    let sizeBytesIsExact: Bool
    let isBinary: Bool

    func bind(
        endpoint: BridgeSourceEndpoint,
        reviewGeneration: BridgeReviewGeneration
    ) -> BridgeContentHandle {
        let handleId = BridgeProductContentHandleIdentity.handleId(
            endpointId: endpoint.endpointId,
            itemId: identity.itemIdentity,
            role: identity.role,
            contentHash: identity.contentHash
        )
        return BridgeContentHandle(
            handleId: handleId,
            itemId: identity.itemIdentity,
            role: identity.role,
            endpointId: endpoint.endpointId,
            reviewGeneration: reviewGeneration,
            contentHash: identity.contentHash,
            contentHashAlgorithm: contentHashAlgorithm,
            cacheKey:
                "\(endpoint.endpointId):\(identity.itemIdentity):\(identity.role.rawValue):\(identity.contentHash)",
            mimeType: mimeType,
            language: language,
            sizeBytes: sizeBytes,
            sizeBytesIsExact: sizeBytesIsExact,
            isBinary: isBinary
        )
    }
}

struct BridgeSharedReviewItemDescriptorTemplate: Equatable, Sendable {
    let itemId: String
    let semanticItemVersion: Int
    let itemKind: BridgeReviewItemDescriptor.Kind
    let basePath: String?
    let headPath: String?
    let changeKind: BridgeFileChangeKind
    let fileClass: BridgeFileClass
    let language: String?
    let fileExtension: String?
    let sizeBytes: Int
    let baseContentHash: String?
    let headContentHash: String?
    let contentHashAlgorithm: String
    let additions: Int
    let deletions: Int
    let isHiddenByDefault: Bool
    let hiddenReason: String?
    let reviewPriority: BridgeReviewPriority
    let baseHandle: BridgeSharedReviewContentHandleTemplate?
    let headHandle: BridgeSharedReviewContentHandleTemplate?
    let diffHandle: BridgeSharedReviewContentHandleTemplate?
    let fileHandle: BridgeSharedReviewContentHandleTemplate?
    let provenance: BridgeProvenanceSummary
    let annotationSummary: BridgeAnnotationSummary
    let reviewState: BridgeFileReviewState
    let collapsed: Bool

    func bind(
        baseEndpoint: BridgeSourceEndpoint,
        headEndpoint: BridgeSourceEndpoint,
        reviewGeneration: BridgeReviewGeneration
    ) -> BridgeReviewItemDescriptor {
        func bindHandle(
            _ template: BridgeSharedReviewContentHandleTemplate?
        ) -> BridgeContentHandle? {
            guard let template else { return nil }
            let endpoint =
                template.endpointRole == .base
                ? baseEndpoint
                : headEndpoint
            return template.bind(endpoint: endpoint, reviewGeneration: reviewGeneration)
        }
        let roles = BridgeReviewItemDescriptor.ContentRoles(
            base: bindHandle(baseHandle),
            head: bindHandle(headHandle),
            diff: bindHandle(diffHandle),
            file: bindHandle(fileHandle)
        )
        return BridgeReviewItemDescriptor(
            itemId: itemId,
            itemKind: itemKind,
            itemVersion: semanticItemVersion,
            basePath: basePath,
            headPath: headPath,
            changeKind: changeKind,
            fileClass: fileClass,
            language: language,
            extension: fileExtension,
            sizeBytes: sizeBytes,
            baseContentHash: baseContentHash,
            headContentHash: headContentHash,
            contentHashAlgorithm: contentHashAlgorithm,
            additions: additions,
            deletions: deletions,
            isHiddenByDefault: isHiddenByDefault,
            hiddenReason: hiddenReason,
            reviewPriority: reviewPriority,
            contentRoles: roles,
            cacheKey: roles.allHandles.map(\.cacheKey).joined(separator: "|"),
            provenance: provenance,
            annotationSummary: annotationSummary,
            reviewState: reviewState,
            collapsed: collapsed
        )
    }
}

struct BridgeSharedReviewGroup: Equatable, Sendable {
    let groupIdentity: String
    let orderedItemIdentities: [String]
}

struct BridgeSharedReviewSummary: Equatable, Sendable {
    let filesChanged: Int
    let additions: Int
    let deletions: Int
}

struct BridgeSharedReviewPackageTemplate: Sendable {
    let baseEndpoint: BridgeResolvedReviewEndpointKey
    let headEndpoint: BridgeResolvedReviewEndpointKey
    let orderedItemIdentities: [String]
    let descriptorCores: [BridgeSharedReviewDescriptorCore]
    let groups: [BridgeSharedReviewGroup]
    let summary: BridgeSharedReviewSummary
    let retainedByteCount: Int
    let itemTemplates: [BridgeSharedReviewItemDescriptorTemplate]
    let backing: BridgeSharedReviewContentBacking?

    init(
        baseEndpoint: BridgeResolvedReviewEndpointKey,
        headEndpoint: BridgeResolvedReviewEndpointKey,
        orderedItemIdentities: [String],
        descriptorCores: [BridgeSharedReviewDescriptorCore],
        groups: [BridgeSharedReviewGroup],
        summary: BridgeSharedReviewSummary,
        retainedByteCount: Int,
        itemTemplates: [BridgeSharedReviewItemDescriptorTemplate] = [],
        backing: BridgeSharedReviewContentBacking? = nil
    ) {
        self.baseEndpoint = baseEndpoint
        self.headEndpoint = headEndpoint
        self.orderedItemIdentities = orderedItemIdentities
        self.descriptorCores = descriptorCores
        self.groups = groups
        self.summary = summary
        self.retainedByteCount = retainedByteCount
        self.itemTemplates = itemTemplates
        self.backing = backing
    }

    var contentLocatorCount: Int {
        if let backing {
            return backing.locatorCount
        }
        return descriptorCores.reduce(into: 0) { count, descriptor in
            count += descriptor.baseLocator == nil ? 0 : 1
            count += descriptor.headLocator == nil ? 0 : 1
        }
    }

    func invalidateBacking() {
        backing?.invalidate()
    }
}

extension BridgeSharedReviewPackageTemplate: Equatable {
    static func == (left: Self, right: Self) -> Bool {
        left.baseEndpoint == right.baseEndpoint
            && left.headEndpoint == right.headEndpoint
            && left.orderedItemIdentities == right.orderedItemIdentities
            && left.descriptorCores == right.descriptorCores
            && left.groups == right.groups
            && left.summary == right.summary
            && left.retainedByteCount == right.retainedByteCount
            && left.itemTemplates == right.itemTemplates
    }
}
