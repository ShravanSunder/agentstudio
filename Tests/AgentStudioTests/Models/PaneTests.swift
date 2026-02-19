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
        let pane = makePane(provider: .zmx, lifetime: .persistent)

        XCTAssertNotNil(pane.terminalState)
        XCTAssertEqual(pane.terminalState?.provider, .zmx)
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
            provider: .zmx,
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
        // Layout panes always have a drawer (empty by default)
        XCTAssertNotNil(decoded.drawer)
        XCTAssertTrue(decoded.drawer!.paneIds.isEmpty)
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
            XCTAssertEqual(state.url.absoluteString, "https://docs.swift.org")
            XCTAssertFalse(state.showNavigation)
        } else {
            XCTFail("Expected .webview content")
        }
    }

    func test_codable_roundTrip_paneWithDrawer() throws {
        let drawerPaneId = UUID()
        let drawer = Drawer(
            paneIds: [drawerPaneId],
            layout: Layout(paneId: drawerPaneId),
            activePaneId: drawerPaneId,
            isExpanded: false
        )
        let pane = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Host"),
            kind: .layout(drawer: drawer)
        )

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        XCTAssertNotNil(decoded.drawer)
        XCTAssertEqual(decoded.drawer!.paneIds.count, 1)
        XCTAssertEqual(decoded.drawer!.paneIds[0], drawerPaneId)
        XCTAssertEqual(decoded.drawer!.activePaneId, drawerPaneId)
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

    // MARK: - DrawerChild Pane

    func test_drawerChild_codable_roundTrip() throws {
        let parentId = UUID()
        let pane = Pane(
            content: .webview(WebviewState(url: URL(string: "https://test.com")!, showNavigation: true)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Web Drawer"),
            kind: .drawerChild(parentPaneId: parentId)
        )

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        XCTAssertEqual(decoded.id, pane.id)
        XCTAssertEqual(decoded.metadata.title, "Web Drawer")
        XCTAssertTrue(decoded.isDrawerChild)
        XCTAssertEqual(decoded.parentPaneId, parentId)
        XCTAssertNil(decoded.drawer)
        if case .webview(let state) = decoded.content {
            XCTAssertEqual(state.url.absoluteString, "https://test.com")
        } else {
            XCTFail("Expected .webview content")
        }
    }

    // MARK: - Drawer

    func test_drawer_codable_roundTrip() throws {
        let id1 = UUID()
        let id2 = UUID()
        let layout = Layout(paneId: id1).inserting(paneId: id2, at: id1, direction: .horizontal, position: .after)
        let drawer = Drawer(paneIds: [id1, id2], layout: layout, activePaneId: id2, isExpanded: false)

        let data = try encoder.encode(drawer)
        let decoded = try decoder.decode(Drawer.self, from: data)

        XCTAssertEqual(decoded.paneIds.count, 2)
        XCTAssertEqual(decoded.activePaneId, id2)
        XCTAssertFalse(decoded.isExpanded)
        XCTAssertEqual(decoded.paneIds[0], id1)
        XCTAssertEqual(decoded.paneIds[1], id2)
        // minimizedPaneIds is transient — always empty after decode
        XCTAssertTrue(decoded.minimizedPaneIds.isEmpty)
    }

    func test_drawer_defaultValues() {
        let drawer = Drawer()

        XCTAssertTrue(drawer.paneIds.isEmpty)
        XCTAssertNil(drawer.activePaneId)
        XCTAssertFalse(drawer.isExpanded)
        XCTAssertTrue(drawer.minimizedPaneIds.isEmpty)
    }

    // MARK: - PaneKind

    func test_paneKind_layout_hasDrawer() {
        let pane = makePane()
        XCTAssertNotNil(pane.drawer)
        XCTAssertFalse(pane.isDrawerChild)
        XCTAssertNil(pane.parentPaneId)
    }

    func test_paneKind_drawerChild_hasNoDrawer() {
        let parentId = UUID()
        let pane = Pane(
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil)),
            kind: .drawerChild(parentPaneId: parentId)
        )
        XCTAssertNil(pane.drawer)
        XCTAssertTrue(pane.isDrawerChild)
        XCTAssertEqual(pane.parentPaneId, parentId)
    }

    func test_withDrawer_mutatesDrawer() {
        var pane = makePane()
        let childId = UUID()
        pane.withDrawer { drawer in
            drawer.paneIds.append(childId)
            drawer.activePaneId = childId
        }
        XCTAssertEqual(pane.drawer?.paneIds, [childId])
        XCTAssertEqual(pane.drawer?.activePaneId, childId)
    }

    func test_withDrawer_noOpForDrawerChild() {
        let parentId = UUID()
        var pane = Pane(
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil)),
            kind: .drawerChild(parentPaneId: parentId)
        )
        pane.withDrawer { drawer in
            drawer.paneIds.append(UUID()) // should be no-op
        }
        XCTAssertNil(pane.drawer)
    }

    // MARK: - Drawer Default State

    func test_drawer_defaultInit_isCollapsed() {
        // Assert — Drawer() defaults to isExpanded: false
        let drawer = Drawer()
        XCTAssertFalse(drawer.isExpanded)
        XCTAssertTrue(drawer.paneIds.isEmpty)
    }

    func test_pane_defaultKind_hasCollapsedDrawer() {
        // Arrange — default Pane init uses .layout(drawer: Drawer())
        let pane = Pane(
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil))
        )

        // Assert
        XCTAssertNotNil(pane.drawer)
        XCTAssertFalse(pane.drawer!.isExpanded)
        XCTAssertTrue(pane.drawer!.paneIds.isEmpty)
    }
}
