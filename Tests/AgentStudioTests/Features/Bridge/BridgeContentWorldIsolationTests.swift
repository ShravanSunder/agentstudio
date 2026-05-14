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
        func test_pageWorld_cannotAccessBridgeInternal() async throws {
            let bridgeWorld = WKContentWorld.world(name: "agentStudioBridgeIsolationTest")
            let pageProbe = ContentWorldIsolationMessageHandler()
            let config = WebPageTestHarness.makeConfiguration()

            let messageHandler = RPCMessageHandler()
            config.userContentController.add(
                messageHandler,
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
                _ = try await page.callJavaScript(
                    BridgeBootstrap.generateScript(bridgeNonce: UUID().uuidString, pushNonce: UUID().uuidString),
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
