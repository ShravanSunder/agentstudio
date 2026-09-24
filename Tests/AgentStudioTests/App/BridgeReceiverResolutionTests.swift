import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@Suite("Bridge receiver resolution")
struct BridgeReceiverResolutionTests {
    @Test("a drawer terminal addresses its owner terminal's receiver, never one of its own")
    func drawerTerminalMapsToOwnerReceiver() {
        // Arrange
        let owner = Self.terminalPane()
        let drawerTerminal = Self.terminalPane(kind: .drawerChild(parentPaneId: owner.id))
        let panes = [owner.id: owner, drawerTerminal.id: drawerTerminal]

        // Act
        let receiver = BridgeReceiverResolution.receiver(
            forCommandPaneId: drawerTerminal.id,
            zoomSourcePaneIdByCompanionPaneId: [:],
            pane: { panes[$0] }
        )

        // Assert
        #expect(receiver == .terminal(owner.id), "CWD protection reads the owner, not the drawer terminal")
    }

    @Test("a drawer child of a standalone Bridge addresses that Bridge")
    func drawerChildOfBridgeMapsToStandaloneReceiver() {
        // Arrange
        let bridge = Pane(
            content: .bridgePanel(BridgePaneState(panelKind: .fileViewer)), metadata: PaneMetadata(title: "Bridge"))
        let drawerTerminal = Self.terminalPane(kind: .drawerChild(parentPaneId: bridge.id))
        let panes = [bridge.id: bridge, drawerTerminal.id: drawerTerminal]

        // Act
        let receiver = BridgeReceiverResolution.receiver(
            forCommandPaneId: drawerTerminal.id,
            zoomSourcePaneIdByCompanionPaneId: [:],
            pane: { panes[$0] }
        )

        // Assert
        #expect(receiver == .standalone(bridge.id))
    }

    @Test("terminals, standalone Bridges and Zoom companions resolve to their own receivers")
    func directReceivers() {
        // Arrange
        let terminal = Self.terminalPane()
        let bridge = Pane(
            content: .bridgePanel(BridgePaneState(panelKind: .fileViewer)), metadata: PaneMetadata(title: "Bridge"))
        let companionPaneId = UUIDv7.generate()
        let panes = [terminal.id: terminal, bridge.id: bridge]
        let resolve = { (paneId: UUID) in
            BridgeReceiverResolution.receiver(
                forCommandPaneId: paneId,
                zoomSourcePaneIdByCompanionPaneId: [companionPaneId: terminal.id],
                pane: { panes[$0] }
            )
        }

        // Act / Assert
        #expect(resolve(terminal.id) == .terminal(terminal.id))
        #expect(resolve(bridge.id) == .standalone(bridge.id))
        #expect(resolve(companionPaneId) == .terminal(terminal.id))
        #expect(resolve(UUIDv7.generate()) == nil, "an unknown pane has no receiver")
    }

    @Test("an owner that is neither a terminal nor a Bridge has no receiver")
    func otherOwnersHaveNoReceiver() throws {
        // Arrange
        let webview = Pane(
            content: .webview(WebviewState(url: try #require(URL(string: "https://github.com")))),
            metadata: PaneMetadata(title: "Web")
        )
        let drawerTerminal = Self.terminalPane(kind: .drawerChild(parentPaneId: webview.id))
        let panes = [webview.id: webview, drawerTerminal.id: drawerTerminal]

        // Act
        let receiver = BridgeReceiverResolution.receiver(
            forCommandPaneId: drawerTerminal.id,
            zoomSourcePaneIdByCompanionPaneId: [:],
            pane: { panes[$0] }
        )

        // Assert
        #expect(receiver == nil)
    }

    private static func terminalPane(kind: PaneKind? = nil) -> Pane {
        Pane(
            content: .terminal(
                TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
            ),
            metadata: PaneMetadata(title: "Terminal"),
            kind: kind
        )
    }
}
