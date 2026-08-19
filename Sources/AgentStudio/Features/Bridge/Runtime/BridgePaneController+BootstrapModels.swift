import AgentStudioCore
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
