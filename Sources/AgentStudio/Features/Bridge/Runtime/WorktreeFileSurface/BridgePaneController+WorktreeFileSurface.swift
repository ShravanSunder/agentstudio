import Foundation

private struct BridgeWorktreeOpenTreeExtent: Sendable {
    let pathCount: Int?
    let estimatedTotalHeightPixels: Double?
}

private let worktreeFileTreeRowHeightPixels: Double = 24
private let estimatedRowsPerScopedDirectory = 1000
private let estimatedRowsForRootDirectory = 10_000

@MainActor
extension BridgePaneController {
    func handleWorktreeFileSurfaceOpenSourceStream(
        _ params: WorktreeFileSurfaceMethods.OpenSourceStreamMethod.Params
    ) async throws -> BridgeWorktreeSnapshotFrame {
        let worktree = try makeWorktreeFileSurfaceAuthority()
        let generation = nextWorktreeFileSurfaceGeneration + 1
        nextWorktreeFileSurfaceGeneration = generation
        let openedSource: BridgeWorktreeFileOpenedSource
        do {
            openedSource = try BridgeWorktreeFileSourceProvider.openSource(
                spec: params,
                worktree: worktree,
                subscriptionGeneration: generation
            )
        } catch BridgeWorktreeFileSourceProviderError.worktreeMismatch {
            throw RPCMethodDispatchError.invalidParams("Worktree/File selector does not match pane worktree")
        } catch BridgeWorktreeFileSourceProviderError.rootTokenMismatch {
            throw RPCMethodDispatchError.invalidParams("Worktree/File selector root token is stale")
        } catch BridgeWorktreeFileSourceProviderError.selectorEscapesRoot {
            throw RPCMethodDispatchError.invalidParams("Worktree/File selector escapes worktree root")
        } catch BridgeWorktreeFileSourceProviderError.unsupportedReservedContract {
            throw RPCMethodDispatchError.invalidParams("Worktree/File selector requests unsupported reserved streams")
        }

        let treeExtent = await Self.resolveOpenTreeExtent(
            rootURL: worktree.path,
            scopedPaths: openedSource.canonicalPathScope
        )
        guard generation == nextWorktreeFileSurfaceGeneration else {
            throw RPCMethodDispatchError.handlerFailure("Stale Worktree/File source generation")
        }
        let streamId = "worktree-file:\(paneId.uuidString)"
        pendingWorktreeFileIntakeFrames.removeAll(keepingCapacity: true)
        await resourceLeaseRegistry.reset(paneId: paneId, protocolId: "worktree-file")
        await worktreeFileResourceStore.reset(protocolId: "worktree-file")
        let snapshotFrame = BridgeWorktreeFileSurfaceFrameBuilder.snapshot(
            request: BridgeWorktreeFileSnapshotBuildRequest(
                paneId: paneId.uuidString,
                source: openedSource.source,
                requestSelector: params,
                streamId: streamId,
                sequence: 0,
                treePathCount: treeExtent.pathCount,
                treeEstimatedTotalHeightPixels: treeExtent.estimatedTotalHeightPixels,
                treeWindowStartIndex: 0,
                treeWindowRowCount: 0,
                treeRowHeightPixels: worktreeFileTreeRowHeightPixels,
                includeStatusDescriptor: openedSource.includeStatuses
            )
        )
        let resourceBodies = try Self.makeSnapshotResourceBodies(snapshotFrame)
        let fileDescriptors = try await BridgeWorktreeFileMaterializer.materializeInitialFileDescriptors(
            request: BridgeWorktreeFileMaterializationRequest(
                rootURL: worktree.path,
                paneId: paneId,
                openedSource: openedSource,
                streamId: streamId,
                firstSequence: 1
            )
        )
        guard generation == nextWorktreeFileSurfaceGeneration else {
            throw RPCMethodDispatchError.handlerFailure("Stale Worktree/File source generation")
        }
        try await activateWorktreeFileSurfaceLeases(snapshotFrame)
        try await activateWorktreeFileSurfaceLeases(
            fileDescriptors.map { $0.frame.descriptor.contentDescriptor.descriptor }
        )
        for resourceBody in resourceBodies {
            await worktreeFileResourceStore.register(resourceBody.resource, body: resourceBody.body)
        }
        for fileDescriptor in fileDescriptors {
            await worktreeFileResourceStore.register(fileDescriptor.resource, body: fileDescriptor.body)
        }
        pendingWorktreeFileIntakeFrames = try Self.makeIntakeFrameStrings(
            fileDescriptors.map(\.frame)
        )
        return snapshotFrame
    }

    private func makeWorktreeFileSurfaceAuthority() throws -> Worktree {
        guard let repoId = runtime.metadata.repoId,
            let worktreeId = runtime.metadata.worktreeId
        else {
            throw RPCMethodDispatchError.invalidParams("Worktree/File pane is missing repo or worktree identity")
        }
        let rootURL = try worktreeFileSurfaceRootURL()
        return Worktree(
            id: worktreeId,
            repoId: repoId,
            name: runtime.metadata.worktreeName ?? rootURL.lastPathComponent,
            path: rootURL
        )
    }

    private func worktreeFileSurfaceRootURL() throws -> URL {
        if case .workspace(let rootPath, _) = bridgePaneState.source {
            return URL(fileURLWithPath: rootPath).standardizedFileURL.resolvingSymlinksInPath()
        }
        if let cwd = runtime.metadata.cwd {
            return cwd.standardizedFileURL.resolvingSymlinksInPath()
        }
        throw RPCMethodDispatchError.invalidParams("Worktree/File pane is missing a root path")
    }

    private nonisolated static func resolveOpenTreeExtent(
        rootURL: URL,
        scopedPaths: [String]
    ) async -> BridgeWorktreeOpenTreeExtent {
        // swiftlint:disable:next no_task_detached
        await Task.detached(priority: .utility) {
            let targetPaths =
                scopedPaths.isEmpty || scopedPaths == ["."]
                ? [rootURL]
                : scopedPaths.map { rootURL.appending(path: $0) }
            var fileCount = 0
            var missingCount = 0
            var directoryCount = 0
            for targetPath in targetPaths {
                let values = try? targetPath.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                if values?.isRegularFile == true {
                    fileCount += 1
                } else if values?.isDirectory == true {
                    directoryCount += 1
                } else {
                    missingCount += 1
                }
            }
            if directoryCount == 0 {
                return BridgeWorktreeOpenTreeExtent(pathCount: fileCount, estimatedTotalHeightPixels: nil)
            }
            let estimatedRowsPerDirectory =
                scopedPaths.isEmpty || scopedPaths == ["."]
                ? estimatedRowsForRootDirectory
                : estimatedRowsPerScopedDirectory
            let estimatedRows =
                fileCount
                + missingCount
                + (directoryCount * estimatedRowsPerDirectory)
            return BridgeWorktreeOpenTreeExtent(
                pathCount: nil,
                estimatedTotalHeightPixels: Double(estimatedRows) * worktreeFileTreeRowHeightPixels
            )
        }.value
    }

    private func activateWorktreeFileSurfaceLeases(_ snapshotFrame: BridgeWorktreeSnapshotFrame) async throws {
        var descriptors = [snapshotFrame.treeDescriptor.descriptor]
        if let statusDescriptor = snapshotFrame.statusDescriptor?.descriptor {
            descriptors.append(statusDescriptor)
        }
        try await activateWorktreeFileSurfaceLeases(descriptors)
    }

    private func activateWorktreeFileSurfaceLeases(
        _ descriptors: [BridgeResourceDescriptor]
    ) async throws {
        for descriptor in descriptors {
            guard
                let resource = BridgeTransportResourceURL.parse(
                    descriptor.resourceUrl,
                    allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
                )
            else {
                throw RPCMethodDispatchError.handlerFailure("Invalid Worktree/File descriptor URL")
            }
            let expectedRevocationRevision = resourceLeaseRegistry.revocationRevision(
                paneId: paneId,
                protocolId: resource.protocolId,
                resourceKind: resource.resourceKind
            )
            let registered = await resourceLeaseRegistry.register(
                resource,
                paneId: paneId,
                descriptorId: descriptor.descriptorId,
                maxBytes: descriptor.content.maxBytes,
                expectedRevocationRevision: expectedRevocationRevision
            )
            guard registered else {
                throw RPCMethodDispatchError.handlerFailure("Failed to register Worktree/File descriptor lease")
            }
        }
    }

    private nonisolated static func makeIntakeFrameStrings(
        _ frames: [BridgeWorktreeFileDescriptorFrame]
    ) throws -> [String] {
        let encoder = JSONEncoder()
        let envelopeEncoder = BridgePushEnvelopeEncoder()
        return try frames.map { frame in
            try envelopeEncoder.encodeIntakeFrame(
                metadata: BridgeIntakeFrameMetadata(
                    kind: .delta,
                    streamId: frame.streamId,
                    generation: frame.generation,
                    sequence: frame.sequence
                ),
                payload: encoder.encode(frame),
                traceContext: nil
            )
        }
    }

    private struct WorktreeFileSurfaceResourceBodyRegistration: Sendable {
        let resource: BridgeTransportResourceURL
        let body: BridgeWorktreeFileResourceBody
    }

    private nonisolated static func makeSnapshotResourceBodies(
        _ snapshotFrame: BridgeWorktreeSnapshotFrame
    ) throws -> [WorktreeFileSurfaceResourceBodyRegistration] {
        let encoder = JSONEncoder()
        let treeResource = try parsedWorktreeFileResource(
            descriptor: snapshotFrame.treeDescriptor.descriptor
        )
        let treeBody = BridgeWorktreeTreeWindowResourceBody(
            source: snapshotFrame.source,
            treeSizeFacts: snapshotFrame.treeSizeFacts,
            rows: []
        )
        var registrations = [
            WorktreeFileSurfaceResourceBodyRegistration(
                resource: treeResource,
                body: BridgeWorktreeFileResourceBody(
                    data: try encoder.encode(treeBody),
                    mimeType: "application/json"
                )
            )
        ]

        if let statusDescriptor = snapshotFrame.statusDescriptor?.descriptor {
            let statusResource = try parsedWorktreeFileResource(descriptor: statusDescriptor)
            let statusBody = BridgeWorktreeStatusResourceBody(
                source: snapshotFrame.source,
                patch: BridgeWorktreeStatusPatch(
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
            )
            registrations.append(
                WorktreeFileSurfaceResourceBodyRegistration(
                    resource: statusResource,
                    body: BridgeWorktreeFileResourceBody(
                        data: try encoder.encode(statusBody),
                        mimeType: "application/json"
                    )
                ))
        }
        return registrations
    }

    private nonisolated static func parsedWorktreeFileResource(
        descriptor: BridgeResourceDescriptor
    ) throws -> BridgeTransportResourceURL {
        guard
            let resource = BridgeTransportResourceURL.parse(
                descriptor.resourceUrl,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            )
        else {
            throw RPCMethodDispatchError.handlerFailure("Invalid Worktree/File descriptor URL")
        }
        return resource
    }
}
