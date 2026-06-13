import Foundation
import Testing

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

    func test_defaultInit_generatesV7PaneId() {
        let pane = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata()
        )

        #expect(UUIDv7.isV7(pane.id))
        #expect(pane.metadata.paneId == PaneId(uuid: pane.id))
    }

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
            metadata: PaneMetadata(title: "Web")
        )

        #expect((pane.terminalState) == nil)
        #expect((pane.provider) == nil)
        #expect((pane.lifetime) == nil)
    }

    @Test

    func test_contentTypeMapping_bridgePanel_mapsToDiff() {
        let pane = Pane(
            content: .bridgePanel(
                BridgePaneState(panelKind: .diffViewer, source: .commit(sha: "abc123"))
            ),
            metadata: PaneMetadata(title: "Bridge Diff")
        )

        #expect(pane.metadata.contentType == .diff)
    }

    @Test

    func test_contentTypeMapping_codeViewer_mapsToCodeViewer() {
        let pane = Pane(
            content: .codeViewer(
                CodeViewerState(filePath: URL(fileURLWithPath: "/tmp/main.swift"), scrollToLine: 42)
            ),
            metadata: PaneMetadata(title: "Code")
        )

        #expect(pane.metadata.contentType == .codeViewer)
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

    func test_launchDirectory_readsFromMetadata() {
        let launchDirectory = URL(fileURLWithPath: "/tmp")
        let pane = makePane(launchDirectory: launchDirectory)
        #expect(pane.metadata.launchDirectory == launchDirectory)
    }

    @Test

    func test_worktreeId_returnsId_forLiveFacets() {
        let wtId = UUID()
        let repoId = UUID()
        let launchDirectory = URL(fileURLWithPath: "/tmp/worktree")
        let pane = makePane(
            launchDirectory: launchDirectory,
            facets: PaneContextFacets(repoId: repoId, worktreeId: wtId, cwd: launchDirectory)
        )
        #expect(pane.worktreeId == wtId)
        #expect(pane.repoId == repoId)
    }

    @Test

    func test_worktreeId_returnsNil_withoutWorktreeFacets() {
        let pane = makePane()
        #expect((pane.worktreeId) == nil)
        #expect((pane.repoId) == nil)
    }

    // MARK: - Codable Round-Trip

    @Test

    func test_codable_roundTrip_terminalPane() throws {
        let pane = makePane(
            launchDirectory: URL(fileURLWithPath: "/tmp"),
            title: "My Term",
            provider: .zmx,
            lifetime: .persistent,
            residency: .active
        )

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        #expect(decoded.id == pane.id)
        #expect(decoded.content == pane.content)
        #expect(decoded.metadata.title == "My Term")
        #expect(decoded.residency == SessionResidency.active)
        // Layout panes always have a drawer (empty by default)
        #expect((decoded.drawer) != nil)
        #expect(decoded.drawer!.paneIds.isEmpty)
    }

    @Test

    func test_codable_roundTrip_webviewPane() throws {
        let pane = Pane(
            content: .webview(WebviewState(url: URL(string: "https://docs.swift.org")!, showNavigation: false)),
            metadata: PaneMetadata(title: "Docs")
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
            isExpanded: false
        )
        let pane = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(title: "Host"),
            kind: .layout(drawer: drawer)
        )

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        #expect((decoded.drawer) != nil)
        #expect(decoded.drawer!.paneIds.count == 1)
        #expect(decoded.drawer!.paneIds[0] == drawerPaneId)
        #expect(!(decoded.drawer!.isExpanded))
    }

    @Test

    func test_codable_roundTrip_worktreeSource() throws {
        let wtId = UUID()
        let repoId = UUID()
        let worktreeURL = URL(fileURLWithPath: "/tmp/worktree")
        let pane = makePane(
            launchDirectory: worktreeURL,
            facets: PaneContextFacets(repoId: repoId, worktreeId: wtId, cwd: worktreeURL)
        )

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
            #expect(abs((decodedExpiry.timeIntervalSince1970) - (expiry.timeIntervalSince1970)) <= 0.001)
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

    // MARK: - Strict Greenfield Decoding

    @Test

    func test_decode_withoutKind_throws() throws {
        let drawerPaneId = UUID()
        let drawer = Drawer(
            paneIds: [drawerPaneId],
            isExpanded: true
        )
        let pane = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(title: "Legacy Host"),
            kind: .layout(drawer: drawer)
        )

        let currentData = try encoder.encode(pane)
        guard var legacyObject = try JSONSerialization.jsonObject(with: currentData) as? [String: Any] else {
            Issue.record("Expected pane JSON dictionary")
            return
        }
        legacyObject.removeValue(forKey: "kind")
        legacyObject["drawer"] = try JSONSerialization.jsonObject(with: encoder.encode(drawer))

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        #expect(throws: Error.self) {
            try decoder.decode(Pane.self, from: legacyData)
        }
    }

    @Test

    func test_decode_withoutKindAndDrawer_throws() throws {
        let pane = makePane(
            title: "Legacy Empty Drawer",
            provider: .zmx
        )

        let currentData = try encoder.encode(pane)
        guard var legacyObject = try JSONSerialization.jsonObject(with: currentData) as? [String: Any] else {
            Issue.record("Expected pane JSON dictionary")
            return
        }
        legacyObject.removeValue(forKey: "kind")
        legacyObject.removeValue(forKey: "drawer")

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        #expect(throws: Error.self) {
            try decoder.decode(Pane.self, from: legacyData)
        }
    }

    @Test

    func test_decode_withV4PaneId_throws() throws {
        let pane = makePane(
            title: "NonCanonicalId",
            provider: .zmx
        )
        let currentData = try encoder.encode(pane)
        guard var object = try JSONSerialization.jsonObject(with: currentData) as? [String: Any] else {
            Issue.record("Expected pane JSON dictionary")
            return
        }
        object["id"] = UUID().uuidString
        let nonCanonicalData = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: Error.self) {
            try decoder.decode(Pane.self, from: nonCanonicalData)
        }
    }

    @Test

    func test_decode_withMismatchedMetadataPaneId_throws() throws {
        let pane = makePane(
            title: "MismatchedMetadataId",
            provider: .zmx
        )
        let currentData = try encoder.encode(pane)
        guard var object = try JSONSerialization.jsonObject(with: currentData) as? [String: Any] else {
            Issue.record("Expected pane JSON dictionary")
            return
        }
        guard var metadata = object["metadata"] as? [String: Any] else {
            Issue.record("Expected metadata dictionary")
            return
        }

        var mismatchedPaneId = UUIDv7.generate()
        while mismatchedPaneId == pane.id {
            mismatchedPaneId = UUIDv7.generate()
        }
        metadata["paneId"] = mismatchedPaneId.uuidString
        object["metadata"] = metadata

        let mismatchedData = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: Error.self) {
            try decoder.decode(Pane.self, from: mismatchedData)
        }
    }

    // MARK: - PaneMetadata

    @Test

    func test_metadata_worktreeId_extractsFromWorktreeSource() {
        let wtId = UUID()
        let repoId = UUID()
        let worktreeURL = URL(fileURLWithPath: "/tmp/worktree")
        let metadata = PaneMetadata(
            launchDirectory: worktreeURL,
            facets: PaneContextFacets(repoId: repoId, worktreeId: wtId, cwd: worktreeURL)
        )

        #expect(metadata.worktreeId == wtId)
        #expect(metadata.repoId == repoId)
    }

    @Test

    func test_metadata_worktreeId_returnsNil_forFloatingSource() {
        let metadata = PaneMetadata()

        #expect((metadata.worktreeId) == nil)
        #expect((metadata.repoId) == nil)
    }

    @Test

    func test_metadata_defaultValues() {
        let metadata = PaneMetadata()

        #expect(metadata.title == "Terminal")
        #expect((metadata.cwd) == nil)
        #expect(metadata.tags.isEmpty)
    }

    @Test

    func test_metadata_codable_roundTrip_withTags() throws {
        let metadata = PaneMetadata(
            launchDirectory: URL(fileURLWithPath: "/tmp"),
            title: "Tagged",
            facets: PaneContextFacets(
                cwd: URL(fileURLWithPath: "/home/user"),
                tags: ["focus", "dev"]
            )
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)
        let decoded = try JSONDecoder().decode(PaneMetadata.self, from: data)

        #expect(decoded.title == "Tagged")
        #expect(decoded.tags == ["focus", "dev"])
        #expect(decoded.cwd == URL(fileURLWithPath: "/home/user"))
    }

    @Test

    func test_metadata_decode_missingCanonicalFields_throws() throws {
        let metadata = PaneMetadata(
            launchDirectory: URL(fileURLWithPath: "/tmp"),
            title: "Canonical"
        )
        let data = try JSONEncoder().encode(metadata)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Expected metadata JSON dictionary")
            return
        }
        object.removeValue(forKey: "contentType")
        let invalidData = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: Error.self) {
            try JSONDecoder().decode(PaneMetadata.self, from: invalidData)
        }
    }

    // MARK: - DrawerChild Pane

    @Test

    func test_drawerChild_codable_roundTrip() throws {
        let parentId = UUID()
        let pane = Pane(
            content: .webview(WebviewState(url: URL(string: "https://test.com")!, showNavigation: true)),
            metadata: PaneMetadata(title: "Web Drawer"),
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
        let drawer = Drawer(paneIds: [id1, id2], isExpanded: false)

        let data = try encoder.encode(drawer)
        let decoded = try decoder.decode(Drawer.self, from: data)

        #expect(decoded.paneIds.count == 2)
        #expect(!(decoded.isExpanded))
        #expect(decoded.paneIds[0] == id1)
        #expect(decoded.paneIds[1] == id2)
    }

    @Test

    func test_drawer_defaultValues() {
        let drawer = Drawer()

        #expect(drawer.paneIds.isEmpty)
        #expect(!(drawer.isExpanded))
    }

    @Test
    func test_drawer_ignoresLegacyActivePaneIdEncoding() throws {
        let id = UUID()
        let drawer = Drawer(
            paneIds: [id],
            isExpanded: true
        )
        let currentJSON = try #require(String(data: try encoder.encode(drawer), encoding: .utf8))
        let legacyJSON = currentJSON.replacingOccurrences(
            of: "\"isExpanded\"",
            with: "\"activePaneId\":\"\(id.uuidString)\",\"isExpanded\""
        )

        let decodedDrawer = try decoder.decode(Drawer.self, from: Data(legacyJSON.utf8))

        #expect(decodedDrawer.drawerId == drawer.drawerId)
        #expect(decodedDrawer.parentPaneId == drawer.parentPaneId)
        #expect(decodedDrawer.paneIds == drawer.paneIds)
        #expect(decodedDrawer.isExpanded == drawer.isExpanded)
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
            metadata: PaneMetadata(),
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
        }
        #expect(pane.drawer?.paneIds == [childId])
    }

    @Test

    func test_withDrawer_noOpForDrawerChild() {
        let parentId = UUID()
        var pane = Pane(
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(),
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
            metadata: PaneMetadata()
        )

        // Assert
        #expect((pane.drawer) != nil)
        #expect(!(pane.drawer!.isExpanded))
        #expect(pane.drawer!.paneIds.isEmpty)
    }
}
