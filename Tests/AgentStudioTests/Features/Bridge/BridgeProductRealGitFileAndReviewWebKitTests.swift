import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgeProductRealGitFileAndReviewWebKitTests {
        private struct LiveProof {
            let fileDOMAfterFileSwitch: BridgeProductWebKitCarrierDOMSnapshot
            let fileCorrelationObserved: Bool
            let fileModeActivated: Bool
            let filePathSelected: Bool
            let native: BridgeProductWebKitCarrierNativeSnapshot
            let reviewDOMBeforeFileSwitch: BridgeProductWebKitCarrierDOMSnapshot
            let sourceOracle: LiveSourceOracle
            let trace: BridgeProductWebKitCarrierTrace
        }

        private struct LiveSourceOracle {
            let canaryText: String
            let path: String
            let sha256: String
        }

        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("bundled comm worker carries real-git File and Review product data through production WebKit")
        func bundledWorkerCarriesRealGitFileAndReviewProductData() async throws {
            // Arrange
            let repoURL = try FilesystemTestGitRepo.create(named: "bridge-product-file-review-webkit")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repoURL)
            let sourceOracle = try makeSourceOracle(repoURL: repoURL)
            let traceRecorder = BridgeProductWebKitCarrierTraceRecorder()
            let controller = makeController(
                repoURL: repoURL,
                traceRecorder: traceRecorder
            )

            // Act
            let run = try await collectLiveProof(
                controller: controller,
                sourceOracle: sourceOracle,
                traceRecorder: traceRecorder
            )

            // Assert
            assertProof(run)
        }

        private func makeController(
            repoURL: URL,
            traceRecorder: BridgeProductWebKitCarrierTraceRecorder
        ) -> BridgePaneController {
            let paneId = UUIDv7.generate()
            return BridgePaneController(
                paneId: paneId,
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(
                        rootPath: repoURL.path,
                        baseline: .localDefaultBranch(branchName: "main")
                    )
                ),
                metadata: PaneMetadata(
                    paneId: PaneId(uuid: paneId),
                    contentType: .diff,
                    launchDirectory: repoURL,
                    title: "Bridge Product Carrier",
                    facets: PaneContextFacets(
                        repoId: UUIDv7.generate(),
                        worktreeId: UUIDv7.generate(),
                        worktreeName: "bridge-product-carrier",
                        cwd: repoURL
                    )
                ),
                reviewSourceProvider: BridgeReviewSourceProviderFactory.gitProvider(
                    repositoryPath: repoURL
                ),
                telemetryRuntimePolicy: .live,
                telemetryScopeGate: BridgeTelemetryScopeGate(enabledScopes: []),
                telemetryRecorder: traceRecorder
            )
        }

        private func collectLiveProof(
            controller: BridgePaneController,
            sourceOracle: LiveSourceOracle,
            traceRecorder: BridgeProductWebKitCarrierTraceRecorder
        ) async throws -> BridgeProductWebKitCarrierRunResult<LiveProof> {
            try await BridgeProductWebKitCarrierTestSupport.withHostedController(controller) { hostedController in
                hostedController.loadApp()

                _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
                    let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(
                        hostedController.page
                    )
                    let native = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(
                        hostedController
                    )
                    return dom?.hasAppRoot == true && native.lifecycle == "active"
                }
                _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
                    let trace = await traceRecorder.scrubbedTrace()
                    return trace.hasCanonicalEagerSubscriptions
                        && trace.hasFileMetadataWindow
                        && trace.hasReviewMetadataPublication
                }
                _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
                    let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(
                        hostedController.page
                    )
                    guard let dom, let reviewRenderedItemId = dom.reviewRenderedItemId else {
                        return false
                    }
                    return dom.hasReviewShell
                        && dom.hasReviewCodeViewPanel
                        && dom.reviewSelectedContentState == "ready"
                        && dom.correlations.contains { correlation in
                            correlation.surface == "review"
                                && correlation.semanticItemId == reviewRenderedItemId
                                && correlation.role == "head"
                                && correlation.observedSHA256 == sourceOracle.sha256
                                && correlation.disposition == "painted"
                                && correlation.readableText.contains(sourceOracle.canaryText)
                        }
                }
                let reviewDOMBeforeFileSwitch =
                    await BridgeProductWebKitCarrierTestSupport.domSnapshot(
                        hostedController.page
                    ) ?? .unavailable
                let fileModeActivated = await BridgeProductWebKitCarrierTestSupport.activateFileMode(
                    hostedController.page
                )
                let filePathSelected: Bool
                if fileModeActivated {
                    filePathSelected = await BridgeProductWebKitCarrierTestSupport.waitUntil(
                        timeout: .seconds(15)
                    ) {
                        await BridgeProductWebKitCarrierTestSupport.selectFilePath(
                            hostedController.page,
                            path: sourceOracle.path
                        )
                    }
                } else {
                    filePathSelected = false
                }
                let fileCorrelationObserved = await BridgeProductWebKitCarrierTestSupport.waitUntil(
                    timeout: .seconds(15)
                ) {
                    let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(
                        hostedController.page
                    )
                    return dom?.correlations.contains { correlation in
                        correlation.surface == "file"
                            && correlation.role == "file"
                            && correlation.observedSHA256 == sourceOracle.sha256
                            && correlation.readableText.contains(sourceOracle.canaryText)
                    } == true
                }
                let fileDOMAfterFileSwitch =
                    await BridgeProductWebKitCarrierTestSupport.domSnapshot(
                        hostedController.page
                    ) ?? .unavailable

                return LiveProof(
                    fileDOMAfterFileSwitch: fileDOMAfterFileSwitch,
                    fileCorrelationObserved: fileCorrelationObserved,
                    fileModeActivated: fileModeActivated,
                    filePathSelected: filePathSelected,
                    native: await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(hostedController),
                    reviewDOMBeforeFileSwitch: reviewDOMBeforeFileSwitch,
                    sourceOracle: sourceOracle,
                    trace: await traceRecorder.scrubbedTrace()
                )
            }
        }

        private func assertProof(
            _ run: BridgeProductWebKitCarrierRunResult<LiveProof>
        ) {
            let fileDOM = run.value.fileDOMAfterFileSwitch
            let reviewDOM = run.value.reviewDOMBeforeFileSwitch
            assertPackagedFrameLiveness(reviewDOM, fileDOM: fileDOM, host: run.hostSnapshot)
            #expect(
                reviewDOM.hasAppRoot && fileDOM.hasAppRoot,
                "W0 product seam: the current bundled BridgeWeb app did not mount"
            )
            #expect(
                run.value.native.lifecycle == "active",
                "W0 product seam: the bundled worker did not open the production product session; native=\(run.value.native)"
            )
            #expect(
                run.value.trace.hasCanonicalEagerSubscriptions,
                "W0 product seam: the worker did not open canonical eager File+Review subscriptions; trace=\(run.value.trace)"
            )
            #expect(
                run.value.trace.hasFileMetadataWindow,
                "W0 product seam: production agentstudio-git File metadata did not reach the worker stream; trace=\(run.value.trace)"
            )
            #expect(
                run.value.trace.hasReviewMetadataPublication,
                "W0 product seam: production agentstudio-git Review metadata did not reach the worker stream; trace=\(run.value.trace)"
            )
            #expect(
                run.value.native.nextControlRequestSequence > 1,
                "W0 product seam: worker-initiated product command POSTs were not acknowledged; native=\(run.value.native)"
            )
            #expect(
                run.value.native.nextMetadataStreamSequence > 1,
                "W0 product seam: streamed metadata frames and bodyless observations did not advance; native=\(run.value.native)"
            )
            #expect(
                run.value.native.inFlightControlRequestSequence == nil,
                "W0 product seam: a product command remained in flight; native=\(run.value.native)"
            )
            #expect(
                reviewDOM.hasReviewModeHost && fileDOM.hasFileModeHost,
                "W0 product seam: the canonical File+Review viewer hosts were not both constructed; reviewDOM=\(reviewDOM), fileDOM=\(fileDOM)"
            )
            #expect(
                reviewDOM.hasReviewShell,
                "W0 construction seam: Review metadata crossed the worker but no product Review shell mounted; reviewDOM=\(reviewDOM), trace=\(run.value.trace)"
            )
            #expect(
                reviewDOM.hasReviewCodeViewPanel
                    && reviewDOM.reviewSelectedContentState == "ready"
                    && reviewDOM.reviewSelectedContentLineCount > 0,
                "W0 content-observation seam: Swift emitted Review content, but the worker did not acknowledge and drain the concurrent content streams into a ready CodeView; reviewDOM=\(reviewDOM), native=\(run.value.native)"
            )
            #expect(
                reviewDOM.reviewSelectedDisplayPath == run.value.sourceOracle.path,
                "G0 PACKAGED SELECTED IDENTITY MISSING: selected Review path did not match the live-git oracle; selected=\(reviewDOM.reviewSelectedDisplayPath ?? "missing"), expected=\(run.value.sourceOracle.path)"
            )
            #expect(
                reviewDOM.reviewRenderedItemId?.isEmpty == false,
                "G0 PACKAGED SEMANTIC ITEM MISSING: rendered Review item did not retain its canonical semantic identity"
            )
            assertPaintCorrelation(
                reviewDOM.correlations.first { correlation in
                    correlation.surface == "review"
                        && correlation.semanticItemId == reviewDOM.reviewRenderedItemId
                        && correlation.role == "head"
                },
                expectedSemanticItemId: reviewDOM.reviewRenderedItemId,
                expectedSurface: "review",
                sourceOracle: run.value.sourceOracle
            )
            #expect(
                run.value.fileModeActivated,
                "G0 PACKAGED FILE MODE MISSING: the real bundled File control was not available"
            )
            #expect(
                run.value.filePathSelected,
                "G0 PACKAGED FILE SELECTION MISSING: File mode did not select the live-git source through the real tree"
            )
            #expect(
                run.value.fileCorrelationObserved,
                "G0 PACKAGED FILE PAINT MISSING: File mode never painted the independently read live-git source"
            )
            assertPaintCorrelation(
                fileDOM.correlations.first { correlation in
                    correlation.surface == "file"
                        && correlation.role == "file"
                        && correlation.observedSHA256 == run.value.sourceOracle.sha256
                },
                expectedSemanticItemId: nil,
                expectedSurface: "file",
                sourceOracle: run.value.sourceOracle
            )
            #expect(
                run.teardownSnapshot.hasZeroResidue,
                "W0 teardown seam: production product session retained transport residue; snapshot=\(run.teardownSnapshot)"
            )
        }

        private func assertPackagedFrameLiveness(
            _ reviewDOM: BridgeProductWebKitCarrierDOMSnapshot,
            fileDOM: BridgeProductWebKitCarrierDOMSnapshot,
            host: BridgeProductWebKitCarrierHostSnapshot
        ) {
            #expect(reviewDOM.documentVisibilityState == "visible", "host=\(host)")
            #expect(fileDOM.documentVisibilityState == "visible", "host=\(host)")
            #expect(reviewDOM.frameLivenessRafAlive == "true", "host=\(host)")
            #expect(reviewDOM.frameLivenessRafFiredCount > 0, "host=\(host)")
            #expect(reviewDOM.frameLivenessRafScheduledCount > 0, "host=\(host)")
        }

        private func assertPaintCorrelation(
            _ correlation: BridgeProductWebKitCarrierPaintCorrelation?,
            expectedSemanticItemId: String?,
            expectedSurface: String,
            sourceOracle: LiveSourceOracle
        ) {
            #expect(
                correlation != nil,
                "G0 PACKAGED SOURCE CORRELATION MISSING: \(expectedSurface) did not correlate selected item, descriptor, role, request, live-git bytes, readable DOM, and painted disposition"
            )
            guard let correlation else { return }
            #expect(correlation.surface == expectedSurface)
            #expect(correlation.itemId == correlation.semanticItemId)
            #expect(!correlation.pierreItemId.isEmpty)
            #expect(!correlation.publicationId.isEmpty)
            if let expectedSemanticItemId {
                #expect(correlation.semanticItemId == expectedSemanticItemId)
            }
            #expect(!correlation.descriptorId.isEmpty)
            #expect(!correlation.requestId.isEmpty)
            #expect(!correlation.sourceIdentity.isEmpty)
            #expect(correlation.sourceGeneration >= 0)
            #expect(correlation.observedSHA256 == sourceOracle.sha256)
            #expect(correlation.disposition == "painted")
            #expect(!correlation.readableDOMSelector.isEmpty)
            #expect(
                correlation.readableText.contains(sourceOracle.canaryText),
                "G0 PACKAGED READABLE SOURCE MISSING: \(expectedSurface) readable DOM did not contain the independently read live-git canary"
            )
        }

        private func makeSourceOracle(repoURL: URL) throws -> LiveSourceOracle {
            let path = "tracked.txt"
            let sourceData = try Data(contentsOf: repoURL.appending(path: path))
            return LiveSourceOracle(
                canaryText: "updated",
                path: path,
                sha256: SHA256.hash(data: sourceData)
                    .map { String(format: "%02x", $0) }
                    .joined()
            )
        }
    }
}
