import AgentStudioCore
import Foundation
import WebKit

struct BridgeBootstrapScriptInput {
    let reviewPaneId: String
    let reviewStreamId: String
    let panelKind: BridgePanelKind
    let telemetryConfig: BridgeTelemetryBootstrapConfig?
    let bridgeWorld: WKContentWorld
}

struct BridgeBootstrapArtifacts {
    let script: WKUserScript
}

struct BridgeSchemeHandlerRegistrationInput {
    let paneId: UUID
    let appRootURL: URL
    let telemetrySessionOwner: BridgePaneTelemetrySessionOwner?
    let productSessionRouter: BridgeProductSchemeSessionRouter
}

package struct BridgePaneTelemetrySessionDependencies: Sendable {
    let installation: BridgeTelemetrySessionInstallation
    let owner: BridgePaneTelemetrySessionOwner
}

package struct BridgePaneProductSessionDependencies {
    let installation: BridgeProductSessionInstallation
    let owner: BridgePaneProductSessionOwner
    let committedCallTarget: BridgePaneProductCommittedCallTarget?
    let fileSourceAcceptanceRelay: BridgePaneFileSourceAcceptanceRelay?
    let productProvider: BridgePaneProductSchemeProvider?

    init(
        installation: BridgeProductSessionInstallation,
        owner: BridgePaneProductSessionOwner,
        committedCallTarget: BridgePaneProductCommittedCallTarget? = nil,
        fileSourceAcceptanceRelay: BridgePaneFileSourceAcceptanceRelay? = nil,
        productProvider: BridgePaneProductSchemeProvider? = nil
    ) {
        self.installation = installation
        self.owner = owner
        self.committedCallTarget = committedCallTarget
        self.fileSourceAcceptanceRelay = fileSourceAcceptanceRelay
        self.productProvider = productProvider
    }
}
