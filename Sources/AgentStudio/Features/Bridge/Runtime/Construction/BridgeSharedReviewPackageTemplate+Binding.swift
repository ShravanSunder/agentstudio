import CryptoKit
import Foundation

extension BridgeSharedReviewPackageTemplate {
    static func make(
        result: BridgeReviewPipelineResult,
        baseEndpointKey: BridgeResolvedReviewEndpointKey,
        headEndpointKey: BridgeResolvedReviewEndpointKey,
        backing: BridgeSharedReviewContentBacking
    ) -> Self {
        let package = result.package
        let templates = package.orderedItemIds.compactMap { itemId in
            package.itemsById[itemId].map {
                descriptorTemplate($0, baseEndpointId: package.baseEndpoint.endpointId)
            }
        }
        let descriptorCores = templates.map { template in
            BridgeSharedReviewDescriptorCore(
                itemIdentity: template.itemId,
                semanticVersion: [
                    template.baseContentHash ?? "none",
                    template.headContentHash ?? "none",
                ].joined(separator: ".."),
                baseLocator: template.baseHandle.map(sharedLocator),
                headLocator: template.headHandle.map(sharedLocator)
            )
        }
        let retainedMetadataByteCount = templates.reduce(0) { partialResult, template in
            let identityBytes = template.itemId.utf8.count
            let basePathBytes = template.basePath?.utf8.count ?? 0
            let headPathBytes = template.headPath?.utf8.count ?? 0
            return partialResult + identityBytes + basePathBytes + headPathBytes + 192
        }
        return Self(
            baseEndpoint: baseEndpointKey,
            headEndpoint: headEndpointKey,
            orderedItemIdentities: package.orderedItemIds,
            descriptorCores: descriptorCores,
            groups: package.groups.map {
                BridgeSharedReviewGroup(
                    groupIdentity: $0.groupId,
                    orderedItemIdentities: $0.orderedItemIds
                )
            },
            summary: BridgeSharedReviewSummary(
                filesChanged: package.summary.filesChanged,
                additions: package.summary.additions,
                deletions: package.summary.deletions
            ),
            retainedByteCount: retainedMetadataByteCount + backing.capturedByteCount,
            itemTemplates: templates,
            backing: backing
        )
    }

    func bind(_ request: BridgeReviewPipelineRequest) throws -> BridgeReviewPipelineResult {
        let descriptors = itemTemplates.map {
            $0.bind(
                baseEndpoint: request.baseEndpoint,
                headEndpoint: request.headEndpoint,
                reviewGeneration: request.reviewGeneration
            )
        }
        let package = try BridgeReviewPackageBuilder.buildFromDescriptors(
            request: BridgeReviewDescriptorPackageBuildRequest(
                packageId: request.packageId,
                query: request.query,
                baseEndpoint: request.baseEndpoint,
                headEndpoint: request.headEndpoint,
                descriptors: descriptors,
                checkpointIds: request.checkpointIds,
                reviewGeneration: request.reviewGeneration,
                generatedAtUnixMilliseconds: request.generatedAtUnixMilliseconds
            )
        )
        return BridgeReviewPipelineResult(
            package: package,
            registeredContentHandles: descriptors.flatMap(\.contentRoles.allHandles)
        )
    }

    private static func descriptorTemplate(
        _ descriptor: BridgeReviewItemDescriptor,
        baseEndpointId: String
    ) -> BridgeSharedReviewItemDescriptorTemplate {
        let baseHandle = descriptor.contentRoles.base.map {
            handleTemplate($0, baseEndpointId: baseEndpointId)
        }
        let headHandle = descriptor.contentRoles.head.map {
            handleTemplate($0, baseEndpointId: baseEndpointId)
        }
        let diffHandle = descriptor.contentRoles.diff.map {
            handleTemplate($0, baseEndpointId: baseEndpointId)
        }
        let fileHandle = descriptor.contentRoles.file.map {
            handleTemplate($0, baseEndpointId: baseEndpointId)
        }
        return BridgeSharedReviewItemDescriptorTemplate(
            itemId: descriptor.itemId,
            semanticItemVersion: semanticItemVersion(
                descriptor: descriptor,
                handleTemplates: [baseHandle, headHandle, diffHandle, fileHandle]
            ),
            itemKind: descriptor.itemKind,
            basePath: descriptor.basePath,
            headPath: descriptor.headPath,
            changeKind: descriptor.changeKind,
            fileClass: descriptor.fileClass,
            language: descriptor.language,
            fileExtension: descriptor.extension,
            sizeBytes: descriptor.sizeBytes,
            baseContentHash: descriptor.baseContentHash,
            headContentHash: descriptor.headContentHash,
            contentHashAlgorithm: descriptor.contentHashAlgorithm,
            additions: descriptor.additions,
            deletions: descriptor.deletions,
            isHiddenByDefault: descriptor.isHiddenByDefault,
            hiddenReason: descriptor.hiddenReason,
            reviewPriority: descriptor.reviewPriority,
            baseHandle: baseHandle,
            headHandle: headHandle,
            diffHandle: diffHandle,
            fileHandle: fileHandle,
            provenance: descriptor.provenance,
            annotationSummary: descriptor.annotationSummary,
            reviewState: descriptor.reviewState,
            collapsed: descriptor.collapsed
        )
    }

    private static func semanticItemVersion(
        descriptor: BridgeReviewItemDescriptor,
        handleTemplates: [BridgeSharedReviewContentHandleTemplate?]
    ) -> Int {
        var components: [String] = []
        components.append(descriptor.itemId)
        components.append(descriptor.itemKind.rawValue)
        components.append(descriptor.basePath ?? "")
        components.append(descriptor.headPath ?? "")
        components.append(descriptor.changeKind.rawValue)
        components.append(descriptor.fileClass.rawValue)
        components.append(descriptor.language ?? "")
        components.append(descriptor.extension ?? "")
        components.append(String(descriptor.sizeBytes))
        components.append(descriptor.baseContentHash ?? "")
        components.append(descriptor.headContentHash ?? "")
        components.append(descriptor.contentHashAlgorithm)
        components.append(String(descriptor.additions))
        components.append(String(descriptor.deletions))
        components.append(String(descriptor.isHiddenByDefault))
        components.append(descriptor.hiddenReason ?? "")
        components.append(descriptor.reviewPriority.rawValue)
        components.append(descriptor.reviewState.rawValue)
        components.append(String(descriptor.collapsed))
        components.append(String(descriptor.annotationSummary.threadCount))
        components.append(String(descriptor.annotationSummary.unresolvedThreadCount))
        components.append(String(descriptor.annotationSummary.commentCount))
        components.append(contentsOf: descriptor.provenance.paneIds.map(\.uuidString))
        components.append(contentsOf: descriptor.provenance.agentSessionIds)
        components.append(contentsOf: descriptor.provenance.promptIds)
        components.append(contentsOf: descriptor.provenance.operationIds)
        components.append(contentsOf: descriptor.provenance.sourceKinds.map(\.rawValue))
        for handleTemplate in handleTemplates {
            guard let handleTemplate else {
                components.append("no-handle")
                continue
            }
            components.append(contentsOf: [
                handleTemplate.identity.itemIdentity,
                handleTemplate.identity.role.rawValue,
                handleTemplate.identity.contentHash,
                String(describing: handleTemplate.endpointRole),
                handleTemplate.contentHashAlgorithm,
                handleTemplate.mimeType,
                handleTemplate.language ?? "",
                String(handleTemplate.sizeBytes),
                String(handleTemplate.sizeBytesIsExact),
                String(handleTemplate.isBinary),
            ])
        }

        var hasher = SHA256()
        for component in components {
            let data = Data(component.utf8)
            hasher.update(data: Data("\(data.count):".utf8))
            hasher.update(data: data)
        }
        let digest = Array(hasher.finalize())
        let rawValue = digest.prefix(8).reduce(UInt64.zero) { partialResult, byte in
            (partialResult << 8) | UInt64(byte)
        }
        return Int(rawValue & 0x001F_FFFF_FFFF_FFFF)
    }

    private static func handleTemplate(
        _ handle: BridgeContentHandle,
        baseEndpointId: String
    ) -> BridgeSharedReviewContentHandleTemplate {
        BridgeSharedReviewContentHandleTemplate(
            identity: BridgeSharedReviewContentIdentity(
                itemIdentity: handle.itemId,
                role: handle.role,
                contentHash: handle.contentHash
            ),
            endpointRole: handle.endpointId == baseEndpointId ? .base : .head,
            contentHashAlgorithm: handle.contentHashAlgorithm,
            mimeType: handle.mimeType,
            language: handle.language,
            sizeBytes: handle.sizeBytes,
            sizeBytesIsExact: handle.sizeBytesIsExact,
            isBinary: handle.isBinary
        )
    }

    private static func sharedLocator(
        _ template: BridgeSharedReviewContentHandleTemplate
    ) -> BridgeSharedReviewContentLocator {
        BridgeSharedReviewContentLocator(
            providerIdentity: template.endpointRole == .base ? "base" : "head",
            contentIdentity: template.identity.contentHash,
            digest: template.identity.contentHash
        )
    }
}
