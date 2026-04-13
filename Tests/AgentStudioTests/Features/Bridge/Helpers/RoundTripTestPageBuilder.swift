import Foundation
import Testing
import WebKit

@testable import AgentStudio

/// Assembles a fully-wired WebPage for round-trip integration tests.
///
/// Replicates the same setup as `BridgePaneController` (bridge world: RPCMessageHandler +
/// BridgeBootstrap; scheme handler: BridgeSchemeHandler) but adds a page-world test probe
/// (`testProbe` message handler + `BridgeTestHarness` script) for capturing events.
///
/// This follows the pattern from `BridgeTransportIntegrationTests.test_pageWorld_cannotAccessBridgeInternal`
/// where a parallel setup is built because `WebPage` does not expose its configuration post-creation.
@MainActor
enum RoundTripTestPageBuilder {

    /// The assembled components for a round-trip test.
    struct Components {
        let page: WebPage
        let router: RPCRouter
        let messageHandler: RPCMessageHandler
        let testProbe: IntegrationTestMessageHandler
        let bridgeNonce: String
        let pushNonce: String
        let bridgeWorld: WKContentWorld

        /// Tracks whether the bridge.ready handshake has been received.
        /// Tests set this after dispatching bridge.ready to gate push plans.
        var isBridgeReady = false
    }

    /// Build a fully-wired WebPage with both bridge world and page-world test harness.
    ///
    /// - Parameter fileProvider: Optional file provider for the scheme handler's resource route.
    /// - Returns: Assembled components ready for testing.
    static func build(fileProvider: (any BridgeFileProvider)? = nil) -> Components {
        let bridgeWorld = WKContentWorld.world(name: "agentStudioBridge")
        let bridgeNonce = UUID().uuidString
        let pushNonce = UUID().uuidString

        var config = WebPageTestHarness.makeConfiguration()

        // Bridge world: message handler (same as BridgePaneController)
        let messageHandler = RPCMessageHandler()
        config.userContentController.add(
            messageHandler,
            contentWorld: bridgeWorld,
            name: "rpc"
        )

        // Bridge world: bootstrap script (same as BridgePaneController)
        let bootstrapScript = WKUserScript(
            source: BridgeBootstrap.generateScript(bridgeNonce: bridgeNonce, pushNonce: pushNonce),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: bridgeWorld
        )
        config.userContentController.addUserScript(bootstrapScript)

        // Page world: test harness script (captures bridge events, sends commands)
        let testHarnessScript = WKUserScript(
            source: BridgeTestHarness.generateScript(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
            // No content world parameter → page world (default)
        )
        config.userContentController.addUserScript(testHarnessScript)

        // Page world: test probe message handler (captures postMessage calls from harness)
        let testProbe = IntegrationTestMessageHandler()
        config.userContentController.add(testProbe, contentWorld: .page, name: "testProbe")

        // Scheme handler (same as BridgePaneController, optionally with file provider)
        var schemeHandler = BridgeSchemeHandler(paneId: UUID())
        schemeHandler.fileProvider = fileProvider
        if let scheme = URLScheme("agentstudio") {
            config.urlSchemeHandlers[scheme] = schemeHandler
        }

        // Create page with bridge policies
        let page = WebPage(
            configuration: config,
            navigationDecider: BridgeNavigationDecider(),
            dialogPresenter: WebviewDialogHandler()
        )

        // Wire router
        let router = RPCRouter()

        // Build the components struct first so the closure can capture it.
        // isBridgeReady starts false; tests set it true after handshake.
        var components = Components(
            page: page,
            router: router,
            messageHandler: messageHandler,
            testProbe: testProbe,
            bridgeNonce: bridgeNonce,
            pushNonce: pushNonce,
            bridgeWorld: bridgeWorld
        )

        // Wire message handler → router with isBridgeReady gating.
        // The closure captures `components` by reference via the returned struct.
        // For round-trip tests, we always pass isBridgeReady=true because the
        // bootstrap handles the ready gate — by the time page-world JS sends
        // commands, the bridge is always ready.
        messageHandler.onValidJSON = { json in
            await router.dispatch(json: json, isBridgeReady: true)
        }

        return components
    }
}
