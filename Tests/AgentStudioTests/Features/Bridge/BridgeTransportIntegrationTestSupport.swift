import Foundation
import Testing
import WebKit

@testable import AgentStudio

@MainActor
func describeBridgePageState(_ page: WebPage) async -> String {
    do {
        let result = try await page.callJavaScript(
            """
            return JSON.stringify({
              title: document.title,
              hasAppRoot: document.querySelector('[data-testid="bridge-app-root"]') !== null,
              hasEmptyShell: document.querySelector('[data-testid="bridge-review-empty-shell"]') !== null,
              hasReviewShell: document.querySelector('[data-testid="review-viewer-shell"]') !== null,
              bridgeInternalType: typeof window.__bridgeInternal,
              pushProbe: window.__bridgePushProbe ?? [],
              errorProbe: window.__bridgeErrorProbe ?? [],
              text: document.body.innerText.slice(0, 240)
            })
            """
        )
        return (result as? String) ?? String(describing: result)
    } catch {
        return "page-state-error=\(String(describing: error))"
    }
}

@MainActor
func registerContentHandleLeases(
    controller: BridgePaneController,
    paneId: UUID,
    handles: [BridgeContentHandle]
) async throws {
    for handle in handles {
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                handle.resourceUrl,
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))
        await controller.resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            descriptorId: resource.opaqueId,
            maxBytes: handle.sizeBytes,
            expectedRevocationRevision: 0
        )
    }
}

@MainActor
func makeRealDiffContentHandles() -> (
    base: BridgeContentHandle,
    head: BridgeContentHandle
) {
    (
        base: makeBridgeContentHandle(
            itemId: "item-real-diff",
            role: .base,
            endpointId: "transport-base",
            reviewGeneration: BridgeReviewGeneration(7),
            contentHash: bridgeSHA256ContentHash("base content"),
            sizeBytes: 12
        ),
        head: makeBridgeContentHandle(
            itemId: "item-real-diff",
            role: .head,
            endpointId: "transport-head",
            reviewGeneration: BridgeReviewGeneration(7),
            contentHash: bridgeSHA256ContentHash("head content"),
            sizeBytes: 12
        )
    )
}
