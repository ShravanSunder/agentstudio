import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Pane filesystem location policy")
struct PaneFilesystemLocationPolicyTests {
    @Test("current pane content has an exhaustive location contract")
    func currentPaneContentHasAnExhaustiveLocationContract() throws {
        let terminal = PaneContent.terminal(
            TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
        )
        let webview = PaneContent.webview(
            WebviewState(url: try #require(URL(string: "https://example.com")))
        )
        let bridgeFiles = PaneContent.bridgePanel(
            BridgePaneState(
                panelKind: .fileViewer,
                source: .workspace(rootPath: "/work/files", baseline: .headMinusOne)
            )
        )
        let bridgeReview = PaneContent.bridgePanel(
            BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/work/review", baseline: .unstaged)
            )
        )
        let codeViewer = PaneContent.codeViewer(
            CodeViewerState(filePath: URL(filePath: "/work/code/Sources/App.swift"), scrollToLine: 8)
        )
        let unsupported = PaneContent.unsupported(
            UnsupportedContent(type: "future", version: 1, rawState: nil)
        )

        #expect(PaneFilesystemLocationPolicy.requirement(for: terminal) == .required)
        #expect(PaneFilesystemLocationPolicy.requirement(for: bridgeFiles) == .required)
        #expect(PaneFilesystemLocationPolicy.requirement(for: bridgeReview) == .required)
        #expect(PaneFilesystemLocationPolicy.requirement(for: codeViewer) == .required)
        #expect(PaneFilesystemLocationPolicy.requirement(for: webview) == .optional)
        #expect(PaneFilesystemLocationPolicy.requirement(for: unsupported) == .optional)
    }

    @Test("restore accepts normalized CWD before content repair sources")
    func restoreAcceptsNormalizedCWDBeforeContentRepairSources() {
        let content = PaneContent.codeViewer(
            CodeViewerState(filePath: URL(filePath: "/fallback/File.swift"), scrollToLine: nil)
        )

        let resolution = PaneFilesystemLocationPolicy.resolveRestoredCWD(
            for: content,
            cwd: URL(filePath: "/work/project/../project/Sources"),
            launchDirectory: URL(filePath: "/launch")
        )

        #expect(
            resolution
                == .valid(URL(filePath: "/work/project/Sources", directoryHint: .isDirectory))
        )
    }

    @Test("restore repairs required pane locations from content-owned sources")
    func restoreRepairsRequiredPaneLocationsFromContentOwnedSources() {
        let terminal = PaneContent.terminal(
            TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
        )
        let bridge = PaneContent.bridgePanel(
            BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/work/review", baseline: .staged)
            )
        )
        let codeViewer = PaneContent.codeViewer(
            CodeViewerState(filePath: URL(filePath: "/work/code/File.swift"), scrollToLine: nil)
        )

        #expect(
            PaneFilesystemLocationPolicy.resolveRestoredCWD(
                for: terminal,
                cwd: nil,
                launchDirectory: URL(filePath: "/work/terminal")
            ) == .repaired(URL(filePath: "/work/terminal", directoryHint: .isDirectory))
        )
        #expect(
            PaneFilesystemLocationPolicy.resolveRestoredCWD(
                for: bridge,
                cwd: nil,
                launchDirectory: URL(filePath: "/wrong-owner")
            ) == .repaired(URL(filePath: "/work/review", directoryHint: .isDirectory))
        )
        #expect(
            PaneFilesystemLocationPolicy.resolveRestoredCWD(
                for: codeViewer,
                cwd: nil,
                launchDirectory: URL(filePath: "/wrong-owner")
            ) == .repaired(URL(filePath: "/work/code", directoryHint: .isDirectory))
        )
    }

    @Test("unrepairable required panes degrade while optional panes remain locationless")
    func unrepairableRequiredPanesDegradeWhileOptionalPanesRemainLocationless() throws {
        let bridgeWithoutWorkspace = PaneContent.bridgePanel(
            BridgePaneState(panelKind: .diffViewer, source: .commit(sha: "abc123"))
        )
        let webview = PaneContent.webview(
            WebviewState(url: try #require(URL(string: "https://example.com")))
        )
        let unsupported = PaneContent.unsupported(
            UnsupportedContent(type: "future", version: 1, rawState: nil)
        )

        #expect(
            PaneFilesystemLocationPolicy.resolveRestoredCWD(
                for: bridgeWithoutWorkspace,
                cwd: nil,
                launchDirectory: nil
            ) == .degradedRequired
        )
        #expect(
            PaneFilesystemLocationPolicy.resolveRestoredCWD(
                for: webview,
                cwd: nil,
                launchDirectory: nil
            ) == .valid(nil)
        )
        #expect(
            PaneFilesystemLocationPolicy.resolveRestoredCWD(
                for: unsupported,
                cwd: nil,
                launchDirectory: nil
            ) == .valid(nil)
        )
    }

    @Test("runtime accepts only normalized absolute file CWD samples")
    func runtimeAcceptsOnlyNormalizedAbsoluteFileCWDSamples() {
        #expect(
            PaneFilesystemLocationPolicy.runtimeCWDUpdate(
                URL(filePath: "/work/project/../project/Sources")
            ) == .accepted(URL(filePath: "/work/project/Sources", directoryHint: .isDirectory))
        )
        #expect(PaneFilesystemLocationPolicy.runtimeCWDUpdate(nil) == .rejected)
        #expect(
            PaneFilesystemLocationPolicy.runtimeCWDUpdate(URL(string: "https://example.com/path")) == .rejected
        )
    }

    @Test("normalized CWD values preserve filesystem directory identity")
    func normalizedCWDValuesPreserveFilesystemDirectoryIdentity() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser

        let resolution = PaneFilesystemLocationPolicy.resolveRestoredCWD(
            for: .terminal(
                TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
            ),
            cwd: homeDirectory,
            launchDirectory: nil
        )

        #expect(resolution == .valid(homeDirectory))
        guard case .valid(let admittedDirectory) = resolution else { return }
        #expect(admittedDirectory?.hasDirectoryPath == true)
    }
}
