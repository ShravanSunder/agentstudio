import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class AppPoliciesBridgeTests {
    @Test("Bridge content byte cache keeps per-item cap far below total capacity")
    func bridgeContentByteCacheKeepsPerItemCapBelowTotalCapacity() {
        #expect(AppPolicies.Bridge.contentMaxBytesPerItem == 4 * 1024 * 1024)
        #expect(AppPolicies.Bridge.contentCacheMaxBytes == 128 * 1024 * 1024)
        #expect(AppPolicies.Bridge.contentMaxBytesPerItem < AppPolicies.Bridge.contentCacheMaxBytes)
        #expect(
            AppPolicies.Bridge.contentCacheMaxBytes / AppPolicies.Bridge.contentMaxBytesPerItem
                >= 32
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
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [handle], reviewGeneration: 7)

        do {
            _ = try await store.load(handleId: handle.handleId, requestedGeneration: 7)
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
