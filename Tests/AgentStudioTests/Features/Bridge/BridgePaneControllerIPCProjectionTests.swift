import AgentStudioAppIPC
import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgePaneControllerIPCProjectionTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("IPC refresh builds package from pane worktree context")
        func ipcRefresh_buildsPackageFromPaneWorktreeContext() async throws {
            let worktreeId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
            let baseEndpoint = makeBridgeEndpoint(endpointId: "index", kind: .index)
            let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
            let changedFile = makeBridgeEndpointChangedFile(
                fileId: "source",
                path: "Sources/App/View.swift",
                sizeBytes: 100,
                oldContentHash: bridgeSHA256ContentHash("old"),
                newContentHash: bridgeSHA256ContentHash("new")
            )
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: baseEndpoint,
                    headEndpoint: headEndpoint,
                    changedFiles: [changedFile]
                ),
                contentByHandleId: [:]
            )
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: "/tmp/worktree", baseline: .unstaged)
                ),
                metadata: PaneMetadata(
                    contentType: .diff,
                    title: "Bridge Review",
                    facets: PaneContextFacets(worktreeId: worktreeId)
                ),
                reviewSourceProvider: provider
            )
            defer { controller.teardown() }
            let correlationId = UUID()

            let result = try await controller.refreshReviewForIPC(correlationId: correlationId)

            #expect(result.paneId == controller.paneId)
            #expect(result.refreshed == true)
            #expect(result.status == "ready")
            #expect(result.correlationId == correlationId)
            #expect(result.packageId == controller.paneState.diff.packageMetadata?.packageId)
            #expect(controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-source"])
            #expect(await provider.recordedContentRequestsCount() == 0)
        }

        @Test("IPC content body returns text without duplicate base64 for UTF-8 content")
        func ipcContentBody_returnsTextWithoutDuplicateBase64ForUtf8Content() async throws {
            let handle = makeBridgeContentHandle(
                itemId: "item-source",
                role: .head,
                reviewGeneration: 7,
                contentHash: bridgeSHA256ContentHash("let value = 1\n"),
                sizeBytes: 14
            )
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: makeBridgeEndpoint(endpointId: "index", kind: .index),
                    headEndpoint: makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree),
                    changedFiles: []
                ),
                contentByHandleId: [
                    handle.handleId: makeContentResult(handle: handle, data: "let value = 1\n")
                ]
            )
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil),
                reviewSourceProvider: provider
            )
            defer { controller.teardown() }
            await controller.reviewContentStore.activate(handles: [handle], reviewGeneration: 7)

            let result = try await controller.loadContentForIPC(
                contentHandleId: handle.handleId,
                reviewGeneration: 7
            )

            #expect(result.contentText == "let value = 1\n")
            #expect(result.contentBase64 == nil)
        }

        @Test("IPC content body rejects payloads that exceed the IPC response budget")
        func ipcContentBody_rejectsPayloadsThatExceedIPCResponseBudget() async throws {
            let oversizedText = String(repeating: "a", count: 1_000_000)
            let handle = makeBridgeContentHandle(
                itemId: "item-source",
                role: .head,
                reviewGeneration: 7,
                contentHash: bridgeSHA256ContentHash(oversizedText),
                sizeBytes: oversizedText.utf8.count
            )
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: makeBridgeEndpoint(endpointId: "index", kind: .index),
                    headEndpoint: makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree),
                    changedFiles: []
                ),
                contentByHandleId: [
                    handle.handleId: makeContentResult(handle: handle, data: oversizedText)
                ]
            )
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil),
                reviewSourceProvider: provider
            )
            defer { controller.teardown() }
            await controller.reviewContentStore.activate(handles: [handle], reviewGeneration: 7)

            await #expect(throws: AppIPCBridgeError.self) {
                _ = try await controller.loadContentForIPC(
                    contentHandleId: handle.handleId,
                    reviewGeneration: 7
                )
            }
        }

        @Test("IPC package snapshot rejects oversized metadata projections before frame encoding")
        func ipcPackageSnapshot_rejectsOversizedMetadataProjectionsBeforeFrameEncoding() async throws {
            let worktreeId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
            let longPathSegment = String(repeating: "very-long-folder-name/", count: 180)
            let changedFiles = (0..<260).map { index in
                makeBridgeEndpointChangedFile(
                    fileId: "source-\(index)",
                    path: "Sources/\(longPathSegment)File\(index).swift",
                    sizeBytes: 100,
                    oldContentHash: bridgeSHA256ContentHash("old-\(index)"),
                    newContentHash: bridgeSHA256ContentHash("new-\(index)")
                )
            }
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: makeBridgeEndpoint(endpointId: "index", kind: .index),
                    headEndpoint: makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree),
                    changedFiles: changedFiles
                ),
                contentByHandleId: [:]
            )
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: "/tmp/worktree", baseline: .unstaged)
                ),
                metadata: PaneMetadata(
                    contentType: .diff,
                    title: "Bridge Review",
                    facets: PaneContextFacets(worktreeId: worktreeId)
                ),
                reviewSourceProvider: provider
            )
            defer { controller.teardown() }

            _ = try await controller.refreshReviewForIPC(correlationId: nil)

            #expect(throws: AppIPCBridgeError.self) {
                _ = try controller.ipcReviewPackageSnapshot()
            }
        }
    }
}
