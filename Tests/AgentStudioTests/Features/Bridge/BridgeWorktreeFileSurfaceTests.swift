import Foundation
import Testing

@testable import AgentStudio

struct BridgeWorktreeFileSurfaceTests {
    @Test("snapshot frame carries provider source identity and early tree size facts")
    func snapshotFrameCarriesProviderSourceIdentityAndEarlyTreeSizeFacts() throws {
        let sourceIdentity = makeSourceIdentity()

        let frame = BridgeWorktreeFileSurfaceFrameBuilder.snapshot(
            request: BridgeWorktreeFileSnapshotBuildRequest(
                paneId: "pane-1",
                source: sourceIdentity,
                requestSelector: nil,
                streamId: "worktree:pane-1",
                sequence: 0,
                treePathCount: 12_500,
                treeEstimatedTotalHeightPixels: nil,
                treeWindowStartIndex: 0,
                treeWindowRowCount: 250,
                treeRowHeightPixels: 22,
                treeRows: [],
                includeStatusPatch: true
            )
        )

        #expect(frame.kind == "snapshot")
        #expect(frame.frameKind == "worktree.snapshot")
        #expect(frame.source == sourceIdentity)
        #expect(frame.statusPatch?.staged == nil)
        #expect(frame.treeSizeFacts.extentKind == .exactPathCount)
        #expect(frame.treeSizeFacts.pathCount == 12_500)
        #expect(frame.treeSizeFacts.windowStartIndex == 0)
        #expect(frame.treeSizeFacts.windowRowCount == 250)
        #expect(frame.treeSizeFacts.rowHeightPixels == 22)
        #expect(frame.treeSizeFacts.estimatedTotalHeightPixels == 275_000)
    }

    @Test("snapshot frame can echo request selector for diagnostics")
    func snapshotFrameCanEchoRequestSelectorForDiagnostics() throws {
        let selector = BridgeWorktreeFileSurfaceSourceSpec(
            clientRequestId: "request-1",
            repoId: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            worktreeId: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
            rootPathToken: "root-token-1",
            cwdScope: nil,
            pathScope: ["Sources"],
            includeStatuses: true,
            includeComments: false,
            includeAgentComms: false,
            freshness: .live
        )

        let frame = BridgeWorktreeFileSurfaceFrameBuilder.snapshot(
            request: BridgeWorktreeFileSnapshotBuildRequest(
                paneId: "pane-1",
                source: makeSourceIdentity(),
                requestSelector: selector,
                streamId: "worktree:pane-1",
                sequence: 0,
                treePathCount: 10,
                treeEstimatedTotalHeightPixels: nil,
                treeWindowStartIndex: 0,
                treeWindowRowCount: 10,
                treeRowHeightPixels: 22,
                treeRows: [],
                includeStatusPatch: true
            )
        )

        #expect(frame.requestSelector == selector)
    }

    @Test("file descriptor frame carries explicit virtualized extent before content bytes")
    func fileDescriptorFrameCarriesExplicitVirtualizedExtentBeforeContentBytes() throws {
        let sourceIdentity = makeSourceIdentity()

        let frame = try BridgeWorktreeFileSurfaceFrameBuilder.fileDescriptor(
            request: BridgeWorktreeFileDescriptorBuildRequest(
                paneId: "pane-1",
                source: sourceIdentity,
                streamId: "worktree:pane-1",
                sequence: 1,
                path: "Sources/App/View.swift",
                fileId: "file-view-swift",
                contentHandle: "content-view-swift-head",
                contentHash: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
                sizeBytes: 8192,
                isBinary: false,
                contentAvailability: .readable,
                language: "swift",
                fileExtension: "swift",
                virtualizedExtentKind: .exactLineCount,
                lineCount: 320,
                estimatedContentHeightPixels: nil
            )
        )

        #expect(frame.kind == "delta")
        #expect(frame.frameKind == "worktree.fileDescriptor")
        #expect(frame.descriptor.sourceIdentity == sourceIdentity)
        #expect(frame.descriptor.path == "Sources/App/View.swift")
        #expect(frame.descriptor.contentHandle == "content-view-swift-head")
        #expect(
            frame.descriptor.contentHash
                == "sha256:1111111111111111111111111111111111111111111111111111111111111111"
        )
        #expect(frame.descriptor.contentDescriptor.descriptor.resourceKind == "worktree.fileContent")
        #expect(frame.descriptor.contentDescriptor.descriptor.content.expectedBytes == 8192)
        #expect(frame.descriptor.virtualizedExtentKind == .exactLineCount)
        #expect(frame.descriptor.lineCount == 320)
        #expect(frame.descriptor.estimatedContentHeightPixels == nil)

        let parsedResource = try #require(
            BridgeTransportResourceURL.parse(
                frame.descriptor.contentDescriptor.descriptor.resourceUrl,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            )
        )
        #expect(parsedResource.protocolId == "worktree-file")
        #expect(parsedResource.resourceKind == "worktree.fileContent")
        #expect(parsedResource.opaqueId == frame.descriptor.contentHandle)
    }

    @Test("tree window frame carries stable extent facts before row body hydration")
    func treeWindowFrameCarriesStableExtentFactsBeforeRowBodyHydration() throws {
        let sourceIdentity = makeSourceIdentity()

        let frame = BridgeWorktreeFileSurfaceFrameBuilder.treeWindow(
            request: BridgeWorktreeTreeWindowBuildRequest(
                paneId: "pane-1",
                source: sourceIdentity,
                streamId: "worktree:pane-1",
                sequence: 2,
                treeWindowKey: "tree-window-visible-0",
                pathScope: ["Sources", "Tests"],
                treePathCount: 12_500,
                treeEstimatedTotalHeightPixels: nil,
                treeWindowStartIndex: 250,
                treeWindowRowCount: 100,
                treeRowHeightPixels: 22,
                rows: [],
                metadataLineage: BridgeWorktreeFileMetadataLineage(
                    loadedBy: "idle",
                    lane: "idle"
                )
            )
        )

        #expect(frame.kind == "delta")
        #expect(frame.frameKind == "worktree.treeWindow")
        #expect(frame.projectionIdentity.source == sourceIdentity)
        #expect(frame.projectionIdentity.pathScope == ["Sources", "Tests"])
        #expect(frame.projectionIdentity.treeWindowKey == "tree-window-visible-0")
        #expect(frame.treeSizeFacts.extentKind == .exactPathCount)
        #expect(frame.treeSizeFacts.pathCount == 12_500)
        #expect(frame.treeSizeFacts.windowStartIndex == 250)
        #expect(frame.treeSizeFacts.windowRowCount == 100)
        #expect(frame.treeSizeFacts.estimatedTotalHeightPixels == 275_000)
    }

    @Test("tree window can carry conservative estimated extent without exact path count")
    func treeWindowCanCarryConservativeEstimatedExtentWithoutExactPathCount() throws {
        let sourceIdentity = makeSourceIdentity()

        let frame = BridgeWorktreeFileSurfaceFrameBuilder.treeWindow(
            request: BridgeWorktreeTreeWindowBuildRequest(
                paneId: "pane-1",
                source: sourceIdentity,
                streamId: "worktree:pane-1",
                sequence: 2,
                treeWindowKey: "tree-window-visible-0",
                pathScope: [],
                treePathCount: nil,
                treeEstimatedTotalHeightPixels: 550_000,
                treeWindowStartIndex: 0,
                treeWindowRowCount: 100,
                treeRowHeightPixels: 22,
                rows: [],
                metadataLineage: BridgeWorktreeFileMetadataLineage(
                    loadedBy: "idle",
                    lane: "idle"
                )
            )
        )

        #expect(frame.treeSizeFacts.extentKind == .estimatedTotalHeight)
        #expect(frame.treeSizeFacts.pathCount == nil)
        #expect(frame.treeSizeFacts.estimatedTotalHeightPixels == 550_000)
    }

    @Test("snapshot can omit status patch when selector disables statuses")
    func snapshotCanOmitStatusPatchWhenSelectorDisablesStatuses() throws {
        let frame = BridgeWorktreeFileSurfaceFrameBuilder.snapshot(
            request: BridgeWorktreeFileSnapshotBuildRequest(
                paneId: "pane-1",
                source: makeSourceIdentity(),
                requestSelector: nil,
                streamId: "worktree:pane-1",
                sequence: 0,
                treePathCount: 10,
                treeEstimatedTotalHeightPixels: nil,
                treeWindowStartIndex: 0,
                treeWindowRowCount: 10,
                treeRowHeightPixels: 22,
                treeRows: [],
                includeStatusPatch: false
            )
        )

        #expect(frame.statusPatch == nil)
    }

    @Test("unavailable file extent is reserved for binary or metadata-only content")
    func unavailableFileExtentIsReservedForBinaryOrMetadataOnlyContent() throws {
        let sourceIdentity = makeSourceIdentity()

        let frame = try BridgeWorktreeFileSurfaceFrameBuilder.fileDescriptor(
            request: BridgeWorktreeFileDescriptorBuildRequest(
                paneId: "pane-1",
                source: sourceIdentity,
                streamId: "worktree:pane-1",
                sequence: 2,
                path: "Assets/logo.png",
                fileId: "file-logo-png",
                contentHandle: "content-logo-png",
                contentHash: nil,
                sizeBytes: 42_000,
                isBinary: true,
                contentAvailability: .metadataOnly,
                language: nil,
                fileExtension: "png",
                virtualizedExtentKind: .unavailable,
                lineCount: nil,
                estimatedContentHeightPixels: nil
            )
        )

        #expect(frame.descriptor.isBinary)
        #expect(frame.descriptor.virtualizedExtentKind == .unavailable)
        #expect(frame.descriptor.lineCount == nil)
        #expect(frame.descriptor.estimatedContentHeightPixels == nil)
        #expect(frame.descriptor.contentHash == nil)
        #expect(frame.descriptor.contentDescriptor.descriptor.content.encoding == .binary)
    }

    @Test("preview bounded descriptor preserves metadata without requiring full content extent")
    func previewBoundedDescriptorPreservesMetadataWithoutRequiringFullContentExtent() throws {
        let frame = try BridgeWorktreeFileSurfaceFrameBuilder.fileDescriptor(
            request: BridgeWorktreeFileDescriptorBuildRequest(
                paneId: "pane-1",
                source: makeSourceIdentity(),
                streamId: "worktree:pane-1",
                sequence: 5,
                path: "Logs/huge.log",
                fileId: "file-huge-log",
                contentHandle: "content-huge-log-preview",
                contentHash: "sha256:2222222222222222222222222222222222222222222222222222222222222222",
                sizeBytes: AppPolicies.Bridge.contentMaxBytesPerItem + 1,
                isBinary: false,
                contentAvailability: .readable,
                language: nil,
                fileExtension: "log",
                virtualizedExtentKind: .previewBounded,
                lineCount: nil,
                estimatedContentHeightPixels: nil
            )
        )

        #expect(frame.descriptor.virtualizedExtentKind == .previewBounded)
        #expect(
            frame.descriptor.contentHash
                == "sha256:2222222222222222222222222222222222222222222222222222222222222222"
        )
        #expect(frame.descriptor.sizeBytes == AppPolicies.Bridge.contentMaxBytesPerItem + 1)
        #expect(
            frame.descriptor.contentDescriptor.descriptor.content.maxBytes
                == AppPolicies.Bridge.contentMaxBytesPerItem
        )
    }

    @Test("estimated-height file descriptor carries conservative extent before content bytes")
    func estimatedHeightFileDescriptorCarriesConservativeExtentBeforeContentBytes() throws {
        let frame = try BridgeWorktreeFileSurfaceFrameBuilder.fileDescriptor(
            request: BridgeWorktreeFileDescriptorBuildRequest(
                paneId: "pane-1",
                source: makeSourceIdentity(),
                streamId: "worktree:pane-1",
                sequence: 6,
                path: "Sources/App/Generated.swift",
                fileId: "file-generated-swift",
                contentHandle: "content-generated-swift",
                contentHash: "sha256:3333333333333333333333333333333333333333333333333333333333333333",
                sizeBytes: 96_000,
                isBinary: false,
                contentAvailability: .readable,
                language: "swift",
                fileExtension: "swift",
                virtualizedExtentKind: .estimatedHeight,
                lineCount: nil,
                estimatedContentHeightPixels: 18_000
            )
        )

        #expect(frame.descriptor.virtualizedExtentKind == .estimatedHeight)
        #expect(frame.descriptor.lineCount == nil)
        #expect(frame.descriptor.estimatedContentHeightPixels == 18_000)
        #expect(frame.descriptor.contentDescriptor.descriptor.resourceKind == "worktree.fileContent")
    }

    @Test("unavailable file extent accepts unreadable text and metadata-only content")
    func unavailableFileExtentAcceptsUnreadableTextAndMetadataOnlyContent() throws {
        let unreadableText = try BridgeWorktreeFileSurfaceFrameBuilder.fileDescriptor(
            request: BridgeWorktreeFileDescriptorBuildRequest(
                paneId: "pane-1",
                source: makeSourceIdentity(),
                streamId: "worktree:pane-1",
                sequence: 5,
                path: "Sources/App/Private.swift",
                fileId: "file-private-swift",
                contentHandle: "content-private-swift",
                contentHash: nil,
                sizeBytes: 4096,
                isBinary: false,
                contentAvailability: .unreadable,
                language: "swift",
                fileExtension: "swift",
                virtualizedExtentKind: .unavailable,
                lineCount: nil,
                estimatedContentHeightPixels: nil
            )
        )
        let metadataOnlyText = try BridgeWorktreeFileSurfaceFrameBuilder.fileDescriptor(
            request: BridgeWorktreeFileDescriptorBuildRequest(
                paneId: "pane-1",
                source: makeSourceIdentity(),
                streamId: "worktree:pane-1",
                sequence: 6,
                path: "Sources/App/MetadataOnly.swift",
                fileId: "file-metadata-only-swift",
                contentHandle: "content-metadata-only-swift",
                contentHash: nil,
                sizeBytes: 4096,
                isBinary: false,
                contentAvailability: .metadataOnly,
                language: "swift",
                fileExtension: "swift",
                virtualizedExtentKind: .unavailable,
                lineCount: nil,
                estimatedContentHeightPixels: nil
            )
        )

        #expect(unreadableText.descriptor.virtualizedExtentKind == .unavailable)
        #expect(metadataOnlyText.descriptor.virtualizedExtentKind == .unavailable)
    }

    @Test("file invalidation frame carries source and handle facts without descriptor replacement")
    func fileInvalidationFrameCarriesSourceAndHandleFactsWithoutDescriptorReplacement() throws {
        let sourceIdentity = makeSourceIdentity()

        let frame = BridgeWorktreeFileSurfaceFrameBuilder.fileInvalidated(
            request: BridgeWorktreeFileInvalidationBuildRequest(
                source: sourceIdentity,
                streamId: "worktree:pane-1",
                sequence: 6,
                path: "Sources/App/View.swift",
                fileId: "file-view-swift",
                reason: .contentChanged,
                contentHandleIds: ["content-view-swift-head"],
                latestDescriptor: nil
            )
        )

        #expect(frame.kind == "delta")
        #expect(frame.frameKind == "worktree.fileInvalidated")
        #expect(frame.source == sourceIdentity)
        #expect(frame.invalidation.reason == .contentChanged)
        #expect(frame.invalidation.contentHandleIds == ["content-view-swift-head"])
        #expect(frame.invalidation.latestDescriptor == nil)
    }

    @Test("reset frame revokes source without replacement descriptor by default")
    func resetFrameRevokesSourceWithoutReplacementDescriptorByDefault() throws {
        let sourceIdentity = makeSourceIdentity()

        let frame = BridgeWorktreeFileSurfaceFrameBuilder.reset(
            request: BridgeWorktreeResetBuildRequest(
                streamId: "worktree:pane-1",
                sequence: 7,
                reason: .providerRestart,
                source: sourceIdentity,
                replacementDescriptor: nil
            )
        )

        #expect(frame.kind == "reset")
        #expect(frame.frameKind == "worktree.reset")
        #expect(frame.generation == sourceIdentity.subscriptionGeneration)
        #expect(frame.reason == .providerRestart)
        #expect(frame.source == sourceIdentity)
        #expect(frame.replacementDescriptor == nil)
    }

    @Test("extent diagnostics expose allowlisted metadata only")
    func extentDiagnosticsExposeAllowlistedMetadataOnly() throws {
        let diagnostic = BridgeWorktreeFileSurfaceFrameBuilder.extentDiagnostics(
            request: BridgeWorktreeExtentDiagnosticsBuildRequest(
                source: makeSourceIdentity(),
                totalTreePathCount: 12_500,
                treeEstimatedTotalHeightPixels: 275_000,
                fileExtentKindCounts: [.exactLineCount: 7, .estimatedHeight: 2, .previewBounded: 1, .unavailable: 3],
                rejectionReasonCounts: [.selectorEscapesRoot: 2, .unsupportedComments: 1]
            )
        )
        let encoded = String(data: try JSONEncoder().encode(diagnostic), encoding: .utf8) ?? ""

        #expect(diagnostic.sourceId == "worktree-source-1")
        #expect(diagnostic.totalTreePathCount == 12_500)
        #expect(diagnostic.fileExtentKindCounts[.unavailable] == 3)
        #expect(encoded.contains("Sources/App/View.swift") == false)
        #expect(encoded.contains("agentstudio://resource") == false)
        #expect(encoded.contains("content-view-swift-head") == false)
    }

    @Test("exact line-count extent rejects descriptors without line count")
    func exactLineCountExtentRejectsDescriptorsWithoutLineCount() throws {
        #expect(throws: BridgeWorktreeFileSurfaceFrameBuilderError.self) {
            _ = try BridgeWorktreeFileSurfaceFrameBuilder.fileDescriptor(
                request: BridgeWorktreeFileDescriptorBuildRequest(
                    paneId: "pane-1",
                    source: makeSourceIdentity(),
                    streamId: "worktree:pane-1",
                    sequence: 3,
                    path: "Sources/App/View.swift",
                    fileId: "file-view-swift",
                    contentHandle: "content-view-swift-head",
                    contentHash: nil,
                    sizeBytes: 8192,
                    isBinary: false,
                    contentAvailability: .readable,
                    language: "swift",
                    fileExtension: "swift",
                    virtualizedExtentKind: .exactLineCount,
                    lineCount: nil,
                    estimatedContentHeightPixels: nil
                )
            )
        }
    }

    @Test("unavailable extent rejects readable text descriptors")
    func unavailableExtentRejectsReadableTextDescriptors() throws {
        #expect(throws: BridgeWorktreeFileSurfaceFrameBuilderError.self) {
            _ = try BridgeWorktreeFileSurfaceFrameBuilder.fileDescriptor(
                request: BridgeWorktreeFileDescriptorBuildRequest(
                    paneId: "pane-1",
                    source: makeSourceIdentity(),
                    streamId: "worktree:pane-1",
                    sequence: 4,
                    path: "Sources/App/View.swift",
                    fileId: "file-view-swift",
                    contentHandle: "content-view-swift-head",
                    contentHash: nil,
                    sizeBytes: 8192,
                    isBinary: false,
                    contentAvailability: .readable,
                    language: "swift",
                    fileExtension: "swift",
                    virtualizedExtentKind: .unavailable,
                    lineCount: nil,
                    estimatedContentHeightPixels: nil
                )
            )
        }
    }

    @Test("extent validation errors do not stringify raw paths")
    func extentValidationErrorsDoNotStringifyRawPaths() throws {
        do {
            _ = try BridgeWorktreeFileSurfaceFrameBuilder.fileDescriptor(
                request: BridgeWorktreeFileDescriptorBuildRequest(
                    paneId: "pane-1",
                    source: makeSourceIdentity(),
                    streamId: "worktree:pane-1",
                    sequence: 4,
                    path: "Sources/App/View.swift",
                    fileId: "file-view-swift",
                    contentHandle: "content-view-swift-head",
                    contentHash: nil,
                    sizeBytes: 8192,
                    isBinary: false,
                    contentAvailability: .readable,
                    language: "swift",
                    fileExtension: "swift",
                    virtualizedExtentKind: .unavailable,
                    lineCount: nil,
                    estimatedContentHeightPixels: nil
                )
            )
            Issue.record("Expected readable unavailable extent to throw")
        } catch {
            #expect(String(describing: error).contains("Sources/App/View.swift") == false)
            #expect(String(reflecting: error).contains("Sources/App/View.swift") == false)
        }
    }

    private func makeSourceIdentity() -> BridgeWorktreeFileSurfaceSourceIdentity {
        BridgeWorktreeFileSurfaceSourceIdentity(
            sourceId: "worktree-source-1",
            repoId: "repo-1",
            worktreeId: "worktree-1",
            subscriptionGeneration: 3,
            sourceCursor: "cursor-3",
            rootRevisionToken: "root-token-1"
        )
    }
}
