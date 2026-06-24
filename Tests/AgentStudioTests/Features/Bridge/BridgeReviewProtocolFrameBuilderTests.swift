import Foundation
import Testing

@testable import AgentStudio

struct BridgeReviewProtocolFrameBuilderTests {
    @Test("snapshot frame attaches root and content resource descriptors")
    func snapshotFrameAttachesRootAndContentResourceDescriptors() throws {
        let package = try makeReviewPackage()

        let frame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-1",
                sourceIdentity: "review-source-1",
                streamId: "stream-1",
                sequence: 0,
                package: package,
                changesetCluster: nil
            )
        )

        #expect(frame.kind == "snapshot")
        #expect(frame.frameKind == "review.snapshot")
        #expect(frame.package.rootDescriptor.descriptor.resourceKind == "review-package")
        #expect(frame.package.rootDescriptor.ref.expectedIdentity.paneId == "pane-1")
        #expect(frame.package.contentDescriptors.count == 2)
        let contentDescriptor = try #require(frame.package.contentDescriptors.first)
        #expect(contentDescriptor.descriptor.protocolId == "review")
        #expect(contentDescriptor.descriptor.resourceKind == "content")
        #expect(contentDescriptor.descriptor.identity.revision == nil)
        #expect(contentDescriptor.ref.descriptorId == contentDescriptor.descriptor.descriptorId)

        let encoded = try JSONEncoder().encode(frame)
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let packageObject = try #require(object["package"] as? [String: Any])
        #expect(packageObject["contentDescriptors"] != nil)
    }

    @Test("snapshot frame emits preview-only integrity for non-sha256 host hashes")
    func snapshotFrameEmitsPreviewOnlyIntegrityForNonSHA256HostHashes() throws {
        let package = try makeReviewPackageWithHostContentHashAlgorithm()

        let frame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-1",
                sourceIdentity: "review-source-1",
                streamId: "stream-1",
                sequence: 0,
                package: package,
                changesetCluster: nil
            )
        )

        let previewOnlyDescriptor = try #require(
            frame.package.contentDescriptors.first {
                $0.descriptor.content.integrity?.kind == .previewOnly
            }
        )
        #expect(previewOnlyDescriptor.descriptor.content.integrity?.algorithm == nil)
        #expect(previewOnlyDescriptor.descriptor.content.integrity?.value == nil)
        #expect(previewOnlyDescriptor.descriptor.content.integrity?.manifestResourceId == nil)
    }

    @Test("snapshot frame builder preserves flexible changeset cluster metadata")
    func snapshotFrameBuilderPreservesFlexibleChangesetClusterMetadata() throws {
        let package = try makeReviewPackage()
        let metadata = BridgeReviewChangesetClusterMetadata(
            clusterId: "cluster-1",
            sourceId: "review-source-1",
            algorithm: "idleDebounce",
            lifecycle: "live",
            confidence: "freshScan",
            baselineCursor: "cursor-a",
            headCursor: "cursor-b",
            baselineRef: nil,
            headRef: nil,
            fromUnixMilliseconds: nil,
            toUnixMilliseconds: nil,
            includedPathHints: ["Sources/App/View.swift"],
            groupingReason: "agent idle debounce closed the batch",
            limitations: ["overflowRecovered"]
        )
        let frame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-1",
                sourceIdentity: "review-source-1",
                streamId: "stream-1",
                sequence: 0,
                package: package,
                changesetCluster: metadata
            )
        )

        let encoded = try JSONEncoder().encode(frame)
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let packageObject = try #require(object["package"] as? [String: Any])
        let clusterObject = try #require(packageObject["changesetCluster"] as? [String: Any])

        #expect(clusterObject["sourceId"] as? String == "review-source-1")
        #expect(clusterObject["algorithm"] as? String == "idleDebounce")
        #expect(clusterObject["confidence"] as? String == "freshScan")
        #expect(clusterObject["limitations"] as? [String] == ["overflowRecovered"])
    }

    @Test("snapshot frame rejects content resource URLs that do not match handle id")
    func snapshotFrameRejectsMismatchedContentResourceId() throws {
        let package = try makeReviewPackageWithMismatchedContentResourceId()

        #expect(throws: BridgeReviewProtocolFrameBuilderError.self) {
            _ = try BridgeReviewProtocolFrameBuilder.snapshot(
                request: BridgeReviewProtocolSnapshotBuildRequest(
                    paneId: "pane-1",
                    sourceIdentity: "review-source-1",
                    streamId: "stream-1",
                    sequence: 0,
                    package: package,
                    changesetCluster: nil
                )
            )
        }
    }

    @Test("diff package metadata slice carries review protocol frame")
    func diffPackageMetadataSliceCarriesReviewProtocolFrame() throws {
        let package = try makeReviewPackage()
        let frame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-1",
                sourceIdentity: package.query.queryId,
                streamId: "review:pane-1",
                sequence: package.revision,
                package: package,
                changesetCluster: nil
            )
        )

        let encoded = try JSONEncoder().encode(
            DiffPackageMetadataSlice(package: package, protocolFrame: frame)
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let protocolFrame = try #require(object["protocolFrame"] as? [String: Any])

        #expect(protocolFrame["frameKind"] as? String == "review.snapshot")
        #expect(protocolFrame["package"] != nil)
    }

    @Test("diff package delta slice carries review protocol frame")
    func diffPackageDeltaSliceCarriesReviewProtocolFrame() throws {
        let package = try makeReviewPackage()
        let frame = try BridgeReviewProtocolFrameBuilder.delta(
            request: BridgeReviewProtocolDeltaBuildRequest(
                paneId: "pane-1",
                sourceIdentity: package.query.queryId,
                streamId: "review:pane-1",
                sequence: package.revision,
                fromRevision: package.revision - 1,
                toRevision: package.revision,
                package: package
            )
        )
        let delta = BridgeReviewDelta(
            packageId: package.packageId,
            reviewGeneration: package.reviewGeneration,
            revision: package.revision + 1,
            operations: BridgeReviewDelta.Operations()
        )

        let encoded = try JSONEncoder().encode(
            DiffPackageDeltaSlice(delta: delta, protocolFrame: frame)
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let protocolFrame = try #require(object["protocolFrame"] as? [String: Any])

        #expect(protocolFrame["frameKind"] as? String == "review.delta")
        #expect(protocolFrame["packageId"] as? String == package.packageId)
        #expect(protocolFrame["operationsDescriptor"] != nil)
        #expect(protocolFrame["contentDescriptors"] != nil)
    }

    @Test("diff state stores and clears package protocol frames with package facts")
    @MainActor
    func diffStateStoresAndClearsPackageProtocolFramesWithPackageFacts() throws {
        let package = try makeReviewPackage()
        let snapshotFrame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-1",
                sourceIdentity: package.query.queryId,
                streamId: "review:pane-1",
                sequence: package.revision,
                package: package,
                changesetCluster: nil
            )
        )
        let delta = BridgeReviewDelta(
            packageId: package.packageId,
            reviewGeneration: package.reviewGeneration,
            revision: package.revision + 1,
            operations: BridgeReviewDelta.Operations()
        )
        let deltaFrame = try BridgeReviewProtocolFrameBuilder.delta(
            request: BridgeReviewProtocolDeltaBuildRequest(
                paneId: "pane-1",
                sourceIdentity: package.query.queryId,
                streamId: "review:pane-1",
                sequence: delta.revision,
                fromRevision: package.revision,
                toRevision: delta.revision,
                package: package
            )
        )
        let state = DiffState()

        state.setPackageMetadata(package, protocolFrame: .snapshot(snapshotFrame))
        state.setPackageDelta(delta, protocolFrame: .delta(deltaFrame))

        #expect(state.packageMetadata == package)
        #expect(state.packageSnapshotProtocolFrame == .snapshot(snapshotFrame))
        #expect(state.packageDelta == delta)
        #expect(state.packageDeltaProtocolFrame == .delta(deltaFrame))

        state.setPackageMetadata(nil)
        state.setPackageDelta(nil)

        #expect(state.packageMetadata == nil)
        #expect(state.packageSnapshotProtocolFrame == nil)
        #expect(state.packageDelta == nil)
        #expect(state.packageDeltaProtocolFrame == nil)
    }

    @Test("diff package protocol frame slice carries standalone reset and invalidation frames")
    func diffPackageProtocolFrameSliceCarriesStandaloneFrames() throws {
        let resetFrame = BridgeReviewProtocolFrameBuilder.reset(
            request: BridgeReviewProtocolResetBuildRequest(
                sourceIdentity: "review-source-1",
                streamId: "review:pane-1",
                generation: 4,
                sequence: 5,
                reason: "authorityChanged",
                packageId: "package-1",
                replacementDescriptor: nil
            )
        )
        let resetEncoded = try JSONEncoder().encode(
            DiffPackageProtocolFrameSlice(protocolFrame: .reset(resetFrame))
        )
        let resetObject = try #require(
            JSONSerialization.jsonObject(with: resetEncoded) as? [String: Any]
        )
        let resetProtocolFrame = try #require(resetObject["protocolFrame"] as? [String: Any])
        #expect(resetProtocolFrame["frameKind"] as? String == "review.reset")
        #expect(resetProtocolFrame["sourceIdentity"] as? String == "review-source-1")

        let invalidationFrame = BridgeReviewProtocolFrameBuilder.invalidation(
            request: BridgeReviewProtocolInvalidationBuildRequest(
                streamId: "review:pane-1",
                generation: 4,
                sequence: 6,
                scope: "items",
                itemIds: ["item-a"],
                pathHints: nil,
                reason: "watchEvent"
            )
        )
        let invalidationEncoded = try JSONEncoder().encode(
            DiffPackageProtocolFrameSlice(protocolFrame: .invalidation(invalidationFrame))
        )
        let invalidationObject = try #require(
            JSONSerialization.jsonObject(with: invalidationEncoded) as? [String: Any]
        )
        let invalidationProtocolFrame = try #require(
            invalidationObject["protocolFrame"] as? [String: Any]
        )
        let invalidation = try #require(invalidationProtocolFrame["invalidation"] as? [String: Any])
        #expect(invalidationProtocolFrame["frameKind"] as? String == "review.invalidate")
        #expect(invalidation["itemIds"] as? [String] == ["item-a"])
    }

    @Test("snapshot frame preserves package changeset cluster through native package model")
    func snapshotFramePreservesPackageChangesetClusterThroughNativePackageModel() throws {
        let metadata = BridgeReviewChangesetClusterMetadata(
            clusterId: "cluster-1",
            sourceId: "review-source-1",
            algorithm: "idleDebounce",
            lifecycle: "closed",
            confidence: "freshScan",
            baselineCursor: nil,
            headCursor: "cursor-b",
            baselineRef: "main",
            headRef: nil,
            fromUnixMilliseconds: 1,
            toUnixMilliseconds: 2,
            includedPathHints: ["Sources/App/View.swift"],
            groupingReason: "agent idle debounce closed the batch",
            limitations: ["overflowRecovered"]
        )
        let package = try makeReviewPackage().withChangesetCluster(metadata)
        let frame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-1",
                sourceIdentity: package.query.queryId,
                streamId: "review:pane-1",
                sequence: package.revision,
                package: package,
                changesetCluster: package.changesetCluster
            )
        )

        let encoded = try JSONEncoder().encode(
            DiffPackageMetadataSlice(package: package, protocolFrame: frame)
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let protocolFrame = try #require(object["protocolFrame"] as? [String: Any])
        let packageObject = try #require(protocolFrame["package"] as? [String: Any])
        let clusterObject = try #require(packageObject["changesetCluster"] as? [String: Any])
        #expect(clusterObject["lifecycle"] as? String == "closed")
        #expect(clusterObject["headCursor"] as? String == "cursor-b")
        #expect(clusterObject["limitations"] as? [String] == ["overflowRecovered"])
    }

    @Test("reset frame carries source identity optional package and replacement descriptor")
    func resetFrameCarriesSourceIdentityOptionalPackageAndReplacementDescriptor() throws {
        let package = try makeReviewPackage()
        let replacementFrame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-1",
                sourceIdentity: "review-source-1",
                streamId: "review:pane-1",
                sequence: package.revision,
                package: package,
                changesetCluster: nil
            )
        )
        let replacementDescriptor = replacementFrame.package.rootDescriptor
        let frame = BridgeReviewProtocolFrameBuilder.reset(
            request: BridgeReviewProtocolResetBuildRequest(
                sourceIdentity: "review-source-1",
                streamId: "review:pane-1",
                generation: 4,
                sequence: 5,
                reason: "authorityChanged",
                packageId: "package-1",
                replacementDescriptor: replacementDescriptor
            )
        )

        #expect(frame.kind == "reset")
        #expect(frame.frameKind == "review.reset")
        #expect(frame.sourceIdentity == "review-source-1")
        #expect(frame.packageId == "package-1")
        #expect(frame.replacementDescriptor == replacementDescriptor)
    }

    @Test("invalidation frame carries metadata-only invalidation facts")
    func invalidationFrameCarriesMetadataOnlyInvalidationFacts() throws {
        let frame = BridgeReviewProtocolFrameBuilder.invalidation(
            request: BridgeReviewProtocolInvalidationBuildRequest(
                streamId: "review:pane-1",
                generation: 4,
                sequence: 5,
                scope: "items",
                itemIds: ["item-a"],
                pathHints: nil,
                reason: "watchEvent"
            )
        )

        #expect(frame.kind == "delta")
        #expect(frame.frameKind == "review.invalidate")
        #expect(frame.invalidation.scope == "items")
        #expect(frame.invalidation.itemIds == ["item-a"])
        #expect(frame.invalidation.reason == "watchEvent")
    }

    private func makeReviewPackage() throws -> BridgeReviewPackage {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
        let comparison = BridgeEndpointComparison(
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            changedFiles: [
                makeBridgeEndpointChangedFile(fileId: "source", path: "Sources/App/View.swift", sizeBytes: 100)
            ]
        )
        let query = makeBridgeReviewQuery(
            baseEndpointId: baseEndpoint.endpointId,
            headEndpointId: headEndpoint.endpointId
        )
        return try BridgeReviewPackageBuilder.build(
            request: BridgeReviewPackageBuildRequest(
                packageId: "package-1",
                query: query,
                comparison: comparison,
                checkpointIds: [],
                reviewGeneration: 3,
                generatedAtUnixMilliseconds: 4
            )
        )
    }

    private func makeReviewPackageWithHostContentHashAlgorithm() throws -> BridgeReviewPackage {
        let package = try makeReviewPackage()
        let item = try #require(package.itemsById["item-source"])
        let head = try #require(item.contentRoles.head)
        let updatedHead = BridgeContentHandle(
            handleId: head.handleId,
            itemId: head.itemId,
            role: head.role,
            endpointId: head.endpointId,
            reviewGeneration: head.reviewGeneration,
            resourceUrl: head.resourceUrl,
            contentHash: "git-oid:abc123",
            contentHashAlgorithm: "git-oid",
            cacheKey: head.cacheKey,
            mimeType: head.mimeType,
            language: head.language,
            sizeBytes: head.sizeBytes,
            isBinary: head.isBinary
        )
        let updatedItem = BridgeReviewItemDescriptor(
            itemId: item.itemId,
            itemKind: item.itemKind,
            itemVersion: item.itemVersion,
            basePath: item.basePath,
            headPath: item.headPath,
            changeKind: item.changeKind,
            fileClass: item.fileClass,
            language: item.language,
            extension: item.extension,
            sizeBytes: item.sizeBytes,
            baseContentHash: item.baseContentHash,
            headContentHash: updatedHead.contentHash,
            contentHashAlgorithm: updatedHead.contentHashAlgorithm,
            additions: item.additions,
            deletions: item.deletions,
            isHiddenByDefault: item.isHiddenByDefault,
            hiddenReason: item.hiddenReason,
            reviewPriority: item.reviewPriority,
            contentRoles: BridgeReviewItemDescriptor.ContentRoles(
                base: item.contentRoles.base,
                head: updatedHead,
                diff: item.contentRoles.diff,
                file: item.contentRoles.file
            ),
            cacheKey: item.cacheKey,
            provenance: item.provenance,
            annotationSummary: item.annotationSummary,
            reviewState: item.reviewState,
            collapsed: item.collapsed
        )
        return BridgeReviewPackage(
            packageId: package.packageId,
            schemaVersion: package.schemaVersion,
            reviewGeneration: package.reviewGeneration,
            revision: package.revision,
            query: package.query,
            baseEndpoint: package.baseEndpoint,
            headEndpoint: package.headEndpoint,
            orderedItemIds: package.orderedItemIds,
            itemsById: package.itemsById.merging([updatedItem.itemId: updatedItem]) { _, next in next },
            groups: package.groups,
            summary: package.summary,
            filterState: package.filterState,
            generatedAtUnixMilliseconds: package.generatedAtUnixMilliseconds
        )
    }

    private func makeReviewPackageWithMismatchedContentResourceId() throws -> BridgeReviewPackage {
        let package = try makeReviewPackage()
        let item = try #require(package.itemsById["item-source"])
        let head = try #require(item.contentRoles.head)
        let updatedHead = BridgeContentHandle(
            handleId: head.handleId,
            itemId: head.itemId,
            role: head.role,
            endpointId: head.endpointId,
            reviewGeneration: head.reviewGeneration,
            resourceUrl: "agentstudio://resource/review/content/foreign-\(head.handleId)?generation=3",
            contentHash: head.contentHash,
            contentHashAlgorithm: head.contentHashAlgorithm,
            cacheKey: head.cacheKey,
            mimeType: head.mimeType,
            language: head.language,
            sizeBytes: head.sizeBytes,
            isBinary: head.isBinary
        )
        let updatedItem = BridgeReviewItemDescriptor(
            itemId: item.itemId,
            itemKind: item.itemKind,
            itemVersion: item.itemVersion,
            basePath: item.basePath,
            headPath: item.headPath,
            changeKind: item.changeKind,
            fileClass: item.fileClass,
            language: item.language,
            extension: item.extension,
            sizeBytes: item.sizeBytes,
            baseContentHash: item.baseContentHash,
            headContentHash: item.headContentHash,
            contentHashAlgorithm: item.contentHashAlgorithm,
            additions: item.additions,
            deletions: item.deletions,
            isHiddenByDefault: item.isHiddenByDefault,
            hiddenReason: item.hiddenReason,
            reviewPriority: item.reviewPriority,
            contentRoles: BridgeReviewItemDescriptor.ContentRoles(
                base: item.contentRoles.base,
                head: updatedHead,
                diff: item.contentRoles.diff,
                file: item.contentRoles.file
            ),
            cacheKey: item.cacheKey,
            provenance: item.provenance,
            annotationSummary: item.annotationSummary,
            reviewState: item.reviewState,
            collapsed: item.collapsed
        )
        return BridgeReviewPackage(
            packageId: package.packageId,
            schemaVersion: package.schemaVersion,
            reviewGeneration: package.reviewGeneration,
            revision: package.revision,
            query: package.query,
            baseEndpoint: package.baseEndpoint,
            headEndpoint: package.headEndpoint,
            orderedItemIds: package.orderedItemIds,
            itemsById: package.itemsById.merging([updatedItem.itemId: updatedItem]) { _, next in next },
            groups: package.groups,
            summary: package.summary,
            filterState: package.filterState,
            generatedAtUnixMilliseconds: package.generatedAtUnixMilliseconds
        )
    }
}
