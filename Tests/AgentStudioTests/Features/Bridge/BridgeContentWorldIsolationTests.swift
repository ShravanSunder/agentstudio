import Foundation
import Testing
import WebKit

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    final class BridgeContentWorldIsolationTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test
        func test_contentWorldIsolationAndReadyBootstrapOnlyScriptMessageRPC() async throws {
            let bridgeWorld = WKContentWorld.world(name: "agentStudioBridgeProtocolRPCTest")
            let pageProbe = ContentWorldIsolationMessageHandler()
            let rpcRecorder = ContentWorldIsolationMessageHandler()
            let config = WebPageTestHarness.makeConfiguration()

            config.userContentController.add(
                rpcRecorder,
                contentWorld: bridgeWorld,
                name: "rpc"
            )
            config.userContentController.add(pageProbe, contentWorld: .page, name: "pageProbe")
            defer {
                config.userContentController.removeScriptMessageHandler(forName: "rpc", contentWorld: bridgeWorld)
                config.userContentController.removeScriptMessageHandler(forName: "pageProbe", contentWorld: .page)
                config.userContentController.removeAllUserScripts()
            }

            try await WebPageTestHarness.withManagedPage(
                WebPage(
                    configuration: config,
                    navigationDecider: BridgeNavigationDecider(),
                    dialogPresenter: WebviewDialogHandler()
                )
            ) { page in
                _ = page.load(URL(string: "about:blank")!)
                try await waitForPageLoad(page)

                _ = try await page.callJavaScript(
                    BridgeBootstrap.generateScript(bridgeNonce: "bridge-nonce", pushNonce: "push-nonce"),
                    contentWorld: bridgeWorld
                )

                _ = try await page.callJavaScript(
                    "window.webkit.messageHandlers.pageProbe.postMessage(typeof window.__bridgeInternal)"
                )
                let sawProbeMessage = await waitForMessageCount(pageProbe, atLeast: 1)
                #expect(sawProbeMessage, "Expected page-world probe callback")
                #expect(pageProbe.receivedMessages.count == 1, "Page world probe should receive exactly one message")
                #expect(
                    pageProbe.receivedMessages.first as? String == "undefined",
                    "window.__bridgeInternal should be 'undefined' in page world")

                _ = try await page.callJavaScript(
                    """
                    document.dispatchEvent(new CustomEvent('__bridge_command', {
                      detail: {
                        jsonrpc: '2.0',
                        id: 'page-protocol-rpc',
                        protocol: 'review',
                        method: 'stream.open',
                        params: {},
                        __nonce: 'bridge-nonce'
                      }
                    }));
                    """
                )
                await settleAsyncCallbacks(turns: 20)
                #expect(rpcRecorder.receivedMessages.isEmpty)

                _ = try await page.callJavaScript(
                    """
                    document.dispatchEvent(new CustomEvent('__bridge_command', {
                      detail: {
                        jsonrpc: '2.0',
                        id: 'page-method-only-open-stream',
                        method: 'review.openStream',
                        params: {},
                        __nonce: 'bridge-nonce'
                      }
                    }));
                    """
                )
                await settleAsyncCallbacks(turns: 20)
                #expect(rpcRecorder.receivedMessages.isEmpty)

                _ = try await page.callJavaScript(
                    """
                    document.dispatchEvent(new CustomEvent('__bridge_ready', {
                      detail: { requestId: 'bridge-ready-test' }
                    }));
                    """
                )

                let didReceiveBridgeReadyRPC = await waitForMessageCount(rpcRecorder, atLeast: 1)
                #expect(didReceiveBridgeReadyRPC, "Expected one-shot bridge.ready bootstrap to reach Swift")
                #expect(rpcRecorder.receivedMessages.count == 1)
                #expect((rpcRecorder.receivedMessages.first as? String)?.contains("bridge.ready") == true)
                #expect((rpcRecorder.receivedMessages.first as? String)?.contains("bridge-ready-test") == true)
                #expect((rpcRecorder.receivedMessages.first as? String)?.contains("bridge-protocol-rpc") != true)
            }
        }

        private func waitForMessageCount(
            _ handler: ContentWorldIsolationMessageHandler,
            atLeast expectedCount: Int
        ) async -> Bool {
            for _ in 0..<200_000 {
                if handler.receivedMessages.count >= expectedCount {
                    return true
                }
                await Task.yield()
            }
            return handler.receivedMessages.count >= expectedCount
        }

        private func waitForPageLoad(_ page: WebPage, timeout: Duration = .seconds(2)) async throws {
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                if !page.isLoading {
                    break
                }
                await Task.yield()
            }
            try #require(!page.isLoading, "Page did not finish loading within \(timeout)")
            await settleAsyncCallbacks(turns: 40)
        }

        private func settleAsyncCallbacks(turns: Int) async {
            for _ in 0..<turns {
                await Task.yield()
            }
        }
    }
}

final class ContentWorldIsolationMessageHandler: NSObject, WKScriptMessageHandler {
    private let lock = NSLock()
    nonisolated(unsafe) private var storage: [Any] = []

    var receivedMessages: [Any] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        lock.lock()
        storage.append(message.body)
        lock.unlock()
    }
}
