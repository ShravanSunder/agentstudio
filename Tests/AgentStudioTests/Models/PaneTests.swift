import XCTest
@testable import AgentStudio

final class PaneTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    // MARK: - Convenience Accessors

    func test_terminalState_returnsState_forTerminalContent() {
        let pane = makePane(provider: .tmux, lifetime: .persistent)

        XCTAssertNotNil(pane.terminalState)
        XCTAssertEqual(pane.terminalState?.provider, .tmux)
        XCTAssertEqual(pane.terminalState?.lifetime, .persistent)
    }

    func test_terminalState_returnsNil_forNonTerminalContent() {
        let pane = Pane(
            content: .webview(WebviewState(url: URL(string: "https://example.com")!, showNavigation: true)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Web")
        )

        XCTAssertNil(pane.terminalState)
        XCTAssertNil(pane.provider)
        XCTAssertNil(pane.lifetime)
    }

    func test_provider_returnsSessionProvider_forTerminal() {
        let pane = makePane(provider: .ghostty)
        XCTAssertEqual(pane.provider, .ghostty)
    }

    func test_lifetime_returnsSessionLifetime_forTerminal() {
        let pane = makePane(lifetime: .temporary)
        XCTAssertEqual(pane.lifetime, .temporary)
    }

    func test_title_readsFromMetadata() {
        let pane = makePane(title: "My Terminal")
        XCTAssertEqual(pane.title, "My Terminal")
    }

    func test_title_writesToMetadata() {
        var pane = makePane(title: "Old")
        pane.title = "New"
        XCTAssertEqual(pane.title, "New")
        XCTAssertEqual(pane.metadata.title, "New")
    }

    func test_agent_readsFromMetadata() {
        let pane = makePane(agent: .claude)
        XCTAssertEqual(pane.agent, .claude)
    }

    func test_agent_writesToMetadata() {
        var pane = makePane()
        XCTAssertNil(pane.agent)
        pane.agent = .claude
        XCTAssertEqual(pane.agent, .claude)
        XCTAssertEqual(pane.metadata.agentType, .claude)
    }

    func test_source_delegatesToMetadata() {
        let source = TerminalSource.floating(workingDirectory: URL(fileURLWithPath: "/tmp"), title: "Float")
        let pane = makePane(source: source)
        XCTAssertEqual(pane.source, source)
    }

    func test_worktreeId_returnsId_forWorktreeSource() {
        let wtId = UUID()
        let repoId = UUID()
        let pane = makePane(source: .worktree(worktreeId: wtId, repoId: repoId))
        XCTAssertEqual(pane.worktreeId, wtId)
        XCTAssertEqual(pane.repoId, repoId)
    }

    func test_worktreeId_returnsNil_forFloatingSource() {
        let pane = makePane(source: .floating(workingDirectory: nil, title: nil))
        XCTAssertNil(pane.worktreeId)
        XCTAssertNil(pane.repoId)
    }

    // MARK: - Codable Round-Trip

    func test_codable_roundTrip_terminalPane() throws {
        let pane = makePane(
            source: .floating(workingDirectory: URL(fileURLWithPath: "/tmp"), title: "Float"),
            title: "My Term",
            agent: .claude,
            provider: .tmux,
            lifetime: .persistent,
            residency: .active
        )

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        XCTAssertEqual(decoded.id, pane.id)
        XCTAssertEqual(decoded.content, pane.content)
        XCTAssertEqual(decoded.metadata.title, "My Term")
        XCTAssertEqual(decoded.metadata.agentType, .claude)
        XCTAssertEqual(decoded.residency, SessionResidency.active)
        XCTAssertNil(decoded.drawer)
    }

    func test_codable_roundTrip_webviewPane() throws {
        let pane = Pane(
            content: .webview(WebviewState(url: URL(string: "https://docs.swift.org")!, showNavigation: false)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Docs")
        )

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        XCTAssertEqual(decoded.id, pane.id)
        if case .webview(let state) = decoded.content {
            XCTAssertEqual(state.activeTab?.url.absoluteString, "https://docs.swift.org")
            XCTAssertFalse(state.showNavigation)
        } else {
            XCTFail("Expected .webview content")
        }
    }

    func test_codable_roundTrip_paneWithDrawer() throws {
        let drawerPane = DrawerPane(
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Drawer Term")
        )
        let drawer = Drawer(
            panes: [drawerPane],
            activeDrawerPaneId: drawerPane.id,
            isExpanded: false
        )
        let pane = Pane(
            content: .terminal(TerminalState(provider: .tmux, lifetime: .persistent)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Host"),
            drawer: drawer
        )

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        XCTAssertNotNil(decoded.drawer)
        XCTAssertEqual(decoded.drawer!.panes.count, 1)
        XCTAssertEqual(decoded.drawer!.panes[0].id, drawerPane.id)
        XCTAssertEqual(decoded.drawer!.panes[0].metadata.title, "Drawer Term")
        XCTAssertEqual(decoded.drawer!.activeDrawerPaneId, drawerPane.id)
        XCTAssertFalse(decoded.drawer!.isExpanded)
    }

    func test_codable_roundTrip_worktreeSource() throws {
        let wtId = UUID()
        let repoId = UUID()
        let pane = makePane(source: .worktree(worktreeId: wtId, repoId: repoId))

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        XCTAssertEqual(decoded.worktreeId, wtId)
        XCTAssertEqual(decoded.repoId, repoId)
    }

    func test_codable_roundTrip_pendingUndoResidency() throws {
        let expiry = Date(timeIntervalSince1970: 2_000_000)
        let pane = makePane(residency: .pendingUndo(expiresAt: expiry))

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        if case .pendingUndo(let decodedExpiry) = decoded.residency {
            XCTAssertEqual(decodedExpiry.timeIntervalSince1970, expiry.timeIntervalSince1970, accuracy: 0.001)
        } else {
            XCTFail("Expected .pendingUndo residency")
        }
    }

    func test_codable_roundTrip_backgroundedResidency() throws {
        let pane = makePane(residency: .backgrounded)

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        XCTAssertEqual(decoded.residency, .backgrounded)
    }

    // MARK: - PaneMetadata

    func test_metadata_worktreeId_extractsFromWorktreeSource() {
        let wtId = UUID()
        let repoId = UUID()
        let metadata = PaneMetadata(source: .worktree(worktreeId: wtId, repoId: repoId))

        XCTAssertEqual(metadata.worktreeId, wtId)
        XCTAssertEqual(metadata.repoId, repoId)
    }

    func test_metadata_worktreeId_returnsNil_forFloatingSource() {
        let metadata = PaneMetadata(source: .floating(workingDirectory: nil, title: nil))

        XCTAssertNil(metadata.worktreeId)
        XCTAssertNil(metadata.repoId)
    }

    func test_metadata_defaultValues() {
        let metadata = PaneMetadata(source: .floating(workingDirectory: nil, title: nil))

        XCTAssertEqual(metadata.title, "Terminal")
        XCTAssertNil(metadata.cwd)
        XCTAssertNil(metadata.agentType)
        XCTAssertEqual(metadata.tags, [])
    }

    func test_metadata_codable_roundTrip_withTags() throws {
        let metadata = PaneMetadata(
            source: .floating(workingDirectory: URL(fileURLWithPath: "/tmp"), title: "Test"),
            title: "Tagged",
            cwd: URL(fileURLWithPath: "/home/user"),
            agentType: .claude,
            tags: ["focus", "dev"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)
        let decoded = try JSONDecoder().decode(PaneMetadata.self, from: data)

        XCTAssertEqual(decoded.title, "Tagged")
        XCTAssertEqual(decoded.tags, ["focus", "dev"])
        XCTAssertEqual(decoded.agentType, .claude)
        XCTAssertEqual(decoded.cwd, URL(fileURLWithPath: "/home/user"))
    }

    // MARK: - DrawerPane

    func test_drawerPane_codable_roundTrip() throws {
        let dp = DrawerPane(
            content: .webview(WebviewState(url: URL(string: "https://test.com")!, showNavigation: true)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Web Drawer")
        )

        let data = try encoder.encode(dp)
        let decoded = try decoder.decode(DrawerPane.self, from: data)

        XCTAssertEqual(decoded.id, dp.id)
        XCTAssertEqual(decoded.metadata.title, "Web Drawer")
        if case .webview(let state) = decoded.content {
            XCTAssertEqual(state.activeTab?.url.absoluteString, "https://test.com")
        } else {
            XCTFail("Expected .webview content")
        }
    }

    // MARK: - Drawer

    func test_drawer_codable_roundTrip() throws {
        let dp1 = DrawerPane(
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "D1")
        )
        let dp2 = DrawerPane(
            content: .codeViewer(CodeViewerState(filePath: URL(fileURLWithPath: "/tmp/file.swift"), scrollToLine: 10)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "D2")
        )
        let drawer = Drawer(panes: [dp1, dp2], activeDrawerPaneId: dp2.id, isExpanded: false)

        let data = try encoder.encode(drawer)
        let decoded = try decoder.decode(Drawer.self, from: data)

        XCTAssertEqual(decoded.panes.count, 2)
        XCTAssertEqual(decoded.activeDrawerPaneId, dp2.id)
        XCTAssertFalse(decoded.isExpanded)
        XCTAssertEqual(decoded.panes[0].metadata.title, "D1")
        XCTAssertEqual(decoded.panes[1].metadata.title, "D2")
    }

    func test_drawer_defaultValues() {
        let drawer = Drawer()

        XCTAssertTrue(drawer.panes.isEmpty)
        XCTAssertNil(drawer.activeDrawerPaneId)
        XCTAssertTrue(drawer.isExpanded)
    }
}
