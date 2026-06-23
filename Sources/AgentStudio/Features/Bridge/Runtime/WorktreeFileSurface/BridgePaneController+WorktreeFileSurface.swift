import Foundation

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

        let treePathCount = await Self.countCurrentTreePaths(
            rootURL: worktree.path,
            scopedPaths: openedSource.canonicalPathScope
        )
        let snapshotFrame = BridgeWorktreeFileSurfaceFrameBuilder.snapshot(
            request: BridgeWorktreeFileSnapshotBuildRequest(
                paneId: paneId.uuidString,
                source: openedSource.source,
                requestSelector: params,
                streamId: "worktree-file:\(paneId.uuidString)",
                sequence: 0,
                treePathCount: treePathCount,
                treeEstimatedTotalHeightPixels: nil,
                treeWindowStartIndex: 0,
                treeWindowRowCount: 0,
                treeRowHeightPixels: 24,
                includeStatusDescriptor: openedSource.includeStatuses
            )
        )
        try await activateWorktreeFileSurfaceLeases(snapshotFrame)
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

    private nonisolated static func countCurrentTreePaths(
        rootURL: URL,
        scopedPaths: [String]
    ) async -> Int {
        // swiftlint:disable:next no_task_detached
        await Task.detached(priority: .utility) {
            let targetPaths =
                scopedPaths.isEmpty || scopedPaths == ["."]
                ? [rootURL]
                : scopedPaths.map { rootURL.appending(path: $0) }
            var pathCount = 0
            for targetPath in targetPaths {
                pathCount += Self.countCurrentTreePaths(rootURL: targetPath)
            }
            return pathCount
        }.value
    }

    private nonisolated static func countCurrentTreePaths(rootURL: URL) -> Int {
        guard
            let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return 0
        }
        var pathCount = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]),
                values.isDirectory == true || values.isRegularFile == true
            else {
                continue
            }
            pathCount += 1
        }
        return pathCount
    }

    private func activateWorktreeFileSurfaceLeases(_ snapshotFrame: BridgeWorktreeSnapshotFrame) async throws {
        var descriptors = [snapshotFrame.treeDescriptor.descriptor]
        if let statusDescriptor = snapshotFrame.statusDescriptor?.descriptor {
            descriptors.append(statusDescriptor)
        }
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
}
