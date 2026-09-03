import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite(.serialized)
final class AppPoliciesBridgeTests {
    @Test("Bridge lifecycle diagnostics use a bounded observability-only window")
    func bridgeLifecycleDiagnosticsUseBoundedPolicy() {
        #expect(AppPolicies.Bridge.operationLifecycleTerminalWindow == .seconds(30))
        #expect(AppPolicies.Bridge.operationLifecycleMaximumTrackedStageAttempts == 4096)
    }

    @Test("Review refresh impact work has explicit Git traversal and blob limits")
    func reviewRefreshImpactWorkUsesBoundedPolicy() {
        #expect(AppPolicies.Bridge.reviewRefreshImpactMaximumCommitTraversalCount == 256)
        #expect(AppPolicies.Bridge.reviewRefreshImpactMaximumDiffableBlobByteCount == 1 * 1024 * 1024)
    }

    @Test("Worktree annotation continuity uses explicit bounded Git evidence policy")
    func worktreeAnnotationContinuityUsesBoundedGitEvidencePolicy() {
        #expect(AppPolicies.Bridge.worktreeAnnotationContinuityMaximumCommitCount == 10)
        #expect(AppPolicies.Bridge.worktreeAnnotationContinuityMaximumTraversalCount == 256)
    }

    @Test("Bridge content byte cache uses the approved 16 MiB per-item safety cap")
    func bridgeContentByteCacheUsesApprovedPerItemSafetyCap() {
        #expect(AppPolicies.Bridge.contentMaxBytesPerItem == 16 * 1024 * 1024)
        #expect(AppPolicies.Bridge.contentCacheMaxBytes == 128 * 1024 * 1024)
        #expect(AppPolicies.Bridge.contentMaxBytesPerItem < AppPolicies.Bridge.contentCacheMaxBytes)
        #expect(
            AppPolicies.Bridge.contentCacheMaxBytes / AppPolicies.Bridge.contentMaxBytesPerItem
                >= 8
        )
    }

    @Test("Bridge content store rejects one byte over the AppPolicies per-item cap")
    func bridgeContentStoreRejectsOneByteOverPolicyPerItemCap() async throws {
        let oversizedByteCount = AppPolicies.Bridge.contentMaxBytesPerItem + 1
        let oversizedBody = String(repeating: "a", count: oversizedByteCount)
        let handle = makeBridgeContentHandle(
            itemId: "item-oversized",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash(oversizedBody),
            sizeBytes: oversizedByteCount
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: oversizedBody)
            ]
        )
        let loaderCache = BridgeReviewContentLoaderCache(provider: provider)
        let productAdmission = try BridgeProductAdmissionTestContext.make()

        do {
            _ = try await loaderCache.load(
                handle: handle,
                productAdmission: productAdmission.context
            )
            Issue.record("Expected oversized content failure")
        } catch let failure as BridgeProviderFailure {
            #expect(
                failure
                    == .oversizedContent(
                        handleId: handle.handleId,
                        sizeBytes: oversizedByteCount
                    )
            )
        } catch {
            Issue.record("Expected BridgeProviderFailure, got \(error)")
        }
    }

    @Test("Bridge apply pump policy matches BridgeWeb mirror")
    func bridgeApplyPumpPolicyMatchesBridgeWebMirror() throws {
        let mirrorSource = try String(
            contentsOfFile: "BridgeWeb/src/core/demand/bridge-content-demand-policy.ts",
            encoding: .utf8
        )
        let normalizedMirrorSource = mirrorSource.replacingOccurrences(of: "_", with: "")

        #expect(
            normalizedMirrorSource
                .contains(
                    "applyPumpFrameBudgetMilliseconds: \(AppPolicies.Bridge.applyPumpFrameBudgetMilliseconds)"
                )
        )
        #expect(
            normalizedMirrorSource
                .contains(
                    "applyPumpMaxUnitsPerFrame: \(AppPolicies.Bridge.applyPumpMaxUnitsPerFrame)"
                )
        )
        #expect(
            normalizedMirrorSource
                .contains(
                    "applyPumpStaleScanLimit: \(AppPolicies.Bridge.applyPumpStaleScanLimit)"
                )
        )
        #expect(
            normalizedMirrorSource
                .contains(
                    "applyPumpNoStarvationSelectedBatchLimit: \(AppPolicies.Bridge.applyPumpNoStarvationSelectedBatchLimit)"
                )
        )
        #expect(
            normalizedMirrorSource
                .contains(
                    "selectedApplyInitialWindowLineCount: \(AppPolicies.Bridge.selectedApplyInitialWindowLineCount)"
                )
        )
    }
}
