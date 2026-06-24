import Foundation
import Testing
import WebKit

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    final class BridgeTransportPushBoundaryTests {
        private let bridgeContentWorld = WKContentWorld.world(name: "agentStudioBridge")

        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test
        func test_pushJSON_deliversThroughBridgeWorldInternalAPI() async throws {
            let paneId = UUIDv7.generate()
            let state = BridgePaneState(panelKind: .diffViewer, source: nil)
            let controller = BridgePaneController(paneId: paneId, state: state)
            defer { controller.teardown() }

            try await WebPageTestHarness.withManagedPage(controller.page) { page in
                controller.loadApp()
                try await waitForPageLoad(page)

                let didCompleteBridgeReadyHandshake = await waitUntil {
                    controller.isBridgeReady
                }
                try #require(didCompleteBridgeReadyHandshake, "Bridge app did not complete ready handshake")

                try await installBridgeInternalPushProbe(page)
                controller.paneState.diff.setStatus(.loading)

                let didReceivePushThroughBridgeWorld = await waitUntil {
                    await self.bridgeInternalPushProbeDidReceive(page)
                }
                let pageState = await describeBridgePageState(page)
                #expect(
                    didReceivePushThroughBridgeWorld,
                    "Expected Swift push delivery to call bridge-world __bridgeInternal.applyEnvelopeJSON: \(pageState)"
                )
            }
        }

        private func waitForPageLoad(_ page: WebPage, timeout: Duration = .seconds(2)) async throws {
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                if !page.isLoading { break }
                await Task.yield()
            }
            try #require(!page.isLoading, "Page did not finish loading within \(timeout)")
            await settleAsyncCallbacks(turns: 40)
        }

        private func waitUntil(
            timeout: Duration = .seconds(2),
            _ condition: @escaping () async -> Bool
        ) async -> Bool {
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                if await condition() {
                    return true
                }
                await Task.yield()
            }
            return await condition()
        }

        private func settleAsyncCallbacks(turns: Int) async {
            for _ in 0..<turns {
                await Task.yield()
            }
        }

        private func installBridgeInternalPushProbe(_ page: WebPage) async throws {
            _ = try await page.callJavaScript(
                """
                window.__bridgeInternalPushProbe = { didReceive: false };
                const originalApplyEnvelopeJSON = window.__bridgeInternal.applyEnvelopeJSON;
                window.__bridgeInternal.applyEnvelopeJSON = function(envelopeJSON) {
                  window.__bridgeInternalPushProbe.didReceive = true;
                  originalApplyEnvelopeJSON.call(window.__bridgeInternal, envelopeJSON);
                };
                """,
                contentWorld: bridgeContentWorld
            )
        }

        private func bridgeInternalPushProbeDidReceive(_ page: WebPage) async -> Bool {
            do {
                let result = try await page.callJavaScript(
                    """
                    return window.__bridgeInternalPushProbe?.didReceive === true
                    """,
                    contentWorld: bridgeContentWorld
                )
                return (result as? Bool) == true
            } catch {
                return false
            }
        }

        private func describeBridgePageState(_ page: WebPage) async -> String {
            do {
                let result = try await page.callJavaScript(
                    """
                    return JSON.stringify({
                      title: document.title,
                      hasAppRoot: document.querySelector('[data-testid="bridge-app-root"]') !== null,
                      hasEmptyShell: document.querySelector('[data-testid="bridge-review-empty-shell"]') !== null,
                      hasReviewShell: document.querySelector('[data-testid="review-viewer-shell"]') !== null,
                      bridgeInternalType: typeof window.__bridgeInternal
                    })
                    """
                )
                return (result as? String) ?? String(describing: result)
            } catch {
                return String(describing: error)
            }
        }
    }
}
