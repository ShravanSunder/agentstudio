import CoreGraphics
import Testing

@testable import AgentStudio

struct AgentStudioStartupDiagnosticActionTests {
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

    @Test("startup diagnostic finite frame check rejects invalid bounds")
    func finiteFrameCheckRejectsInvalidBounds() {
        #expect(AppDelegate.frameIsFiniteAndPositive(CGRect(x: 0, y: 0, width: 100, height: 50)))
        #expect(!AppDelegate.frameIsFiniteAndPositive(CGRect(x: 0, y: 0, width: 0, height: 50)))
        #expect(!AppDelegate.frameIsFiniteAndPositive(CGRect(x: 0, y: 0, width: -100, height: 50)))
        #expect(!AppDelegate.frameIsFiniteAndPositive(CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 50)))
    }

    @Test("launch restore bounds reader returns the first emitted bounds")
    func launchRestoreBoundsReaderReturnsFirstEmittedBounds() async {
        let expectedBounds = CGRect(x: 10, y: 20, width: 300, height: 200)
        let stream = AsyncStream<CGRect> { continuation in
            continuation.yield(expectedBounds)
            continuation.finish()
        }

        let bounds = await AppDelegate.firstLaunchRestoreBounds(from: stream, timeout: .seconds(3))

        #expect(bounds == expectedBounds)
    }

    @Test("launch restore bounds reader returns nil when the stream finishes without bounds")
    func launchRestoreBoundsReaderReturnsNilForFinishedStream() async {
        let stream = AsyncStream<CGRect> { continuation in
            continuation.finish()
        }

        let bounds = await AppDelegate.firstLaunchRestoreBounds(from: stream, timeout: .seconds(3))

        #expect(bounds == nil)
    }
}
