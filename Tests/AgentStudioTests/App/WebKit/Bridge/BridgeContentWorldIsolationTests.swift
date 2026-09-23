import Foundation
import Testing
import WebKit

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    final class BridgeContentWorldIsolationTests {
        init() {
            installTestCoreAtomsIfNeeded()
        }

        @Test
        func test_contentWorldIsolationAndReadyBootstrapOnlyScriptMessageRPC() async throws {
            let bridgeWorld = WKContentWorld.world(name: "agentStudioBridgeProtocolRPCTest")
            let pageProbe = WebKitScriptMessageRecorder()
            let rpcRecorder = WebKitScriptMessageRecorder()
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
                await waitForPageLoad(page)

                _ = try await page.callJavaScript(
                    BridgeBootstrap.generateScript(),
                    contentWorld: bridgeWorld
                )

                _ = try await page.callJavaScript(
                    "window.webkit.messageHandlers.pageProbe.postMessage(typeof window.__bridgeInternal)"
                )
                await pageProbe.waitForMessages(atLeast: 1)
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
                // Read once, unbarriered. This can only fail if a forbidden command
                // reached Swift, which is a real product failure at any speed. The
                // claim that it NEVER arrives is carried by the ordered assertion
                // below: `bridge.ready` is dispatched last, and once it has been
                // delivered anything dispatched before it would already be here.
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
                #expect(rpcRecorder.receivedMessages.isEmpty)

                _ = try await page.callJavaScript(
                    """
                    document.dispatchEvent(new CustomEvent('__bridge_ready', {
                      detail: { requestId: 'bridge-ready-test' }
                    }));
                    """
                )

                await rpcRecorder.waitForMessages(atLeast: 1)
                #expect(rpcRecorder.receivedMessages.count == 1)
                #expect((rpcRecorder.receivedMessages.first as? String)?.contains("bridge.ready") == true)
                #expect((rpcRecorder.receivedMessages.first as? String)?.contains("bridge-ready-test") == true)
                #expect((rpcRecorder.receivedMessages.first as? String)?.contains("bridge-protocol-rpc") != true)
            }
        }

        private func waitForPageLoad(_ page: WebPage) async {
            await WebPageEventWaits.waitForNavigationToFinish(page)
        }
    }
}
