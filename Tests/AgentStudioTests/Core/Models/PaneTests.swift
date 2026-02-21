import Testing
import Foundation

@testable import AgentStudio

@Suite(.serialized)
final class PaneTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    // MARK: - Convenience Accessors

    @Test

    func test_terminalState_returnsState_forTerminalContent() {
        let pane = makePane(provider: .zmx, lifetime: .persistent)

        #expect((pane.terminalState) != nil)
        #expect(pane.terminalState?.provider == .zmx)
        #expect(pane.terminalState?.lifetime == .persistent)
    }

    @Test

    func test_terminalState_returnsNil_forNonTerminalContent() {
        let pane = Pane(
            content: .webview(WebviewState(url: URL(string: "https://example.com")!, showNavigation: true)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Web")
        )

        #expect((pane.terminalState) == nil)
        #expect((pane.provider) == nil)
        #expect((pane.lifetime) == nil)
    }

    @Test

    func test_provider_returnsSessionProvider_forTerminal() {
        let pane = makePane(provider: .ghostty)
        #expect(pane.provider == .ghostty)
    }

    @Test

    func test_lifetime_returnsSessionLifetime_forTerminal() {
        let pane = makePane(lifetime: .temporary)
        #expect(pane.lifetime == .temporary)
    }

    @Test

    func test_title_readsFromMetadata() {
        let pane = makePane(title: "My Terminal")
        #expect(pane.title == "My Terminal")
    }

    @Test

    func test_title_writesToMetadata() {
        var pane = makePane(title: "Old")
        pane.title = "New"
        #expect(pane.title == "New")
        #expect(pane.metadata.title == "New")
    }

    @Test

    func test_agent_readsFromMetadata() {
        let pane = makePane(agent: .claude)
        #expect(pane.agent == .claude)
    }

    @Test

    func test_agent_writesToMetadata() {
        var pane = makePane()
        #expect((pane.agent) == nil)
        pane.agent = .claude
        #expect(pane.agent == .claude)
        #expect(pane.metadata.agentType == .claude)
    }

    @Test

    func test_source_delegatesToMetadata() {
        let source = TerminalSource.floating(workingDirectory: URL(fileURLWithPath: "/tmp"), title: "Float")
        let pane = makePane(source: source)
        #expect(pane.source == source)
    }

    @Test

    func test_worktreeId_returnsId_forWorktreeSource() {
        let wtId = UUID()
        let repoId = UUID()
        let pane = makePane(source: .worktree(worktreeId: wtId, repoId: repoId))
        #expect(pane.worktreeId == wtId)
        #expect(pane.repoId == repoId)
    }

    @Test

    func test_worktreeId_returnsNil_forFloatingSource() {
        let pane = makePane(source: .floating(workingDirectory: nil, title: nil))
        #expect((pane.worktreeId) == nil)
        #expect((pane.repoId) == nil)
    }

    // MARK: - Codable Round-Trip

    @Test

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

        #expect(decoded.id == pane.id)
        #expect(decoded.content == pane.content)
        #expect(decoded.metadata.title == "My Term")
        #expect(decoded.metadata.agentType == .claude)
        #expect(decoded.residency == SessionResidency.active)
        // Layout panes always have a drawer (empty by default)
        #expect((decoded.drawer) != nil)
        #expect(decoded.drawer!.paneIds.isEmpty)
    }

    @Test

    func test_codable_roundTrip_webviewPane() throws {
        let pane = Pane(
            content: .webview(WebviewState(url: URL(string: "https://docs.swift.org")!, showNavigation: false)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Docs")
        )

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        #expect(decoded.id == pane.id)
        if case .webview(let state) = decoded.content {
            #expect(state.url.absoluteString == "https://docs.swift.org")
            #expect(!(state.showNavigation))
        } else {
            Issue.record("Expected .webview content")
        }
    }

    @Test

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

        #expect((decoded.drawer) != nil)
        #expect(decoded.drawer!.paneIds.count == 1)
        #expect(decoded.drawer!.paneIds[0] == drawerPaneId)
        #expect(decoded.drawer!.activePaneId == drawerPaneId)
        #expect(!(decoded.drawer!.isExpanded))
    }

    @Test

    func test_codable_roundTrip_worktreeSource() throws {
        let wtId = UUID()
        let repoId = UUID()
        let pane = makePane(source: .worktree(worktreeId: wtId, repoId: repoId))

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        #expect(decoded.worktreeId == wtId)
        #expect(decoded.repoId == repoId)
    }

    @Test

    func test_codable_roundTrip_pendingUndoResidency() throws {
        let expiry = Date(timeIntervalSince1970: 2_000_000)
        let pane = makePane(residency: .pendingUndo(expiresAt: expiry))

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        if case .pendingUndo(let decodedExpiry) = decoded.residency {
            #expect(decodedExpiry.timeIntervalSince1970 == expiry.timeIntervalSince1970, accuracy: 0.001)
        } else {
            Issue.record("Expected .pendingUndo residency")
        }
    }

    @Test

    func test_codable_roundTrip_backgroundedResidency() throws {
        let pane = makePane(residency: .backgrounded)

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        #expect(decoded.residency == .backgrounded)
    }

    // MARK: - Legacy Decoding

    @Test

    func test_legacyDecode_withoutKind_usesTopLevelDrawer() throws {
        let drawerPaneId = UUID()
        let drawer = Drawer(
            paneIds: [drawerPaneId],
            layout: Layout(paneId: drawerPaneId),
            activePaneId: drawerPaneId,
            isExpanded: true
        )
        let pane = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Legacy Host"),
            kind: .layout(drawer: drawer)
        )

        let currentData = try encoder.encode(pane)
        var legacyObject = try #require(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "kind")
        legacyObject["drawer"] = try JSONSerialization.jsonObject(with: encoder.encode(drawer))

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decoded = try decoder.decode(Pane.self, from: legacyData)

        #expect(decoded.id == pane.id)
        #expect((decoded.drawer) != nil)
        #expect(decoded.drawer?.paneIds == [drawerPaneId])
        #expect(decoded.drawer?.activePaneId == drawerPaneId)
        #expect(decoded.drawer?.isExpanded ?? false)
    }

    @Test

    func test_legacyDecode_withoutKindAndDrawer_defaultsEmptyDrawer() throws {
        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            title: "Legacy Empty Drawer",
            provider: .zmx
        )

        let currentData = try encoder.encode(pane)
        var legacyObject = try #require(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "kind")
        legacyObject.removeValue(forKey: "drawer")

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decoded = try decoder.decode(Pane.self, from: legacyData)

        #expect(decoded.id == pane.id)
        #expect((decoded.drawer) != nil)
        #expect(decoded.drawer?.paneIds.isEmpty ?? false)
        #expect((decoded.drawer?.activePaneId) == nil)
    }

    // MARK: - PaneMetadata

    @Test

    func test_metadata_worktreeId_extractsFromWorktreeSource() {
        let wtId = UUID()
        let repoId = UUID()
        let metadata = PaneMetadata(source: .worktree(worktreeId: wtId, repoId: repoId))

        #expect(metadata.worktreeId == wtId)
        #expect(metadata.repoId == repoId)
    }

    @Test

    func test_metadata_worktreeId_returnsNil_forFloatingSource() {
        let metadata = PaneMetadata(source: .floating(workingDirectory: nil, title: nil))

        #expect((metadata.worktreeId) == nil)
        #expect((metadata.repoId) == nil)
    }

    @Test

    func test_metadata_defaultValues() {
        let metadata = PaneMetadata(source: .floating(workingDirectory: nil, title: nil))

        #expect(metadata.title == "Terminal")
        #expect((metadata.cwd) == nil)
        #expect((metadata.agentType) == nil)
        #expect(metadata.tags == [])
    }

    @Test

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

        #expect(decoded.title == "Tagged")
        #expect(decoded.tags == ["focus", "dev"])
        #expect(decoded.agentType == .claude)
        #expect(decoded.cwd == URL(fileURLWithPath: "/home/user"))
    }

    // MARK: - DrawerChild Pane

    @Test

    func test_drawerChild_codable_roundTrip() throws {
        let parentId = UUID()
        let pane = Pane(
            content: .webview(WebviewState(url: URL(string: "https://test.com")!, showNavigation: true)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Web Drawer"),
            kind: .drawerChild(parentPaneId: parentId)
        )

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        #expect(decoded.id == pane.id)
        #expect(decoded.metadata.title == "Web Drawer")
        #expect(decoded.isDrawerChild)
        #expect(decoded.parentPaneId == parentId)
        #expect((decoded.drawer) == nil)
        if case .webview(let state) = decoded.content {
            #expect(state.url.absoluteString == "https://test.com")
        } else {
            Issue.record("Expected .webview content")
        }
    }

    // MARK: - Drawer

    @Test

    func test_drawer_codable_roundTrip() throws {
        let id1 = UUID()
        let id2 = UUID()
        let layout = Layout(paneId: id1).inserting(paneId: id2, at: id1, direction: .horizontal, position: .after)
        let drawer = Drawer(paneIds: [id1, id2], layout: layout, activePaneId: id2, isExpanded: false)

        let data = try encoder.encode(drawer)
        let decoded = try decoder.decode(Drawer.self, from: data)

        #expect(decoded.paneIds.count == 2)
        #expect(decoded.activePaneId == id2)
        #expect(!(decoded.isExpanded))
        #expect(decoded.paneIds[0] == id1)
        #expect(decoded.paneIds[1] == id2)
        // minimizedPaneIds is transient — always empty after decode
        #expect(decoded.minimizedPaneIds.isEmpty)
    }

    @Test

    func test_drawer_defaultValues() {
        let drawer = Drawer()

        #expect(drawer.paneIds.isEmpty)
        #expect((drawer.activePaneId) == nil)
        #expect(!(drawer.isExpanded))
        #expect(drawer.minimizedPaneIds.isEmpty)
    }

    // MARK: - PaneKind

    @Test

    func test_paneKind_layout_hasDrawer() {
        let pane = makePane()
        #expect((pane.drawer) != nil)
        #expect(!(pane.isDrawerChild))
        #expect((pane.parentPaneId) == nil)
    }

    @Test

    func test_paneKind_drawerChild_hasNoDrawer() {
        let parentId = UUID()
        let pane = Pane(
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil)),
            kind: .drawerChild(parentPaneId: parentId)
        )
        #expect((pane.drawer) == nil)
        #expect(pane.isDrawerChild)
        #expect(pane.parentPaneId == parentId)
    }

    @Test

    func test_withDrawer_mutatesDrawer() {
        var pane = makePane()
        let childId = UUID()
        pane.withDrawer { drawer in
            drawer.paneIds.append(childId)
            drawer.activePaneId = childId
        }
        #expect(pane.drawer?.paneIds == [childId])
        #expect(pane.drawer?.activePaneId == childId)
    }

    @Test

    func test_withDrawer_noOpForDrawerChild() {
        let parentId = UUID()
        var pane = Pane(
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil)),
            kind: .drawerChild(parentPaneId: parentId)
        )
        pane.withDrawer { drawer in
            drawer.paneIds.append(UUID())  // should be no-op
        }
        #expect((pane.drawer) == nil)
    }

    // MARK: - Drawer Default State

    @Test

    func test_drawer_defaultInit_isCollapsed() {
        // Assert — Drawer() defaults to isExpanded: false
        let drawer = Drawer()
        #expect(!(drawer.isExpanded))
        #expect(drawer.paneIds.isEmpty)
    }

    @Test

    func test_pane_defaultKind_hasCollapsedDrawer() {
        // Arrange — default Pane init uses .layout(drawer: Drawer())
        let pane = Pane(
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil))
        )

        // Assert
        #expect((pane.drawer) != nil)
        #expect(!(pane.drawer!.isExpanded))
        #expect(pane.drawer!.paneIds.isEmpty)
    }
}
