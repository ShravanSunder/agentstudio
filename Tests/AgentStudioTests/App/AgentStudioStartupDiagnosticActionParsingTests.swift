import CoreGraphics
import Testing

@testable import AgentStudio

struct AgentStudioStartupDiagnosticActionParsingTests {
    @Test("startup diagnostic action is disabled unless exact env value is present")
    func disabledUnlessExactEnvironmentValueIsPresent() {
        #expect(AgentStudioStartupDiagnosticAction.fromEnvironment([:]) == nil)
        #expect(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: "off"
            ]) == nil)
        #expect(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: "new-terminal"
            ]) == nil)
    }

    @Test("startup diagnostic action parses new tab command")
    func parsesNewTabCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " new-tab "
            ]))

        #expect(action.kind == .newTab)
        #expect(action.commandName == "newTab")
    }

    @Test("startup diagnostic action parses command bar repo filter command")
    func parsesCommandBarRepoFilterCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " command-bar-repo-filter "
            ]))

        #expect(action.kind == .commandBarRepoFilter)
        #expect(action.commandName == "commandBarRepoFilter")
    }

    @Test("startup diagnostic action parses cross-tab move geometry smoke command")
    func parsesCrossTabMoveGeometrySmokeCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " cross-tab-move-geometry-smoke "
            ]))

        #expect(action.kind == .crossTabMoveGeometrySmoke)
        #expect(action.commandName == "crossTabMoveGeometrySmoke")
    }

    @Test("startup diagnostic action parses ipc terminal smoke command")
    func parsesIPCTerminalSmokeCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " ipc-terminal-smoke "
            ]))

        #expect(action.kind == .ipcTerminalSmoke)
        #expect(action.commandName == "ipcTerminalSmoke")
    }

    @Test("startup diagnostic action parses bridge review observability smoke command")
    func parsesBridgeReviewObservabilitySmokeCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " bridge-review-observability-smoke "
            ]))

        #expect(action.kind == .bridgeReviewObservabilitySmoke)
        #expect(action.commandName == "bridgeReviewObservabilitySmoke")
    }

    @Test("startup diagnostic action parses bridge file view observability smoke command")
    func parsesBridgeFileViewObservabilitySmokeCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " bridge-file-view-observability-smoke "
            ]))

        #expect(action.kind == .bridgeFileViewObservabilitySmoke)
        #expect(action.commandName == "bridgeFileViewObservabilitySmoke")
        #expect(action.suppressesAutomaticLaunchPaneRestore)
    }

    @Test("startup diagnostic action parses bridge review to file view observability smoke command")
    func parsesBridgeReviewToFileViewObservabilitySmokeCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " bridge-review-to-file-view-observability-smoke "
            ]))

        #expect(action.kind == .bridgeReviewToFileViewObservabilitySmoke)
        #expect(action.commandName == "bridgeReviewToFileViewObservabilitySmoke")
        #expect(action.suppressesAutomaticLaunchPaneRestore)
    }

    @Test("startup diagnostic action parses bridge file view command route observability smoke command")
    func parsesBridgeFileViewCommandRouteObservabilitySmokeCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey:
                    " bridge-file-view-command-route-observability-smoke "
            ]))

        #expect(action.kind == .bridgeFileViewCommandRouteObservabilitySmoke)
        #expect(action.commandName == "bridgeFileViewCommandRouteObservabilitySmoke")
        #expect(action.suppressesAutomaticLaunchPaneRestore)
    }

    @Test("startup diagnostic action parses bridge file view targeted route observability smoke command")
    func parsesBridgeFileViewTargetedRouteObservabilitySmokeCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey:
                    " bridge-file-view-targeted-route-observability-smoke "
            ]))

        #expect(action.kind == .bridgeFileViewTargetedRouteObservabilitySmoke)
        #expect(action.commandName == "bridgeFileViewTargetedRouteObservabilitySmoke")
        #expect(action.suppressesAutomaticLaunchPaneRestore)
    }

    @Test("startup diagnostic action parses sidebar performance proof command")
    func parsesSidebarPerformanceProofCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " sidebar-performance-proof "
            ]))

        #expect(action.kind == .sidebarPerformanceProof)
        #expect(action.commandName == "sidebarPerformanceProof")
    }

    @Test("startup diagnostic action parses TCC upgrade probe command")
    func parsesTCCUpgradeProbeCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " tcc-upgrade-probe "
            ]))

        #expect(action.kind == .tccUpgradeProbe)
        #expect(action.commandName == "tccUpgradeProbe")
    }

    @Test("startup diagnostic action parses add watch folder command and path")
    func parsesAddWatchFolderCommandAndPath() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " add-watch-folder "
            ]))
        let folderURL = try #require(
            AgentStudioStartupDiagnosticAction.watchFolderURL(from: [
                AgentStudioStartupDiagnosticAction.watchFolderEnvironmentKey: " ~/agentstudio-fixture "
            ]))

        #expect(action.kind == .addWatchFolder)
        #expect(action.commandName == "addWatchFolder")
        #expect(folderURL.path.hasSuffix("/agentstudio-fixture"))
    }

    @Test("startup diagnostic watch folder path is optional")
    func watchFolderPathIsOptional() {
        #expect(AgentStudioStartupDiagnosticAction.watchFolderURL(from: [:]) == nil)
        #expect(
            AgentStudioStartupDiagnosticAction.watchFolderURL(from: [
                AgentStudioStartupDiagnosticAction.watchFolderEnvironmentKey: "   "
            ]) == nil)
    }

    @Test("cross-tab smoke render proof requires visible terminal views, mounted surfaces, and valid geometry")
    func crossTabSmokeRenderProofRequiresFullVisibleGeometry() {
        let proof = CrossTabMoveGeometrySmokeRenderProof(
            expectedVisiblePaneCount: 3,
            terminalViewCount: 3,
            surfaceIdCount: 3,
            mountedSurfaceCount: 3,
            validGeometryCount: 3
        )

        #expect(proof.succeeded)
        #expect(proof.attributes["agentstudio.startup_diagnostic.expected_visible_pane.count"] == .int(3))
        #expect(proof.attributes["agentstudio.startup_diagnostic.fixture.terminal_view.count"] == .int(3))
        #expect(proof.attributes["agentstudio.startup_diagnostic.fixture.surface_reference.count"] == .int(3))
        #expect(proof.attributes["agentstudio.startup_diagnostic.fixture.surface.count"] == .int(3))
        #expect(proof.attributes["agentstudio.startup_diagnostic.fixture.valid_geometry.count"] == .int(3))
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(true))
    }

    @Test("cross-tab smoke render proof fails when visible geometry is missing")
    func crossTabSmokeRenderProofFailsWhenVisibleGeometryIsMissing() {
        let proof = CrossTabMoveGeometrySmokeRenderProof(
            expectedVisiblePaneCount: 3,
            terminalViewCount: 3,
            surfaceIdCount: 3,
            mountedSurfaceCount: 3,
            validGeometryCount: 2
        )

        #expect(!proof.succeeded)
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(false))
    }
}
