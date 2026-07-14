import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgeProductRealGitFileAndReviewWebKitTests {
        private struct LiveProof {
            let dom: BridgeProductWebKitCarrierDOMSnapshot
            let legacyEgress: BridgeProductWebKitCarrierLegacyEgressSnapshot
            let native: BridgeProductWebKitCarrierNativeSnapshot
            let sourceOracle: LiveSourceOracle
            let trace: BridgeProductWebKitCarrierTrace
        }

        private struct LiveSourceOracle {
            let canaryText: String
            let itemId: String
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
            let legacyEgressRecorder = BridgeProductWebKitCarrierLegacyEgressRecorder()
            let controller = makeController(
                repoURL: repoURL,
                traceRecorder: traceRecorder,
                legacyEgressRecorder: legacyEgressRecorder
            )

            // Act
            let run = try await collectLiveProof(
                controller: controller,
                sourceOracle: sourceOracle,
                traceRecorder: traceRecorder,
                legacyEgressRecorder: legacyEgressRecorder
            )

            // Assert
            assertProof(run)
        }

        private func makeController(
            repoURL: URL,
            traceRecorder: BridgeProductWebKitCarrierTraceRecorder,
            legacyEgressRecorder: BridgeProductWebKitCarrierLegacyEgressRecorder
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
                telemetryRecorder: traceRecorder,
                pushEnvelopeSink: { _, envelope, _ in
                    await legacyEgressRecorder.recordPush(byteCount: envelope.utf8.count)
                },
                preEncodedIntakeFrameSink: { _, frame in
                    await legacyEgressRecorder.recordIntake(
                        byteCount: frame.envelopeJSON.utf8.count
                    )
                }
            )
        }

        private func collectLiveProof(
            controller: BridgePaneController,
            sourceOracle: LiveSourceOracle,
            traceRecorder: BridgeProductWebKitCarrierTraceRecorder,
            legacyEgressRecorder: BridgeProductWebKitCarrierLegacyEgressRecorder
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
                    return dom?.hasReviewShell == true
                        && dom?.hasReviewCodeViewPanel == true
                        && dom?.reviewSelectedContentState == "ready"
                }

                return LiveProof(
                    dom: await BridgeProductWebKitCarrierTestSupport.domSnapshot(hostedController.page)
                        ?? .unavailable,
                    legacyEgress: await legacyEgressRecorder.snapshot(),
                    native: await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(hostedController),
                    sourceOracle: sourceOracle,
                    trace: await traceRecorder.scrubbedTrace()
                )
            }
        }

        private func assertProof(
            _ run: BridgeProductWebKitCarrierRunResult<LiveProof>
        ) {
            #expect(
                run.value.dom.hasAppRoot,
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
                run.value.dom.hasFileModeHost && run.value.dom.hasReviewModeHost,
                "W0 product seam: the canonical File+Review viewer hosts were not both constructed; dom=\(run.value.dom)"
            )
            #expect(
                run.value.dom.hasReviewShell,
                "W0 construction seam: Review metadata crossed the worker but no product Review shell mounted; dom=\(run.value.dom), legacyEgress=\(run.value.legacyEgress), trace=\(run.value.trace)"
            )
            #expect(
                run.value.dom.hasReviewCodeViewPanel
                    && run.value.dom.reviewSelectedContentState == "ready"
                    && run.value.dom.reviewSelectedContentLineCount > 0,
                "W0 content-observation seam: Swift emitted Review content, but the worker did not acknowledge and drain the concurrent content streams into a ready CodeView while both legacy page sinks were closed; dom=\(run.value.dom), legacyEgress=\(run.value.legacyEgress), native=\(run.value.native)"
            )
            #expect(
                run.value.dom.reviewSelectedDisplayPath == run.value.sourceOracle.path,
                "G0 PACKAGED SELECTED IDENTITY MISSING: selected Review path did not match the live-git oracle; selected=\(run.value.dom.reviewSelectedDisplayPath ?? "missing"), expected=\(run.value.sourceOracle.path)"
            )
            #expect(
                run.value.dom.reviewRenderedItemId == run.value.sourceOracle.itemId,
                "G0 PACKAGED SEMANTIC ITEM MISSING: rendered Review item did not match the live-git oracle; rendered=\(run.value.dom.reviewRenderedItemId ?? "missing"), expected=\(run.value.sourceOracle.itemId)"
            )
            assertPaintCorrelation(
                run.value.dom.correlations.first { correlation in
                    correlation.surface == "review"
                        && correlation.itemId == run.value.sourceOracle.itemId
                        && correlation.role == "head"
                },
                expectedSurface: "review",
                sourceOracle: run.value.sourceOracle
            )
            assertPaintCorrelation(
                run.value.dom.correlations.first { correlation in
                    correlation.surface == "file"
                        && correlation.itemId == run.value.sourceOracle.itemId
                },
                expectedSurface: "file",
                sourceOracle: run.value.sourceOracle
            )
            #expect(
                run.teardownSnapshot.hasZeroResidue,
                "W0 teardown seam: production product session retained transport residue; snapshot=\(run.teardownSnapshot)"
            )
        }

        private func assertPaintCorrelation(
            _ correlation: BridgeProductWebKitCarrierPaintCorrelation?,
            expectedSurface: String,
            sourceOracle: LiveSourceOracle
        ) {
            #expect(
                correlation != nil,
                "G0 PACKAGED SOURCE CORRELATION MISSING: \(expectedSurface) did not correlate selected item, descriptor, role, request, live-git bytes, readable DOM, and painted disposition"
            )
            guard let correlation else { return }
            #expect(correlation.surface == expectedSurface)
            #expect(correlation.semanticItemId == sourceOracle.itemId)
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
                itemId: "item-\(path)",
                path: path,
                sha256: SHA256.hash(data: sourceData)
                    .map { String(format: "%02x", $0) }
                    .joined()
            )
        }
    }
}
