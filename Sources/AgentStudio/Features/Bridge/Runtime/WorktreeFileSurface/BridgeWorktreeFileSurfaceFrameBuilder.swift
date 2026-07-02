import Foundation

struct BridgeWorktreeFileSnapshotBuildRequest: Equatable, Sendable {
    let paneId: String
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let requestSelector: BridgeWorktreeFileSurfaceSourceSpec?
    let streamId: String
    let sequence: Int
    let treePathCount: Int?
    let treeEstimatedTotalHeightPixels: Double?
    let treeWindowStartIndex: Int?
    let treeWindowRowCount: Int?
    let treeRowHeightPixels: Double
    let treeRows: [BridgeWorktreeTreeRowMetadata]
    let includeStatusPatch: Bool
}

struct BridgeWorktreeTreeWindowBuildRequest: Equatable, Sendable {
    let paneId: String
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let streamId: String
    let sequence: Int
    let treeWindowKey: String
    let pathScope: [String]
    let treePathCount: Int?
    let treeEstimatedTotalHeightPixels: Double?
    let treeWindowStartIndex: Int?
    let treeWindowRowCount: Int?
    let treeRowHeightPixels: Double
    let rows: [BridgeWorktreeTreeRowMetadata]
    let metadataLineage: BridgeWorktreeFileMetadataLineage
}

enum BridgeWorktreeFileContentAvailability: Equatable, Sendable {
    case readable
    case unreadable
    case metadataOnly
}

struct BridgeWorktreeFileDescriptorBuildRequest: Equatable, Sendable {
    let paneId: String
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let streamId: String
    let sequence: Int
    let path: String
    let fileId: String
    let contentHandle: String
    let sizeBytes: Int
    let isBinary: Bool
    let contentAvailability: BridgeWorktreeFileContentAvailability
    let language: String?
    let fileExtension: String?
    let virtualizedExtentKind: BridgeWorktreeFileVirtualizedExtentKind
    let lineCount: Int?
    let estimatedContentHeightPixels: Double?
}

struct BridgeWorktreeFileInvalidationBuildRequest: Equatable, Sendable {
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let streamId: String
    let sequence: Int
    let path: String
    let fileId: String?
    let reason: BridgeWorktreeFileInvalidationReason
    let contentHandleIds: [String]?
    let latestDescriptor: BridgeWorktreeFileDescriptor?
}

struct BridgeWorktreeResetBuildRequest: Equatable, Sendable {
    let streamId: String
    let sequence: Int
    let reason: BridgeWorktreeResetReason
    let source: BridgeWorktreeFileSurfaceSourceIdentity?
    let replacementDescriptor: BridgeAttachedResourceDescriptor?
}

struct BridgeWorktreeExtentDiagnosticsBuildRequest: Equatable, Sendable {
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let totalTreePathCount: Int
    let treeEstimatedTotalHeightPixels: Double?
    let fileExtentKindCounts: [BridgeWorktreeFileVirtualizedExtentKind: Int]
    let rejectionReasonCounts: [BridgeWorktreeExtentDiagnosticsRejectionReason: Int]
}

enum BridgeWorktreeFileSurfaceFrameBuilderError: Error, Equatable, Sendable {
    case exactLineCountMissingLineCount
    case estimatedHeightMissingEstimate
    case unavailableExtentForReadableText
}

private struct BridgeWorktreeDescriptorScope {
    let paneId: String
    let protocolId: String
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let streamId: String
}

private struct BridgeWorktreeAttachedDescriptorBuildRequest {
    let scope: BridgeWorktreeDescriptorScope
    let resourceKind: String
    let descriptorId: String
    let content: BridgeResourceContentDescriptor
    let window: BridgeResourceWindowDescriptor?
}

enum BridgeWorktreeFileSurfaceFrameBuilder {
    static func snapshot(
        request: BridgeWorktreeFileSnapshotBuildRequest
    ) -> BridgeWorktreeSnapshotFrame {
        let treeSizeFacts = treeSizeFacts(
            pathCount: request.treePathCount,
            estimatedTotalHeightPixels: request.treeEstimatedTotalHeightPixels,
            windowStartIndex: request.treeWindowStartIndex,
            windowRowCount: request.treeWindowRowCount,
            rowHeightPixels: request.treeRowHeightPixels
        )
        let statusPatch: BridgeWorktreeStatusPatch? =
            request.includeStatusPatch
            ? BridgeWorktreeStatusPatch(
                counts: BridgeWorktreeStatusPatchCounts(
                    staged: nil,
                    unstaged: nil,
                    untracked: nil
                ),
                branchFacts: BridgeWorktreeStatusPatchBranchFacts(
                    branchName: nil,
                    ahead: nil,
                    behind: nil
                )
            )
            : nil

        return BridgeWorktreeSnapshotFrame(
            streamId: request.streamId,
            sequence: request.sequence,
            source: request.source,
            requestSelector: request.requestSelector,
            treeRows: request.treeRows,
            treeSizeFacts: treeSizeFacts,
            statusPatch: statusPatch,
            metadataLineage: BridgeWorktreeFileMetadataLineage(
                loadedBy: "startup_window",
                lane: "foreground"
            )
        )
    }

    static func treeWindow(
        request: BridgeWorktreeTreeWindowBuildRequest
    ) -> BridgeWorktreeTreeWindowFrame {
        let projectionIdentity = BridgeWorktreeTreeProjectionIdentity(
            source: request.source,
            pathScope: request.pathScope,
            sortKey: nil,
            groupKey: nil,
            filterKey: nil,
            treeWindowKey: request.treeWindowKey
        )
        return BridgeWorktreeTreeWindowFrame(
            streamId: request.streamId,
            sequence: request.sequence,
            projectionIdentity: projectionIdentity,
            rows: request.rows,
            treeSizeFacts: treeSizeFacts(
                pathCount: request.treePathCount,
                estimatedTotalHeightPixels: request.treeEstimatedTotalHeightPixels,
                windowStartIndex: request.treeWindowStartIndex,
                windowRowCount: request.treeWindowRowCount,
                rowHeightPixels: request.treeRowHeightPixels
            ),
            metadataLineage: request.metadataLineage
        )
    }

    static func fileDescriptor(
        request: BridgeWorktreeFileDescriptorBuildRequest
    ) throws -> BridgeWorktreeFileDescriptorFrame {
        try validateVirtualizedExtent(request: request)

        let contentDescriptor = attachedDescriptor(
            request: BridgeWorktreeAttachedDescriptorBuildRequest(
                scope: BridgeWorktreeDescriptorScope(
                    paneId: request.paneId,
                    protocolId: "worktree-file",
                    source: request.source,
                    streamId: request.streamId
                ),
                resourceKind: "worktree.fileContent",
                descriptorId: request.contentHandle,
                content: BridgeResourceContentDescriptor(
                    mediaType: contentMediaType(
                        pathExtension: request.fileExtension,
                        isBinary: request.isBinary
                    ),
                    encoding: request.isBinary ? .binary : .utf8,
                    expectedBytes: request.sizeBytes,
                    maxBytes: contentMaxBytes(for: request),
                    integrity: nil
                ),
                window: nil
            )
        )
        let descriptor = BridgeWorktreeFileDescriptor(
            path: request.path,
            fileId: request.fileId,
            contentHandle: request.contentHandle,
            contentDescriptor: contentDescriptor,
            contentHash: nil,
            sourceIdentity: request.source,
            sizeBytes: request.sizeBytes,
            virtualizedExtentKind: request.virtualizedExtentKind,
            lineCount: request.lineCount,
            estimatedContentHeightPixels: request.estimatedContentHeightPixels,
            isBinary: request.isBinary,
            language: request.language,
            fileExtension: request.fileExtension,
            modifiedAtUnixMilliseconds: nil
        )

        return BridgeWorktreeFileDescriptorFrame(
            streamId: request.streamId,
            sequence: request.sequence,
            descriptor: descriptor
        )
    }

    static func fileInvalidated(
        request: BridgeWorktreeFileInvalidationBuildRequest
    ) -> BridgeWorktreeFileInvalidatedFrame {
        BridgeWorktreeFileInvalidatedFrame(
            streamId: request.streamId,
            sequence: request.sequence,
            source: request.source,
            invalidation: BridgeWorktreeFileInvalidation(
                path: request.path,
                fileId: request.fileId,
                reason: request.reason,
                contentHandleIds: request.contentHandleIds,
                latestDescriptor: request.latestDescriptor
            )
        )
    }

    static func reset(request: BridgeWorktreeResetBuildRequest) -> BridgeWorktreeResetFrame {
        BridgeWorktreeResetFrame(
            streamId: request.streamId,
            sequence: request.sequence,
            reason: request.reason,
            source: request.source,
            replacementDescriptor: request.replacementDescriptor
        )
    }

    static func extentDiagnostics(
        request: BridgeWorktreeExtentDiagnosticsBuildRequest
    ) -> BridgeWorktreeExtentDiagnostics {
        BridgeWorktreeExtentDiagnostics(
            sourceId: request.source.sourceId,
            subscriptionGeneration: request.source.subscriptionGeneration,
            totalTreePathCount: request.totalTreePathCount,
            treeEstimatedTotalHeightPixels: request.treeEstimatedTotalHeightPixels,
            fileExtentKindCounts: request.fileExtentKindCounts,
            rejectionReasonCounts: request.rejectionReasonCounts
        )
    }

    private static func attachedDescriptor(
        request: BridgeWorktreeAttachedDescriptorBuildRequest
    ) -> BridgeAttachedResourceDescriptor {
        let identity = BridgeResourceIdentity(
            paneId: request.scope.paneId,
            protocolId: request.scope.protocolId,
            sourceId: request.scope.source.sourceId,
            packageId: nil,
            generation: request.scope.source.subscriptionGeneration,
            revision: nil,
            streamId: request.scope.streamId,
            cursor: request.scope.source.sourceCursor
        )
        let resourceUrl =
            "agentstudio://resource/\(request.scope.protocolId)/\(request.resourceKind)/\(request.descriptorId)"
            + "?generation=\(request.scope.source.subscriptionGeneration)&cursor=\(request.scope.source.sourceCursor)"
        let descriptor = BridgeResourceDescriptor(
            descriptorId: request.descriptorId,
            protocolId: request.scope.protocolId,
            resourceKind: request.resourceKind,
            resourceUrl: resourceUrl,
            identity: identity,
            content: request.content,
            window: request.window
        )

        return BridgeAttachedResourceDescriptor(
            ref: BridgeDescriptorRef(
                descriptorId: descriptor.descriptorId,
                expectedProtocol: descriptor.protocolId,
                expectedResourceKind: descriptor.resourceKind,
                expectedIdentity: identity
            ),
            descriptor: descriptor
        )
    }

    private static func contentMediaType(pathExtension: String?, isBinary: Bool) -> String {
        if isBinary {
            return "application/octet-stream"
        }
        if pathExtension == "json" {
            return "application/json"
        }
        return "text/plain"
    }

    private static func treeSizeFacts(
        pathCount: Int?,
        estimatedTotalHeightPixels: Double?,
        windowStartIndex: Int?,
        windowRowCount: Int?,
        rowHeightPixels: Double
    ) -> BridgeWorktreeTreeVirtualizedSizeFacts {
        let resolvedEstimatedHeight = estimatedTotalHeightPixels ?? Double(pathCount ?? 0) * rowHeightPixels
        return BridgeWorktreeTreeVirtualizedSizeFacts(
            extentKind: pathCount == nil ? .estimatedTotalHeight : .exactPathCount,
            pathCount: pathCount,
            windowStartIndex: windowStartIndex,
            windowRowCount: windowRowCount,
            rowHeightPixels: rowHeightPixels,
            estimatedTotalHeightPixels: resolvedEstimatedHeight
        )
    }

    private static func contentMaxBytes(for request: BridgeWorktreeFileDescriptorBuildRequest) -> Int {
        let requiresBoundedPreview =
            request.virtualizedExtentKind == .previewBounded
            || request.sizeBytes > AppPolicies.Bridge.contentMaxBytesPerItem
        if requiresBoundedPreview {
            return AppPolicies.Bridge.contentMaxBytesPerItem
        }
        return max(request.sizeBytes, 1)
    }

    private static func validateVirtualizedExtent(
        request: BridgeWorktreeFileDescriptorBuildRequest
    ) throws {
        switch request.virtualizedExtentKind {
        case .exactLineCount:
            guard request.lineCount != nil else {
                throw BridgeWorktreeFileSurfaceFrameBuilderError.exactLineCountMissingLineCount
            }
        case .estimatedHeight:
            guard request.estimatedContentHeightPixels != nil else {
                throw BridgeWorktreeFileSurfaceFrameBuilderError.estimatedHeightMissingEstimate
            }
        case .previewBounded:
            break
        case .unavailable:
            let unavailableAllowed =
                request.isBinary
                || request.sizeBytes > AppPolicies.Bridge.contentMaxBytesPerItem
                || request.contentAvailability != .readable
            guard unavailableAllowed else {
                throw BridgeWorktreeFileSurfaceFrameBuilderError.unavailableExtentForReadableText
            }
        }
    }
}
