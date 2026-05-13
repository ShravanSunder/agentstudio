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
            var config = WebPageTestHarness.makeConfiguration()
            let scheme = try #require(URLScheme("agentstudio-isolation"))
            config.urlSchemeHandlers[scheme] = ContentWorldIsolationBlankPageSchemeHandler()

            let messageHandler = RPCMessageHandler()
            config.userContentController.add(
                messageHandler,
                contentWorld: bridgeWorld,
                name: "rpc"
            )

            let bootstrapScript = WKUserScript(
                source: BridgeBootstrap.generateScript(bridgeNonce: UUID().uuidString, pushNonce: UUID().uuidString),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: bridgeWorld
            )
            config.userContentController.addUserScript(bootstrapScript)
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
                _ = page.load(URL(string: "agentstudio-isolation://app/blank.html")!)
                try await waitForPageLoad(page)

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

        private func waitForPageLoad(_ page: WebPage, timeout: Duration = .seconds(5)) async throws {
            for _ in 0..<50_000 {
                if !page.isLoading { break }
                await Task.yield()
            }
            try #require(!page.isLoading, "Page did not finish loading within \(timeout)")
            await settleAsyncCallbacks(turns: 40)
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

        private func settleAsyncCallbacks(turns: Int) async {
            for _ in 0..<turns {
                await Task.yield()
            }
        }
    }
}

private struct ContentWorldIsolationBlankPageSchemeHandler: URLSchemeHandler {
    func reply(for request: URLRequest) -> some AsyncSequence<URLSchemeTaskResult, any Error> {
        AsyncThrowingStream<URLSchemeTaskResult, any Error> { continuation in
            let html = "<html><head><title>Bridge Isolation</title></head><body></body></html>"
            let data = Data(html.utf8)
            guard let url = request.url else {
                continuation.finish()
                return
            }
            continuation.yield(
                .response(
                    URLResponse(
                        url: url,
                        mimeType: "text/html",
                        expectedContentLength: data.count,
                        textEncodingName: "utf-8"
                    )))
            continuation.yield(.data(data))
            continuation.finish()
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
