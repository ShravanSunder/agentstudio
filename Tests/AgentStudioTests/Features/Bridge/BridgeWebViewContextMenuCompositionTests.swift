import AgentStudioTestSupport
import Foundation
import Testing

@Suite("Bridge Web View context-menu composition")
struct BridgeWebViewContextMenuCompositionTests {
    @Test("Bridge replaces the native menu while ordinary Webview preserves it")
    func contextMenuReplacementIsBridgeOnly() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let bridgeViewURL = projectRoot.appendingPathComponent(
            "Sources/AgentStudio/Features/Bridge/Views/BridgePaneContentView.swift"
        )
        let webviewViewURL = projectRoot.appendingPathComponent(
            "Sources/AgentStudio/Features/Webview/Views/WebviewPaneContentView.swift"
        )

        // Act
        let bridgeViewSource = try String(contentsOf: bridgeViewURL, encoding: .utf8)
        let webviewViewSource = try String(contentsOf: webviewViewURL, encoding: .utf8)
        let contextMenuStart = try #require(
            bridgeViewSource.range(of: ".webViewContextMenu")
        )
        let followingFrame = try #require(
            bridgeViewSource.range(
                of: ".frame",
                range: contextMenuStart.upperBound..<bridgeViewSource.endIndex
            )
        )
        let contextMenuComposition = bridgeViewSource[
            contextMenuStart.lowerBound..<followingFrame.lowerBound
        ]

        // Assert
        #expect(bridgeViewSource.components(separatedBy: ".webViewContextMenu").count == 2)
        #expect(contextMenuComposition.contains("EmptyView()"))
        #expect(!webviewViewSource.contains(".webViewContextMenu"))
    }
}
