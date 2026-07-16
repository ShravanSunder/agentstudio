import AgentStudioProgrammaticControl
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

        @Test("IPC package snapshot omits materialized package payload")
        func ipcPackageSnapshot_omitsMaterializedPackagePayload() async throws {
            let worktreeId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: makeBridgeEndpoint(endpointId: "index", kind: .index),
                    headEndpoint: makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree),
                    changedFiles: [
                        makeBridgeEndpointChangedFile(
                            fileId: "source",
                            path: "Sources/App/View.swift",
                            sizeBytes: 100,
                            oldContentHash: bridgeSHA256ContentHash("old"),
                            newContentHash: bridgeSHA256ContentHash("new")
                        )
                    ]
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

            let result = try controller.ipcReviewPackageSnapshot()
            let encodedResult = try JSONEncoder().encode(result)
            let encodedPayload = try #require(String(data: encodedResult, encoding: .utf8))

            #expect(result.paneId == controller.paneId)
            #expect(result.status == "ready")
            #expect(result.packageId == controller.paneState.diff.packageMetadata?.packageId)
            #expect(result.reviewGeneration == controller.paneState.diff.packageMetadata?.reviewGeneration.rawValue)
            #expect(result.summary?.filesChanged == 1)
            #expect(encodedPayload.contains("\"package\"") == false)
            #expect(encodedPayload.contains("\"items\"") == false)
        }

        @Test("IPC content descriptor returns metadata without loading body bytes")
        func ipcContentDescriptor_returnsMetadataWithoutLoadingBodyBytes() async throws {
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
            installIPCContentDescriptorPackage(handle, in: controller)
            let productAdmission = try #require(controller.productAdmissionGate.acquire())
            await controller.reviewContentStore.activate(
                handles: [handle],
                reviewGeneration: 7,
                productAdmission: productAdmission
            )

            let result = try await controller.loadContentForIPC(
                contentHandleId: handle.handleId,
                reviewGeneration: 7
            )

            let encodedResult = try JSONEncoder().encode(result)
            let encodedPayload = try #require(String(data: encodedResult, encoding: .utf8))
            #expect(result.paneId == controller.paneId)
            #expect(result.handle.handleId == handle.handleId)
            #expect(result.mimeType == handle.mimeType)
            #expect(result.byteCount == handle.sizeBytes)
            #expect(encodedPayload.contains("resourceUrl") == false)
            #expect(encodedPayload.contains("contentText") == false)
            #expect(encodedPayload.contains("contentBase64") == false)
            #expect(await provider.recordedContentRequestsCount() == 0)
        }

        @Test("IPC content descriptor rejects content after teardown revokes review authority")
        func ipcContentDescriptor_rejectsContentAfterTeardownRevokesReviewAuthority() async throws {
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
            installIPCContentDescriptorPackage(handle, in: controller)
            let productAdmission = try #require(controller.productAdmissionGate.acquire())
            await controller.reviewContentStore.activate(
                handles: [handle],
                reviewGeneration: 7,
                productAdmission: productAdmission
            )

            controller.teardown()

            await #expect(throws: BridgeIPCProjectionError.self) {
                _ = try await controller.loadContentForIPC(
                    contentHandleId: handle.handleId,
                    reviewGeneration: 7
                )
            }
            #expect(await provider.recordedContentRequestsCount() == 0)
        }

        @Test("IPC content descriptor does not start provider body load")
        func ipcContentDescriptor_doesNotStartProviderBodyLoad() async throws {
            let handle = makeBridgeContentHandle(
                itemId: "item-source",
                role: .head,
                reviewGeneration: 7,
                contentHash: bridgeSHA256ContentHash("let value = 1\n"),
                sizeBytes: 14
            )
            let gate = BridgeContentLoadGate()
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: makeBridgeEndpoint(endpointId: "index", kind: .index),
                    headEndpoint: makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree),
                    changedFiles: []
                ),
                contentByHandleId: [
                    handle.handleId: makeContentResult(handle: handle, data: "let value = 1\n")
                ],
                contentLoadGate: gate
            )
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil),
                reviewSourceProvider: provider
            )
            defer { controller.teardown() }
            installIPCContentDescriptorPackage(handle, in: controller)
            let productAdmission = try #require(controller.productAdmissionGate.acquire())
            await controller.reviewContentStore.activate(
                handles: [handle],
                reviewGeneration: 7,
                productAdmission: productAdmission
            )

            let result = try await controller.loadContentForIPC(
                contentHandleId: handle.handleId,
                reviewGeneration: 7
            )

            #expect(result.handle.handleId == handle.handleId)
            #expect(await provider.recordedContentRequestsCount() == 0)
            await gate.releaseAll()
        }

        @Test("IPC content descriptor reflects active handle after byte cap tightens")
        func ipcContentDescriptor_reflectsActiveHandleAfterByteCapTightens() async throws {
            let handle = makeBridgeContentHandle(
                itemId: "item-source",
                role: .head,
                reviewGeneration: 7,
                contentHash: bridgeSHA256ContentHash("preserved"),
                sizeBytes: 9
            )
            let tightenedHandle = BridgeContentHandle(
                handleId: handle.handleId,
                itemId: handle.itemId,
                role: handle.role,
                endpointId: handle.endpointId,
                reviewGeneration: handle.reviewGeneration,
                contentHash: handle.contentHash,
                contentHashAlgorithm: handle.contentHashAlgorithm,
                cacheKey: handle.cacheKey,
                mimeType: handle.mimeType,
                language: handle.language,
                sizeBytes: 4,
                isBinary: handle.isBinary
            )
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: makeBridgeEndpoint(endpointId: "index", kind: .index),
                    headEndpoint: makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree),
                    changedFiles: []
                ),
                contentByHandleId: [
                    handle.handleId: makeContentResult(handle: handle, data: "preserved")
                ]
            )
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil),
                reviewSourceProvider: provider
            )
            defer { controller.teardown() }
            installIPCContentDescriptorPackage(handle, in: controller)
            let productAdmission = try #require(controller.productAdmissionGate.acquire())
            await controller.reviewContentStore.activate(
                handles: [handle],
                reviewGeneration: 7,
                productAdmission: productAdmission
            )
            let initialResult = try await controller.loadContentForIPC(
                contentHandleId: handle.handleId,
                reviewGeneration: 7
            )
            #expect(initialResult.byteCount == 9)

            await controller.reviewContentStore.activate(
                handles: [tightenedHandle],
                reviewGeneration: 7,
                productAdmission: productAdmission
            )

            let tightenedResult = try await controller.loadContentForIPC(
                contentHandleId: handle.handleId,
                reviewGeneration: 7
            )
            #expect(tightenedResult.byteCount == 4)
            #expect(await provider.recordedContentRequestsCount() == 0)
        }

        @Test("IPC content descriptor does not serialize oversized body payloads")
        func ipcContentDescriptor_doesNotSerializeOversizedBodyPayloads() async throws {
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
            installIPCContentDescriptorPackage(handle, in: controller)
            let productAdmission = try #require(controller.productAdmissionGate.acquire())
            await controller.reviewContentStore.activate(
                handles: [handle],
                reviewGeneration: 7,
                productAdmission: productAdmission
            )

            let result = try await controller.loadContentForIPC(
                contentHandleId: handle.handleId,
                reviewGeneration: 7
            )

            let encodedResult = try JSONEncoder().encode(result)
            let encodedPayload = try #require(String(data: encodedResult, encoding: .utf8))
            #expect(result.byteCount == oversizedText.utf8.count)
            #expect(encodedPayload.contains(oversizedText) == false)
            #expect(await provider.recordedContentRequestsCount() == 0)
        }

        @Test("IPC package snapshot omits oversized item projections before frame encoding")
        func ipcPackageSnapshot_omitsOversizedItemProjectionsBeforeFrameEncoding() async throws {
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

            let result = try controller.ipcReviewPackageSnapshot()
            let encodedResult = try JSONEncoder().encode(result)
            let encodedPayload = try #require(String(data: encodedResult, encoding: .utf8))

            #expect(result.packageId == controller.paneState.diff.packageMetadata?.packageId)
            #expect(result.summary?.filesChanged == changedFiles.count)
            #expect(encodedPayload.contains(longPathSegment) == false)
            #expect(encodedPayload.contains("\"items\"") == false)
        }

        @Test("IPC render state maps bridge diagnostics probes and bounds discard records")
        func ipcRenderState_mapsBridgeDiagnosticsProbesAndBoundsDiscardRecords() async throws {
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil)
            )
            defer { controller.teardown() }

            try await WebPageTestHarness.withManagedPage(controller.page) { page in
                _ = try await page.callJavaScript(
                    """
                    window.__bridgeVisibleHydrationStateProbe = {
                      reportedVisibleItemCount: 24,
                      trackedVisibleItemCount: 12,
                      truncatedVisibleItemCount: 12,
                      untrackedItemCount: 3,
                      loadingItemCount: 4,
                      readyItemCount: 5,
                      failedItemCount: 6,
                      deferredItemCount: 7,
                      abortedItemCount: 8,
                      pausedNow: true
                    };
                    window.__bridgeVisibleHydrationDiscardProbe = {
                      readyResultDiscardCount: 25,
                      records: Array.from({ length: 25 }, (_, index) => ({
                        hadState: index >= 5,
                        pausedNow: index % 2 === 0
                      }))
                    };
                    window.__bridgeFrameJankProbe = {
                      long_task: { count: 2, total_ms: 44.5, max_ms: 30.25 },
                      dropped_frame: { count: 3, worst_gap_ms: 19.75 },
                      last_long_task_at_ms: 1234.5
                    };
                    window.__bridgeProductMetadataStreamDiagnostic = {
                      kind: 'productMetadataStream',
                      acknowledgedFrameCount: 1,
                      activeSubscriptionCount: 2,
                      committedFrameCount: 1,
                      decoderState: 'poisoned',
                      expectedNextStreamSequence: 1,
                      failureCode: 'stream_identity_mismatch',
                      failureStage: 'acknowledgement',
                      identityMismatchField: 'metadataStreamId',
                      lastChunkByteCount: 256,
                      lastAcknowledgedStreamSequence: 0,
                      lastCommittedFrameKind: 'metadataStream.accepted',
                      lastRoutedFrameKind: 'subscription.accepted',
                      lifecycleState: 'failed',
                      peakRetainedByteCount: 512,
                      pushCount: 2,
                      readFulfilledCount: 3,
                      readPending: false,
                      readRequestCount: 4,
                      receivedByteCount: 768,
                      retainedByteCount: 0,
                      routeFailureCode: 'unknown_subscription',
                      routedFrameCount: 2,
                      streamOpenCount: 1
                    };
                    """
                )

                let result = try await controller.renderStateForIPC()
                let hydrationState = try #require(result.summary.visibleHydrationStateProbe)
                let discardProbe = try #require(result.summary.visibleHydrationDiscardProbe)
                let frameJankProbe = try #require(result.summary.frameJankProbe)
                let metadataStream = try #require(result.diagnostics.productMetadataStream)
                let productSession = result.diagnostics.productSession

                #expect(hydrationState.reportedVisibleItemCount == 24)
                #expect(hydrationState.trackedVisibleItemCount == 12)
                #expect(hydrationState.truncatedVisibleItemCount == 12)
                #expect(hydrationState.untrackedItemCount == 3)
                #expect(hydrationState.loadingItemCount == 4)
                #expect(hydrationState.readyItemCount == 5)
                #expect(hydrationState.failedItemCount == 6)
                #expect(hydrationState.deferredItemCount == 7)
                #expect(hydrationState.abortedItemCount == 8)
                #expect(hydrationState.pausedNow == true)
                #expect(discardProbe.readyResultDiscardCount == 25)
                #expect(discardProbe.records.count == 20)
                #expect(discardProbe.records.allSatisfy { $0.hadState == true })
                #expect(discardProbe.records.first?.pausedNow == false)
                #expect(frameJankProbe.longTask.count == 2)
                #expect(frameJankProbe.longTask.totalMs == 44.5)
                #expect(frameJankProbe.longTask.maxMs == 30.25)
                #expect(frameJankProbe.droppedFrame.count == 3)
                #expect(frameJankProbe.droppedFrame.worstGapMs == 19.75)
                #expect(frameJankProbe.lastLongTaskAtMs == 1234.5)
                #expect(result.visibleHydrationStateProbe == hydrationState)
                #expect(result.visibleHydrationDiscardProbe == discardProbe)
                #expect(result.frameJankProbe == frameJankProbe)
                expectProductMetadataStreamDiagnostic(metadataStream)
                #expect(productSession.activeProducerCount == 0)
                #expect(productSession.activeProducerTaskCount == 0)
                #expect(productSession.activeContentLeaseCount == 0)
                #expect(productSession.queuedFrameCount == 0)
                #expect(productSession.queuedByteCount == 0)
                #expect(productSession.pendingFrameWaiterCount == 0)
                #expect(productSession.inFlightFrameReceiptCount == 0)
                #expect(productSession.pendingLifecycleAcknowledgementCount == 0)
                #expect(productSession.nextMetadataStreamSequence == 0)
            }
        }

        @Test("IPC render state rejects negative worker acknowledgement diagnostics")
        func ipcRenderState_rejectsNegativeWorkerAcknowledgementDiagnostics() async throws {
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil)
            )
            defer { controller.teardown() }

            try await WebPageTestHarness.withManagedPage(controller.page) { page in
                _ = try await page.callJavaScript(
                    """
                    window.__bridgeProductMetadataStreamDiagnostic = {
                      kind: 'productMetadataStream',
                      acknowledgedFrameCount: -1,
                      lastAcknowledgedStreamSequence: -2,
                      failureStage: 'acknowledgement'
                    };
                    """
                )

                let result = try await controller.renderStateForIPC()
                let diagnostic = try #require(result.diagnostics.productMetadataStream)

                #expect(diagnostic.acknowledgedFrameCount == nil)
                #expect(diagnostic.lastAcknowledgedStreamSequence == nil)
                #expect(diagnostic.failureStage == "acknowledgement")
            }
        }

        @Test("IPC render state leaves absent bridge diagnostics probes nil")
        func ipcRenderState_leavesAbsentBridgeDiagnosticsProbesNil() async throws {
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil)
            )
            defer { controller.teardown() }

            try await WebPageTestHarness.withManagedPage(controller.page) { _ in
                let result = try await controller.renderStateForIPC()

                #expect(result.summary.visibleHydrationStateProbe == nil)
                #expect(result.summary.visibleHydrationDiscardProbe == nil)
                #expect(result.summary.frameJankProbe == nil)
                #expect(result.visibleHydrationStateProbe == nil)
                #expect(result.visibleHydrationDiscardProbe == nil)
                #expect(result.frameJankProbe == nil)
                #expect(result.diagnostics.productMetadataStream == nil)
                #expect(result.diagnostics.productSession.activeProducerCount == 0)
            }
        }

        @Test("IPC render state preserves native product session diagnostics when page projection fails")
        func ipcRenderState_preservesNativeProductSessionDiagnosticsWhenPageProjectionFails() async throws {
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil)
            )
            defer { controller.teardown() }

            try await WebPageTestHarness.withManagedPage(controller.page) { page in
                _ = try await page.callJavaScript("JSON.stringify = () => null;")

                let result = try await controller.renderStateForIPC()

                #expect(!result.diagnostics.evaluateSucceeded)
                #expect(result.diagnostics.pageErrorKinds == ["render_state_result_not_string"])
                #expect(result.diagnostics.productMetadataStream == nil)
                #expect(result.diagnostics.productSession.activeProducerCount == 0)
                #expect(result.diagnostics.productSession.nextMetadataStreamSequence == 0)
            }
        }

        @Test("IPC telemetry snapshot reports package status without exposing samples")
        func ipcTelemetrySnapshot_reportsPackageStatusWithoutExposingSamples() async throws {
            let worktreeId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: makeBridgeEndpoint(endpointId: "index", kind: .index),
                    headEndpoint: makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree),
                    changedFiles: [
                        makeBridgeEndpointChangedFile(
                            fileId: "source",
                            path: "Sources/App/View.swift",
                            sizeBytes: 100,
                            oldContentHash: bridgeSHA256ContentHash("old"),
                            newContentHash: bridgeSHA256ContentHash("new")
                        )
                    ]
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
            _ = try await controller.selectReviewItemForIPC(itemId: "item-source", correlationId: nil)

            let snapshot = try await controller.telemetrySnapshotForIPC()

            #expect(snapshot.paneId == controller.paneId)
            #expect(snapshot.kind == .unavailable)
            #expect(snapshot.unavailableReason == .disabled)
            #expect(snapshot.report == nil)
        }
    }
}

private func expectProductMetadataStreamDiagnostic(
    _ diagnostic: IPCBridgeProductMetadataStreamDiagnostic
) {
    #expect(diagnostic.kind == .productMetadataStream)
    #expect(diagnostic.acknowledgedFrameCount == 1)
    #expect(diagnostic.activeSubscriptionCount == 2)
    #expect(diagnostic.committedFrameCount == 1)
    #expect(diagnostic.decoderState == "poisoned")
    #expect(diagnostic.expectedNextStreamSequence == 1)
    #expect(diagnostic.failureCode == "stream_identity_mismatch")
    #expect(diagnostic.failureStage == "acknowledgement")
    #expect(diagnostic.identityMismatchField == "metadataStreamId")
    #expect(diagnostic.lastChunkByteCount == 256)
    #expect(diagnostic.lastAcknowledgedStreamSequence == 0)
    #expect(diagnostic.lastCommittedFrameKind == "metadataStream.accepted")
    #expect(diagnostic.lastRoutedFrameKind == "subscription.accepted")
    #expect(diagnostic.lifecycleState == "failed")
    #expect(diagnostic.peakRetainedByteCount == 512)
    #expect(diagnostic.pushCount == 2)
    #expect(diagnostic.readFulfilledCount == 3)
    #expect(diagnostic.readPending == false)
    #expect(diagnostic.readRequestCount == 4)
    #expect(diagnostic.receivedByteCount == 768)
    #expect(diagnostic.retainedByteCount == 0)
    #expect(diagnostic.routeFailureCode == "unknown_subscription")
    #expect(diagnostic.routedFrameCount == 2)
    #expect(diagnostic.streamOpenCount == 1)
}

@MainActor
private func installIPCContentDescriptorPackage(
    _ handle: BridgeContentHandle,
    in controller: BridgePaneController
) {
    let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
    let headEndpoint = makeBridgeEndpoint(endpointId: handle.endpointId, kind: .workingTree)
    let descriptor = makeBridgeReviewItemDescriptor(
        itemId: handle.itemId,
        path: "\(handle.itemId).swift",
        fileClass: .source,
        contentRoles: BridgeReviewItemDescriptor.ContentRoles(head: handle)
    )
    controller.paneState.diff.setPackageMetadata(
        BridgeReviewPackage(
            packageId: "ipc-content-descriptor-package",
            schemaVersion: 1,
            reviewGeneration: handle.reviewGeneration,
            revision: 0,
            query: makeBridgeReviewQuery(
                baseEndpointId: baseEndpoint.endpointId,
                headEndpointId: headEndpoint.endpointId
            ),
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            orderedItemIds: [handle.itemId],
            itemsById: [handle.itemId: descriptor],
            groups: [],
            summary: BridgeReviewPackageSummary(
                filesChanged: 1,
                additions: 0,
                deletions: 0,
                visibleFileCount: 1,
                hiddenFileCount: 0
            ),
            filterState: BridgeViewFilter(),
            generatedAtUnixMilliseconds: 1
        )
    )
}
