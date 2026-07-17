import Testing

@testable import AgentStudio

struct BridgeProductPaintStartupDiagnosticTests {
    @Test("startup diagnostic action parses Bridge product paint correlation command")
    func parsesBridgeProductPaintCorrelationCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " bridge-product-paint-correlation "
            ]))

        #expect(action.kind == .bridgeProductPaintCorrelation)
        #expect(action.commandName == "bridgeProductPaintCorrelation")
        #expect(action.suppressesAutomaticLaunchPaneRestore)
    }

    @Test("Bridge product paint diagnostic correlates Review and File through painted DOM")
    func bridgeProductPaintDiagnosticCorrelatesReviewAndFilePaint() {
        let javaScript = AppDelegate.bridgeProductPaintCorrelationJavaScript(
            relativePath: "tracked.txt",
            sha256: "expected-sha",
            canary: "expected-canary"
        )

        #expect(javaScript.contains("data-bridge-painted-source-correlations"))
        #expect(javaScript.contains("correlation?.surface === surface"))
        #expect(javaScript.contains("correlation?.observedSha256 === expectedSha256"))
        #expect(javaScript.contains("correlation?.disposition === 'painted'"))
        #expect(javaScript.contains("correlation?.text?.includes(expectedCanary)"))
        #expect(javaScript.contains("correlation?.descriptorId"))
        #expect(javaScript.contains("correlation?.requestId"))
        #expect(javaScript.contains("correlation?.sourceIdentity"))
        #expect(javaScript.contains("Number.isSafeInteger(correlation?.sourceGeneration)"))
        #expect(javaScript.contains("correlation?.semanticItemId === correlation?.itemId"))
        #expect(javaScript.contains("correlation?.publicationId === paintedPublicationId"))
        #expect(javaScript.contains("correlation?.pierreItemId"))
        #expect(javaScript.contains("correlation.pierreItemId === correlation.itemId"))
        #expect(javaScript.contains("correlation?.itemId === selectedItemId"))
        #expect(javaScript.contains("correlation?.position === 'whole'"))
        #expect(javaScript.contains("data-selected-item-id"))
        #expect(javaScript.contains("data-worktree-rendered-item-id"))
        #expect(javaScript.contains("bridge-viewer-context-file"))
        #expect(javaScript.contains("data-item-path"))
        #expect(javaScript.contains("__bridgeFrameLivenessProbe?.rafAlive"))
    }

    @Test("Bridge product paint diagnostic reloads and proves worker replacement replay")
    func bridgeProductPaintDiagnosticReloadsAndProvesWorkerReplacementReplay() throws {
        let source = try String(
            contentsOfFile:
                "Sources/AgentStudio/App/Boot/AppDelegate+BridgeProductPaintCorrelationStartupDiagnostics.swift",
            encoding: .utf8
        )

        #expect(source.contains("controller.loadApp()"))
        #expect(source.contains("controller.requestViewerSurface(.review)"))
        #expect(source.contains("reload_replay_succeeded"))
        #expect(source.contains("worker_replacement_observed"))
    }

    @Test("Bridge product paint diagnostic focuses and proves its exact host is visible before paint")
    func bridgeProductPaintDiagnosticFocusesVisibleHostBeforePaint() throws {
        let source = try String(
            contentsOfFile:
                "Sources/AgentStudio/App/Boot/AppDelegate+BridgeProductPaintCorrelationStartupDiagnostics.swift",
            encoding: .utf8
        )
        let focusRange = try #require(
            source.range(
                of: "paneTabViewController()?.execute(.focusPane, target: pane.id, targetType: .pane)"
            )
        )
        let visibilityRange = try #require(
            source.range(of: "waitForBridgeProductPaintHostVisibility(controller: bridgeView.controller)")
        )
        let correlationRange = try #require(
            source.range(of: "let initialProof = await waitForBridgeProductPaintCorrelation(")
        )

        #expect(focusRange.lowerBound < visibilityRange.lowerBound)
        #expect(visibilityRange.lowerBound < correlationRange.lowerBound)
        #expect(source.contains("document.visibilityState === 'visible'"))
    }

}
