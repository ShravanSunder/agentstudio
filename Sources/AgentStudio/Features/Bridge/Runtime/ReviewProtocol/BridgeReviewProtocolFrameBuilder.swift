import Foundation

struct BridgeReviewProtocolSnapshotBuildRequest: Equatable, Sendable {
    let paneId: String
    let sourceIdentity: String
    let streamId: String
    let sequence: Int
    let package: BridgeReviewPackage
    let changesetCluster: BridgeReviewChangesetClusterMetadata?
}

struct BridgeReviewProtocolDeltaBuildRequest: Equatable, Sendable {
    let paneId: String
    let sourceIdentity: String
    let streamId: String
    let sequence: Int
    let fromRevision: Int
    let toRevision: Int
    let package: BridgeReviewPackage
}

struct BridgeReviewProtocolResetBuildRequest: Equatable, Sendable {
    let sourceIdentity: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let reason: String
    let packageId: String?
    let replacementDescriptor: BridgeAttachedResourceDescriptor?
}

struct BridgeReviewProtocolInvalidationBuildRequest: Equatable, Sendable {
    let streamId: String
    let generation: Int
    let sequence: Int
    let scope: String
    let itemIds: [String]?
    let pathHints: [String]?
    let reason: String
}

enum BridgeReviewProtocolFrameBuilderError: Error, Equatable, Sendable {
    case invalidContentResourceUrl(String)
    case contentResourceIdMismatch(handleId: String, resourceId: String)
}

enum BridgeReviewProtocolFrameBuilder {
    static func snapshot(
        request: BridgeReviewProtocolSnapshotBuildRequest
    ) throws -> BridgeReviewSnapshotFrame {
        let rootDescriptor = packageRootDescriptor(
            paneId: request.paneId,
            sourceIdentity: request.sourceIdentity,
            streamId: request.streamId,
            package: request.package
        )
        let contentDescriptors = try request.package.itemsById.values
            .flatMap(\.contentRoles.allHandles)
            .sorted { left, right in left.handleId < right.handleId }
            .map { handle in
                try contentDescriptor(
                    handle: handle,
                    paneId: request.paneId,
                    sourceIdentity: request.sourceIdentity,
                    streamId: request.streamId,
                    package: request.package
                )
            }

        return BridgeReviewSnapshotFrame(
            streamId: request.streamId,
            generation: request.package.reviewGeneration.rawValue,
            sequence: request.sequence,
            package: BridgeReviewSnapshotPackageIdentity(
                packageId: request.package.packageId,
                sourceIdentity: request.sourceIdentity,
                generation: request.package.reviewGeneration.rawValue,
                revision: request.package.revision,
                rootDescriptor: rootDescriptor,
                contentDescriptors: contentDescriptors,
                changesetCluster: request.changesetCluster
            )
        )
    }

    static func delta(
        request: BridgeReviewProtocolDeltaBuildRequest
    ) throws -> BridgeReviewDeltaFrame {
        let operationsDescriptor = deltaOperationsDescriptor(
            paneId: request.paneId,
            sourceIdentity: request.sourceIdentity,
            streamId: request.streamId,
            fromRevision: request.fromRevision,
            toRevision: request.toRevision,
            package: request.package
        )
        let contentDescriptors = try request.package.itemsById.values
            .flatMap(\.contentRoles.allHandles)
            .sorted { left, right in left.handleId < right.handleId }
            .map { handle in
                try contentDescriptor(
                    handle: handle,
                    paneId: request.paneId,
                    sourceIdentity: request.sourceIdentity,
                    streamId: request.streamId,
                    package: request.package
                )
            }

        return BridgeReviewDeltaFrame(
            streamId: request.streamId,
            generation: request.package.reviewGeneration.rawValue,
            sequence: request.sequence,
            packageId: request.package.packageId,
            fromRevision: request.fromRevision,
            toRevision: request.toRevision,
            operationsDescriptor: operationsDescriptor,
            contentDescriptors: contentDescriptors
        )
    }

    static func reset(request: BridgeReviewProtocolResetBuildRequest) -> BridgeReviewResetFrame {
        BridgeReviewResetFrame(
            streamId: request.streamId,
            generation: request.generation,
            sequence: request.sequence,
            reason: request.reason,
            sourceIdentity: request.sourceIdentity,
            packageId: request.packageId,
            replacementDescriptor: request.replacementDescriptor
        )
    }

    static func invalidation(
        request: BridgeReviewProtocolInvalidationBuildRequest
    ) -> BridgeReviewInvalidationFrame {
        BridgeReviewInvalidationFrame(
            streamId: request.streamId,
            generation: request.generation,
            sequence: request.sequence,
            invalidation: BridgeReviewInvalidationFrame.Invalidation(
                scope: request.scope,
                itemIds: request.itemIds,
                pathHints: request.pathHints,
                reason: request.reason
            )
        )
    }

    private static func packageRootDescriptor(
        paneId: String,
        sourceIdentity: String,
        streamId: String,
        package: BridgeReviewPackage
    ) -> BridgeAttachedResourceDescriptor {
        let descriptorId =
            "review-package-\(package.packageId)-\(package.reviewGeneration.rawValue)-\(package.revision)"
        let resourceUrl =
            "agentstudio://resource/review/review-package/\(descriptorId)?generation=\(package.reviewGeneration.rawValue)&revision=\(package.revision)"
        let identity = BridgeResourceIdentity(
            paneId: paneId,
            protocolId: "review",
            sourceId: sourceIdentity,
            packageId: package.packageId,
            generation: package.reviewGeneration.rawValue,
            revision: package.revision,
            streamId: streamId,
            cursor: nil
        )
        let descriptor = BridgeResourceDescriptor(
            descriptorId: descriptorId,
            protocolId: "review",
            resourceKind: "review-package",
            resourceUrl: resourceUrl,
            identity: identity,
            content: BridgeResourceContentDescriptor(
                mediaType: "application/json",
                encoding: .utf8,
                expectedBytes: nil,
                maxBytes: AppPolicies.Bridge.ipcMaxResponsePayloadBytes,
                integrity: nil
            ),
            window: nil
        )
        return attachedDescriptor(refIdentity: identity, descriptor: descriptor)
    }

    private static func deltaOperationsDescriptor(
        paneId: String,
        sourceIdentity: String,
        streamId: String,
        fromRevision: Int,
        toRevision: Int,
        package: BridgeReviewPackage
    ) -> BridgeAttachedResourceDescriptor {
        let descriptorId = "review-delta-\(package.packageId)-\(fromRevision)-\(toRevision)"
        let resourceUrl =
            "agentstudio://resource/review/review-delta/\(descriptorId)?generation=\(package.reviewGeneration.rawValue)&revision=\(toRevision)"
        let identity = BridgeResourceIdentity(
            paneId: paneId,
            protocolId: "review",
            sourceId: sourceIdentity,
            packageId: package.packageId,
            generation: package.reviewGeneration.rawValue,
            revision: toRevision,
            streamId: streamId,
            cursor: nil
        )
        let descriptor = BridgeResourceDescriptor(
            descriptorId: descriptorId,
            protocolId: "review",
            resourceKind: "review-delta",
            resourceUrl: resourceUrl,
            identity: identity,
            content: BridgeResourceContentDescriptor(
                mediaType: "application/json",
                encoding: .utf8,
                expectedBytes: nil,
                maxBytes: AppPolicies.Bridge.ipcMaxResponsePayloadBytes,
                integrity: nil
            ),
            window: nil
        )
        return attachedDescriptor(refIdentity: identity, descriptor: descriptor)
    }

    private static func contentDescriptor(
        handle: BridgeContentHandle,
        paneId: String,
        sourceIdentity: String,
        streamId: String,
        package: BridgeReviewPackage
    ) throws -> BridgeAttachedResourceDescriptor {
        guard
            let resource = BridgeTransportResourceURL.parse(
                handle.resourceUrl,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewContentResourceKinds
            )
        else {
            throw BridgeReviewProtocolFrameBuilderError.invalidContentResourceUrl(handle.resourceUrl)
        }
        guard resource.opaqueId == handle.handleId else {
            throw BridgeReviewProtocolFrameBuilderError.contentResourceIdMismatch(
                handleId: handle.handleId,
                resourceId: resource.opaqueId
            )
        }
        let identity = BridgeResourceIdentity(
            paneId: paneId,
            protocolId: "review",
            sourceId: sourceIdentity,
            packageId: package.packageId,
            generation: handle.reviewGeneration.rawValue,
            revision: resource.revision,
            streamId: streamId,
            cursor: resource.cursor
        )
        let descriptor = BridgeResourceDescriptor(
            descriptorId: resource.opaqueId,
            protocolId: "review",
            resourceKind: "content",
            resourceUrl: resource.canonicalURL,
            identity: identity,
            content: BridgeResourceContentDescriptor(
                mediaType: handle.mimeType,
                encoding: handle.isBinary ? .binary : .utf8,
                expectedBytes: handle.sizeBytes,
                maxBytes: max(handle.sizeBytes, 1),
                integrity: contentIntegrityDescriptor(for: handle)
            ),
            window: nil
        )
        return attachedDescriptor(refIdentity: identity, descriptor: descriptor)
    }

    private static func contentIntegrityDescriptor(
        for handle: BridgeContentHandle
    ) -> BridgeIntegrityDescriptor {
        guard handle.contentHashAlgorithm == "sha256", !handle.contentHash.isEmpty else {
            return BridgeIntegrityDescriptor(
                kind: .previewOnly,
                algorithm: nil,
                value: nil,
                manifestResourceId: nil
            )
        }
        return BridgeIntegrityDescriptor(
            kind: .wholeHash,
            algorithm: "sha256",
            value: handle.contentHash,
            manifestResourceId: nil
        )
    }

    private static func attachedDescriptor(
        refIdentity: BridgeResourceIdentity,
        descriptor: BridgeResourceDescriptor
    ) -> BridgeAttachedResourceDescriptor {
        BridgeAttachedResourceDescriptor(
            ref: BridgeDescriptorRef(
                descriptorId: descriptor.descriptorId,
                expectedProtocol: descriptor.protocolId,
                expectedResourceKind: descriptor.resourceKind,
                expectedIdentity: refIdentity
            ),
            descriptor: descriptor
        )
    }
}
